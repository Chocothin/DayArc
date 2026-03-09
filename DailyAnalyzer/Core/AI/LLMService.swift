//
//  LLMService.swift
//  Dayflow
//

import Foundation
import Combine
import AppKit
import AVFoundation
import SwiftUI
import GRDB

struct ProcessedBatchResult {
    let cards: [ActivityCardData]
    let cardIds: [Int64]
}

protocol LLMServicing {
    func processBatch(_ batchId: Int64, completion: @escaping (Result<ProcessedBatchResult, Error>) -> Void)
}

final class LLMService: LLMServicing {
    static let shared: LLMServicing = LLMService()
    private let videoProcessingService = VideoProcessingService()
    
    private var provider: LLMProvider? {
        let config = AIProviderConfig.load()
        let type = config.selectedProviderType
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("\n🏗️ [LLMService] Creating provider at \(timestamp)")
        print("   Provider type: \(type.rawValue)")

        switch type {
        case .gemini:
            if let apiKey = config.apiKeys[.gemini], !apiKey.isEmpty {
                let preference = GeminiModelPreference.load()
                return GeminiDirectProvider(apiKey: apiKey, preference: preference)
            } else {
                print("❌ [LLMService] No API key found for Gemini in AIProviderConfig")
                return nil
            }
            
        case .ollama:
            let endpoint = config.localEndpoints[.ollama] ?? "http://localhost:11434"
            return OllamaProvider(endpoint: endpoint)
            
        // Fallback/TODO for others if they implement LLMProvider
        case .openai, .claude, .lmstudio:
            print("⚠️ [LLMService] Provider \(type.rawValue) not yet fully supported in background analysis. Falling back to Gemini if available.")
            // Try to fallback to Gemini if key exists
            if let apiKey = config.apiKeys[.gemini], !apiKey.isEmpty {
                let preference = GeminiModelPreference.load()
                return GeminiDirectProvider(apiKey: apiKey, preference: preference)
            }
            return nil
        }
    }

    private func providerName() -> String {
        return AIProviderConfig.load().selectedProviderType.rawValue.lowercased()
    }
    
    /// Retry operation with exponential backoff
    private func retryWithBackoff<T>(
        maxRetries: Int = 3,
        initialDelay: TimeInterval = 2.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var currentDelay = initialDelay
        var attempts = 0
        
        while true {
            do {
                return try await operation()
            } catch {
                attempts += 1
                guard attempts <= maxRetries else { throw error }
                
                // Check if error is retryable
                if !isRetryable(error) { throw error }
                
                Logger.shared.warning("⚠️ [LLMService] Operation failed (attempt \(attempts)/\(maxRetries)). Retrying in \(currentDelay)s. Error: \(error.localizedDescription)", source: "LLMService")
                
                try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                currentDelay *= 2.0
            }
        }
    }
    
    private func isRetryable(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Check for network errors
        if nsError.domain == NSURLErrorDomain { return true }
        
        // Check for specific provider errors (e.g. Gemini)
        if nsError.domain == "GeminiError" {
            // Retry on 5xx (Server Error) and 429 (Rate Limit)
            // Do not retry on 401 (Auth) or 400 (Bad Request)
            let code = nsError.code
            return (code >= 500 && code < 600) || code == 429 || code == 408 // Timeout
        }
        
        // Generic check for "rate limit" or "network" in description
        let description = error.localizedDescription.lowercased()
        if description.contains("rate limit") || 
           description.contains("network") || 
           description.contains("connection") ||
           description.contains("timeout") {
            return true
        }
        
        return false
    }
    
