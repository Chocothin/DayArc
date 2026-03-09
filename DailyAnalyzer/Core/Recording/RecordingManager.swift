//
//  RecordingManager.swift
//  DayArc
//
//  Coordinates screen recording components
//

import Foundation
import ScreenCaptureKit

@MainActor
final class RecordingManager: ObservableObject {
    static let shared = RecordingManager()
    
    @Published var isRecording: Bool = false
    @Published var recordingError: String?
    
    private var screenRecorder: ScreenRecorder?
    private let storageManager = StorageManager.shared
    
    private init() {}
    
    /// Start screen recording
    func startRecording() async throws {
        guard !isRecording else { return }
        
        // Check permissions first
        let hasPermission = await PermissionsManager.shared.checkScreenRecordingPermission()
        guard hasPermission else {
            recordingError = "Screen recording permission not granted"
            throw RecordingError.permissionDenied
        }
        
        // Check disk space
        guard storageManager.hasSufficientDiskSpace() else {
            recordingError = "Insufficient disk space. Please free up at least 500MB."
            throw RecordingError.insufficientDiskSpace
        }
        
        // Initialize ScreenRecorder
        screenRecorder = ScreenRecorder()
        
        // Start recording
        screenRecorder?.start()
        
        isRecording = true
        recordingError = nil
        
        print("[RecordingManager] Recording started")
    }
    
    /// Stop screen recording
    func stopRecording() async {
        guard isRecording else { return }
        
        await screenRecorder?.stop()
        screenRecorder = nil
        
        isRecording = false
        print("[RecordingManager] Recording stopped")
    }
}

enum RecordingError: Error {
    case permissionDenied
    case noDisplays
    case failedToStart
    case insufficientDiskSpace
}
