import Foundation

/// StorageManager 대체용 스탑게이트. 아직 실제 DB 로직 없음.
public protocol StorageManaging {
    func configure(basePath: URL) throws
    func fetchTimelineCards(forDay day: String) -> [TimelineCardLite]
    func fetchObservations(range: (Int, Int)) -> [Observation]
    func fetchRecentLLMCalls(limit: Int) -> [LLMCall]
}

/// 이후 Dayflow StorageManager로 교체 예정.
public final class StorageScaffold: StorageManaging {
    private var basePath: URL?

    public init() {}

    public func configure(basePath: URL) throws {
        self.basePath = basePath
    }

    public func fetchTimelineCards(forDay day: String) -> [TimelineCardLite] {
        // TODO: GRDB StorageManager.fetchTimelineCards(forDay:)
        _ = basePath // keep reference for future use
        return []
    }

    public func fetchObservations(range: (Int, Int)) -> [Observation] {
        // TODO: GRDB StorageManager.fetchObservations(startTs:endTs:)
        return []
    }

    public func fetchRecentLLMCalls(limit: Int) -> [LLMCall] {
        // TODO: GRDB StorageManager.fetchRecentLLMCallsForDebug
        return []
    }
}
