# Sacred Aesthetic

The app should feel like reading a sacred text — serene, warm, grounded.

## Why this matters

ShantiSangha is rooted in Hindu and Buddhist wisdom. The visual language must reflect that — not as decoration, but as an expression of the values the app embodies. When someone opens the app, they should feel they've entered a calm, intentional space.

## Rules

- **Saffron/gold/parchment palette only** — never blue, green, purple, or cold tech colors
- **Sacred icons** — use `SacredIcons.vue`, never emojis. Icons should evoke temple art, not Silicon Valley
- **Serif headings** — classical typography that feels like scripture, not a startup
- **Warm shadows** — `rgba(82,54,29,...)`, never cool grey
- **No flashy animations** — subtle transitions only (`duration-200`)
- **Wisdom quotes** from Gita, Dhammapada, Yoga Sutras in appropriate places
- **Language is gentle and reflective** — not clinical, corporate, or performative

## The feeling

When someone opens ShantiSangha, they should feel:
- "This is calm"
- "This is mine"
- "I can breathe here"

Not:
- "This is another app"
- "This wants something from me"
- "This is overwhelming"

## Technical Quick Reference

- **Backgrounds:** `#faf5ed → #f5ebe0 → #efe3d4`, cards `rgba(250,245,237,0.88)`
- **Text:** primary `#2b1e10`, secondary `#6b5740`, muted `#9a8568`, subtle `#b5996f`
- **Accent:** saffron `#c4873b`, deep saffron `#8b5a1b`
- **Borders:** `rgba(139,90,43,0.12)`
- **Icons:** `SacredIcons.vue` — lotus, dialogue, scroll, chakra, diya, shankha, om, dharma
- **Cards:** `rounded-2xl`, `backdrop-blur-[20px]`, warm shadows `rgba(82,54,29,...)`
- **Buttons:** `bg-gradient-to-r from-[#c4873b] to-[#8b5a1b]` with `min-h-[44px]`
- **Inputs:** `border-[rgba(139,90,43,0.12)]`, `focus:border-[#c4873b]`
- **Section labels:** `text-[9px] uppercase tracking-[0.2em] text-[#a38d6d]`
