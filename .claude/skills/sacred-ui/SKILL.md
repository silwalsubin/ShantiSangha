---
name: sacred-ui
description: "Enforces the ShantiSangha sacred design system and iOS UX patterns when creating or editing UI code — Vue/Tailwind and SwiftUI. Use this skill whenever the user asks to build, edit, style, or create any UI component, page, view, screen, button, card, form, modal, or layout in this project. Also trigger when the user mentions colors, fonts, spacing, icons, animations, visual styling, gestures, navigation, transitions, loading states, empty states, or interaction patterns. Even if the user doesn't mention 'sacred' or 'design system', always apply these rules when touching UI code. This skill covers both how things LOOK (colors, fonts, layout) and how things FEEL (gestures, transitions, loading behavior, navigation flow)."
---

# Sacred UI — ShantiSangha Design System

This skill ensures every piece of UI code in ShantiSangha follows the sacred design system: a warm, serene, Hindu-Buddhist aesthetic using saffron, gold, and parchment tones. The design should feel like reading a sacred text — calm, private, breathable.

The reason this matters: ShantiSangha is a spiritual companion app. Cold tech colors, harsh fonts, or cluttered layouts would break the trust and serenity users need. Every pixel should say "this is calm, this is mine, I can breathe here."

## Core Philosophy

- **Warm, never cold.** Saffron, gold, parchment. Never blue, green (except status), purple, or grey-toned tech colors.
- **Serif, always.** Georgia on web, New York (`.design(.serif)`) on iOS. No sans-serif anywhere.
- **Simple, not busy.** One path, not seven doors. If it needs explanation, it's too complex.
- **Mobile-first.** Design for 375px / iPhone SE first. 44px minimum touch targets on everything tappable.
- **No emojis.** Use `SacredIcons` components exclusively for iconography.
- **Gentle language.** Never clinical or corporate. Reflective and warm.

## Color Tokens

Never use raw hex values in component code. Always use the design tokens.

### Vue / Tailwind Classes

