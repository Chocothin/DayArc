import Foundation

/// Settings/외부 UI에서 DayflowCoreConfig를 생성해 엔진으로 전달하는 브리지 헬퍼.
/// 현재는 순수 데이터 구조만 포함하며, 호출 측에서 엔진 start/stop 여부를 결정한다.
public struct DayflowConfigBridge {
    public init() {}

    /// Settings 값으로부터 Config 생성
    public func makeConfig(
        basePath: URL?,
        allowWrites: Bool,
        provider: LLMProviderKind,
        apiKey: String?,
        endpoint: URL?
    ) -> DayflowCoreConfig {
        DayflowCoreConfig(
            basePath: basePath,
            allowWrites: allowWrites,
            provider: provider,
            credentials: ProviderCredentials(apiKey: apiKey, endpoint: endpoint)
        )
    }

    /// 엔진에 설정 적용 (side-effect 없음). start/stop은 호출 측에서 판단.
    public func applyConfig(_ config: DayflowCoreConfig) {
        DayflowEngine.shared.configure(config)
    }
}

/// Settings UI가 사용할 수 있는 프로바이더 옵션 예시
public enum DayflowProviderOption: String, CaseIterable {
    case gemini
    case ollama
    case dayflowBackend
    case custom

    public var kind: LLMProviderKind {
        switch self {
        case .gemini: return .gemini
        case .ollama: return .ollama
        case .dayflowBackend: return .dayflowBackend
        case .custom: return .custom("custom")
        }
    }
}
