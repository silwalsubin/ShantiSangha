# AI Therapy Web App: Technical Stack Research and Options

## Purpose

This document summarizes the technical stack options, product constraints, and implementation tradeoffs for building an AI-powered therapy-style web application.

It is written to help choose between a faster wellness-focused MVP and a more compliance-heavy clinical platform.

## Current Product Preference

The chosen direction for this project is:

- `Wellness / emotional support app`
- `Final brand name: ShantiSangha`

This means the product should be framed around:

- emotional support
- guided reflection
- journaling
- self-help exercises
- mood support
- wellness coaching

This also means the product should avoid positioning itself as:

- a licensed therapist
- a clinical treatment platform
- a diagnostic tool
- a crisis hotline

## Executive Summary

The most important early decision is not frontend vs backend framework. It is product scope:

1. `Wellness / emotional support app`
2. `Clinical therapy platform`

That choice changes:

- compliance requirements
- vendor selection
- data handling
- hosting strategy
- AI feature boundaries
- operational risk

### Recommended Starting Path

For a first version, the strongest option is:

- Position the product as `AI emotional support`, `guided reflection`, `journaling`, `CBT-style exercises`, and `self-help coaching`
- Avoid claiming it is a licensed therapist or clinical treatment tool
- Build with a modern TypeScript web stack
- Use OpenAI `Responses API` for the conversational intelligence layer
- Add explicit safety and escalation systems outside the model

This gives the best speed-to-market while still leaving room to evolve toward a more regulated product later.

### Status

This recommendation is now the selected path for the project.

## Product Positioning Options

### Option A: Wellness MVP

This product focuses on:

- emotional support
- journaling
- mood tracking
- reflection prompts
- habit formation
- guided exercises
- non-diagnostic mental wellness conversations

#### Benefits

- faster to ship
- lower compliance burden
- easier vendor flexibility
- lower legal and operational risk
- easier UX experimentation

#### Risks

- must avoid presenting the app as a licensed therapist
- must handle crisis situations carefully
- still requires strong privacy and safety practices

### Option B: Clinical Therapy Platform

This product may involve:

- licensed therapist workflows
- clinical notes
- diagnoses
- treatment plans
- PHI and HIPAA obligations
- provider dashboards
- appointments and care coordination

#### Benefits

- higher enterprise and healthcare value
- clearer path to payer/provider partnerships
- stronger defensibility if executed well

#### Risks

- much slower to launch
- significantly more compliance and vendor review
- more legal, operational, and support burden
- more complex audit, access control, and retention requirements

### Chosen Direction

Choose `Option A: Wellness MVP`.

Keep the brand, product copy, onboarding, and safety design aligned with a wellness-first scope.

## Core Architecture Recommendation

If starting from scratch, a practical architecture is:

- Frontend: `Next.js` + `TypeScript`
- Styling: `Tailwind CSS`
- Backend: `Next.js` server routes initially, then separate API service when needed
- Database: `PostgreSQL`
- Semantic retrieval: `pgvector`
- Auth: `Clerk` or `Auth.js`
- Background jobs: `BullMQ` + `Redis`
- Object storage: `S3`-compatible storage
- Observability: `Langfuse` or `Helicone` plus internal audit tables
- AI orchestration: OpenAI `Responses API`

### Why This Stack

- TypeScript across frontend and backend reduces context switching
- Next.js is fast for shipping product and admin surfaces
- Postgres keeps primary data and vector search in one place at the beginning
- BullMQ handles summaries, retries, follow-up jobs, and async processing cleanly
- This stack is popular, well-supported, and practical for a small team

## Frontend Options

### Option 1: Next.js

#### Best for

- shipping quickly
- web-first product
- auth-heavy experiences
- dashboards
- SSR and SEO if needed

#### Pros

- large ecosystem
- good DX
- easy integration with auth, payments, and APIs
- ideal for startup velocity

#### Cons

- can become messy if API and background logic grow too large inside the app

### Option 2: React SPA + Separate Backend

#### Best for

- teams that want stricter separation from day one

#### Pros

- cleaner service boundaries
- can simplify scaling later

#### Cons

- slower initial development
- more deployment and API wiring overhead

### Recommendation

Choose `Next.js` first unless the team already has a strong reason to separate frontend and backend immediately.

## Backend Options

### Option 1: Next.js Route Handlers for MVP

