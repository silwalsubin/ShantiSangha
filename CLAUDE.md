# CLAUDE.md — Project Rules for ShantiSangha

## Design System — Sacred Scripture Theme

All UI work MUST follow the Hindu scripture-inspired design language. This is a strict requirement for every frontend change.

### Icons
- Use `SacredIcons.vue` component (`src/components/icons/SacredIcons.vue`) for all navigation and feature icons
- Available icons: `om`, `dialogue`, `scroll`, `chakra`, `lotus`, `diya`, `shankha`
- NEVER use emojis as UI icons — add new SVG icons to `SacredIcons.vue` when needed
- Icon style: thin line-art (stroke-width 1.5), sacred geometry motifs

### Color Palette
- **Background:** Parchment gradient `#faf5ed → #f5ebe0 → #efe3d4`
- **Text primary:** `#2b1e10` (deep earth brown)
- **Text secondary:** `#6b5740` (warm brown)
- **Text muted:** `#9a8568`, `#b5996f`
- **Accent/active:** Saffron `#c4873b`, deep saffron `#8b5a1b`
- **Borders:** `rgba(139,90,43,0.12)` to `rgba(139,90,43,0.15)`
- **Cards/surfaces:** `rgba(250,245,237,0.88)` to `rgba(250,245,237,0.95)`
- **Active nav:** Gradient from `rgba(196,135,59,0.15)` with saffron left border
- NEVER use blue, green, or cold/tech-feeling colors

### Typography
- Headings: `font-serif`, `font-bold`, with `tracking-wide`
- Section labels: `text-[9px]` or `text-[10px]`, `uppercase`, `tracking-[0.2em]`, saffron/muted color
- Body text: default sans-serif, warm brown colors
- Quotes: `italic`, muted saffron tone (`#b5996f`)

### UI Elements
- Rounded corners: `rounded-xl` for nav items, `rounded-2xl` for cards
- Shadows: warm-toned `rgba(82,54,29,...)` — never cool grey shadows
- Dividers: dashed borders `border-dashed border-[rgba(139,90,43,0.12)]`
- Backdrop blur: `backdrop-blur-[20px]`
- Logo mark: Gradient circle `from-[#c4873b] to-[#8b5a1b]` with Om icon
- Include wisdom quotes (Hindu/Buddhist scripture) in footer areas and auth pages

### Tone
- The app should feel like reading a sacred text — serene, warm, grounded
- Avoid flashy animations, bright colors, or modern SaaS aesthetics
- Prefer subtle transitions (`duration-200`)
- Language should be gentle and reflective, not clinical or corporate

## Tech Stack
- **Frontend:** Vite + Vue 3 + TypeScript + Tailwind CSS v3 + Clerk auth
- **Backend:** ASP.NET Core .NET 8 + EF Core + PostgreSQL (pgvector) + Redis + Hangfire
- **Infrastructure:** AWS (ECS Fargate, RDS, ElastiCache, S3, CloudFront) + Terraform
- **CI/CD:** GitHub Actions (backend-deploy, frontend-deploy, terraform)

## API
- All API routes are under `/api` prefix
- Frontend calls `/api/*` (same origin via CloudFront)
- Auth: Clerk JWT with `MapInboundClaims = false` to preserve `sub` claim
- User resolution: `ICurrentUser` scoped service (auto-creates on first call)

## Deployment
- Push to `main` auto-triggers deploys (backend if `backend/**` changes, frontend if `frontend/**` changes)
- Terraform changes require manual `apply` via workflow dispatch
- Backend Deploy uses latest ECR image + latest task definition revision
- Frontend Deploy builds with `VITE_API_BASE_URL=/api`, syncs to S3, invalidates CloudFront
