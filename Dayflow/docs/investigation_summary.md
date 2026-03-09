# Dayflow Architecture & Data Flow (Investigation Notes)

## High-Level Flow
- Screen recording runs continuously (1 fps, 15 s segments) via `ScreenRecorder`; segments saved as mp4 under `~/Library/Application Support/Dayflow/recordings` and indexed in SQLite (`chunks`).
- `AnalysisManager` batches completed chunks into ~15 min windows and hands each batch to `LLMService`.
- `LLMService` stitches batch video, calls configured LLM provider for transcription/observations, then generates/updates timeline cards; batches marked processed in DB.
- Timelapse videos generated per card and stored under `~/Library/Application Support/Dayflow/timelapses/{yyyy-MM-dd}/`.
- UI pulls timeline cards from DB per day (4 AM boundary) and renders in Canvas timeline; overlap resolution is display-only.

## Recording Pipeline
- `Core/Recording/ScreenRecorder.swift`
  - Uses ScreenCaptureKit; state machine (idle/starting/recording/finishing/paused).
  - Captures active display at ~1080p, 1 fps; 15 s chunks via `AVAssetWriter`.
  - Reacts to display changes, sleep/lock/screensaver; auto-pause/resume; retries transient SCStream errors; marks user-initiated stops.
  - Registers chunks in DB (`registerChunk`, `markChunkCompleted/Failed`) through `StorageManager`.
- Storage paths/limits: base dir `Application Support/Dayflow`; recordings and timelapses subfolders; storage limits in `StoragePreferences`.

## Database & Storage
- `Core/Recording/StorageManager.swift` (GRDB SQLite, WAL mode).
- Tables (key fields):
  - `chunks(id, start_ts, end_ts, file_url, status, is_deleted)`
  - `analysis_batches(id, batch_start_ts, batch_end_ts, status, reason, llm_metadata, detailed_transcription, created_at)`
  - `batch_chunks(batch_id, chunk_id)`
  - `timeline_cards(id, batch_id, start/end, start_ts/end_ts, day, title, summary, category, subcategory, detailed_summary, metadata(distractions/apps), video_summary_url, is_deleted)`
  - `observations(id, batch_id, start_ts, end_ts, observation, metadata, llm_model)`
  - `llm_calls(...)` audit log for all LLM requests.
- Key APIs:
  - Chunk lifecycle: `nextFileURL`, `registerChunk`, `markChunkCompleted/Failed`, `fetchUnprocessedChunks`, `chunksForBatch`, `fetchChunksInTimeRange`.
  - Batching: `saveBatch`, `updateBatchStatus/markBatchFailed`, `allBatches`, `resetBatchStatuses`, `deleteTimelineCards/Observations`.
  - AI data: `saveObservations/fetchObservations*`, `updateBatchLLMMetadata/fetchBatchLLMMetadata`, `insertLLMCall`, `fetchLLMCalls*`.
  - Timeline: `saveTimelineCardShell`, `updateTimelineCardVideoURL`, `replaceTimelineCardsInRange` (soft-delete overlap, returns deleted video paths), `fetchTimelineCards(forDay/byTimeRange/byId)`.
- Purge: hourly purge for recordings; separate timelapse purge via `TimelapseStorageManager` (size-based, oldest-first).

## Analysis & Scheduling
- `Core/Analysis/AnalysisManager.swift`
  - Timer every 60s; builds ~15 min batches from completed chunks (looks back 24h).
  - Skips batches <5 min (`skipped_short`); sets status in DB; Sentry transaction per batch.
  - Calls `llmService.processBatch`; on success generates timelapses for each card (stitches relevant chunks, 20x speed, 24 fps) and updates `video_summary_url`.
  - Reprocessing helpers for a day or specific batches: deletes cards/videos/observations, resets batch statuses, reruns batches sequentially with progress callbacks.

## LLM Service & Providers
- `Core/AI/LLMService.swift`
  - Provider selection from `llmProviderType` (UserDefaults): `.geminiDirect`, `.dayflowBackend` (stub), `.ollamaLocal`, legacy migration from chat cli.
  - `processBatch`: stitch chunk files → provider `transcribeVideo` → `saveObservations`; if empty, mark analyzed. Otherwise build sliding 1h window context (recent observations + existing cards + categories) → provider `generateActivityCards` → replace cards in that window (`replaceTimelineCardsInRange`) and delete obsolete timelapses. Marks batch analyzed, captures analytics.
  - Friendly error mapping; logs via `AnalyticsService` and `LLMLogger`.
- Logging: `Core/AI/LLMLogger.swift` sanitizes URLs/headers/bodies, writes to `llm_calls`, fires analytics `llm_api_call`.

### Gemini Direct (cloud)
- `Core/AI/GeminiDirectProvider.swift`
  - Uploads stitched mp4 to Google Generative Language API (resumable first, fallback simple upload).
  - Transcription prompt: enforce exact video duration, 3–5 segments/15 min, idle detection, purpose-based grouping; JSON array `{startTimestamp,endTimestamp,description}`.
  - Card prompt: “digital anthropologist” tone; cards 10–60 min; category list from user config; includes distractions/appSites; strict JSON.
  - Retry/backoff by error class; partial 503 JSON salvage; model fallback; sensitive field redaction in logs.

### Local (Ollama / LM Studio / custom)
- `Core/AI/OllamaProvider.swift`
  - Extracts frames every 60s, describes each via local OpenAI-compatible endpoint; merges to observations.
  - Card generation: title/summary, category normalization, optional merge with previous card (LLM check, caps >60 min), otherwise append.
  - `callOllamaAPI` shared HTTP layer with 3 attempts, 2/4/8s backoff; logs via `LLMLogger` but avoids persisting base64 frame payloads.
  - Model ID/engine/API key from UserDefaults; supports custom engine analytics tagging.

### Dayflow Backend
- `Core/AI/DayflowBackendProvider.swift` is stubbed (`fatalError` in methods).

## UI Consumption
- `Views/UI/CanvasTimelineDataView.swift`
  - Loads `timeline_cards` for a day (4 AM boundary), maps to `TimelineActivity`, resolves overlap visually, renders cards on canvas grid; 60s refresh timer; today view auto-scrolls near current time; shows recording status pulse.
  - Uses `CategoryStore` for colors/idle, `FaviconService` to fetch favicons, `selectedActivity` binding for detail selection.
- `Views/UI/MainView.swift`
  - Houses timeline tab with date navigation, recording toggle (AppState), category filter, and embeds Canvas timeline view.

## Permissions & Startup
- `App/AppDelegate.swift`
  - Initializes Sentry/PostHog, migrates onboarding state, sets up `ScreenRecorder` with auto-start based on onboarding completion and saved preference; gate on ScreenCaptureKit permission.
  - Starts analysis job after short delay; observes recording toggle for analytics; handles termination and deep links.

## Storage Cleanup
- Recordings: managed by `StorageManager.purgeIfNeeded` (timer-based).
- Timelapses: `TimelapseStorageManager` enforces byte limit, deletes oldest files first when over limit.

## Notable Behaviors
- Sliding 1-hour card regeneration keeps recent timeline coherent across batches.
- Overlap resolution in UI only; DB data remains as generated.
- Timelapse generation per card is asynchronous and paths are persisted to `timeline_cards.video_summary_url`.
- LLM call logs sanitize secrets; base64 frame data is not stored.
