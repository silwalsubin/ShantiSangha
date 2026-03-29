# Mobile First

Most spiritual moments happen on phones — commuting, before sleep, during a break. The mobile experience is the primary experience.

## Why this matters

A person feeling anxious at 2am will reach for their phone, not their laptop. If the app doesn't feel natural on a small screen, it fails at the moment it matters most.

## Rules

- **Design for 375px first**, then scale up — not the other way around
- **44px minimum** touch targets on all interactive elements
- **`100dvh`** for full-height layouts (accounts for mobile browser chrome)
- **`pb-[env(safe-area-inset-bottom)]`** for iPhone safe areas
- **`p-4 sm:p-6`** for responsive card padding
- **`text-2xl sm:text-3xl`** for responsive headings
- **Bottom tab bar** is the primary navigation on mobile
- **No hover-only interactions** — everything must work with touch
- **Press feedback** (`active:scale-[0.98]`) on every tappable element so touch feels responsive

## How to test

Every UI change must be checked in Chrome DevTools mobile view (iPhone SE, 375px) before committing. If it looks broken on mobile, it doesn't ship.
