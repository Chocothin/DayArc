import Foundation

// 공통 모델 스탑게이트. 실제 Dayflow 타입으로 교체 예정.
public struct Observation: Sendable, Codable {
    public let id: Int64?
    public let batchId: Int64
    public let startTs: Int
    public let endTs: Int
    public let observation: String
    public let metadata: String?
    public let llmModel: String?
    public let createdAt: Date?
}

public struct LLMCall: Sendable, Codable {
    public let timestamp: Date?
    public let latency: TimeInterval?
    public let input: String?
    public let output: String?
}

public struct RecordingChunk: Sendable, Codable {
    public let id: Int64
    public let startTs: Int
    public let endTs: Int
    public let fileUrl: String
    public let status: String
}

public enum DayflowError: Error {
    case notInitialized
    case notPermitted
    case unsupported
}
