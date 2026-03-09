# Walkthrough: UI Localization, Timeline Reprocessing, and Disk Usage

## Overview
This update introduces full Korean localization support across the application, adds granular control for reprocessing timeline activities, and provides detailed disk usage statistics for recordings and timelapses.

## Changes

### 1. UI Localization
We have localized all major views to support both English and Korean based on the user's "Report Language" setting.

- **DashboardView**: Localized titles, charts, and stats cards.
- **AnalysisView**: Localized report generation controls and options.
- **SettingsView**: Localized all settings sections (General, AI Provider, Recording, Obsidian, Scheduler).
- **LogsView**: Localized log viewer interface.
- **TimelineView**: Localized timeline header, empty states, and card details.

### 2. Per-Card Reprocessing
Users can now reprocess individual timeline cards if the initial analysis was incorrect or incomplete.

- **TimelineCardView**: Added a "Reprocess" button (cycle arrow icon) to each card.
- **TimelineViewModel**: Implemented `reprocessCard(_:)` to reset the specific batch status and trigger the analysis job.
- **Visual Feedback**: The button shows a loading spinner while the card is being reprocessed.

### 3. Disk Usage Breakdown
The Storage settings now show separate usage statistics for raw recordings and generated timelapses.

- **SettingsView**: Updated `RecordingSettings` to display:
  - Recordings Usage (e.g., 1.2 GB / Max 10 GB)
  - Timelapses Usage (e.g., 500 MB / Max 10 GB)
- **StorageManager**: Added `currentRecordingUsageBytes()` to calculate recording folder size.
- **TimelapseStorageManager**: Utilized existing `currentUsageBytes()` for timelapse folder size.
- **Real-time Updates**: Usage stats update automatically when the settings view is open.

## Verification Results

### Build Verification
- **Command**: `xcodebuild -scheme DayArc -destination 'platform=macOS' build`
- **Result**: **BUILD SUCCEEDED**

### Manual Verification Steps
1.  **Localization**:
    -   Go to Settings > General > Report Language.
    -   Switch between "English" and "한국어".
    -   Verify that Dashboard, Analysis, Timeline, and Logs views update their text accordingly.
2.  **Timeline Reprocessing**:
    -   Go to Timeline view.
    -   Hover over a card (or look for the button).
    -   Click the "Reprocess" button.
    -   Verify the button turns into a spinner.
    -   Wait for a few seconds and verify the card updates (or the timeline refreshes).
3.  **Disk Usage**:
    -   Go to Settings > Recording (or Storage section).
    -   Verify that "Recordings" and "Timelapses" show separate usage values.
    -   Check if the values seem reasonable based on your usage.

## Next Steps
-   Test the reprocessing flow with actual data to ensure the backend analysis picks up the reset batch correctly.
-   Verify that the disk usage limits are actually enforced by the background cleanup tasks (this was existing logic, but good to verify since we touched the storage manager).
