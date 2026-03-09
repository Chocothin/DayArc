//
//  DayArcApp.swift
//  DayArc
//
//  Created on 2025-11-17.
//  Daily productivity analyzer
//

import SwiftUI

@main
struct DayArcApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
        }
    }
}

// App Delegate for lifecycle management
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.info("🚀 DayArc Application Started - Version: ReprocessingFix-v2", source: "AppDelegate")
        
        // Initialize managers
        _ = StorageManager.shared
        _ = AnalysisManager.shared
        
        // Initialize LogsViewModel to start capturing logs immediately
        Task { @MainActor in
            _ = LogsViewModel.shared
        }

        // Check and request permissions on first launch
        Logger.shared.info("Checking permissions...", source: "App")
        PermissionsManager.shared.checkAndRequestPermissions()

        // Migrate legacy Python config/state if present
        Logger.shared.debug("Running migration check...", source: "App")
        MigrationManager.shared.migrateIfNeeded()

        // Initialize scheduler
        Logger.shared.info("Setting up scheduler...", source: "App")
        SchedulerManager.shared.setup()
        
        // Start AI analysis pipeline
        Logger.shared.info("Starting analysis pipeline...", source: "App")
        AnalysisManager.shared.startAnalysisJob()
        
        // Register database path for legacy DB finder
        Task {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dbPath = appSupport.appendingPathComponent("DayArc/chunks.sqlite").path
            UserDefaults.standard.set(dbPath, forKey: "DayArcDatabasePath")
            Logger.shared.debug("Registered database path: \(dbPath)", source: "App")
        }

        Logger.shared.info("Application initialization complete", source: "App")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep app running in background
        return false
    }
}
