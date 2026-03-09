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

    private var config = DayflowCoreConfig()
    // 기본은 NO-OP 스캐폴드이지만, 읽기 전용 검증을 위해 실제 StorageManager를 시도한다.
    private var storage: StorageManaging
    private var recording: RecordingControlling
    private var analysis: AnalysisControlling
    private var llmService: LLMServicing

    public init(
        storage: StorageManaging = StorageScaffold(),
        recording: RecordingControlling = RecordingScaffold(),
        analysis: AnalysisControlling = AnalysisScaffold(),
        llmService: LLMServicing = LLMScaffold(),
        factory: ComponentFactory? = nil
    ) {
        self.storage = storage
        self.recording = recording
        self.analysis = analysis
        self.llmService = llmService

        // 우선순위: 명시적 팩토리 → 동적 타입 탐색 → NO-OP 유지
        if let f = factory {
            applyFactory(f)
        } else {
            if let dynStorage = NSClassFromString("StorageManager") as? StorageManaging.Type {
                self.storage = dynStorage.init()
            }
            if let dynRecorder = NSClassFromString("ScreenRecorder") as? RecordingControlling.Type {
                self.recording = dynRecorder.init()
            }
            if let dynAnalyzer = NSClassFromString("AnalysisManager") as? AnalysisControlling.Type {
                self.analysis = dynAnalyzer.init()
            }
            if let dynLLM = NSClassFromString("LLMService") as? LLMServicing.Type {
                self.llmService = dynLLM.init()
            }
        }
    }

    /// 설정만 갱신. 부작용 없음.
    public func configure(_ config: DayflowCoreConfig) {
        self.config = config
        if let base = config.basePath {
            try? storage.configure(basePath: base)
        } else if let auto = Self.defaultBasePathCandidates().first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            try? storage.configure(basePath: auto)
        }
    }

    // MARK: - 파이프라인 제어 (현재 더미/가드 포함)

    /// 녹화/분석 파이프라인 시작.
    public func start() {
        guard config.allowWrites else {
            print("[DayflowEngine] allowWrites=false → start()는 더미로 처리")
            return
        }
        recording.startRecording()
        analysis.startAnalyzer()
    }

    /// 파이프라인 중지.
    public func stop() {
        analysis.stopAnalyzer()
        recording.stopRecording()
    }

    // MARK: - 명시적 컴포넌트 주입

    /// 외부에서 실제 구현을 주입하고 싶을 때 사용.
    public func setComponents(
        storage: StorageManaging? = nil,
        recording: RecordingControlling? = nil,
        analysis: AnalysisControlling? = nil,
        llmService: LLMServicing? = nil
    ) {
        if let storage { self.storage = storage }
        if let recording { self.recording = recording }
        if let analysis { self.analysis = analysis }
        if let llmService { self.llmService = llmService }
    }

    // MARK: - 읽기 전용 쿼리 (스텁/Storage 기반)

    /// 타임라인 조회. 실제 구현 시 GRDB StorageManager.fetchTimelineCards(forDay:)로 교체.
    public func timeline(for day: Date) async -> [TimelineCardLite] {
        let dayString = Self.dayString(from: day)
        return storage.fetchTimelineCards(forDay: dayString)
    }

    /// 최근 LLM 호출 로그 조회.
    public func recentLLMCalls(limit: Int = 50) async -> [LLMCall] {
        storage.fetchRecentLLMCalls(limit: limit)
    }

    /// 최근 Observations 조회: 유닉스 타임 범위
    public func observations(startTs: Int, endTs: Int) async -> [Observation] {
        storage.fetchObservations(range: (startTs, endTs))
    }
}

// MARK: - 향후 연결 참고
// - Storage: Dayflow StorageManager 포함 + basePath 주입 후 마이그레이션 실행.
// - Recording: allowWrites==true인 경우에만 ScreenRecorder 활성화(권한 필요).
// - Analysis: AnalysisManager 타이머(60s)로 배치/LLM 처리.
// - Telemetry: 현재 No-Op, 필요 시 실제 Analytics/Sentry 구현으로 대체.

// MARK: - Helpers
extension DayflowEngine {
    /// 4AM 기준 day string (yyyy-MM-dd) 계산
    static func dayString(from date: Date) -> String {
        let cal = Calendar.current
        let fourAM = cal.date(bySettingHour: 4, minute: 0, second: 0, of: date)!
        let startOfDay = date < fourAM ? cal.date(byAdding: .day, value: -1, to: fourAM)! : fourAM
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = cal.timeZone
        return fmt.string(from: startOfDay)
    }

    /// Dayflow 기본 데이터 경로 후보
    public static func defaultBasePathCandidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/Dayflow"),
            home.appendingPathComponent("Library/Containers/app.dayflow.macos/Data/Library/Application Support/Dayflow"),
            home.appendingPathComponent("Library/Group Containers/app.dayflow.macos/Library/Application Support/Dayflow")
        ]
    }
}

// MARK: - Factory 적용
extension DayflowEngine {
    func applyFactory(_ factory: ComponentFactory) {
        if let storage = factory.makeStorageManager() { self.storage = storage }
        if let recorder = factory.makeRecorder() { self.recording = recorder }
        if let analyzer = factory.makeAnalyzer() { self.analysis = analyzer }
        if let llm = factory.makeLLMService() { self.llmService = llm }
    }
}
