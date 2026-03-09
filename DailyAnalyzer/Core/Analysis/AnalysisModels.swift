//
//  AnalysisModels.swift
//  DayArc
//
//  Created from Dayflow/Models/AnalysisModels.swift
//

import Foundation

/// Represents a recording chunk from the database
struct RecordingChunk: Codable, Sendable {
    let id: Int64
    let startTs: Int
    let endTs: Int
    let fileUrl: String
    let status: String
    
    var duration: TimeInterval {
        TimeInterval(endTs - startTs)
    }
}


struct Distraction: Codable, Sendable, Identifiable {
    let id: UUID
    let startTime: String
    let endTime: String
    let title: String
    let summary: String
    let videoSummaryURL: String? // Optional link to video summary for the distraction

    // Custom decoder to handle missing 'id'
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Try to decode 'id', if not found or nil, assign a new UUID
        self.id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.startTime = try container.decode(String.self, forKey: .startTime)
        self.endTime = try container.decode(String.self, forKey: .endTime)
        self.title = try container.decode(String.self, forKey: .title)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.videoSummaryURL = try container.decodeIfPresent(String.self, forKey: .videoSummaryURL)
    }

    // Add explicit init to maintain memberwise initializer if needed elsewhere,
    // though Codable synthesis might handle this. It's good practice.
    init(id: UUID = UUID(), startTime: String, endTime: String, title: String, summary: String, videoSummaryURL: String? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.title = title
        self.summary = summary
        self.videoSummaryURL = videoSummaryURL
    }

    // CodingKeys needed for custom decoder
    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, title, summary, videoSummaryURL
    }
}
