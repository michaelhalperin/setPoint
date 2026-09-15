# Idea: order the suggested food from Wolt / 10bis

_Added 2026-09-15 · status: idea, not planned or built_

## The idea

When a check-in suggests what to eat ("Here's your lunch: chicken breast, rice
and olive oil"), show a button beside it that opens **Wolt** or **10bis** so the
user can order that food right away.

## Why it fits

- Check-ins often fire when someone is busy: at work, between meetings, far from
  their kitchen. "Eat this now" doesn't help if there's no food nearby.
  "Order this now" does.
- It turns the suggestion into one tap to get the food, which is the whole
  promise of the app ("exactly what to eat, one tap").
- 10bis is what many Israeli office workers already use for lunch, and those
  are the people who skip meals.

## How it could work for the user

1. A check-in arrives with the suggested plate.
2. Under the usual "I ate this" button there's also "Order on Wolt" / "Order on 10bis".
3. Tapping it opens the app, searching for something close to the suggestion
   (for example "chicken rice bowl") near the user.
4. The user picks and orders there. Back in SetPoint, they log what they
   actually got, or tap "I ate this".

## Things to figure out first

- **The suggestions are home foods, not restaurant dishes.** Today the app picks
  from a fixed list of simple foods (eggs, banana, rice, yogurt…). Restaurants
  don't sell "2 hard-boiled eggs + a banana". We'd need either a "meal to order"
  version of each suggestion (e.g. "grilled chicken + rice" → search "chicken rice"),
  or to show the order button only for suggestions that make sense to order.
- **How far can we link in?** Check whether Wolt and 10bis let us open their app
  on a search or a restaurant (links / deep links). Adding the exact dish to the
  cart for the user probably isn't possible without a partnership.
- **Partnership or affiliate deal?** If they have one, this could also earn money.
- **Israel only.** Wolt works in other countries; 10bis doesn't. Decide what users
  outside Israel see.
- **Logging after ordering.** Restaurant portions vary. Maybe the photo log is the
  natural next step ("snap it when it arrives").
- **Timing.** Delivery takes 30–60 min. For a check-in that's already late, show
  a quick snack to eat now as well as the order.
- **Allergies still apply.** Only suggest searches that fit the user's
  restrictions; the restaurant menu itself is out of our control, so say so.

---

# Build plan

## The approach in short

We can't put a dish in someone's Wolt / 10bis cart. Neither company has a public
API for that. What we *can* do is open their app on a **search** for a dish
that's close to what the check-in suggested. So the plan has three parts:

1. **A second, small food list of "dishes you can order"** (chicken rice bowl,
   shakshuka, tuna sandwich…), with rough calories, protein, allergens and a
   search word for each app. The check-in picks the closest dish with plain,
   tested code, the same way it picks home food today. **No AI.** The golden rule
   still holds.
2. **An "Order it" button** on the check-in that opens Wolt or 10bis on that search.
3. **An "I ordered" state** so the app waits for the delivery instead of
   escalating, then asks the user to log the food when it arrives.

Everything sits behind a feature flag and is only shown to users in Israel.

## Phase 0: check it's possible (1–2 days, before any code)

Test on a real iPhone with both apps installed:

- [ ] **Wolt links:** does a `wolt.com/…` web link open the Wolt app, or the
      browser? Is there a search link that works (a restaurant or dish search
      for the user's city)? Does the `wolt://` scheme accept a search?
- [ ] **10bis links:** same questions for `10bis.co.il/next/…` (the site has
      `/restaurants/search/`) and the 10bis app.
- [ ] **Which search words find real results:** Hebrew or English? Try ~15 dishes
      in Tel Aviv / Jerusalem / a smaller city and write down what works.
- [ ] **Money:** Wolt Israel runs an affiliate program through TradeDoubler
      (links get a tracking code). Check whether app links are allowed and what
      it pays. Ask 10bis whether they have anything similar.
- [ ] **Terms / branding:** can we name them and use their logos on a button?
      Until confirmed, use plain text buttons ("Order on Wolt"), not logos.

**Go / no-go:** if neither app can be opened on a useful search, stop here, or
shrink the feature to "open Wolt/10bis home screen", which is much weaker.

## Phase 1: the "Order it" button (MVP)

### Backend
- **`backend/src/data/orderableDishes.ts`**: new curated list, ~30–40 dishes
  that are common on Israeli delivery apps. Each has: `slug`, English label,
  rough `kcal` / `proteinG`, `allergens`, `tags` (vegetarian, vegan…), `slots`
  (breakfast / lunch / dinner) and `search: { wolt, tenbis }` words from Phase 0.
- **`backend/src/solver/orderDish.ts`**: `pickOrderDish(gap, restrictions, slot)`.
  It filters out dishes that break the user's restrictions (reuse
  `filterAllowedFoods` from `solver/exclusions.ts`), then picks the one closest
  to the meal's calorie + protein target. Deterministic, with a tie-break on slug.
  Returns `null` when nothing fits, so no button is shown.
- **Schema (one Prisma migration):** nullable snapshot columns on `Prescription`:
  `orderDishSlug`, `orderLabel`, `orderKcal`, `orderProteinG`. On `CheckIn`:
  `orderedAt`, `orderProvider`.
- **`jobs/scoreConfidence.ts`**: when a MEAL check-in fires and the user is
  eligible, attach the dish to the prescription.
- **Eligibility** (small pure function): feature flag `ORDER_LINKS_ENABLED` is on,
  user timezone is `Asia/Jerusalem` (a later settings toggle overrides), the
  check-in kind is `MEAL` (not refuel / calendar heads-up), and it's lunch or
  dinner (breakfast later if Phase 0 shows it works).
- **`GET /api/home` + `GET /api/checkins/:id`**: add
  `prescription.order = { label, kcal, proteinG, links: [{ provider, url }] }`.
  **The server builds the URLs** from templates in one config file, so if Wolt
  changes its link format we fix it with a deploy, not an App Store update.

### iOS
- **DTOs:** add the optional `order` block to `Prescription`.
- **`PrescriptionView` + the Today check-in takeover (`TodayHero`)**: under
  "I ate this", add a quiet row: *"Not near food? Order a chicken rice bowl"*
  with one button per provider. Tapping it opens the URL with `openURL`.
- **`project.yml`**: if Phase 0 uses app schemes, add them to
  `LSApplicationQueriesSchemes` so we can hide the button when the app isn't
  installed. Otherwise use web links, which fall back to the browser.
- A small allergy note under the button: *"Restaurants vary. Check the menu for
  allergens."*
- `-uiStub prescription-order` for screenshots.

### Tests
- Backend: dish picker respects every restriction token; picks deterministically;
  returns `null` when nothing fits; eligibility rules; link builder escapes Hebrew.
- iOS: DTO decoding with and without `order`; the row hides when `order` is nil.

## Phase 2: "I ordered it"

Without this, the check-in keeps escalating while the food is on the way.

- **Backend:** `POST /api/checkins/:id/ordered { provider }` sets `orderedAt` +
  `orderProvider` and holds the check-in like a snooze for ~50 min (reuse the
  `defer` path with `minutes`, but **don't** bump `deferCount`, and never count it
  toward tier escalation or a miss).
- **Escalation (`engine/escalation.ts`)**: when the hold ends with nothing logged,
  send one gentle *"Did your food arrive? Log it"* nudge at the same tier, not a
  firmer one.
- **iOS:** when the user comes back to SetPoint after tapping "Order", show a
  small sheet: *"Did you order?"* → **Yes** (calls `/ordered`) / **Not yet**.
- **Logging on arrival:** "I ate this" logs the dish's estimated macros (the
  existing `POST /api/meals { macros }` path, marked as an estimate), or opens the
  photo log for a real read of the plate.

