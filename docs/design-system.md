# Design System — Sacred Scripture Theme

All UI work MUST follow the Hindu scripture-inspired design language. This is a strict requirement for every frontend change.

## Philosophy

The app should feel like reading a sacred text — serene, warm, grounded. Not a tech product. Not a clinical tool. A spiritual space that users feel is *theirs*.

- Avoid flashy animations, bright colors, or modern SaaS aesthetics
- Prefer subtle transitions (`duration-200`)
- Language should be gentle and reflective, not clinical or corporate
- Include wisdom quotes (Hindu/Buddhist scripture) in footer areas and auth pages

## Icons

- Use `SacredIcons.vue` component (`src/components/icons/SacredIcons.vue`) for all navigation and feature icons
- Available icons: `om`, `dialogue`, `scroll`, `chakra`, `lotus`, `diya`, `shankha`, `dharma`
- NEVER use emojis as UI icons — add new SVG icons to `SacredIcons.vue` when needed
- Icon style: thin line-art (stroke-width 1.2), sacred geometry motifs
- Logo: Lotus icon in a saffron gradient circle with subtle glow animation

## Color Palette

### Backgrounds
- **Page gradient:** `#faf5ed → #f5ebe0 → #efe3d4`
- **Cards/surfaces:** `rgba(250,245,237,0.88)` to `rgba(250,245,237,0.95)`
- **Inputs:** `rgba(250,245,237,0.9)`

### Text
- **Primary:** `#2b1e10` (deep earth brown)
- **Secondary:** `#6b5740` (warm brown)
- **Muted:** `#9a8568`
- **Subtle:** `#b5996f`
- **Section labels:** `#a38d6d`

### Accent
- **Saffron:** `#c4873b` — primary accent, active states
- **Deep saffron:** `#8b5a1b` — gradient endpoints, hover states
- **Saffron gradient:** `from-[#c4873b] to-[#8b5a1b]` — buttons, logo, user chat bubbles

### Borders
- **Default:** `rgba(139,90,43,0.12)`
- **Stronger:** `rgba(139,90,43,0.15)`
- **Dashed dividers:** `border-dashed border-[rgba(139,90,43,0.12)]`

### Shadows
- **Cards:** `shadow-[0_4px_24px_rgba(82,54,29,0.06)]`
- **Elevated:** `shadow-[0_16px_60px_rgba(82,54,29,0.1)]`
- **Buttons:** `shadow-[0_2px_8px_rgba(139,90,27,0.2)]`
- NEVER use cool grey shadows

### Forbidden colors
- No blue, green, purple, or cold/tech-feeling colors anywhere in the UI
- Error states may use warm red tones sparingly

## Typography

- **Headings:** `font-serif`, `font-bold`, `tracking-wide`
- **Section labels:** `text-[9px]` or `text-[10px]`, `uppercase`, `tracking-[0.2em]`, color `#a38d6d`
- **Body:** default sans-serif, warm brown colors
- **Quotes:** `italic`, muted saffron `#b5996f`
- **Responsive sizing:** `text-2xl sm:text-3xl` for headings, `text-[13px] sm:text-sm` for body

## UI Components

### Cards
```
rounded-2xl
border border-[rgba(139,90,43,0.12)]
bg-[rgba(250,245,237,0.88)]
backdrop-blur-[20px]
shadow-[0_4px_24px_rgba(82,54,29,0.06)]
p-4 sm:p-6
```

### Primary buttons
```
rounded-full
bg-gradient-to-r from-[#c4873b] to-[#8b5a1b]
text-white font-semibold
shadow-[0_2px_8px_rgba(139,90,27,0.2)]
min-h-[44px]
transition duration-200 hover:-translate-y-0.5
```

### Secondary buttons
```
rounded-full
border border-[rgba(139,90,43,0.15)]
text-[#6b5740] font-medium
min-h-[44px]
transition duration-200 hover:bg-[rgba(196,135,59,0.06)]
```

### Input fields
```
rounded-2xl
border border-[rgba(139,90,43,0.12)]
bg-[rgba(250,245,237,0.9)]
text-[#2b1e10] placeholder-[#b5996f]
focus:border-[#c4873b] focus:ring-1 focus:ring-[#c4873b]
```

### Navigation (active state)
```
bg-gradient-to-r from-[rgba(196,135,59,0.15)] to-[rgba(196,135,59,0.05)]
text-[#8b5a1b]
shadow-[inset_2px_0_0_#c4873b]
```

### Chat bubbles
- **User:** `bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white rounded-br-md`
- **Assistant:** `bg-[rgba(250,245,237,0.95)] border border-[rgba(139,90,43,0.12)] text-[#2b1e10] rounded-bl-md`

## Mobile-First Rules

- All layouts must look great on 375px width
- Use `p-4 sm:p-6` for card padding
- Use `space-y-4 sm:space-y-6` for section gaps
- Minimum 44px touch targets for all interactive elements
- Use `100dvh` for full-height layouts (accounts for mobile browser chrome)
- Bottom nav: `pb-[env(safe-area-inset-bottom,8px)]` for iPhone safe area
- Responsive text: `text-2xl sm:text-3xl` for headings

## Logo

- Icon: Lotus flower (`SacredIcons name="lotus"`)
- Container: `rounded-full bg-gradient-to-br from-[#c4873b] to-[#8b5a1b] text-white`
- Animation: Subtle pulsing glow (`sacred-glow` keyframes, 3s ease-in-out infinite)
- Sizes: `h-11 w-11` sidebar, `h-9 w-9` mobile header, `h-14 w-14` / `h-16 w-16` auth pages
- Favicon: SVG lotus on saffron gradient circle (`frontend/public/favicon.svg`)