#### Best for

- early product phase
- small team
- low operational overhead

#### Pros

- fastest path to first release
- fewer repos and services
- easier iteration

#### Cons

- background workflows and complex domain logic may outgrow this setup

### Option 2: Fastify API

#### Best for

- performance-conscious backend
- teams that want a lightweight but structured Node service

#### Pros

- fast
- flexible
- lower overhead than heavier frameworks

#### Cons

- less opinionated structure than NestJS

### Option 3: NestJS API

#### Best for

- larger codebase
- more developers
- strongly structured backend

#### Pros

- strong architecture conventions
- good fit for enterprise-ish services
- easier dependency injection and modularization

#### Cons

- more boilerplate
- slower for very early MVP work

### Recommendation

Start with `Next.js` route handlers for MVP and move to `Fastify` or `NestJS` only when:

- jobs become complex
- API boundaries become crowded
- admin and internal tooling expand
- multiple teams need stronger separation

## Database Options

### Option 1: PostgreSQL + pgvector

#### Best for

- most early-stage products
- single source of truth
- semantic memory and search

#### Pros

- mature and reliable
- relational plus vector support
- reduces architectural sprawl

#### Cons

- not the best fit forever if vector workloads become very large

### Option 2: PostgreSQL + Dedicated Vector DB

Examples:

- Pinecone
- Weaviate
- Qdrant

#### Best for

- larger semantic search workloads
- teams that already know they need advanced retrieval tuning

#### Pros

- more specialized vector capabilities

#### Cons

- more infrastructure complexity
- another bill and vendor

### Recommendation

Choose `PostgreSQL + pgvector` first.

## AI Layer Options

### Option 1: OpenAI Responses API

#### Best for

- chat experiences
- tool use
- structured workflows
- stateful assistant behavior

#### Pros

- current core API direction for conversational and agentic workflows
- suitable for structured conversation systems
- easier to evolve into tool-using assistants

#### Cons

- requires deliberate prompt, memory, and safety architecture

### Option 2: Realtime API

#### Best for

- live voice sessions
- low-latency conversational UX

#### Pros

- better for natural speech-based interaction
- useful for voice therapy-style experiences

#### Cons

- more complexity than text-first MVP
- harder to control and QA than async text flows

### Recommendation

Use `Responses API` for the core MVP.

Add `Realtime API` later if live voice sessions become a core product feature.

## Voice Feature Options

### Option 1: Async Voice Journaling

Pipeline:

- user records audio
- app uploads audio
- speech-to-text transcribes it
- model summarizes, reflects, and responds
- text-to-speech optionally reads response aloud

#### Best for

- lower complexity
- safer reviewability
- easier product iteration

### Option 2: Live Voice Companion

Pipeline:

- real-time microphone input
- low-latency streaming model
- interruption handling
- streaming audio output

#### Best for

- higher-engagement product experiences
- premium-feeling assistant UX

#### Tradeoff

This is much harder operationally and from a safety perspective.

### Recommendation

Start with `async voice journaling`, not live voice.

## Authentication and Identity

### Option 1: Clerk

#### Pros

- fast setup
- polished auth UX
- easy social and magic-link support

#### Cons

- another vendor dependency

### Option 2: Auth.js

#### Pros

- flexible
- code-first
- good fit in Next.js ecosystems

#### Cons

- more implementation work

### Recommendation

Use `Clerk` if speed matters most.

Use `Auth.js` if you want tighter control and lower long-term vendor lock-in.

## Hosting Options

### Option 1: Vercel + Managed Add-ons

#### Best for

- rapid web product launch

#### Pros

- very fast deployment flow
- excellent Next.js fit

#### Cons

- may not be the final answer if strong compliance controls are required

### Option 2: AWS-Centric Stack

Examples:

- ECS or EKS
- RDS Postgres
- ElastiCache Redis
- S3
- CloudFront

#### Best for

- longer-term compliance posture
- infrastructure control

#### Pros

- flexible
- enterprise-friendly
- easier to build toward strict compliance requirements

#### Cons

- more DevOps burden

### Option 3: Fly.io / Railway / Render

#### Best for

- lean startup operations

#### Pros

- simpler than AWS
- easier worker deployments than purely serverless setups

#### Cons

- may need migration later depending on compliance needs

### Recommendation

For a wellness MVP:

- `Vercel` for the web app
- `Railway`, `Render`, or `Fly.io` for API workers if needed

For a clinical product:

- lean toward `AWS`

## Safety Architecture

This is the most important system outside the core product UX.

The model should not be the only safety mechanism.

### Recommended Safety Pipeline

1. receive user message
2. run moderation / risk classification
3. run app policy checks for crisis and disallowed cases
4. generate assistant response
5. run post-generation safety review
6. return response or escalation flow
7. log structured risk metadata and outcomes

### Safety Systems To Build

- crisis intent detection
- self-harm escalation flows
- age-related policy handling
- abuse and violence escalation
- hallucination-resistant prompting
- response style constraints
- emergency resource handoff logic
- admin review and audit tools

### Product Boundary Recommendation

Do not market the app as:

- a licensed therapist
- a crisis hotline
- a diagnostic tool

Instead market it as:

- emotional support
- guided reflection
- wellness coaching
- self-help companion

unless the company is ready to operate as a regulated clinical product.

## Data and Memory Design

Avoid storing the entire raw conversation as the only memory strategy.

Use layered memory:

- raw messages
- structured session summaries
- user profile traits and preferences
- safety events
- journaling entries
- explicit saved insights

### Recommendation

Store memory in structured tables and use retrieval selectively. This is safer, cheaper, and easier to reason about than replaying unlimited raw chat history.

## Compliance and Privacy Considerations

### If Building a Wellness Product

You still need:

- strong privacy policy
- data minimization
- deletion flows
- secure storage
- access controls
- incident response thinking

### If Building a Clinical Product

You likely need:

- HIPAA-aligned architecture
- BAAs with applicable vendors
- stricter audit logging
- least-privilege access control
- data retention policy
- formal vendor review
- stronger legal review

### Important OpenAI Considerations

OpenAI documentation indicates:

- `/v1/responses` can be eligible for Zero Data Retention in qualified setups
- `/v1/realtime` can also be eligible for Zero Data Retention
- some capabilities are not HIPAA eligible
- `background=true` is not Zero Data Retention compatible
- web search is listed as not HIPAA eligible

This means the exact product architecture must be selected carefully if the app may handle PHI.

## Practical Stack Packages

### Package A: Fastest Wellness MVP

- Next.js
- TypeScript
- Tailwind CSS
- Postgres
- pgvector
- Clerk
- OpenAI Responses API
- BullMQ + Redis
- S3-compatible storage
- Vercel + worker host

#### Best for

- solo founder
- small startup team
- shipping in weeks

### Package B: Balanced Startup Platform

- Next.js frontend
- Fastify API
- Postgres
- pgvector
- Auth.js or Clerk
- Redis
- BullMQ
- OpenAI Responses API
- observability platform
- AWS or Fly.io / Render deployment mix

#### Best for

- small team expecting growth
- moderate backend complexity
- cleaner separation than all-in-one Next.js

### Package C: Compliance-Forward Clinical Stack

- Next.js frontend
- NestJS or Fastify backend
- Postgres
- pgvector
- Redis
- S3
- AWS-centric deployment
- OpenAI API only where vendor and feature eligibility match compliance needs
- full audit/event system
- role-based admin and clinician tools

#### Best for

- healthcare partnerships
- PHI-heavy workflows
- longer-term regulated roadmap

### Selected Package

Choose `Package A: Fastest Wellness MVP`.

This is the best fit for the current product preference and gives the cleanest path to shipping a useful first version quickly.

## Recommendation Matrix

### Choose Package A if

- speed matters most
- the product is clearly wellness-first
- the team is small
- you want to validate demand before heavy compliance investment

### Choose Package B if

- you want startup speed with somewhat cleaner backend boundaries
- you expect jobs, analytics, and integrations to grow quickly

### Choose Package C if

- the app is intended to support clinical workflows
- PHI handling is core from the start
- enterprise healthcare readiness matters early

## My Recommendation

The best default choice is `Package A`, with the following product framing:

`AI-powered emotional support and guided self-reflection app`

That gives you:

- fastest build velocity
- lower regulatory exposure
- strongest learning loop
- simplest path to launching and iterating

Then, if traction proves the market, evolve toward `Package B` or `Package C`.

## Naming Direction

Since the product is now clearly a wellness and emotional support app, the name should feel:

- calming
- trustworthy
- warm
- simple to remember
- non-clinical
- non-corny
- emotionally safe

