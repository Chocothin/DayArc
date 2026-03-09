//
//  VersionManager.swift
//  DayArc
//
//  Created for version conflict detection and old version cleanup
//

import Foundation
import AppKit

final class VersionManager {
    static let shared = VersionManager()
    
    private let bundleID = "com.dayarc.app"
    private let userDefaults = UserDefaults.standard
    private let lastVersionCheckKey = "lastVersionCheck"
    
    private init() {}
    
    /// Check for multiple installations of DayArc and alert user if found
    func checkForMultipleInstallations(presentingWindow: NSWindow? = nil) {
        let currentAppURL = Bundle.main.bundleURL
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        
        // Find all installations of this app
        let workspace = NSWorkspace.shared
        guard let allInstallations = workspace.urlsForApplications(withBundleIdentifier: bundleID) else {
            return
        }
        
        // Filter out current installation
        let otherInstallations = allInstallations.filter { $0 != currentAppURL }
        
        guard !otherInstallations.isEmpty else {
            // Only one installation found
            print("✅ [VersionManager] Only one installation detected")
            return
        }
        
        print("⚠️ [VersionManager] Found \\(otherInstallations.count) other installation(s)")
        
        // Get version info for each installation
        var installationInfo: [(url: URL, version: String)] = []
        
        for url in otherInstallations {
            if let bundle = Bundle(url: url),
               let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
                installationInfo.append((url, version))
                print("   - \\(url.path) (v\\(version))")
            }
        }
        
        // Show alert to user
        DispatchQueue.main.async {
            self.showMultipleInstallationsAlert(
                currentVersion: currentVersion,
                currentPath: currentAppURL.path,
                otherInstallations: installationInfo,
                presentingWindow: presentingWindow
            )
        }
    }
    
    /// Check if this is first launch after installation/update
    func isFirstLaunchAfterUpdate() -> Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let lastVersion = userDefaults.string(forKey: lastVersionCheckKey)
        
        if lastVersion != currentVersion {
            userDefaults.set(currentVersion, forKey: lastVersionCheckKey)
            return lastVersion != nil // true if updated, false if fresh install
        }
        
        return false
    }
    
    private func showMultipleInstallationsAlert(
        currentVersion: String,
        currentPath: String,
        otherInstallations: [(url: URL, version: String)],
        presentingWindow presentWin: NSWindow?
    ) {
        let alert = NSAlert()
        alert.messageText = "Multiple DayArc Installations Found"
        
        var infoText = "You are currently running DayArc v\\(currentVersion) from:\\n\\(currentPath)\\n\\n"
        infoText += "Other installation(s) found:\\n"
        
        for (url, version) in otherInstallations {
            infoText += "• v\\(version) at \\(url.path)\\n"
        }
        
        infoText += "\\nTo avoid conflicts, we recommend keeping only one installation."
        
        alert.informativeText = infoText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Keep Both")
        
        let response = presentWin != nil
            ? alert.beginSheetModal(for: presentWin!)
            : alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Show in Finder
            for (url, _) in otherInstallations {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
    
    /// Get current app version
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    /// Get current build number
    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    /// Get formatted version string (e.g., "1.0.0 (1)")
    var formattedVersion: String {
        "\\(currentVersion) (\\(currentBuild))"
    }
}
