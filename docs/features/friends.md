# Friends

## Purpose
Connect with people you trust and message them inside the app — text, images, and voice. This is the deliberate social surface; everything else in ShantiSangha remains a private solo space.

## Value
- Bring trusted people into your practice circle without leaking your solo records (journals, AI chats)
- Each message is deliberately authored for the recipient — a sharp boundary against the rest of your private content
- Privacy by default: friend messages bypass the AI entirely, are never embedded or indexed, and are hard-deleted when the friendship ends

## How it works
- A user invites a friend by generating a single-use link from the Friends tab
- The invite is shared via the iOS share sheet (iMessage, Mail, etc.) — Universal Link or `shantisangha://invite/{token}`
- The recipient taps the link, sees a preview of who invited them, and accepts
- Once connected, both users see each other in their Friends list and can open a 1:1 chat
- Chat supports text, images, voice messages, and replies to specific messages
- New messages produce a push notification when the app is backgrounded
- Either side can end the friendship at any time — the message thread and all media are hard-deleted on both sides

## What friends see / never see
- **See**: Display Name, messages sent to/from each other in the chat thread
- **Never see**: journal entries, AI chat history, voice notes (solo), reminders, calendar history

## Privacy guarantees
- Friend messages are NEVER sent to OpenAI / Anthropic / any model provider
- Messages are not embedded, summarized, or indexed
- Solo content remains scoped to `UserId` only — the Friends module never touches it
- Friendships are private to the pair — friend A cannot see who else is in your friend list
- Display Name is required before inviting

## Notifications
- Push alert on new friend message when app is backgrounded — body shows sender Display Name with a generic message preview for privacy
- Configurable via Settings: a single toggle "Notify me when friends message" (default ON)

## Surface
The app gains a 4th tab — Friends. The first three tabs (Home, Reflect, Journey) remain the solo practice loop. Friends is the deliberate social surface, gated by explicit consent.

## Key files
- Backend module: `backend/ShantiSangha.Friends/`
- iOS UI: `ios/ShantiSangha/Views/Friends/`
- iOS deep linking: `ios/ShantiSangha/Services/FriendsDeepLink.swift`, `DeepLinkRouter.swift`
- Universal Link manifest: `frontend/public/.well-known/apple-app-site-association`
- Storage: dedicated S3 bucket `shantisangha-friends-media-{account_id}` provisioned in `infrastructure/terraform/storage.tf`. Separate from the solo voice bucket so retention, IAM, and lifecycle can evolve independently. Backend reads `FRIENDS_MEDIA_BUCKET_NAME` env var (required, no silent fallback).

## API endpoints
- `GET /api/friends` — full friend list with display names and last-message previews
- `GET /api/friends/{friendshipId}` — single friend summary
- `POST /api/friends/invitations` — create invite
- `GET /api/friends/invitations` — list outgoing invites
- `DELETE /api/friends/invitations/{id}` — revoke invite
- `GET /api/friends/invitations/preview/{token}` — read-only preview for the accept screen
- `POST /api/friends/invitations/accept` — atomic accept
- `DELETE /api/friends/{friendshipId}` — end friendship (hard-delete thread + media)
- `GET /api/friends/{friendshipId}/messages?before={cursor}&limit={n}` — paginated message list
- `POST /api/friends/{friendshipId}/messages` — send a text message
- `POST /api/friends/{friendshipId}/messages/image/upload-url` — create a presigned image upload URL
- `POST /api/friends/{friendshipId}/messages/image` — commit an uploaded image message
- `POST /api/friends/{friendshipId}/messages/voice/upload-url` — create a presigned voice upload URL
- `POST /api/friends/{friendshipId}/messages/voice` — commit an uploaded voice message
- `POST /api/friends/{friendshipId}/messages/{messageId}/read` — mark a message as read
- `POST /api/friends/{friendshipId}/messages/read-through` — mark incoming messages through a cursor as read

Text and media send/commit requests may include `replyToMessageId`; responses include `replyPreview` so the client can render the parent context even if the original message is outside the loaded page.
