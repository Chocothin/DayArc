import Foundation

// MARK: - Public Config & Facade (safe/read-only scaffold)

/// 엔진 설정. 기본은 읽기 전용(`allowWrites=false`).
public struct DayflowCoreConfig {
    /// Dayflow 데이터 루트 (`Application Support/Dayflow` 등)
    public var basePath: URL?
    /// 녹화/DB 쓰기 허용 여부. 기본 false → 실수 방지.
    public var allowWrites: Bool
    /// LLM 프로바이더 선택 (실제 연결 시 사용)
    public var provider: LLMProviderKind
    /// 선택적 API 키/엔드포인트 (Gemini/Ollama 등)
    public var credentials: ProviderCredentials?

    public init(
        basePath: URL? = nil,
        allowWrites: Bool = false,
        provider: LLMProviderKind = .gemini,
        credentials: ProviderCredentials? = nil
    ) {
        self.basePath = basePath
        self.allowWrites = allowWrites
        self.provider = provider
        self.credentials = credentials
    }
}

public enum LLMProviderKind {
    case gemini
    case ollama
    case dayflowBackend
    case custom(String) // 확장용
}

public struct ProviderCredentials {
    public var apiKey: String?
    public var endpoint: URL?
    public init(apiKey: String? = nil, endpoint: URL? = nil) {
        self.apiKey = apiKey
        self.endpoint = endpoint
    }
}

/// 타임라인 카드 최소 표현(경량 모델).
public struct TimelineCardLite: Sendable {
    public let id: Int64
    public let start: Date
    public let end: Date
    public let title: String
    public let category: String
    public let metadataJSON: String?
}

/// Dayflow 기능 내재화를 위한 퍼사드 스캐폴드.
/// 실제 구현/연결 지점은 TODO로 남겨둔 상태.
public final class DayflowEngine: @unchecked Sendable {
    public static let shared = DayflowEngine()
    private init() {}

    private var config = DayflowCoreConfig()

    /// 설정만 갱신. 부작용 없음.
    public func configure(_ config: DayflowCoreConfig) {
        self.config = config
    }

    // MARK: - 파이프라인 제어 (현재 더미)

    /// 녹화/분석 파이프라인 시작 (더미).
    /// 실제 연결 시 `allowWrites` 확인 후 StorageManager/Recorder/AnalysisManager를 시작.
    public func start() {
        guard config.allowWrites else {
            print("[DayflowEngine] allowWrites=false → start()는 더미로 처리")
            return
        }
        // TODO: StorageManager 경로 주입, ScreenRecorder 시작, AnalysisManager 타이머 시작
    }

    /// 파이프라인 중지 (더미).
    public func stop() {
        // TODO: ScreenRecorder/AnalysisManager 정지
    }

    // MARK: - 읽기 전용 쿼리 (스텁)

    /// 타임라인 조회. 실제 구현 시 GRDB StorageManager.fetchTimelineCards(forDay:)로 교체.
    public func timeline(for day: Date) async -> [TimelineCardLite] {
        // TODO: DB 연결 후 실제 데이터 반환
        return []
    }

    /// 최근 LLM 호출 로그 조회 스텁.
    public func recentLLMCalls(limit: Int = 50) async -> [String] {
        // TODO: StorageManager.fetchRecentLLMCallsForDebug
        return []
    }
}

// MARK: - 향후 연결 참고
// - Storage: Dayflow StorageManager 포함 + basePath 주입 후 마이그레이션 실행.
// - Recording: allowWrites==true인 경우에만 ScreenRecorder 활성화(권한 필요).
// - Analysis: AnalysisManager 타이머(60s)로 배치/LLM 처리.
// - Telemetry: 현재 No-Op, 필요 시 실제 Analytics/Sentry 구현으로 대체.
