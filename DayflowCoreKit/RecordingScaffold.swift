import Foundation

/// 녹화/배치 타이머를 위한 스탑게이트. 실제 ScreenRecorder/AnalysisManager로 교체 예정.
public protocol RecordingControlling {
    func startRecording()
    func stopRecording()
}

public protocol AnalysisControlling {
    func startAnalyzer()
    func stopAnalyzer()
}

public final class RecordingScaffold: RecordingControlling {
    public init() {}
    public func startRecording() {
        // TODO: ScreenRecorder start
        print("[RecordingScaffold] startRecording (noop)")
    }
    public func stopRecording() {
        // TODO: ScreenRecorder stop
        print("[RecordingScaffold] stopRecording (noop)")
    }
}

public final class AnalysisScaffold: AnalysisControlling {
    public init() {}
    public func startAnalyzer() {
        // TODO: AnalysisManager.startAnalysisJob
        print("[AnalysisScaffold] startAnalyzer (noop)")
    }
    public func stopAnalyzer() {
        // TODO: AnalysisManager.stopAnalysisJob
        print("[AnalysisScaffold] stopAnalyzer (noop)")
    }
}
