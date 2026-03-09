//
//  AnalysisManager.swift
//  Dayflow
//
//  Re‑written 2025‑05‑07 to use the new `GeminiServicing.processBatch` API.
//  • Drops the per‑chunk URL plumbing – the service handles stitching/encoding.
//  • Still handles batching logic + DB status updates.
//  • Keeps the public `AnalysisManaging` contract unchanged.
//
import Foundation
import AVFoundation
import GRDB



protocol AnalysisManaging {
    func startAnalysisJob()
    func stopAnalysisJob()
    func triggerAnalysisNow()
    func reprocessDay(_ day: String, progressHandler: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void)
    func reprocessSpecificBatches(_ batchIds: [Int64], progressHandler: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void)
}

// MARK: - Analysis Configuration

/// Configuration for AnalysisManager timing and batch processing parameters.
/// Centralizes hardcoded values for easy adjustment and future customization.
struct AnalysisConfiguration {
    /// Interval between automatic analysis checks (default: 60s)
    var checkIntervalSeconds: TimeInterval
    /// Target duration for each analysis batch (default: 900s / 15 min)
    var targetBatchDurationSeconds: TimeInterval
    /// Maximum lookback window for unprocessed chunks (default: 86400s / 24 hours)
    var maxLookbackSeconds: TimeInterval
    /// Minimum batch duration to process (default: 300s / 5 min)
    var minimumBatchDurationSeconds: TimeInterval
    /// Maximum gap between chunks to group them (default: 120s / 2 min)
    var maxChunkGapSeconds: TimeInterval

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

    static let `default` = AnalysisConfiguration()

    /// Loads configuration from UserDefaults, falling back to defaults if not set
    static func loadFromUserDefaults() -> AnalysisConfiguration {
        let defaults = UserDefaults.standard
        let checkInterval = defaults.double(forKey: "analysisConfig.checkIntervalSeconds")
        let targetBatch = defaults.double(forKey: "analysisConfig.targetBatchDurationSeconds")
        let maxLookback = defaults.double(forKey: "analysisConfig.maxLookbackSeconds")
        let minBatch = defaults.double(forKey: "analysisConfig.minimumBatchDurationSeconds")
        let maxGap = defaults.double(forKey: "analysisConfig.maxChunkGapSeconds")

        return AnalysisConfiguration(
            checkIntervalSeconds: checkInterval > 0 ? checkInterval : Self.default.checkIntervalSeconds,
            targetBatchDurationSeconds: targetBatch > 0 ? targetBatch : Self.default.targetBatchDurationSeconds,
            maxLookbackSeconds: maxLookback > 0 ? maxLookback : Self.default.maxLookbackSeconds,
            minimumBatchDurationSeconds: minBatch > 0 ? minBatch : Self.default.minimumBatchDurationSeconds,
            maxChunkGapSeconds: maxGap > 0 ? maxGap : Self.default.maxChunkGapSeconds
        )
    }
}


final class AnalysisManager: AnalysisManaging {
    static let shared = AnalysisManager()
    private let videoProcessingService: VideoProcessingService

    // MARK: - Static DateFormatter (cached for performance)

    /// Cached formatter for clock time (e.g., "11:37 AM")
    private static let clockTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private init() {
        store = StorageManager.shared
        llmService = LLMService.shared
        videoProcessingService = VideoProcessingService()
        config = AnalysisConfiguration.loadFromUserDefaults()
    }

    private let store: any StorageManaging
    private let llmService: any LLMServicing
    private let config: AnalysisConfiguration

    private var analysisTimer: Timer?
    private var isProcessing = false
    private let queue = DispatchQueue(label: "com.dayflow.geminianalysis.queue", qos: .utility)


