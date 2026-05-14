# User Search

## Purpose
Find people on ShantiSangha by name and (optional) location, so you can connect with friends you remember by name but not by phone/email.

## Value
- Discovery without out-of-band sharing — no need to swap invite links over text first
- Combined free-text name + free-text location keeps the UI simple while giving the user enough specificity to disambiguate common names
- Existing friends are filtered out so search is a clean "find new people" surface, not a re-discovery of your current circle

## How it works
- A "Find people" entry on the Friends tab pushes a search screen
- Two text fields: name (required, fuzzy substring match on display name) and an optional "where" field that matches `Country` OR `State` OR `City`
- Backend returns paginated results with display name, avatar, and location (city/state/country as set)
- Tap a result → read-only profile preview sheet (display name, avatar, location)
- Connect/friend-request action is stubbed in v1 — wired up in a follow-up

## What search shows / never shows
- **Shows**: Display Name, avatar (or default initials circle), city/state/country
- **Never shows**: email, friend list, messages, journals, AI chats, voice notes, reminders, push tokens, or anything other than the four fields above

## Filters
- Existing friends are excluded from results
- The current user is excluded (you don't appear in your own search)
- Both filters happen server-side — the iOS layer doesn't need to know who's a friend

## Pagination
- Default page size 20, capped at 50
- Backend returns `totalCount` + `hasMore` so the UI can render counts and trigger infinite scroll
- iOS triggers the next page when the user scrolls within 5 rows of the loaded set's end

## Backend storage
- New EF migration adds the Postgres `pg_trgm` extension and a GIN trigram index on `Profiles.DisplayName` for fast substring search
- Lowercased B-tree indexes on `Profiles.Country`, `State`, `City` keep the location filter cheap

## Key files
- Backend service: `backend/ShantiSangha.Identity/Services/UserSearchService.cs`
- Backend controller: `backend/ShantiSangha.Identity/Controllers/UserSearchController.cs`
- Friends interop: `backend/ShantiSangha.Shared/Interfaces/IFriendsQueryService.cs` (implemented in `backend/ShantiSangha.Friends/Services/FriendsQueryService.cs`)
- Migration: `backend/ShantiSangha.Identity/Migrations/20260425120000_AddUserSearchIndexes.cs`
- iOS UI: `ios/ShantiSangha/Views/Friends/UserSearchView.swift`, `UserProfilePreviewSheet.swift`
- iOS shared avatar component: `ios/ShantiSangha/Views/Components/SacredAvatar.swift`

## API endpoints
- `GET /api/users/search?q={name}&location={loc}&page=1&pageSize=20` — paginated search

## Known limitations
- The location field is literal substring matching, not synonym resolution. "United States" won't match `Country = "USA"`. Revisit if it becomes a real complaint.
- No "block" or "hide me from search" toggle in v1. Add later if the open directory turns out to be too open for some users.
