# CI/CD Setup

## Overview

This repository now includes GitHub Actions workflows for the `frontend/` Nuxt app.

### Included Workflows

- `frontend-ci.yml`
  - runs on every push to `main`
  - runs on every pull request
  - installs dependencies in `frontend/`
  - builds the app with Node 22

- `frontend-deploy.yml`
  - runs on pushes to `main`
  - can also be started manually with `workflow_dispatch`
  - deploys to Vercel when the required secrets are configured

## Required GitHub Secrets For Deployment

Add these repository secrets in GitHub:

- `VERCEL_TOKEN`
- `VERCEL_ORG_ID`
- `VERCEL_PROJECT_ID`

## Recommended Vercel Project Settings

- Framework preset: `Nuxt.js`
- Root directory: `frontend`
- Node version: `22`

## Notes

- CI is active as soon as the workflow files are pushed.
- Deployments will be skipped until the Vercel secrets are added.
- The app runtime expectation is pinned with:
  - `.nvmrc`
  - `frontend/.nvmrc`
  - `frontend/package.json` `engines.node`