    // Keep the existing processBatch implementation for backward compatibility
    func processBatch(_ batchId: Int64, completion: @escaping (Result<ProcessedBatchResult, Error>) -> Void) {
        Task {
            let processingStartTime = Date()
            Logger.shared.info("🎬 Starting processing for batch \(batchId)", source: "LLMService")
            
            // Fetch batch metadata to get time range
            guard let batchInfo = StorageManager.shared.allBatches().first(where: { $0.0 == batchId }) else {
                let error = NSError(domain: "LLMService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Batch \(batchId) not found"])
                Logger.shared.error("Batch \(batchId) not found", source: "LLMService")
                completion(.failure(error))
                return
            }
            
            let (_, batchStartTs, batchEndTs, _) = batchInfo
            
            do {
                // Set a timeout for the entire operation
                let result = try await withThrowingTaskGroup(of: ProcessedBatchResult.self) { group in
                    group.addTask {
                        // 1. Check for provider
                        guard let provider = self.provider else {
                            throw NSError(domain: "LLMService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No LLM provider configured"])
                        }
                        
                        // 2. Get chunks and stitch video
                        let chunks = StorageManager.shared.chunksForBatch(batchId)
                        if chunks.isEmpty {
                            throw NSError(domain: "LLMService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No chunks in batch"])
                        }
                        
                        // Robust path resolution
                        let chunkURLs: [URL] = chunks.compactMap { chunk in
                            if let url = StorageManager.shared.resolveVideoURL(for: chunk.fileUrl) {
                                return url
                            }
                            
                            Logger.shared.error("Could not find video file for chunk \(chunk.id)", source: "LLMService")
                            return nil
                        }
                        
                        if chunkURLs.isEmpty {
                             throw NSError(domain: "LLMService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No valid video files found for batch"])
                        }

                        let stitchStartTime = Date()
                        Logger.shared.debug("[⏱️ 0:00] Starting video stitching for \(chunkURLs.count) chunks", source: "LLMService")
                        
                        // Use VideoProcessingService to stitch
                        let stitchedURL = try await self.videoProcessingService.prepareVideoForProcessing(urls: chunkURLs)
                        let stitchDuration = Date().timeIntervalSince(stitchStartTime)
                        Logger.shared.info("[⏱️ \(String(format: "%.1f", stitchDuration))s] Video stitching completed", source: "LLMService")
                        defer {
                            Task { await self.videoProcessingService.cleanupTemporaryFile(at: stitchedURL) }
                        }
                        
                        // Load video data
                        let videoData = try Data(contentsOf: stitchedURL)
                        let mimeType = "video/mp4"
                        
                        // Get video duration for validation
                        let asset = AVAsset(url: stitchedURL)
                        let duration = try await asset.load(.duration)
                        let durationSeconds = CMTimeGetSeconds(duration)
                        
                        // 3. Transcribe
                        let transcribeStartTime = Date()
                        let elapsedSoFar = Date().timeIntervalSince(processingStartTime)
                        Logger.shared.info("[⏱️ \(String(format: "%.1f", elapsedSoFar))s] Starting transcription with \(self.providerName())", source: "LLMService")
                        let batchStartDate = Date(timeIntervalSince1970: TimeInterval(batchStartTs))
                        
                        let (observations, transcribeLog) = try await self.retryWithBackoff(maxRetries: 3) {
                            try await provider.transcribeVideo(
                                videoData: videoData,
                                mimeType: mimeType,
                                prompt: PromptManager.shared.getPrompt(for: .videoTranscription),
                                batchStartTime: batchStartDate,
                                videoDuration: durationSeconds,
                                batchId: batchId
                            )
                        }
                        
                        StorageManager.shared.saveObservations(batchId: batchId, observations: observations)
                        let transcribeDuration = Date().timeIntervalSince(transcribeStartTime)
                        let totalElapsed = Date().timeIntervalSince(processingStartTime)
                        Logger.shared.info("[⏱️ \(String(format: "%.1f", totalElapsed))s] Transcription completed (took \(String(format: "%.1f", transcribeDuration))s, \(observations.count) observations)", source: "LLMService")
                        
                        if observations.isEmpty {
                            Logger.shared.warning("Transcription returned 0 observations", source: "LLMService")
                            if let logOutput = transcribeLog.output, !logOutput.isEmpty {
                                Logger.shared.debug("   ↳ transcribeLog.output: \(logOutput)", source: "LLMService")
                            }
                            if let logInput = transcribeLog.input, !logInput.isEmpty {
                                Logger.shared.debug("   ↳ transcribeLog.input: \(logInput)", source: "LLMService")
                            }
                            await AnalyticsService.shared.capture("transcription_returned_empty", [
                                "batch_id": batchId,
                                "provider": self.providerName(),
                                "transcribe_latency_ms": Int((transcribeLog.latency ?? 0) * 1000)
                            ])
                            StorageManager.shared.updateBatch(batchId, status: "analyzed")
                            return ProcessedBatchResult(cards: [], cardIds: [])
                        }
                        
                        // 4. Generate Activity Cards (Sliding Window)
                        let currentTime = Date(timeIntervalSince1970: TimeInterval(batchEndTs))
                        let oneHourAgo = currentTime.addingTimeInterval(-3600)
                        
                        let recentObservations = StorageManager.shared.fetchObservationsByTimeRange(from: oneHourAgo, to: currentTime)
                        let existingTimelineCards = StorageManager.shared.fetchTimelineCardsByTimeRange(from: oneHourAgo, to: currentTime)
                        
                        // Convert existing cards to ActivityCardData
                        let cardFormatter = DateFormatter()
                        cardFormatter.dateFormat = "h:mm a"
                        cardFormatter.locale = Locale(identifier: "en_US_POSIX")
                        
                        let existingActivityCards = existingTimelineCards.map { card in
                            ActivityCardData(
                                startTime: cardFormatter.string(from: card.startAt),
                                endTime: cardFormatter.string(from: card.endAt),
                                category: card.category ?? "Unknown",
                                subcategory: card.subcategory ?? "General",
                                title: card.title ?? "Untitled",
                                summary: card.summary ?? "",
                                detailedSummary: card.detailedSummary ?? "",
                                distractions: card.distractions,
                                appSites: card.appSites
                            )
                        }
                        
                        let categories = CategoryStore.descriptorsForLLM()
                        Logger.shared.debug("Loaded \(categories.count) categories for LLM", source: "LLMService")
                        
                        let cardGenStartTime = Date()
                        let elapsedBeforeCardGen = Date().timeIntervalSince(processingStartTime)
                        Logger.shared.info("[⏱️ \(String(format: "%.1f", elapsedBeforeCardGen))s] Starting activity card generation", source: "LLMService")
                        
                        let context = ActivityGenerationContext(
                            batchObservations: observations, // Use current batch observations for generation focus
                            existingCards: existingActivityCards,
                            currentTime: currentTime,
                            categories: categories
                        )
                        
                        let (cards, cardsLog) = try await self.retryWithBackoff(maxRetries: 3) {
                            try await provider.generateActivityCards(
                                observations: recentObservations, // Pass all recent observations for context
                                context: context,
                                batchId: batchId
                            )
                        }
                        let cardGenDuration = Date().timeIntervalSince(cardGenStartTime)
                        let totalElapsedAfterCards = Date().timeIntervalSince(processingStartTime)
                        Logger.shared.info("[⏱️ \(String(format: "%.1f", totalElapsedAfterCards))s] Card generation completed (took \(String(format: "%.1f", cardGenDuration))s, \(cards.count) cards)", source: "LLMService")
                        
                        // 5. Save Cards
                        // Replace old cards with new ones in the time range
                        let (insertedCardIds, deletedVideoPaths) = StorageManager.shared.replaceTimelineCardsInRange(
                            from: oneHourAgo,
                            to: currentTime,
                            with: cards.map { card in
                                TimelineCardShell(
                                    startTimestamp: card.startTime,
                                    endTimestamp: card.endTime,
                                    category: card.category,
                                    subcategory: card.subcategory,
                                    title: card.title,
                                    summary: card.summary,
                                    detailedSummary: card.detailedSummary,
                                    distractions: card.distractions,
                                    appSites: card.appSites
                                )
                            },
                            batchId: batchId
                        )
                        
                        // Clean up deleted video files
                        for path in deletedVideoPaths {
                            let url = URL(fileURLWithPath: path)
                            // Check if file exists before attempting deletion
                            if FileManager.default.fileExists(atPath: url.path) {
                                do {
                                    try FileManager.default.removeItem(at: url)
                                    Logger.shared.info("🗑️ Deleted timelapse: \(path)", source: "LLMService")
                                } catch {
                                    Logger.shared.error("❌ Failed to delete timelapse: \(path) - \(error)", source: "LLMService")
                                }
                            } else {
                                Logger.shared.warning("⚠️ Timelapse file already deleted or not found: \(path)", source: "LLMService")
                            }
                        }
                        
                        // Mark batch as complete
                        StorageManager.shared.updateBatch(batchId, status: "analyzed")

                        // Track analysis batch completed
                        await AnalyticsService.shared.capture("analysis_batch_completed", [
                            "batch_id": batchId,
                            "cards_generated": cards.count,
                            "processing_duration_seconds": Int(Date().timeIntervalSince(processingStartTime)),
                            "llm_provider": self.providerName()
                        ])
                        
                        Logger.shared.info("✅ Successfully processed batch \(batchId). Created \(insertedCardIds.count) cards.", source: "LLMService")
                        return ProcessedBatchResult(cards: cards, cardIds: insertedCardIds)
                    }
                    
