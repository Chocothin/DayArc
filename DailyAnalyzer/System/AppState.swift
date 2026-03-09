//
//  AppState.swift
//  DayArc
//
//  Global application state for DayArc
//

import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    // Recording state
    @Published var isRecordingEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isRecordingEnabled, forKey: "isRecordingEnabled")
            handleRecordingStateChange()
        }
    }
    
    @Published var recordingStatus: RecordingStatus = .idle
    @Published var hasScreenRecordingPermission: Bool = false
    
    private init() {
        // Load saved state
        isRecordingEnabled = UserDefaults.standard.bool(forKey: "isRecordingEnabled")
        
        // Check permissions on launch
        Task {
            await refreshScreenRecordingPermission()
        }
    }
    
    private func handleRecordingStateChange() {
        if isRecordingEnabled {
            Task {
                await startRecording()
            }
        } else {
            Task {
                await stopRecording()
            }
        }
    }
    
    private func startRecording() async {
        let permissionGranted = await refreshScreenRecordingPermission()
        guard permissionGranted else {
            print("[AppState] No screen recording permission")
            isRecordingEnabled = false
            return
        }
        
        recordingStatus = .starting
        
        do {
            try await RecordingManager.shared.startRecording()
            recordingStatus = .recording
            print("[AppState] Recording started successfully")
        } catch {
            print("[AppState] Failed to start recording: \(error)")
            recordingStatus = .idle
            isRecordingEnabled = false
        }
    }
    
    private func stopRecording() async {
        recordingStatus = .stopping
        
        await RecordingManager.shared.stopRecording()
        recordingStatus = .idle
        print("[AppState] Recording stopped successfully")
    }
    
    /// Refreshes the cached screen-recording permission flag.
    @discardableResult
    func refreshScreenRecordingPermission() async -> Bool {
        let granted = await PermissionsManager.shared.checkScreenRecordingPermission()
        hasScreenRecordingPermission = granted
        return granted
    }
}

enum RecordingStatus {
    case idle
    case starting
    case recording
    case paused
    case stopping
    
    var displayString: String {
        switch self {
        case .idle: return "대기 중"
        case .starting: return "시작 중..."
        case .recording: return "녹화 중"
        case .paused: return "일시정지"
        case .stopping: return "중지 중..."
        }
    }
    
    var icon: String {
        switch self {
        case .idle: return "circle"
        case .starting: return "clock"
        case .recording: return "record.circle.fill"
        case .paused: return "pause.circle.fill"
        case .stopping: return "stop.circle"
        }
    }
}
