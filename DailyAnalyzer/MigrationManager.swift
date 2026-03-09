//
//  MigrationManager.swift
//  DayArc
//
//  Light-weight migration from the Python v1 config/state into Swift defaults.
//

import Foundation

class MigrationManager {
    static let shared = MigrationManager()
    private let migrationFlag = "DidMigrateFromPython"

    private init() {}

    func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: migrationFlag) == false else { return }

        var migratedAnything = false

        if migrateConfigYAML() {
            migratedAnything = true
        }

        if migrateStateJSON() {
            migratedAnything = true
        }

        if migratedAnything {
            defaults.set(true, forKey: migrationFlag)
            Logger.shared.info("Completed migration from Python config/state", source: "Migration")
        } else {
            Logger.shared.debug("No Python state found to migrate", source: "Migration")
        }
    }

    // MARK: - Config.yaml (Python)

    private func migrateConfigYAML() -> Bool {
        let configPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Daily Analyzer/config.yaml").path

        guard FileManager.default.fileExists(atPath: configPath),
              let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return false
        }

        let vaultPath = parseValue(forKey: "vault_path", in: contents)
        let dbPath = parseValue(forKey: "database_path", in: contents)

        var updated = false

        if let vaultPath = vaultPath, !vaultPath.isEmpty {
            let config = VaultConfiguration.load()
            if config.vaultPath.isEmpty {
                config.vaultPath = vaultPath
                config.save()
                Logger.shared.info("Migrated vault path from Python: \(vaultPath)", source: "Migration")
                updated = true
            }
        }

        if let dbPath = dbPath, !dbPath.isEmpty {
            UserDefaults.standard.set(dbPath, forKey: "DayflowDatabasePath")
            UserDefaults.standard.set(dbPath, forKey: "DayArcDatabasePath")
            Logger.shared.info("Migrated Dayflow DB path from Python: \(dbPath)", source: "Migration")
            updated = true
        }

        return updated
    }

    // MARK: - state.json (Python)

    private struct LegacyState: Decodable {
        let last_daily_run_date: String?
        let last_weekly_run_date: String?
        let last_monthly_run_date: String?
    }

    private func migrateStateJSON() -> Bool {
        let statePath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".dailyanalyzer/state.json").path

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)) else {
            return false
        }

        guard let legacy = try? JSONDecoder().decode(LegacyState.self, from: data) else {
            return false
        }

        let formatter = ISO8601DateFormatter()
        var migrated = false

        if let daily = legacy.last_daily_run_date,
           let date = formatter.date(from: daily) {
            UserDefaults.standard.set(date, forKey: "LastDailyReportRun")
            migrated = true
        }

        if let weekly = legacy.last_weekly_run_date,
           let date = formatter.date(from: weekly) {
            UserDefaults.standard.set(date, forKey: "LastWeeklyReportRun")
            migrated = true
        }

        if let monthly = legacy.last_monthly_run_date,
           let date = formatter.date(from: monthly) {
            UserDefaults.standard.set(date, forKey: "LastMonthlyReportRun")
            migrated = true
        }

        if migrated {
            Logger.shared.info("Migrated legacy run state from Python", source: "Migration")
        }

        return migrated
    }

    // MARK: - Helpers

    private func parseValue(forKey key: String, in contents: String) -> String? {
        // Very small YAML subset: find "key: value" and strip quotes/whitespace
        for line in contents.components(separatedBy: .newlines) {
            guard line.contains(key) else { continue }
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let rawValue = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
