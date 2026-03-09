# DayArc

AI-powered daily activity analyzer for macOS. Automatically captures your screen at regular intervals, analyzes what you've been working on using LLMs, and generates structured daily reports.

## What It Does

DayArc runs in the background, takes periodic screenshots via ScreenCaptureKit, then sends batches to an LLM for analysis. The result is a timeline of your day — what apps you used, what you worked on, and how your time was spent — without manual tracking.

## Features

- **Automated Screen Capture** — Periodic screenshots at 1 fps using ScreenCaptureKit, organized into 15-minute batches
- **Multi-LLM Support** — Gemini, Claude, GPT-4o, Ollama (local). Switch providers anytime
- **Daily Dashboard** — Summary stats, productivity breakdown, category charts
- **Activity Timeline** — Hour-by-hour view of what you did, auto-categorized
- **On-Demand Analysis** — Re-analyze any time range with custom prompts
- **Obsidian Export** — Save daily reports as Markdown notes to your vault
- **Timelapse Video** — Generate timelapse from captured screenshots
- **Bilingual UI** — Korean / English
- **Privacy First** — All data stays local. API keys stored in Keychain. No telemetry

## Architecture

```
DailyAnalyzer/
├── Core/
│   ├── AI/            # LLM providers (Gemini, Ollama, prompt management)
│   ├── Analysis/      # Batch processing pipeline, activity classification
│   ├── Recording/     # ScreenCaptureKit integration, storage management
│   ├── Video/         # Timelapse generation
│   ├── Security/      # Keychain manager
│   └── Utilities/     # Analytics (local-only), migrations, versioning
├── Views/             # SwiftUI (Dashboard, Timeline, Analysis, Settings, Logs)
├── System/            # AppState, PermissionsManager
└── [top-level]        # Legacy providers, Markdown generators, Obsidian vault
```

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15+
- Screen Recording permission
- API key for at least one LLM provider (or Ollama running locally)

## Build

```bash
open DayArc.xcodeproj
# Build & Run (Cmd+R)
```

Or build a DMG for distribution:

```bash
./build_dmg.sh
```

## Setup

1. Launch DayArc
2. Grant Screen Recording permission when prompted
3. Go to **Settings** → configure your LLM provider and API key
4. Toggle recording on from the toolbar
5. Analysis runs automatically on a schedule, or trigger it manually from the **Analysis** tab

## Acknowledgements

Built with reference to [Dayflow](https://github.com/JerryZLiu/Dayflow) (MIT License, Copyright 2025 Jerry Liu). Dayflow's source is included under `Dayflow/` for reference.

## License

MIT
