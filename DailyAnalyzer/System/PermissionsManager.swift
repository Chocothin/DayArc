//
//  PermissionsManager.swift
//  DayArc
//
//  Manages screen recording permissions for ScreenCaptureKit
//

import Foundation
import ScreenCaptureKit

@MainActor
class PermissionsManager {
    static let shared = PermissionsManager()
    
    private init() {}
    
    /// Check if screen recording permission is granted
    func checkScreenRecordingPermission() async -> Bool {
        // For macOS 13+, ScreenCaptureKit handles permissions internally
        // We'll attempt to get available content and see if it succeeds
        do {
            let availableContent = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            
            // If we can get displays, permission is granted
            return !availableContent.displays.isEmpty
        } catch {
            print("[PermissionsManager] Screen recording permission check failed: \(error)")
            return false
        }
    }
    
    /// Request screen recording permission
    /// Note: This will trigger system permission dialog on first run
    func requestScreenRecordingPermission() async -> Bool {
        // Simply attempting to access SCShareableContent will trigger the permission request
        return await checkScreenRecordingPermission()
    }
    
    /// Open system preferences for screen recording
    func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
    
    /// Compatibility method for App Delegate
    func checkAndRequestPermissions() {
        Task { @MainActor in
            let granted = await requestScreenRecordingPermission()
            AppState.shared.hasScreenRecordingPermission = granted
            if granted {
                Logger.shared.info("Screen recording permission granted", source: "PermissionsManager")
            } else {
                Logger.shared.warning("Screen recording permission denied", source: "PermissionsManager")
            }
            
            // Notifications
            NotificationManager.shared.requestPermission()
            NotificationManager.shared.registerNotificationCategories()
        }
    }
}