                    // Timeout task
                    group.addTask {
                        try await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000) // 15 minutes
                        throw NSError(domain: "LLMService", code: 408, userInfo: [NSLocalizedDescriptionKey: "Processing timed out after 15 minutes"])
                    }
                    
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
                completion(.success(result))
                
            } catch {
                Logger.shared.error("Error processing batch \(batchId): \(error.localizedDescription)", source: "LLMService")
                if let ns = error as NSError?, ns.domain == "GeminiError" {
                    Logger.shared.debug("🔎 GEMINI DEBUG: NSError.userInfo=\(ns.userInfo)", source: "LLMService")
                }

                // Track analysis batch failed
                await AnalyticsService.shared.capture("analysis_batch_failed", [
                    "batch_id": batchId,
                    "error_message": error.localizedDescription,
                    "processing_duration_seconds": Int(Date().timeIntervalSince(processingStartTime)),
                    "llm_provider": self.providerName()
                ])

                // Mark batch as failed
                StorageManager.shared.updateBatch(batchId, status: "failed", reason: error.localizedDescription)
                
                // Create an error card for the failed time period
                let batchStartDate = Date(timeIntervalSince1970: TimeInterval(batchStartTs))
                let batchEndDate = Date(timeIntervalSince1970: TimeInterval(batchEndTs))
                
                let errorCard = self.createErrorCard(
                    batchId: batchId,
                    batchStartTime: batchStartDate,
                    batchEndTime: batchEndDate,
                    error: error
                )
                
                // Replace any existing cards in this time range with the error card
                // This matches the happy path behavior and prevents duplicates
                let (insertedCardIds, deletedVideoPaths) = StorageManager.shared.replaceTimelineCardsInRange(
                    from: batchStartDate,
                    to: batchEndDate,
                    with: [errorCard],
                    batchId: batchId
                )
                
                // Clean up any deleted video files (if there were existing cards)
                for path in deletedVideoPaths {
                    let url = URL(fileURLWithPath: path)
                    // Check if file exists before attempting deletion
                    if FileManager.default.fileExists(atPath: url.path) {
                        do {
                            try FileManager.default.removeItem(at: url)
                            Logger.shared.info("🗑️ Deleted timelapse for replaced card: \(path)", source: "LLMService")
                        } catch {
                            Logger.shared.error("❌ Failed to delete timelapse: \(path) - \(error)", source: "LLMService")
                        }
                    } else {
                        Logger.shared.warning("⚠️ Timelapse file already deleted or not found: \(path)", source: "LLMService")
                    }
                }
                
                if !insertedCardIds.isEmpty {
                    Logger.shared.info("✅ Created error card (ID: \(insertedCardIds.first ?? -1)) for failed batch \(batchId), replacing \(deletedVideoPaths.count) existing cards", source: "LLMService")
                }
                
                // Still return failure but with the error card created
                completion(.failure(error))
            }
        }
    }
    
    
    private func createErrorCard(batchId: Int64, batchStartTime: Date, batchEndTime: Date, error: Error) -> TimelineCardShell {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        let startTimeStr = formatter.string(from: batchStartTime)
        let endTimeStr = formatter.string(from: batchEndTime)
        
        // Calculate duration in minutes
        let duration = Int(batchEndTime.timeIntervalSince(batchStartTime) / 60)
        
        // Get human-readable error message
        let humanError = getHumanReadableError(error)
        
        // Create the error card
        return TimelineCardShell(
            startTimestamp: startTimeStr,
            endTimestamp: endTimeStr,
            category: "System",
            subcategory: "Error",
            title: "Processing failed",
            summary: "Failed to process \(duration) minutes of recording from \(startTimeStr) to \(endTimeStr). \(humanError) Your recording is safe and can be reprocessed.",
            detailedSummary: "Error details: \(error.localizedDescription)\n\nThis recording batch (ID: \(batchId)) failed during AI processing. The original video files are preserved and can be reprocessed by retrying from Settings. Common causes include network issues, API rate limits, or temporary service outages.",
            distractions: nil,
            appSites: nil
        )
    }
    
    private func getHumanReadableError(_ error: Error) -> String {
        // First check if it's an NSError with a domain and code we recognize
        if let nsError = error as NSError? {
            // For HTTP errors, check if we have a specific error message in userInfo
            if nsError.domain == "GeminiError" && nsError.code >= 400 && nsError.code < 600 {
                // Check for specific known API error messages
                let errorMessage = nsError.localizedDescription.lowercased()
                if errorMessage.contains("api key not found") {
                    return "Invalid API key. Please check your Gemini API key in Settings."
                } else if errorMessage.contains("rate limit") || errorMessage.contains("quota") {
                    return "Rate limited. Too many requests to Gemini. Please wait a few minutes."
                } else if errorMessage.contains("unauthorized") {
                    return "Unauthorized. Your Gemini API key may be invalid or expired."
                } else if errorMessage.contains("timeout") {
                    return "Request timed out. The video may be too large or the connection is slow."
                }
                // Fall through to switch statement for generic HTTP error messages
            }

            // Check specific error domains and codes
            switch nsError.domain {
            case "LLMService":
                switch nsError.code {
                case 1: return "No AI provider is configured. Please set one up in Settings."
                case 2: return "The recording batch couldn't be found."
                case 3: return "No video recordings found in this time period."
                case 4: return "Failed to create the video for processing."
                case 5: return "Failed to combine video chunks."
                case 6: return "Failed to prepare video for processing."
                default: break
                }
                
            case "GeminiError", "GeminiProvider":
                switch nsError.code {
                case 1: return "Failed to upload the video to Gemini."
                case 2: return "Gemini took too long to process the video."
                case 3, 5: return "Failed to parse Gemini's response."
                case 4: return "Failed to start video upload to Gemini."
                case 6: return "Invalid video file."
                case 7, 9: return "Gemini returned an unexpected response format."
                case 8, 10: return "Failed to connect to Gemini after multiple attempts."
                case 100: return "The AI generated timestamps beyond the video duration."
                case 101: return "The AI couldn't identify any activities in the video."
                // HTTP status codes
                case 400: return "Invalid API key. Please check your Gemini API key in Settings."
                case 401: return "Unauthorized. Your Gemini API key may be invalid or expired."
                case 403: return "Access forbidden. Check your Gemini API permissions."
                case 429: return "Rate limited. Too many requests to Gemini. Please wait a few minutes."
                case 503: return "Google's Gemini servers returned a 503 error. Google's AI services may be temporarily down. If you see many of these in a row, please wait at least a few hours before retrying. Check the [Google AI Studio status](https://aistudio.google.com/status) page for updates."
                case 500...599: return "Gemini service error. The service may be temporarily down."
                default:
                    // For other HTTP errors, provide context
                    if nsError.code >= 400 && nsError.code < 600 {
                        return "Gemini returned HTTP error \(nsError.code). Check your API settings."
                    }
                    break
                }
                
            case "OllamaProvider":
                switch nsError.code {
                case 1: return "Invalid video duration."
                case 2: return "Failed to process video frame."
                case 4: return "Failed to connect to local AI model."
                case 8, 9, 10: return "The local AI returned an unexpected response."
                case 11: return "The local AI couldn't identify any activities."
                case 12: return "The local AI didn't analyze enough of the video."
                case 13: return "The local AI generated too many segments."
                default: break
                }
                
            case "AnalysisManager":
                switch nsError.code {
                case 1: return "The analysis system was interrupted."
                case 2: return "Failed to reprocess some recordings."
                case 3: return "Couldn't find the recording information."
                default: break
                }
                
            default:
                break
            }
        }
        
        // Fallback to checking the error description for common patterns
        let errorDescription = error.localizedDescription.lowercased()
        
        switch true {
        case errorDescription.contains("rate limit") || errorDescription.contains("429"):
            return "The AI service is temporarily overwhelmed. This usually resolves itself in a few minutes."
            
        case errorDescription.contains("network") || errorDescription.contains("connection"):
            return "Couldn't connect to the AI service. Check your internet connection."
            
        case errorDescription.contains("api key") || errorDescription.contains("unauthorized") || errorDescription.contains("401"):
            return "There's an issue with your API key. Please check your settings."
            
        case errorDescription.contains("503"):
            return "Google's Gemini servers returned a 503 error. Google's AI services may be temporarily down. If you see many of these in a row, please wait at least a few hours before retrying. Check the [Google AI Studio status](https://aistudio.google.com/status) page for updates."
            
        case errorDescription.contains("timeout"):
            return "The AI took too long to respond. This might be due to a long recording or slow connection."
            
        case errorDescription.contains("no observations"):
            return "The AI couldn't understand what was happening in this recording."
            
        case errorDescription.contains("exceed") || errorDescription.contains("duration"):
            return "The AI got confused about the video timing."
            
        case errorDescription.contains("no llm provider") || errorDescription.contains("not configured"):
            return "No AI provider is configured. Please set one up in Settings."
            
        case errorDescription.contains("failed to upload"):
            return "Failed to upload the video for processing."
            
        case errorDescription.contains("invalid response") || errorDescription.contains("json"):
            return "The AI returned an unexpected response format."
            
        case errorDescription.contains("failed after") && errorDescription.contains("attempts"):
            return "Couldn't connect to the AI service after multiple attempts."
            
        default:
            // For unknown errors, keep it simple
            return "An unexpected error occurred."
        }
    }
}
