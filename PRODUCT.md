# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary: the owner (Michael), alone, operating the closed beta from `/admin` in a browser. Trainers are a later surface, not this page.

Job: jump through the day between letting people in, checking whether the product is healthy, and inspecting a specific person. A clever layout that slows that jumping would make the result feel wrong.

## Product Purpose

SetPoint is an iOS app for people who train and cannot eat enough. It closes the daily fueling gap: a check-in when a meal is skipped or too light, a one-tap calorie-dense top-up after a small meal, and an evening check-in when the day is still short. Meal behavior decides when a check-in is due. Wearable HRV/RHR, when enabled, may adjust confidence on an already-due check-in — it never independently diagnoses under-fueling.

`/admin` is the owner's operator page for that product: analytics, users, meals, invite codes, feature flags, and system health. Success here means the owner can sign in, see whether the beta is working, let someone in or mint a code, and open a person, without hunting.

## Positioning

The consumer product is not a calorie counter. Check-ins fire from the meal schedule and the day's remaining gap. The admin page is not a second product: it is the owner's view of the same facts (who is in, what they ate, whether check-ins are firing).

## Operating Context

Members use the iOS app. The owner signs into `/admin` with an admin secret kept in that tab's session storage. The page itself is public HTML and holds no data; every number loads from `/api/admin` after sign-in. Cohorts (for example a trainer's pilot group) and invite codes are how people get in. Invite-only can be on or off via env. Typical motions: grant access, assign cohort/role, mint or disable a code, flip a feature flag, open a person, scan meals, check scheduler/alerts.

## Capabilities and Constraints

Confirmed on `/admin` today: sign-in with admin secret; Overview (range, cohort, KPIs, funnel, daily chart, calories vs target, screens, events, env switches); Users (search, role/cohort/pending filters, inline role/cohort/access edits, person profile with plan, days, weight, check-ins, meals); Meals (cohort/source filters, photo lightbox, load more); Invites (create/copy/disable); Flags (default/on/off/cohort-role-user overrides); Health (scheduler, alerts, wearable modifier, raw metrics JSON).

Technical: one self-contained HTML string in `backend/src/admin/dashboardPage.ts`, served at `GET /admin` with a strict CSP (`script-src 'unsafe-inline'`, styles from Google Fonts today). DOM is built in JS without `innerHTML` from data. Must keep working against the existing `/api/admin` contract. Do not invent metrics, users, or claims.

Undecided: a trainers area (explicitly later). Hebrew/RTL for this page is not required.

## Brand Commitments

Name: SetPoint. Consumer iOS app is dark, ember (`#FF7A3D`) for food, haze indigo for training, Geist-like system sans plus mono numbers. That identity is the member app.

`/admin` is the category-standard light admin (canon, seed `0e09a44e`). Craft peers: Linear, Stripe Dashboard, Vercel. The operator page does not inherit the iOS ember/haze world.

## Evidence on Hand

Live data after sign-in. Demo/synthetic values on the login screen must be labeled if shown. Do not fabricate testimonials, customer counts, or screenshots of the iOS app as proof.

## Product Principles

1. Jumping between jobs stays faster than looking at the page.
2. Real numbers and real actions only; the page never holds secrets or invented stats.
3. One person is a first-class destination, reachable from users, meals, and search.
4. Status that needs the owner (waiting for access, scheduler stale, invite-only off) is visible without opening a tab.
5. Familiar controls over clever structure.

## Accessibility & Inclusion

No product-specific a11y standard was set. Keyboard use and visible focus matter because the owner jumps between sections all day. Body text contrast ≥ 4.5:1.
