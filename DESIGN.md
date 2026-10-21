---
name: SetPoint Admin
description: Light operator admin at Linear / Stripe Dashboard / Vercel craft.
colors:
  canvas: "#F3F4F6"
  rail: "#FFFFFF"
  panel: "#FFFFFF"
  ink: "#111827"
  soft: "#4B5563"
  faint: "#6B7280"
  line: "#E5E7EB"
  line-hi: "#D1D5DB"
  accent: "#1D4ED8"
  accent-soft: "#EFF6FF"
  good: "#047857"
  good-bg: "#ECFDF5"
  bad: "#B91C1C"
  bad-bg: "#FEF2F2"
  warn: "#B45309"
  warn-bg: "#FFFBEB"
typography:
  title:
    fontFamily: "Source Sans 3, ui-sans-serif, system-ui, sans-serif"
    fontSize: "24px"
    fontWeight: 650
    lineHeight: 1.2
    letterSpacing: "-0.03em"
  body:
    fontFamily: "Source Sans 3, ui-sans-serif, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "Source Sans 3, ui-sans-serif, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 500
  figure:
    fontFamily: "Red Hat Mono, ui-monospace, monospace"
    fontSize: "40px"
    fontWeight: 500
    letterSpacing: "-0.03em"
rounded:
  sm: "8px"
  md: "12px"
  pill: "999px"
spacing:
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "28px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "#FFFFFF"
    rounded: "{rounded.sm}"
    height: "36px"
    padding: "0 14px"
  button-primary-hover:
    backgroundColor: "{colors.accent}"
  nav-current:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.accent}"
    rounded: "{rounded.sm}"
  panel:
    backgroundColor: "{colors.panel}"
    rounded: "{rounded.md}"
    padding: "18px"
---

# Design System: SetPoint Admin

## Overview

**Creative North Star: "The Working Admin"**

`/admin` is a category-standard light operator page, executed at Linear / Stripe Dashboard / Vercel craft. The owner jumps all day between access, health, and people; the rail is always there so that jumping never slows. The iOS member app (dark, ember, haze) is a different identity and does not apply here.

Personality is precise, compact, and unadorned. Color does jobs: blue for the current section and primary actions, green/red/amber only for status. Figures are mono. Surfaces are white on cool gray, separated by a 1px rule.

**Key Characteristics:**
- Persistent 232px white rail, blue-wash current item as the only accent
- Off-white canvas `#F3F4F6`, white panels, 12px corners
- Source Sans 3 for UI, Red Hat Mono for IDs and figures
- Compact density; status color only when something is wrong or waiting

## Colors

One accent on a cool gray field. Status hues are reserved.

### Primary
- **Operator Blue** (`#1D4ED8`): current nav (on `#EFF6FF`), primary buttons, links, the active series on charts.

### Neutral
- **Canvas** (`#F3F4F6`): page ground.
- **Rail / Panel** (`#FFFFFF`): sidebar and cards.
- **Ink** (`#111827`): body and headings.
- **Soft** (`#4B5563`): secondary copy and placeholders.
- **Line** (`#E5E7EB`): 1px rules.

### Status
- **Good** (`#047857` on `#ECFDF5`): on / healthy.
- **Bad** (`#B91C1C` on `#FEF2F2`): failing, disabled, error.
- **Warn** (`#B45309` on `#FFFBEB`): waiting, stale, needs the owner.

### Named Rules
**The One Accent Rule.** Blue is current selection and primary action only. It is not decoration.

**The Status-as-Exception Rule.** Green, red, and amber appear only when the state is not the default. A table of completed rows stays ink.

## Typography

**Display Font:** Source Sans 3 (ui-sans-serif, system-ui)
**Body Font:** Source Sans 3
**Label/Mono Font:** Red Hat Mono (ui-monospace)

**Character:** One workhorse grotesk for the product; a tabular mono for anything that is a number, id, or code.

### Hierarchy
- **Title** (650, 24px, -0.03em): page names in the stage.
- **Body** (400, 15px / 1.45): copy and table cells.
- **Label** (500, 13px): field labels, secondary lines.
- **Figure** (Red Hat Mono 500, 40px on Overview KPIs): headline numbers.

### Named Rules
**The Mono Figures Rule.** KPI values, percents, ids, env, event names, and invite codes are Red Hat Mono. Labels stay Source Sans 3.

## Layout

232px sticky rail, stage padded 28×32, max width 1180px. Overview’s first viewport is the rail, the range line, and four KPIs (People, Active last day, Meals, Days fully eaten); supporting metrics sit below the fold. Compact operator density. Breakpoints: 960px (KPI grid 2-up), 720px (rail stacks on top, horizontal section scroller).

## Elevation & Depth

Flat. Depth is a 1px `#E5E7EB` rule and a white panel on the canvas. The toast is the only lifted surface (`0 8px 24px rgba(17, 24, 39, 0.12)`).

### Named Rules
**The Flat-By-Default Rule.** No glow, glass, or gradient. Shadows only on the toast.

## Shapes

8px on controls, 12px on panels, 999px on badges and the waiting count. 1px borders, no offset shadows.

## Components

### Buttons
- **Shape:** 8px, 36px tall, 14px horizontal padding.
- **Primary:** `#1D4ED8` fill, white label, 600.
- **Default:** white fill, `#D1D5DB` border.
- **Danger:** `#B91C1C` label, `#FECACA` border; sits alone, never next to Create or Copy.
- **Sign out:** text control in the rail foot, no chrome.

### Cards / Containers
- White, 12px, 1px `#E5E7EB`, 18px padding. KPI cards on Overview use extra padding in the first viewport.

### Inputs / Fields
- 36px, 8px radius, 1px `#E5E7EB`, white fill. Focus: border `#1D4ED8`. Placeholder `#4B5563`.

### Navigation
- Rail buttons 36px min height, 8px radius. Current: `#EFF6FF` / `#1D4ED8`, 600. Waiting count is a 20px warn pill. Mobile: horizontal scroller under a compact header.

### Chips
- 12px, 999px, 1px border. Status chips only for non-default state.

## Do's and Don'ts

### Do:
- **Do** keep a persistent rail so jumping Overview / Users / Meals / Invites / Flags / Health is one click.
- **Do** put figures in Red Hat Mono and the current section in the blue wash.
- **Do** use warn color for people waiting and for a stale scheduler.

### Don't:
- **Don't** inherit the iOS ember/haze/dark world on this page.
- **Don't** use glow, glass, gradient text, or pill nav.
- **Don't** color every “Done” or “On” if that is the default — status is the exception.
- **Don't** put chart labels inside an SVG with `preserveAspectRatio: none`.
