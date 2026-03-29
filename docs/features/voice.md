# Voice Notes

## Purpose
Speak thoughts aloud when writing feels too heavy. Voice notes capture raw emotion in a way that typing often can't.

## Value
- Lower barrier than writing — just press record and talk
- Async transcription turns voice into searchable text
- Captures tone and nuance that gets lost in typed text
- Useful during commutes, walks, or moments when typing isn't practical

## How it works
- Browser MediaRecorder captures audio (WebM format)
- Two-step upload:
  1. `POST /api/voice/upload-url` → get presigned S3 URL + key
  2. Client uploads audio directly to S3 via presigned PUT
  3. `POST /api/voice/entries` → register entry in database
- Background job (`TranscribeVoiceJob`) transcribes audio asynchronously
- Entry status progresses: Pending → Transcribing → Completed (or Failed)
- Allowed formats: mp3, mp4, m4a, wav, webm, ogg

## Key files
- Frontend: `frontend/src/pages/app/voice/index.vue`
- Backend routes: `backend/ShantiSangha.Api/Routes/VoiceRoutes.cs`
- Storage: `backend/ShantiSangha.Infrastructure/Storage/StorageService.cs`
- Background job: `backend/ShantiSangha.Infrastructure/Jobs/TranscribeVoiceJob.cs`

## API endpoints
- `POST /api/voice/upload-url` — get presigned S3 upload URL
- `POST /api/voice/entries` — register voice entry after upload
- `GET /api/voice/entries` — list voice entries
- `GET /api/voice/entries/{id}` — get entry with transcript

## Q2 improvements planned
- Audio playback with waveform visualization
- Resume where you left off
- Voice-to-journal conversion (transcription → journal entry)
