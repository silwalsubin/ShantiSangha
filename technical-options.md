# ShantiSangha Technical Options

## Purpose

This document outlines the best technical options for building ShantiSangha based on the product goals in `about.md`.

The focus here is on a stack that can support:

- emotional support conversations
- guided reflection
- journaling
- mood check-ins
- coping exercises
- conversation summaries
- saved insights
- voice journaling
- safety and support resource guidance

The goal is to choose a stack that is scalable, practical, and safe for a wellness-first product.

## What The Product Needs Technically

ShantiSangha is not just a chat app. It needs a system that can support:

- real-time and async user interactions
- persistent conversation and journaling history
- structured user memory and saved insights
- voice input and audio processing
- moderation and risk detection
- summaries and background processing
- product analytics and observability
- future personalization and habit-building features

This means the best stack should be strong in:

- developer speed
- AI integration
- data modeling
- background jobs
- safety workflows
- scalability over time

## Recommended Stack

This is the best default stack for ShantiSangha.

### Frontend

- `Next.js`
- `TypeScript`
- `Tailwind CSS`

#### Why

- fast to ship with
- excellent for modern web apps
- easy to build onboarding, chat, journaling, and dashboard-style interfaces
- strong ecosystem and deployment support

## Backend

### Recommended MVP Approach

- `Next.js` route handlers for the initial API layer

### Recommended Scalable Evolution

- move to a dedicated `Fastify` API service as backend complexity grows

#### Why

- Next.js routes are enough for early product speed
- Fastify gives a clean path for scaling APIs, jobs, integrations, and internal services
- this avoids overengineering too early while keeping a clear upgrade path

## Database

- `PostgreSQL`
- `pgvector`

#### Why

- strong relational model for users, sessions, journals, moods, insights, and safety events
- `pgvector` supports semantic retrieval for conversation memory and insight recall
- keeps structured and AI memory data in one place early on
- scales well before needing a dedicated vector database

## Authentication

- `Clerk` for fastest launch

### Alternative

- `Auth.js` if you want more control and less vendor dependency

#### Why

- ShantiSangha needs secure authentication, session handling, and simple onboarding
- Clerk is the quickest path for a polished authentication layer

## AI Layer

- OpenAI `Responses API`

#### Why

- best fit for conversational wellness interactions
- supports structured assistant behavior
- works well for summaries, reflection flows, and guided support
- good foundation for future tool-using workflows

### Recommended AI Responsibilities

Use the AI layer for:

- emotional support conversations
- guided reflection prompts
- journaling assistance
- summaries
- insight generation
- structured wellness support

Do not rely on the model alone for:

- safety enforcement
- crisis handling
- policy decisions

## Voice Stack

### Recommended Starting Approach

- async voice journaling

### Core Components

- speech-to-text for audio transcription
- text-based reflection and summarization
- optional text-to-speech for responses later

#### Why

- easier to build than live voice
- safer to monitor and evaluate
- directly supports the product goal of low-friction reflection

### Later Option

- Realtime voice experience for live conversations

This should come later, not in the first version.

## Background Jobs

- `BullMQ`
- `Redis`

#### Why

ShantiSangha will need background processing for:

- generating summaries
- extracting saved insights
- processing audio uploads
- running follow-up content generation
- retrying failed tasks
- scheduling nudges or wellness reminders later

This is one of the most important pieces for scalability.

## Storage

- `S3`-compatible object storage

#### Use Cases

- voice note uploads
- generated audio files
- exported user content
- internal processing artifacts if needed

## Observability and Product Analytics

### Recommended

- `Langfuse` or `Helicone` for AI traces and prompt analytics
- `PostHog` for product analytics
- internal audit/event tables in the database

#### Why

The product needs visibility into:

- prompt quality
- model failures
- safety events
- feature usage
- retention behavior
- conversation outcomes

## Safety Architecture

This is a core system requirement for ShantiSangha.

### Recommended Safety Pipeline

1. user sends message
2. moderation and risk checks run
3. product policy layer evaluates whether the message can proceed normally
4. assistant response is generated
5. response is reviewed for safety
6. user receives safe reply or support-resource escalation
7. structured event logs are stored

### Safety Systems Needed

- self-harm and distress detection
- escalation flows
- support-resource recommendations
- response-style constraints
- abuse and unsafe-content handling
- structured logging for sensitive events

## Data Model Requirements

At minimum, the product should support:

- users
- profiles
- conversations
- messages
- journals
- mood check-ins
- coping exercise sessions
- saved insights
- summaries
- voice entries
- safety events
- support resource events

### Memory Strategy

Do not depend only on raw chat history.

Use layered memory:

- recent messages
- conversation summaries
- saved personal insights
- mood trends
- journaling history
- user preferences

This will scale better and create a more coherent user experience.

## Deployment Options

### Option A: Startup-Friendly Deployment

- `Vercel` for the web app
- `Railway`, `Render`, or `Fly.io` for backend workers and queues
- managed Postgres and Redis

#### Best for

- fastest launch
- smallest ops burden
- early-stage validation

### Option B: More Controlled Scalable Deployment

- `AWS` for compute, storage, and managed databases

#### Best for

- stronger long-term infrastructure control
- more predictable enterprise scaling
- future compliance and security maturity

## Best Recommendation

For ShantiSangha, the best overall stack is:

- `Next.js`
- `TypeScript`
- `Tailwind CSS`
- `PostgreSQL`
- `pgvector`
- `Clerk`
- OpenAI `Responses API`
- `BullMQ`
- `Redis`
- `S3`-compatible storage
- `Langfuse` or `Helicone`
- `PostHog`
- `Vercel` plus worker hosting

This is the best fit because it balances:

- fast product development
- clean user experience delivery
- scalable AI workflows
- strong support for journaling and memory features
- background processing for summaries and voice
- a clear path to grow without rebuilding everything too early

## Technical Options By Stage

### Stage 1: MVP

- Next.js app
- Next.js route handlers
- Postgres
- pgvector
- Clerk
- Responses API
- BullMQ
- Redis
- S3 storage

### Stage 2: Growth

- split backend into dedicated Fastify service
- add deeper event pipelines
- add more personalized memory systems
- improve analytics and evaluation tooling
- scale worker infrastructure

### Stage 3: Advanced Platform

- live voice features
- more sophisticated recommendation systems
- deeper personalization and habit intelligence
- optional human support workflows
- stronger security and compliance posture if needed

## Alternative Stack Choices

### Alternative 1: All-In-One Fast Build

- Next.js
- Supabase
- OpenAI Responses API

#### Pros

- extremely fast to build
- fewer moving parts

#### Cons

- may become limiting sooner if background jobs and AI workflows get complex

### Alternative 2: Enterprise-Structured Stack

- Next.js frontend
- NestJS backend
- Postgres
- Redis
- S3
- AWS deployment

#### Pros

- strong backend structure
- easier for larger teams

#### Cons

- slower to launch
- more boilerplate and ops work

## Final Recommendation

The strongest technical choice for ShantiSangha is:

`Next.js + TypeScript + PostgreSQL + pgvector + Clerk + OpenAI Responses API + BullMQ + Redis + S3`

With this operating model:

- launch quickly with a web-first MVP
- keep safety systems outside the model
- use structured memory instead of only raw chat
- process summaries and audio asynchronously
- move to a dedicated backend service only when complexity truly requires it

This gives ShantiSangha the best combination of speed, scalability, and product fit.
