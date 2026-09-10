import { randomUUID } from 'node:crypto';
import {
  DeleteObjectCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { env } from '../env.js';

/**
 * Meal-photo storage. Photos live in an S3-compatible bucket (Cloudflare R2 is
 * the intended target), never in Postgres — a base64 photo per meal row would
 * fill the database and drag every meal query. The bucket stays private; the
 * API hands out short-lived signed URLs.
 */
export type PhotoStore = {
  /** Uploads a meal photo and returns its object key. */
  put(userId: string, data: Buffer, mediaType: string): Promise<string>;
  /** A signed GET URL for a stored key. */
  signedUrl(key: string, now?: Date): Promise<string>;
  delete(key: string): Promise<void>;
  /** Removes every photo stored for a user (account deletion, §4). */
  deleteAllForUser(userId: string): Promise<number>;
};

const EXTENSION: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
};

/** Signed URLs stay valid this long from their signing anchor. */
const URL_TTL_SECONDS = 2 * 60 * 60;

export function userPhotoPrefix(userId: string): string {
  return `meals/${userId}/`;
}

export function photoKeyFor(userId: string, mediaType: string, id: string = randomUUID()): string {
  return `${userPhotoPrefix(userId)}${id}.${EXTENSION[mediaType] ?? 'jpg'}`;
}

/**
 * URLs are signed against the start of the current UTC hour, so every read in
 * that hour returns the identical URL and the app's image cache can reuse it.
 * With a 2 h TTL, a URL is always good for at least an hour after it's served.
 */
export function signingAnchor(now: Date): Date {
  const anchor = new Date(now);
  anchor.setUTCMinutes(0, 0, 0);
  return anchor;
}

export type S3PhotoStoreConfig = {
  bucket: string;
  endpoint: string;
  region: string;
  accessKeyId: string;
  secretAccessKey: string;
};

export function createS3PhotoStore(config: S3PhotoStoreConfig): PhotoStore {
  const client = new S3Client({
    region: config.region,
    endpoint: config.endpoint,
    forcePathStyle: true,
    credentials: { accessKeyId: config.accessKeyId, secretAccessKey: config.secretAccessKey },
    // R2 and other S3-compatibles don't all accept the SDK's newer default
    // checksum headers; only send them when an operation requires one.
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
  });
  const Bucket = config.bucket;

  async function deleteKeys(keys: string[]): Promise<void> {
    if (keys.length === 0) return;
    try {
      await client.send(
        new DeleteObjectsCommand({ Bucket, Delete: { Objects: keys.map((Key) => ({ Key })), Quiet: true } }),
      );
    } catch {
      // Some S3-compatibles reject multi-delete; fall back to one at a time.
      for (const Key of keys) await client.send(new DeleteObjectCommand({ Bucket, Key }));
    }
  }

  return {
    async put(userId, data, mediaType) {
      const Key = photoKeyFor(userId, mediaType);
      await client.send(
        new PutObjectCommand({
          Bucket,
          Key,
          Body: data,
          ContentType: mediaType,
          // Keys are unique per upload, so the bytes never change.
          CacheControl: 'private, max-age=31536000, immutable',
        }),
      );
      return Key;
    },

    async signedUrl(key, now = new Date()) {
      return getSignedUrl(client, new GetObjectCommand({ Bucket, Key: key }), {
        expiresIn: URL_TTL_SECONDS,
        signingDate: signingAnchor(now),
      });
    },

    async delete(key) {
      await client.send(new DeleteObjectCommand({ Bucket, Key: key }));
    },

    async deleteAllForUser(userId) {
      let deleted = 0;
      let ContinuationToken: string | undefined;
      do {
        const page = await client.send(
          new ListObjectsV2Command({ Bucket, Prefix: userPhotoPrefix(userId), ContinuationToken }),
        );
        const keys = (page.Contents ?? []).map((o) => o.Key).filter((k): k is string => !!k);
        await deleteKeys(keys);
        deleted += keys.length;
        ContinuationToken = page.IsTruncated ? page.NextContinuationToken : undefined;
      } while (ContinuationToken);
      return deleted;
    },
  };
}

let cached: PhotoStore | null | undefined;

/**
 * The configured photo store, or null when the PHOTO_* env vars are unset.
 * Without a store, photos still reach the AI parser but aren't kept.
 */
export function getPhotoStore(): PhotoStore | null {
  if (cached !== undefined) return cached;
  const configured =
    env.PHOTO_BUCKET && env.PHOTO_S3_ENDPOINT && env.PHOTO_S3_ACCESS_KEY_ID && env.PHOTO_S3_SECRET_ACCESS_KEY;
  cached = configured
    ? createS3PhotoStore({
        bucket: env.PHOTO_BUCKET,
        endpoint: env.PHOTO_S3_ENDPOINT,
        region: env.PHOTO_S3_REGION,
        accessKeyId: env.PHOTO_S3_ACCESS_KEY_ID,
        secretAccessKey: env.PHOTO_S3_SECRET_ACCESS_KEY,
      })
    : null;
  if (!cached) {
    console.warn('[photos] PHOTO_* storage not configured — meal photos are parsed but not stored');
  }
  return cached;
}
