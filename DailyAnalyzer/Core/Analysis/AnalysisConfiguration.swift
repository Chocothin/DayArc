//
//  AnalysisConfiguration.swift
//  DailyAnalyzer
//
//  Configuration object for AnalysisManager hardcoded values.
//  Centralizes timing and duration parameters for easy adjustment.
//

import Foundation

/// Configuration for the AnalysisManager's automatic analysis behavior.
/// All timing values are in seconds for consistency.
struct AnalysisConfiguration {

    // MARK: - Timing Configuration

    /// Interval between automatic analysis checks.
    /// Default: 60 seconds (checks every minute)
    var checkIntervalSeconds: TimeInterval

    /// Target duration for each analysis batch.
    /// Batches aim to group chunks into logical segments of this duration.
    /// Default: 900 seconds (15 minutes)
    var targetBatchDurationSeconds: TimeInterval

    /// Maximum lookback window for unprocessed chunks.
    /// Only chunks newer than (now - maxLookback) will be considered for processing.
    /// Default: 86400 seconds (24 hours)
    var maxLookbackSeconds: TimeInterval

    // MARK: - Batch Processing Configuration

    /// Minimum batch duration to process.
    /// Batches shorter than this will be skipped and marked as 'skipped_short'.
    /// Default: 300 seconds (5 minutes)
    var minimumBatchDurationSeconds: TimeInterval

    /// Maximum gap between chunks to group them into the same batch.
    /// If chunks are separated by more than this duration, they'll be split into separate batches.
    /// Default: 120 seconds (2 minutes)
    var maxChunkGapSeconds: TimeInterval

    // MARK: - Initializer

    /// Creates a configuration with custom values
    /// - Parameters:
    ///   - checkIntervalSeconds: Interval between automatic checks (default: 60)
    ///   - targetBatchDurationSeconds: Target batch duration (default: 900)
    ///   - maxLookbackSeconds: Maximum lookback window (default: 86400)
    ///   - minimumBatchDurationSeconds: Minimum batch duration (default: 300)
    ///   - maxChunkGapSeconds: Maximum gap between chunks (default: 120)
    init(
        checkIntervalSeconds: TimeInterval = 60,
        targetBatchDurationSeconds: TimeInterval = 900,
        maxLookbackSeconds: TimeInterval = 86400,
        minimumBatchDurationSeconds: TimeInterval = 300,
        maxChunkGapSeconds: TimeInterval = 120
    ) {
        self.checkIntervalSeconds = checkIntervalSeconds
        self.targetBatchDurationSeconds = targetBatchDurationSeconds
        self.maxLookbackSeconds = maxLookbackSeconds
        self.minimumBatchDurationSeconds = minimumBatchDurationSeconds
        self.maxChunkGapSeconds = maxChunkGapSeconds
    }

    // MARK: - Default Configuration

    /// Default configuration matching current AnalysisManager behavior:
    /// - Check interval: 60s (1 minute)
    /// - Target batch: 900s (15 minutes)
    /// - Max lookback: 86400s (24 hours)
    /// - Minimum batch: 300s (5 minutes)
    /// - Max chunk gap: 120s (2 minutes)
    static let `default` = AnalysisConfiguration()

    // MARK: - UserDefaults Persistence

    private enum Keys {
        static let checkInterval = "analysisConfig.checkIntervalSeconds"
        static let targetBatchDuration = "analysisConfig.targetBatchDurationSeconds"
        static let maxLookback = "analysisConfig.maxLookbackSeconds"
        static let minimumBatchDuration = "analysisConfig.minimumBatchDurationSeconds"
        static let maxChunkGap = "analysisConfig.maxChunkGapSeconds"
    }

    /// Loads configuration from UserDefaults, falling back to default values if not set
    static func loadFromUserDefaults() -> AnalysisConfiguration {
        let defaults = UserDefaults.standard

        // Only load if values have been explicitly set (non-zero)
        let checkInterval = defaults.double(forKey: Keys.checkInterval)
        let targetBatch = defaults.double(forKey: Keys.targetBatchDuration)
        let maxLookback = defaults.double(forKey: Keys.maxLookback)
        let minBatch = defaults.double(forKey: Keys.minimumBatchDuration)
        let maxGap = defaults.double(forKey: Keys.maxChunkGap)

        return AnalysisConfiguration(
            checkIntervalSeconds: checkInterval > 0 ? checkInterval : Self.default.checkIntervalSeconds,
            targetBatchDurationSeconds: targetBatch > 0 ? targetBatch : Self.default.targetBatchDurationSeconds,
            maxLookbackSeconds: maxLookback > 0 ? maxLookback : Self.default.maxLookbackSeconds,
            minimumBatchDurationSeconds: minBatch > 0 ? minBatch : Self.default.minimumBatchDurationSeconds,
            maxChunkGapSeconds: maxGap > 0 ? maxGap : Self.default.maxChunkGapSeconds
        )
    }

    /// Saves configuration to UserDefaults for persistence
    func saveToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(checkIntervalSeconds, forKey: Keys.checkInterval)
        defaults.set(targetBatchDurationSeconds, forKey: Keys.targetBatchDuration)
        defaults.set(maxLookbackSeconds, forKey: Keys.maxLookback)
        defaults.set(minimumBatchDurationSeconds, forKey: Keys.minimumBatchDuration)
        defaults.set(maxChunkGapSeconds, forKey: Keys.maxChunkGap)
    }

    /// Resets configuration to defaults and removes from UserDefaults
    static func resetToDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.checkInterval)
        defaults.removeObject(forKey: Keys.targetBatchDuration)
        defaults.removeObject(forKey: Keys.maxLookback)
        defaults.removeObject(forKey: Keys.minimumBatchDuration)
        defaults.removeObject(forKey: Keys.maxChunkGap)
    }
}

// MARK: - Convenience Computed Properties

extension AnalysisConfiguration {

    /// Check interval formatted as minutes (for display)
    var checkIntervalMinutes: Double {
        checkIntervalSeconds / 60
    }

    /// Target batch duration formatted as minutes (for display)
    var targetBatchDurationMinutes: Double {
        targetBatchDurationSeconds / 60
    }

    /// Max lookback formatted as hours (for display)
    var maxLookbackHours: Double {
        maxLookbackSeconds / 3600
    }

    /// Minimum batch duration formatted as minutes (for display)
    var minimumBatchDurationMinutes: Double {
        minimumBatchDurationSeconds / 60
    }

    /// Max chunk gap formatted as minutes (for display)
    var maxChunkGapMinutes: Double {
        maxChunkGapSeconds / 60
    }
}