    func startAnalysisJob() {
        #if DEBUG
        print("🔵 [AnalysisManager] startAnalysisJob() called")
        #endif
        stopAnalysisJob()               // ensure single timer
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            #if DEBUG
            print("🔵 [AnalysisManager] Setting up timer with interval: \(self.config.checkIntervalSeconds)s")
            #endif
            self.analysisTimer = Timer.scheduledTimer(timeInterval: self.config.checkIntervalSeconds,
                                                       target: self,
                                                       selector: #selector(self.timerFired),
                                                       userInfo: nil,
                                                       repeats: true)
            #if DEBUG
            print("🔵 [AnalysisManager] Timer created, triggering immediate analysis")
            #endif
            self.triggerAnalysisNow()   // immediate run
        }
    }

    func stopAnalysisJob() {
        analysisTimer?.invalidate(); analysisTimer = nil
    }

    func triggerAnalysisNow() {
        #if DEBUG
        print("🟢 [AnalysisManager] triggerAnalysisNow() called, isProcessing: \(isProcessing)")
        #endif
        guard !isProcessing else {
            #if DEBUG
            print("⚠️ [AnalysisManager] Already processing, skipping")
            #endif
            return
        }
        #if DEBUG
        print("🟢 [AnalysisManager] Queuing processRecordings()")
        #endif
        queue.async { [weak self] in self?.processRecordings() }
    }
    
    func reprocessDay(_ day: String, progressHandler: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { 
                completion(.failure(NSError(domain: "AnalysisManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager deallocated"])))
                return 
            }
            
            let overallStartTime = Date()
            var batchTimings: [(batchId: Int64, duration: TimeInterval)] = []
            
            DispatchQueue.main.async { progressHandler("Preparing to reprocess day \(day)...") }
            
            // 1. Delete existing timeline cards and get video paths to clean up
            let videoPaths = self.store.deleteTimelineCards(forDay: day)
            
            // 2. Clean up video files
            for path in videoPaths {
                if let url = URL(string: path) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            DispatchQueue.main.async { progressHandler("Deleted \(videoPaths.count) video files") }
            
            // 3. Get all batch IDs for the day before resetting
            let batches = self.store.fetchBatches(forDay: day)
            let batchIds = batches.map { $0.id }
            
            if batchIds.isEmpty {
                DispatchQueue.main.async { 
                    progressHandler("No batches found for day \(day)")
                    completion(.success(()))
                }
                return
            }
            
            // 4. Delete observations for these batches
            self.store.deleteObservations(forBatchIds: batchIds)
            DispatchQueue.main.async { progressHandler("Deleted observations for \(batchIds.count) batches") }
            
            // 5. Reset batch statuses to pending
            let resetBatchIds = self.store.resetBatchStatuses(forDay: day)
            DispatchQueue.main.async { progressHandler("Reset \(resetBatchIds.count) batches to pending status") }
            
            // 6. Process each batch sequentially
            var processedCount = 0
            var hasError = false
            
            for (index, batchId) in batchIds.enumerated() {
                if hasError { break }
                
                let batchStartTime = Date()
                let elapsedTotal = Date().timeIntervalSince(overallStartTime)
                
                DispatchQueue.main.async { 
                    progressHandler("Processing batch \(index + 1) of \(batchIds.count)... (Total elapsed: \(self.formatDuration(elapsedTotal)))")
                }
                
                // Use a semaphore to wait for each batch to complete
                let semaphore = DispatchSemaphore(value: 0)
                
                self.queueGeminiRequest(batchId: batchId)
                
                // Wait for batch to complete (check status periodically)
                var isCompleted = false
                while !isCompleted && !hasError {
                    // Sleep on background queue (not blocking main thread)
                    // Note: This runs on a utility queue, so Thread.sleep is acceptable here
                    Thread.sleep(forTimeInterval: 2.0)

                    let currentBatches = self.store.fetchBatches(forDay: day)
                    if let batch = currentBatches.first(where: { $0.id == batchId }) {
                        switch batch.status {
                        case "completed", "analyzed":
                            isCompleted = true
                            processedCount += 1
                            let batchDuration = Date().timeIntervalSince(batchStartTime)
                            batchTimings.append((batchId: batchId, duration: batchDuration))
                            DispatchQueue.main.async {
                                progressHandler("✓ Batch \(index + 1) completed in \(self.formatDuration(batchDuration))")
                            }
                        case "failed", "failed_empty", "skipped_short":
                            // These are acceptable end states
                            isCompleted = true
                            processedCount += 1
                            let batchDuration = Date().timeIntervalSince(batchStartTime)
                            batchTimings.append((batchId: batchId, duration: batchDuration))
                            DispatchQueue.main.async {
                                progressHandler("⚠️ Batch \(index + 1) ended with status '\(batch.status)' after \(self.formatDuration(batchDuration))")
                            }
                        case "processing":
                            // Still processing, continue waiting
                            break
                        default:
                            // Unexpected status, but continue
                            break
                        }
                    }
                }
            }
            
            let totalDuration = Date().timeIntervalSince(overallStartTime)
            
            DispatchQueue.main.async {
                // Build summary with timing stats
                var summary = "\n📊 Reprocessing Summary:\n"
                summary += "Total batches: \(batchIds.count)\n"
                summary += "Processed: \(processedCount)\n"
                summary += "Total time: \(self.formatDuration(totalDuration))\n"
                
                if !batchTimings.isEmpty {
                    summary += "\nBatch timings:\n"
                    for (index, timing) in batchTimings.enumerated() {
                        summary += "  Batch \(index + 1): \(self.formatDuration(timing.duration))\n"
                    }
                    
                    let avgTime = batchTimings.map { $0.duration }.reduce(0, +) / Double(batchTimings.count)
                    summary += "\nAverage time per batch: \(self.formatDuration(avgTime))"
                }
                
                progressHandler(summary)
                
                if hasError {
                    completion(.failure(NSError(domain: "AnalysisManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to reprocess some batches"])))
                } else {
                    completion(.success(()))
                }
            }
        }
    }
    
    func reprocessSpecificBatches(_ batchIds: [Int64], progressHandler: @escaping (String) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { 
                completion(.failure(NSError(domain: "AnalysisManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Manager deallocated"])))
                return 
            }
            
            let overallStartTime = Date()
            var batchTimings: [(batchId: Int64, duration: TimeInterval)] = []
            
            DispatchQueue.main.async { progressHandler("Preparing to reprocess \(batchIds.count) selected batches...") }
            
            let allBatches = self.store.allBatches()
            let existingBatchIds = Set(allBatches.map { $0.id })
            let orderedBatchIds = batchIds.filter { existingBatchIds.contains($0) }

            guard !orderedBatchIds.isEmpty else {
                completion(.failure(NSError(domain: "AnalysisManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not find batch information"])))
                return
            }
            
            DispatchQueue.main.async { progressHandler("Removing timeline cards for selected batches...") }
            let videoPaths = self.store.deleteTimelineCards(forBatchIds: orderedBatchIds)

            self.store.deleteObservations(forBatchIds: orderedBatchIds)

            for path in videoPaths {
                if let url = URL(string: path), url.scheme != nil {
                    try? FileManager.default.removeItem(at: url)
                } else {
                    let fileURL = URL(fileURLWithPath: path)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            let resetBatchIdSet = Set(self.store.resetBatchStatuses(forBatchIds: orderedBatchIds))
            let batchesToProcess = orderedBatchIds.filter { resetBatchIdSet.contains($0) }

            guard !batchesToProcess.isEmpty else {
                DispatchQueue.main.async { progressHandler("No eligible batches found to reprocess.") }
                completion(.failure(NSError(domain: "AnalysisManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "No eligible batches found to reprocess"])))
                return
            }

            DispatchQueue.main.async { progressHandler("Processing \(batchesToProcess.count) batches...") }

            // Process batches
            var processedCount = 0
            var hasError = false
            
            for (index, batchId) in batchesToProcess.enumerated() {
                if hasError { break }
                
                let batchStartTime = Date()
                let elapsedTotal = Date().timeIntervalSince(overallStartTime)
                
                DispatchQueue.main.async { 
                    progressHandler("Processing batch \(index + 1) of \(batchesToProcess.count)... (Total elapsed: \(self.formatDuration(elapsedTotal)))")
                }
                
                self.queueGeminiRequest(batchId: batchId)
                
                // Wait for batch to complete (check status periodically)
                var isCompleted = false
                while !isCompleted && !hasError {
                    // Sleep on background queue (not blocking main thread)
                    // Note: This runs on a utility queue, so Thread.sleep is acceptable here
                    Thread.sleep(forTimeInterval: 2.0)

                    let allBatches = self.store.allBatches()
                    if let batch = allBatches.first(where: { $0.id == batchId }) {
                        switch batch.status {
                        case "completed", "analyzed":
                            isCompleted = true
                            processedCount += 1
                            let batchDuration = Date().timeIntervalSince(batchStartTime)
                            batchTimings.append((batchId: batchId, duration: batchDuration))
                            DispatchQueue.main.async {
                                progressHandler("✓ Batch \(index + 1) completed in \(self.formatDuration(batchDuration))")
                            }
                        case "failed", "failed_empty", "skipped_short":
                            // These are acceptable end states
                            isCompleted = true
                            processedCount += 1
                            let batchDuration = Date().timeIntervalSince(batchStartTime)
                            batchTimings.append((batchId: batchId, duration: batchDuration))
                            DispatchQueue.main.async {
                                progressHandler("⚠️ Batch \(index + 1) ended with status '\(batch.status)' after \(self.formatDuration(batchDuration))")
                            }
                        case "processing":
                            // Still processing, continue waiting
                            break
                        default:
                            // Unexpected status, but continue
                            break
                        }
                    }
                }
            }
            
            // Summary
            let totalDuration = Date().timeIntervalSince(overallStartTime)
            let avgDuration = batchTimings.isEmpty ? 0 : batchTimings.reduce(0) { $0 + $1.duration } / Double(batchTimings.count)
            
            DispatchQueue.main.async {
                progressHandler("""
                ✅ Reprocessing complete!
                • Processed: \(processedCount) of \(batchesToProcess.count) batches
                • Total time: \(self.formatDuration(totalDuration))
                • Average time per batch: \(self.formatDuration(avgDuration))
                """)
            }
            
            completion(.success(()))
        }
    }

    @objc private func timerFired() { triggerAnalysisNow() }


    private func processRecordings() {
        #if DEBUG
        print("🟡 [AnalysisManager] processRecordings() started")
        #endif
        guard !isProcessing else {
            #if DEBUG
            print("⚠️ [AnalysisManager] Already processing in processRecordings, returning")
            #endif
            return
        }
        isProcessing = true
        defer {
            isProcessing = false
            #if DEBUG
            print("🟡 [AnalysisManager] processRecordings() finished")
            #endif
        }

        // 0. Process any pending batches (e.g. from reprocessing)
        let pendingBatchIds = store.fetchPendingBatches()
        if !pendingBatchIds.isEmpty {
            #if DEBUG
            print("🔄 [AnalysisManager] Found \(pendingBatchIds.count) pending batches for reprocessing")
            #endif
            for id in pendingBatchIds {
                #if DEBUG
                print("🚀 [AnalysisManager] Queuing LLM request for pending batch \(id)")
                #endif
                queueGeminiRequest(batchId: id)
            }
        }

        // 1. Gather unprocessed chunks
        let chunks = fetchUnprocessedChunks()
        #if DEBUG
        print("📊 [AnalysisManager] Found \(chunks.count) unprocessed chunks")
        #endif

        // 2. Build logical batches (~15‑min)
        let batches = createBatches(from: chunks)
        #if DEBUG
        print("📊 [AnalysisManager] Created \(batches.count) batches from chunks")
        #endif

        // 3. Persist batch rows & join table
        let batchIDs = batches.compactMap(saveBatch)
        #if DEBUG
        print("📊 [AnalysisManager] Saved \(batchIDs.count) batches to DB: \(batchIDs)")
        #endif

        // 4. Fire LLM for each batch
        for id in batchIDs {
            Logger.shared.info("🚀 [AnalysisManager] Queuing LLM request for batch \(id)", source: "AnalysisManager")
            queueGeminiRequest(batchId: id)
        }
    }


    private func queueGeminiRequest(batchId: Int64) {
        let chunksInBatch = StorageManager.shared.chunksForBatch(batchId)

        if chunksInBatch.isEmpty {
            Logger.shared.warning("Batch \(batchId) has no chunks. Marking as 'failed_empty'.", source: "AnalysisManager")
            self.updateBatchStatus(batchId: batchId, status: "failed_empty")
            return
        }

        let totalVideoDurationSeconds = chunksInBatch.reduce(0.0) { acc, chunk -> TimeInterval in
            let duration = TimeInterval(chunk.endTs - chunk.startTs)
            return acc + duration
        }

        if totalVideoDurationSeconds < config.minimumBatchDurationSeconds {
            Logger.shared.info("Batch \(batchId) duration (\(totalVideoDurationSeconds)s) is less than \(config.minimumBatchDurationSeconds)s. Marking as 'skipped_short'.", source: "AnalysisManager")
            self.updateBatchStatus(batchId: batchId, status: "skipped_short")
            return
        }

        // Sentry transaction removed

        updateBatchStatus(batchId: batchId, status: "processing")

        // Prepare file URLs for video processing with robust path resolution
        let chunkFileURLs: [URL] = chunksInBatch.compactMap { chunk in
            let fileURL = URL(fileURLWithPath: chunk.fileUrl)
            
            // 1. Check if file exists at the stored path
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
            
            // 2. If not, try to resolve relative to recordings root
            // Note: We access StorageManager.shared directly to get the root path
            let fileName = fileURL.lastPathComponent
            let resolvedURL = StorageManager.shared.recordingsRoot.appendingPathComponent(fileName)
            
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                Logger.shared.warning("Resolved missing file at \(chunk.fileUrl) to \(resolvedURL.path)", source: "AnalysisManager")
                return resolvedURL
            }
            
            Logger.shared.error("Could not find video file for chunk \(chunk.id) at \(chunk.fileUrl) or \(resolvedURL.path)", source: "AnalysisManager")
            return nil
        }
        
        if chunkFileURLs.isEmpty {
            let msg = "All video files for batch \(batchId) are missing. Cannot process."
            Logger.shared.error(msg, source: "AnalysisManager")
            self.markBatchFailed(batchId: batchId, reason: msg)
            return
        }

        llmService.processBatch(batchId) { [weak self] (result: Result<ProcessedBatchResult, Error>) in
            guard let self else { return }

            let now = Date()
            let currentDayInfo = now.getDayInfoFor4AMBoundary()
            let currentLogicalDayString = currentDayInfo.dayString
            #if DEBUG
            print("Processing batch \(batchId) for logical day: \(currentLogicalDayString)")
            #endif

            switch result {
            case .success(let processedResult):
                let activityCards = processedResult.cards
                let cardIds = processedResult.cardIds
                #if DEBUG
                print("LLM succeeded for Batch \(batchId). Processing \(activityCards.count) activity cards for day \(currentLogicalDayString).")

                // Transaction finished

                // Debug: Check for duplicate cards from LLM
                print("\n🔍 DEBUG: Checking for duplicate cards from LLM:")
                for (i, card1) in activityCards.enumerated() {
                    for (j, card2) in activityCards.enumerated() where j > i {
                        if card1.startTime == card2.startTime && card1.endTime == card2.endTime && card1.title == card2.title {
                            print("⚠️ DEBUG: Found duplicate cards at indices \(i) and \(j): '\(card1.title)' [\(card1.startTime) - \(card1.endTime)]")
                        }
                    }
                }
                print("✅ DEBUG: Duplicate check complete\n")
                #endif

                guard let firstChunk = chunksInBatch.first else {
                    #if DEBUG
                    print("Error: No chunks found for batch \(batchId) during timestamp conversion")
                    #endif
                    self.markBatchFailed(batchId: batchId, reason: "No chunks found for timestamp conversion")
                    return
                }
                let firstChunkStartDate = Date(timeIntervalSince1970: TimeInterval(firstChunk.startTs))
                #if DEBUG
                print("First chunk starts at real time: \(firstChunkStartDate)")
                #endif

                // Mark batch as completed immediately
                self.updateBatchStatus(batchId: batchId, status: "completed")
                
                let cardCount = activityCards.count
                
                // Generate timelapses asynchronously for each timeline card off the main thread
                Task.detached(priority: .utility) { [weak self, cardIds, cardCount, batchId] in
                    guard let self else {
                        #if DEBUG
                        print("❌ [TIMELAPSE TASK] Self is nil, cannot proceed")
                        #endif
                        return
                    }

                    #if DEBUG
                    print("🎬 [TIMELAPSE TASK] Starting timelapse generation for \(cardIds.count) cards from batch \(batchId)")
                    #endif

                    for (index, cardId) in cardIds.enumerated() {
                        if index >= cardCount {
                            #if DEBUG
                            print("⚠️ [TIMELAPSE TASK] Index \(index) >= cardCount \(cardCount), skipping")
                            #endif
                            continue
                        }

                        #if DEBUG
                        print("📹 [TIMELAPSE TASK] [\(index+1)/\(cardCount)] Processing card \(cardId)")
                        #endif

                        // Fetch the saved timeline card to get Unix timestamps
                        guard let timelineCard = self.store.fetchTimelineCard(byId: cardId) else {
                            #if DEBUG
                            print("❌ [TIMELAPSE TASK] Could not fetch timeline card \(cardId) from database")
                            #endif
                            continue
                        }

                        #if DEBUG
                        print("   Card: '\(timelineCard.title)' [\(timelineCard.startTimestamp) - \(timelineCard.endTimestamp)]")
                        print("   Category: \(timelineCard.category)")
                        print("   Timestamps: \(timelineCard.startTs) - \(timelineCard.endTs)")
                        #endif

                        // Fetch chunks that overlap with this card's time range using Unix timestamps
                        let chunks = self.store.fetchChunksInTimeRange(
                            startTs: timelineCard.startTs,
                            endTs: timelineCard.endTs
                        )

                        if chunks.isEmpty {
                            #if DEBUG
                            print("❌ [TIMELAPSE TASK] No chunks found for timeline card \(cardId) [time range: \(timelineCard.startTs) - \(timelineCard.endTs)]")
                            #endif
                            continue
                        }

                        #if DEBUG
                        print("   ✅ Found \(chunks.count) chunks")
                        #endif

                        do {
                            #if DEBUG
                            print("   🎬 Generating timelapse...")
                            #endif

                            // Convert chunks to URLs
                            let chunkURLs = chunks.compactMap { URL(fileURLWithPath: $0.fileUrl) }
                            #if DEBUG
                            print("   📁 Converted \(chunkURLs.count) chunk URLs")
                            #endif

                            // Stitch chunks together
                            let stitchedVideo = try await self.videoProcessingService.prepareVideoForProcessing(urls: chunkURLs)
                            #if DEBUG
                            print("   ✅ Stitched video prepared at: \(stitchedVideo.path)")
                            #endif

                            // Generate timelapse
                            let timelapseURL = await self.videoProcessingService.generatePersistentTimelapseURL(
                                for: Date(timeIntervalSince1970: TimeInterval(timelineCard.startTs)),
                                originalFileName: String(cardId)
                            )
                            #if DEBUG
                            print("   🎯 Target timelapse URL: \(timelapseURL.path)")
                            #endif

                            try await self.videoProcessingService.generateTimelapse(
                                sourceVideoURL: stitchedVideo,
                                outputTimelapseFileURL: timelapseURL,
                                speedupFactor: 20,  // 20x as requested
                                outputFPS: 24
                            )

                            // Update timeline card with timelapse URL off the main thread to avoid UI stalls
                            let videoPath = timelapseURL.path
                            DispatchQueue.global(qos: .utility).async { [store = self.store] in
                                store.updateTimelineCardVideoURL(cardId: cardId, videoSummaryURL: videoPath)
                                #if DEBUG
                                print("   💾 Updated database with video URL for card \(cardId)")
                                #endif
                            }
                            #if DEBUG
                            print("   ✅ [TIMELAPSE TASK] Completed timelapse for card \(cardId): \(videoPath)")
                            #endif

                            // Cleanup temp file
                            await self.videoProcessingService.cleanupTemporaryFile(at: stitchedVideo)
                            #if DEBUG
                            print("   🗑️  Cleaned up temporary stitched video")
                            #endif
                        } catch {
                            #if DEBUG
                            print("❌ [TIMELAPSE TASK] ERROR generating timelapse for card \(cardId): \(error)")
                            print("   Error details: \(error.localizedDescription)")
                            if let nsError = error as NSError? {
                                print("   Error domain: \(nsError.domain), code: \(nsError.code)")
                            }
                            #endif
                        }
                    }
                    #if DEBUG
                    print("🏁 [TIMELAPSE TASK] Timelapse generation complete for batch \(batchId)")
                    #endif
                }

            case .failure(let err):
                #if DEBUG
                print("LLM failed for Batch \(batchId). Day \(currentLogicalDayString) may have been cleared. Error: \(err.localizedDescription)")
                #endif

                // Transaction finished

                self.markBatchFailed(batchId: batchId, reason: err.localizedDescription)
            }
        }
    }


    private func markBatchFailed(batchId: Int64, reason: String) {
        store.markBatchFailed(batchId: batchId, reason: reason)
    }

    private func updateBatchStatus(batchId: Int64, status: String) {
        store.updateBatchStatus(batchId: batchId, status: status)
    }


    private struct AnalysisBatch { let chunks: [RecordingChunk]; let start: Int; let end: Int }

    private func fetchUnprocessedChunks() -> [RecordingChunk] {
        let oldest = Int(Date().timeIntervalSince1970) - Int(config.maxLookbackSeconds)
        return store.fetchUnprocessedChunks(olderThan: oldest)
    }


private func createBatches(from chunks: [RecordingChunk]) -> [AnalysisBatch] {
    guard !chunks.isEmpty else { return [] }

    let ordered = chunks.sorted { $0.startTs < $1.startTs }
    let maxGap: TimeInterval        = config.maxChunkGapSeconds             // ≤ 2 min between chunks
    let maxBatchDuration: TimeInterval = config.targetBatchDurationSeconds // 900 s (15 min)

    var batches: [AnalysisBatch] = []

    var bucket: [RecordingChunk]   = []
    var bucketDur: TimeInterval    = 0                // sum of 15‑s chunks

    for chunk in ordered {
        if bucket.isEmpty {
            bucket.append(chunk)
            bucketDur = chunk.duration                // first chunk → 15 s
            continue
        }

        let prev       = bucket.last!
        let gap        = TimeInterval(chunk.startTs - prev.endTs)
        let wouldBurst = bucketDur + chunk.duration > maxBatchDuration

        if gap > maxGap || wouldBurst {
            // close current batch
            batches.append(
                AnalysisBatch(chunks: bucket,
                              start: bucket.first!.startTs,
                              end:   bucket.last!.endTs)
            )
            // start new bucket with this chunk
            bucket      = [chunk]
            bucketDur   = chunk.duration
        } else {
            // still in same batch
            bucket.append(chunk)
            bucketDur += chunk.duration
        }
    }

    // Flush any leftover bucket
    if !bucket.isEmpty {
        batches.append(
            AnalysisBatch(chunks: bucket,
                          start: bucket.first!.startTs,
                          end:   bucket.last!.endTs)
        )
    }

    // ─── Special rule: drop the *most‑recent* batch if < 15 min ───
    if let last = batches.last {
        let dur = last.chunks.reduce(0) { $0 + $1.duration }   // sum of 15‑s chunks
        if dur < maxBatchDuration {
            batches.removeLast()
        }
    }

    return batches
}


    private func saveBatch(_ batch: AnalysisBatch) -> Int64? {
        let ids = batch.chunks.map { $0.id }
        return store.saveBatch(startTs: batch.start, endTs: batch.end, chunkIds: ids)
    }


    // Parses a video timestamp like "05:30" into seconds
    private func parseVideoTimestamp(_ timestamp: String) -> TimeInterval? {
        let components = timestamp.components(separatedBy: ":")
        guard components.count == 2,
              let minutes = Int(components[0]),
              let seconds = Int(components[1]) else {
            return nil
        }
        
        return TimeInterval(minutes * 60 + seconds)
    }

    // Formats a Date as a clock time like "11:37 AM"
    private func formatAsClockTime(_ date: Date) -> String {
        return Self.clockTimeFormatter.string(from: date)
    }

    // Parses a clock time like "11:37 AM" to a Date
    private func parseClockTime(_ timeString: String, baseDate: Date) -> Date? {
        guard let time = Self.clockTimeFormatter.date(from: timeString) else { return nil }
        
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        
        return calendar.date(bySettingHour: timeComponents.hour ?? 0,
                           minute: timeComponents.minute ?? 0,
                           second: 0,
                           of: baseDate)
    }
    
    // Formats a duration in seconds to a human-readable string
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        } else {
            return "\(remainingSeconds)s"
        }
    }
}