## Phase 3: polish and measure

- **Settings → You → "Food ordering"**: on/off, and which apps to show (Wolt,
  10bis, both).
- **Notification action:** an "Order" button on the check-in push. It has to open
  SetPoint first (foreground action), which then opens the delivery app.
- **Affiliate tracking** on the links, if Phase 0 found a deal.
- **Manager copy:** add an order-aware line to the fallback copy in
  `managerVoice/` (e.g. *"Stuck at your desk? Order it."*).
- **Metrics** in `GET /api/admin/metrics`: order-button tap rate, "I ordered" rate,
  ordered → meal logged within 2 h, split by provider, and whether check-ins with
  the button get answered more often than ones without.

## Phase 4: only with a real partnership (later)

- Suggest a **specific restaurant and dish** near the user, using partner menu
  data instead of a search word.
- Open straight into that dish, or pre-fill the cart.
- Use the real menu's nutrition info, if they have it, instead of our estimate.

## Decisions needed from Michael

1. Build only after Phase 0 confirms the links work? (recommended)
2. Wolt only first, or Wolt + 10bis together?
3. Lunch + dinner only to start, or breakfast too?
4. Is affiliate money a goal, or is this purely a user feature?
5. Show it to everyone in Israel, or start with a beta cohort behind the flag?