The name should avoid sounding like:

- a hospital product
- a diagnosis tool
- a meditation clone
- a generic AI chatbot
- an app that overpromises therapy outcomes

### Final Naming Decision

The final selected name for the product is:

- `ShantiSangha`

### Why ShantiSangha Works

- `Shanti` brings a calm, peaceful, Sanskrit-inspired emotional tone
- `Sangha` suggests community, support, and shared human connection
- the name feels supportive and non-clinical
- it is more distinctive than plain `Shanti`
- it avoids sounding like a generic AI utility

### Brand Interpretation

`ShantiSangha` can be understood as a calm and supportive community-centered brand for emotional well-being, reflection, and everyday mental wellness.

### Good Naming Directions

#### Direction 1: Calm and supportive

Examples of style:

- gentle
- grounding
- emotionally warm

Example names:

- `Harbor`
- `Haven`
- `Solace`
- `Ember`
- `Luma`
- `Kindred`

#### Direction 2: Reflection and growth

Examples of style:

- introspective
- thoughtful
- personal growth oriented

Example names:

- `Reflectly`
- `Innerpath`
- `Northwell`
- `Mosaic`
- `Stillpoint`
- `Tend`

#### Direction 3: Companion and support

Examples of style:

- friendly
- close
- human-centered

Example names:

- `Alongside`
- `WithYou`
- `Sideby`
- `Companion`
- `Kin`
- `Nearby`

#### Direction 4: Modern wellness brand

Examples of style:

- startup-friendly
- clean
- brandable

Example names:

- `Avela`
- `Elara`
- `Sora`
- `Lunara`
- `Avira`
- `Nomi`

### Strongest Early Name Candidates

If choosing based on brand flexibility, warmth, and wellness fit, the strongest candidates are:

1. `ShantiSangha`
2. `Harbor`
3. `Tend`
4. `Stillpoint`
5. `Kindred`

### Naming Recommendation

The strongest naming direction is:

- `ShantiSangha` as the final chosen brand for the product

Supporting interpretation:

- `ShantiSangha` works best if you want calm, emotional support, and a more relational wellness identity with Sanskrit flavor

### Naming Checklist

Before finalizing the name, validate:

- domain availability
- social handle availability
- trademark risk
- pronunciation simplicity
- whether users immediately understand the emotional tone
- whether the name still works if the product expands later

### Working Positioning Line

Example positioning line for the brand:

`ShantiSangha is a wellness companion for emotional support, reflection, and everyday mental well-being.`

## Current Decision Snapshot

The current preferred path is:

- Product type: `Wellness / emotional support app`
- Stack package: `Package A`
- AI approach: `OpenAI Responses API`
- Product posture: `text-first MVP with safety guardrails`
- Final brand name: `ShantiSangha`

## Suggested MVP Feature Set

- onboarding with consent and clear product boundaries
- chat-based reflection assistant
- journaling
- mood check-ins
- coping exercises
- conversation summaries
- saved insights
- basic voice journaling
- safety escalation and support resources

## Suggested Post-MVP Features

- memory personalization
- therapist marketplace or human escalation
- session history insights
- goals and habit plans
- more advanced voice experience
- clinician or coach dashboard
- care-team collaboration if moving clinical

## Sources

OpenAI and health/privacy guidance referenced during this research:

- OpenAI API data controls guide: https://developers.openai.com/api/docs/guides/your-data
- OpenAI background mode guide: https://developers.openai.com/api/docs/guides/background
- OpenAI Realtime guide: https://developers.openai.com/api/docs/guides/realtime
- OpenAI speech-to-text guide: https://developers.openai.com/api/docs/guides/speech-to-text
- OpenAI text-to-speech guide: https://developers.openai.com/api/docs/guides/text-to-speech
- OpenAI HIPAA / BAA help article: https://help.openai.com/en/articles/8660679-how-can-i-get-a-business-associate
- HHS HIPAA cloud computing guidance: https://www.hhs.gov/hipaa/for-professionals/special-topics/health-information-technology/cloud-computing/index.html

## Decision Prompt

If choosing a direction now, the strongest decision is:

1. Start with `Package A`
2. Position the product as `wellness`, not `clinical therapy`
3. Build a text-first MVP
4. Add async voice journaling second
5. Reassess compliance architecture after real user demand
