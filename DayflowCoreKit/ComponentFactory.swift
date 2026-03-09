import Foundation

/// DayflowCoreKit에서 실제 구현을 주입하기 위한 팩토리 프로토콜.
/// 빌드 시점에 의존성을 명시적으로 전달할 때 사용한다.
public protocol ComponentFactory {
    func makeStorageManager() -> StorageManaging?
    func makeRecorder() -> RecordingControlling?
    func makeAnalyzer() -> AnalysisControlling?
    func makeLLMService() -> LLMServicing?
}

/// 기본 NO-OP 팩토리 (필요 시 커스텀 팩토리 구현)
public struct NoOpComponentFactory: ComponentFactory {
    public init() {}
    public func makeStorageManager() -> StorageManaging? { nil }
    public func makeRecorder() -> RecordingControlling? { nil }
    public func makeAnalyzer() -> AnalysisControlling? { nil }
    public func makeLLMService() -> LLMServicing? { nil }
}