| Purpose | Class |
|---------|-------|
| **Primary text** | `text-sacred-text` (#2b1e10) |
| **Secondary text** | `text-sacred-text-secondary` (#6b5740) |
| **Muted text** | `text-sacred-muted` (#9a8568) |
| **Labels (uppercase)** | `text-sacred-label` (#a38d6d) |
| **Gold accent** | `text-sacred-gold` (#c4873b) |
| **Page background** | `bg-sacred-bg` (#faf5ed) |
| **Card background** | `bg-sacred-bg-card` (rgba(250,245,237,0.88)) |
| **Inner card bg** | `bg-sacred-bg-card-inner` (rgba(250,245,237,0.7)) |
| **Hover state** | `hover:bg-sacred-bg-hover` (rgba(139,90,43,0.06)) |
| **Standard border** | `border-sacred-border` (rgba(139,90,43,0.12)) |
| **Subtle border** | `border-sacred-border-subtle` (rgba(139,90,43,0.1)) |
| **Success** | `text-sacred-green` (#7aa87a), `bg-sacred-green-bg`, `border-sacred-green-border` |
| **Error** | `text-sacred-red` (#b45a3c), `bg-sacred-red-bg`, `border-sacred-red-border` |
| **Gold gradient** | `bg-gradient-to-r from-sacred-gold to-sacred-gold-dark` |

### SwiftUI Colors

Use `Color.sacred*` extensions exclusively:

| Purpose | Token |
|---------|-------|
| **Primary text** | `Color.sacredText` |
| **Secondary text** | `Color.sacredTextSecondary` |
| **Muted text** | `Color.sacredMuted` |
| **Labels** | `Color.sacredLabel` |
| **Gold accent** | `Color.sacredGold` |
| **Gold dark** | `Color.sacredGoldDark` |
| **Gold shine** | `Color.sacredGoldShine` (#e8c47a) |
| **Page background** | `Color.sacredBg` |
| **Card background** | `Color.sacredBgCard` |
| **Success** | `Color.sacredGreen` |
| **Error** | `Color.sacredRed` |
| **Gold gradients** | `LinearGradient.sacredGoldShiny`, `.sacredGoldShinyVertical` |
| **Radial gold** | `RadialGradient.sacredGoldShiny` |

## Typography

### Vue / Tailwind

All text uses the serif font stack (Georgia). Use these custom utility classes:

| Class | Size | Style |
|-------|------|-------|
| `text-sacred-heading` | 24px | semibold, line-height 1.3 |
| `text-sacred-heading-sm` | 20px | semibold, line-height 1.3 |
| `text-sacred-body` | 14px | normal, line-height 1.6 |
| `text-sacred-label` | 10px | semibold, uppercase, tracking 0.2em |
| `text-sacred-caption` | 10px | medium, uppercase, tracking 0.15em |
| `text-sacred-xs` | 9px | bold, uppercase, tracking 0.2em |

For section labels, use this exact pattern:
```html
<span class="text-[9px] font-bold uppercase tracking-[0.2em] text-sacred-label">SECTION NAME</span>
```

### SwiftUI

All fonts must use `.design(.serif)` (New York). Use the `DesignTokens.swift` extensions:

| Token | Size | Weight |
|-------|------|--------|
| `.sacredHero` | 28pt | bold |
| `.sacredTitle` | 22pt | semibold |
| `.sacredHeading` | 20pt | bold |
| `.sacredSubheading` | 18pt | bold |
| `.sacredButtonLabel` | 16pt | semibold |
| `.sacredBody` / `.sacredText` | 14pt | regular |
| `.sacredTextSemibold` | 14pt | semibold |
| `.sacredBodyBold` | 14pt | bold |
| `.sacredSmall` / `.sacredCaption` | 12pt | regular |
| `.sacredSmallSemibold` | 12pt | semibold |
| `.sacredFinePrint` | 11pt | regular |
| `.sacredMicro` | 10pt | regular |
| `.sacredMicroBold` | 10pt | bold |
| `.sacredSectionLabel` | 9pt | bold, tracking +3 |

## Component Patterns

### Buttons

**Vue (primary gold button):**
```html
<button class="min-h-[44px] rounded-full bg-gradient-to-r from-sacred-gold to-sacred-gold-dark px-6 py-3 text-sm font-semibold text-white shadow-sacred-button transition duration-200 active:scale-[0.97]">
  Save
</button>
```

**SwiftUI (primary gold button):**
```swift
Button { action() } label: {
    Text("Save")
        .font(.sacredButtonLabel)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(LinearGradient.sacredGoldShinyVertical)
        .clipShape(Capsule())
}
```

All buttons must be at least 44px/44pt tall. Always add press feedback: `active:scale-[0.97]` on web.

### Cards

**Vue:**
```html
<div class="rounded-sacred-lg border border-sacred-border-subtle bg-sacred-bg-card-inner px-4 py-3 transition-all duration-300">
  <p class="text-sacred-body text-sacred-text">Content</p>
</div>
```

**SwiftUI:**
```swift
VStack(spacing: 8) {
    Text("Content")
        .font(.sacredText)
        .foregroundColor(.sacredText)
}
.padding(.horizontal, 16)
.padding(.vertical, 12)
.background(Color.sacredBgCard)
.clipShape(RoundedRectangle(cornerRadius: 16))
.overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sacredMuted.opacity(0.12), lineWidth: 1))
```

### Status States (cards with status)

| State | Vue border | Vue bg |
|-------|-----------|--------|
| Success/completed | `border-sacred-green-border` | `bg-sacred-green-bg` |
| Error/overdue | `border-sacred-red-border` | `bg-sacred-red-bg` |
| Normal | `border-sacred-border-subtle` | `bg-sacred-bg-card-inner` |

### Dropdowns / Menus

```html
<div class="rounded-xl border border-sacred-border bg-sacred-bg-warm py-1 shadow-sacred-dropdown backdrop-blur-[20px]">
  <!-- menu items -->
</div>
```

### Toast Notifications

- Success: `border-sacred-green-border bg-sacred-green-bg text-sacred-green-dark`
- Error: `border-sacred-red-border bg-sacred-red-bg text-sacred-red`
- Info: `border-sacred-border bg-sacred-bg-card text-sacred-text`
- Container: `rounded-xl border px-4 py-3 text-sm shadow-sacred backdrop-blur-[20px]`

## Shadows

Always use warm-toned shadows. Never use default Tailwind grey shadows.

| Vue class | Value |
|-----------|-------|
| `shadow-sacred` | `0 4px 24px rgba(82,54,29,0.06)` |
| `shadow-sacred-lg` | `0 8px 40px rgba(82,54,29,0.08)` |
| `shadow-sacred-button` | `0 2px 8px rgba(139,90,27,0.2)` |
| `shadow-sacred-glow` | `0 4px 16px rgba(139,90,43,0.25)` |
| `shadow-sacred-dropdown` | `0 4px 16px rgba(82,54,29,0.12)` |

On iOS, use: `.shadow(color: .sacredMuted.opacity(0.15), radius: 8, y: 4)`

## Border Radius

- Standard cards: `rounded-sacred` (16px) or `rounded-sacred-lg` (20px)
- Buttons: `rounded-full` (capsule)
- Menus/toasts: `rounded-xl`

## Icons

Use `SacredIcons.vue` (web) or `SacredIcons.swift` (iOS) exclusively. Never use emoji or external icon libraries.

Available icons: `vajra`, `lotus`, `om`, `scroll`, `dialogue`, `chakra`, `diya`, `shankha`, `flame`, `target`, `check`, `skip`, `recurring`, `dharma`

**Vue usage:**
```html
<SacredIcon name="lotus" :size="22" class="text-sacred-gold" />
```

**SwiftUI usage:**
```swift
SacredIcons.lotus(size: 22)
    .foregroundColor(.sacredGold)
```

## Spacing & Layout

- Page padding: `p-4` mobile, `sm:p-6` desktop
- Card padding: `px-4 py-3` (compact) or `px-6 py-4` (spacious)
- Icon gaps: `gap-1.5` (6px) or `gap-2.5` (10px)
- Section spacing: `mt-6` between sections
- Safe area: `pb-[env(safe-area-inset-bottom)]` on iPhone
- Full height: use `100dvh` not `100vh`

## Animation

Keep animations subtle and serene. No flashy transitions.

- Standard transition: `transition duration-200` or `transition-all duration-300`
- Button press: `active:scale-[0.97]` or `active:scale-[0.98]`
- iOS progress: `.easeOut(duration: 0.5)`
- iOS streak pulse: `.easeOut(duration: 0.8).delay(0.2)`
- Shimmer (gold elements): 3.5s repeating with 2s delay
- iOS haptics: `.light` for taps, `.medium` for confirmations

## Checklist Before Writing UI Code

Before writing any UI, verify:

1. **Colors** — Only `sacred-*` tokens used? No raw hex/rgb values?
2. **Fonts** — Serif only? Using defined font tokens, not arbitrary sizes?
3. **Touch targets** — All tappable elements >= 44px/44pt?
4. **Shadows** — Using warm `shadow-sacred-*` variants, not default grey?
5. **Icons** — Using SacredIcons, not emoji or external libraries?
6. **Spacing** — Mobile-first with `p-4` base, `sm:p-6` desktop?
7. **Borders** — Using `border-sacred-*` tokens?
8. **Animations** — Subtle only? `duration-200` or `duration-300`?
9. **Language** — Gentle, reflective tone? No clinical/corporate text?
10. **Radius** — Using `rounded-sacred` / `rounded-sacred-lg` / `rounded-full`?

## iOS Interaction Patterns

This section governs how things *feel*, not just how they look. A button with the right color but the wrong gesture is still wrong.

### Navigation Philosophy

ShantiSangha uses 3 tabs wrapped in `NavigationStack`. Every screen must be reachable and returnable — no orphaned views.

- **Tab switch** = context change (Home, Reflect, Journey). Never navigate *between* tabs programmatically.
- **NavigationLink push** = drill deeper into the same context (practice → calendar, conversation → chat).
- **Sheet / fullScreenCover** = temporary focused task that returns to the same place (new goal, new journal). Dismiss returns exactly where you were.
- **Never use modals for content the user might want to keep visible.** If it's informational, it belongs inline. Modals are for input.

### Gesture Vocabulary

Every gesture in the app has a specific meaning. Do not mix them.

| Gesture | Meaning | Example |
|---------|---------|---------|
| **Tap** | Navigate or toggle | Tap practice → GoalDetailView |
| **Long press + drag** | Swipe action (commit/skip) | Hold practice → drag right = done |
| **Pull down** | Refresh current data | Pull-to-refresh on any scrollable list |
| **Swipe back** | iOS-native back navigation | Edge swipe to go back |
| **Context menu (long press)** | Secondary actions | Long-press insight → dismiss/share |

Rules:
- Swipe-to-act requires long-press activation first (prevents accidental swipes while scrolling)
- Every swipe action must have an equivalent menu option (accessibility)
- Never hijack iOS-native gestures (edge swipe back, scroll bounce)

### State & Loading Patterns

The user should never see a blank screen and wonder if the app is broken.

- **Loading:** Show the previous data while refreshing. Only show a spinner on first load when there's truly nothing to show.
- **Empty state:** Always provide a warm message and a single clear action. "You haven't set any practices yet" + "Set your first practice" button.
- **Failure:** Never show raw errors. If a fetch fails silently, keep showing cached/previous data. If there's nothing to show, use a gentle fallback message ("Check back in a few minutes").
- **Cancellation:** SwiftUI tears down `.task` on view disappear. Always guard `catch` blocks with `error.isCancellation` — cancelled requests are not errors, never log or display them.
- **Optimistic updates:** For user-initiated actions (check-in, delete), update the UI immediately and reconcile in the background. The user should never wait for a server round-trip to see their action reflected.

### SwiftUI Patterns

- **Data loading:** Use `.task { }` for initial load (fires once per view lifecycle). Use `.refreshable { }` for pull-to-refresh. Never use `.onAppear` for async work — it fires on every appearance including tab switches.
- **Caching:** If data doesn't change within a session (e.g., today's reflection), cache it by date and skip refetch on tab switch. Always allow force-refresh via pull-to-refresh.
- **Keyboard:** Use `.scrollDismissesKeyboard(.interactively)` on any ScrollView with text input. Never let the keyboard cover the active text field.
- **Safe area:** Respect safe areas. Use `.ignoresSafeArea()` only on backgrounds, never on content.
- **Haptics:** `.light` for taps and selections, `.medium` for confirmations and completions. Never use `.heavy` — this is a calm app.

### Transition & Animation Behavior

Animations must be functional (convey state change), not decorative.

- **Check-in complete:** Row slides off-screen (0.2s ease-out), then reappears in "done" state
- **Data appearing:** Fade in with `.easeIn(duration: 0.3)` — never pop
- **Period/tab switching:** Immediate content swap, no crossfade (feels responsive)
- **Progress rings:** Animate fill on appear with `.easeOut(duration: 0.8)` — gives a sense of achievement
- **Dismissing items:** `withAnimation { items.removeAll { ... } }` — smooth removal
- **Never animate:** Navigation pushes (iOS handles this), keyboard appearance, error states

### Accessibility

- **Dynamic Type:** All text must use the `.sacred*` font tokens which scale with system settings. Never hardcode font sizes except in the token definitions.
- **VoiceOver:** Every interactive element needs an accessible label. Swipe actions must have menu alternatives.
- **Contrast:** Sacred gold (#c4873b) on sacred bg (#faf5ed) meets AA contrast. Never go lighter than `.sacredMuted` for meaningful text.
- **Touch targets:** 44pt minimum on everything tappable — this is both an Apple guideline and sacred-ui law.

## Reference Files

For the complete token definitions, read these files:
- **Web tokens:** `frontend/tailwind.config.js`
- **iOS tokens:** `ios/ShantiSangha/Models/DesignTokens.swift`
- **Web icons:** `frontend/src/components/icons/SacredIcons.vue`
- **iOS icons:** `ios/ShantiSangha/Views/Components/SacredIcons.swift`
- **Design principles:** `docs/design-principles/sacred-aesthetic.md`
