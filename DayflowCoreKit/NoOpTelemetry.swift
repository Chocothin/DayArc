import Foundation

/// Dayflow의 Analytics/Sentry를 대체하는 더미 구현.
/// 네트워크 호출이나 파일 쓰기 없이 콘솔 로그만 남긴다(디버그 빌드 한정).
public enum AnalyticsService {
    public static func start(apiKey: String, host: String? = nil) {}
    public static func capture(_ event: String, _ props: [String: Any] = [:]) {
        #if DEBUG
        if props.isEmpty {
            print("[Analytics noop] \(event)")
        } else {
            print("[Analytics noop] \(event) props=\(props)")
        }
        #endif
    }
    public static func withSampling(probability: Double, block: () -> Void) {
        guard probability > 0 else { return }
        block()
    }
    public static func screen(_ name: String, _ props: [String: Any] = [:]) {
        capture("screen_viewed", ["screen": name].merging(props) { _, new in new })
    }
}

public enum SentryHelper {
    public static var isEnabled: Bool = false
    public static func addBreadcrumb(_ breadcrumb: Any) {
        #if DEBUG
        print("[Sentry noop] breadcrumb \(breadcrumb)")
        #endif
    }
}
