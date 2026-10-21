---
version: 1
slug: "backend-src-admin-dashboardpage-ts"
primary_target: "backend/src/admin/dashboardPage.ts"
related_targets: []
---

# /admin — owner dashboard

Mode: Operate. Audience: the owner, alone, jumping all day between access, health, and people. A clever layout that slows that jumping is the failure.

Craft peers (canon, named by the run): Linear, Stripe Dashboard, Vercel.

## Direction contract

THESIS: `/admin` is a light SaaS operator page at Linear/Stripe/Vercel craft — a persistent rail so jumping never slows, the stage showing only the current job. It refuses the dark glow-and-pills look and refuses a metaphor that rearranges navigation.

OWN-WORLD: Off-white canvas `#F3F4F6`, white rail and panels, 1px `#E5E7EB` rules, 12px corners. Ink `#111827`, secondary `#4B5563`. Current nav is a blue wash `#EFF6FF` / `#1D4ED8`. Primary actions solid blue. Status green/red/amber only for status. Source Sans 3 for UI, Red Hat Mono for IDs and figures. Compact density. No glow, glass, or gradient.

STORY: Sign in with the admin secret. See whether anyone is waiting. Jump Overview / Users / Meals / Invites / Flags / Health in one click. Open a person without losing the rail. Save with a toast.

FIRST VIEWPORT: After sign-in, 232px white rail (SetPoint, env, sections, Sign out at the foot). Stage: “Overview”, range line, four KPI cards in a row (People, Active last day, Meals, Days fully eaten). Login, before that, is a centered white card: heading, password, Sign in.

FORM: Category standard (canon), seed `0e09a44e`. Signature interaction: section switch is instant; the rail’s current item is the only accent; save confirmation is a 180ms toast.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
