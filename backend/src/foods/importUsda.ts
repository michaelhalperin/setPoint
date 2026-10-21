/**
 * Downloads USDA FoodData Central dumps (Foundation + SR Legacy) and upserts
 * them into CatalogFood. Run: `pnpm --filter @setpoint/backend foods:import`
 *
 * Data is public domain (CC0). Citation: U.S. Department of Agriculture,
 * Agricultural Research Service. FoodData Central. fdc.nal.usda.gov.
 */
import { execFile } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { mkdir, readdir, readFile, rm, stat } from 'node:fs/promises';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { getPrisma } from '../db/client.js';
import { foodsFromUsdaDump, type CatalogFoodWrite } from './usda.js';

const exec = promisify(execFile);

/** Nightly-stable SR Legacy dump; Foundation URL may shift with each FDC release. */
export const USDA_DUMPS = [
  {
    dataType: 'sr_legacy' as const,
    url: 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip',
  },
  {
    dataType: 'foundation' as const,
    url:
      process.env.USDA_FOUNDATION_URL ??
      'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2025-04-24.zip',
  },
];

const CACHE_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../.cache/usda');

export async function importUsdaCatalog(opts?: {
  cacheDir?: string;
  dumps?: typeof USDA_DUMPS;
}): Promise<{ upserted: number }> {
  const prisma = getPrisma();
  const cacheDir = opts?.cacheDir ?? CACHE_DIR;
  await mkdir(cacheDir, { recursive: true });

  const foods: CatalogFoodWrite[] = [];
  for (const dump of opts?.dumps ?? USDA_DUMPS) {
    const jsonPath = await ensureDump(cacheDir, dump.url);
    const payload = JSON.parse(await readFile(jsonPath, 'utf8')) as unknown;
    const mapped = foodsFromUsdaDump(payload);
    console.log(`USDA ${dump.dataType}: ${mapped.length} foods with energy from ${path.basename(jsonPath)}`);
    foods.push(...mapped);
  }

  const unique = new Map<number, CatalogFoodWrite>();
  for (const food of foods) unique.set(food.fdcId, food);
  const rows = [...unique.values()];

  for (const chunk of chunks(rows, 50)) {
    await Promise.all(
      chunk.map((food) =>
        prisma.catalogFood.upsert({
          where: { fdcId: food.fdcId },
          create: { ...food, source: 'USDA' },
          update: {
            name: food.name,
            category: food.category,
            servingG: food.servingG,
            servingDesc: food.servingDesc,
            kcal100g: food.kcal100g,
            proteinG100g: food.proteinG100g,
            carbsG100g: food.carbsG100g,
            fatG100g: food.fatG100g,
            dataType: food.dataType,
            source: 'USDA',
          },
        }),
      ),
    );
  }

  console.log(`CatalogFood: ${rows.length} USDA foods.`);
  return { upserted: rows.length };
}

async function ensureDump(cacheDir: string, url: string): Promise<string> {
  const zipName = path.basename(new URL(url).pathname);
  const zipPath = path.join(cacheDir, zipName);
  const extractDir = path.join(cacheDir, zipName.replace(/\.zip$/i, ''));
  const existing = await findJson(extractDir);
  if (existing) return existing;

  if (!(await exists(zipPath))) {
    console.log(`Downloading ${url}`);
    const res = await fetch(url, { headers: { 'User-Agent': 'SetPoint/0.1 (https://setpoint.app)' } });
    if (!res.ok || !res.body) throw new Error(`USDA download ${res.status} for ${url}`);
    await pipeline(Readable.fromWeb(res.body as never), createWriteStream(zipPath));
  }

  await rm(extractDir, { recursive: true, force: true });
  await mkdir(extractDir, { recursive: true });
  await exec('unzip', ['-o', '-q', zipPath, '-d', extractDir]);
  const jsonPath = await findJson(extractDir);
  if (!jsonPath) throw new Error(`no JSON in ${zipName}`);
  return jsonPath;
}

async function findJson(dir: string): Promise<string | null> {
  if (!(await exists(dir))) return null;
  const jsons = await walkJson(dir);
  const foods = jsons.filter((p) => !/download.?field/i.test(path.basename(p)));
  return foods[0] ?? jsons[0] ?? null;
}

async function walkJson(dir: string): Promise<string[]> {
  const out: string[] = [];
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...(await walkJson(full)));
    else if (e.name.toLowerCase().endsWith('.json')) out.push(full);
  }
  return out;
}

async function exists(p: string): Promise<boolean> {
  try {
    await stat(p);
    return true;
  } catch {
    return false;
  }
}

function chunks<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  importUsdaCatalog()
    .then(async ({ upserted }) => {
      console.log(`Imported ${upserted} foods.`);
      await getPrisma().$disconnect();
    })
    .catch(async (err) => {
      console.error(err);
      try {
        await getPrisma().$disconnect();
      } catch {
        /* ignore */
      }
      process.exit(1);
    });
}
