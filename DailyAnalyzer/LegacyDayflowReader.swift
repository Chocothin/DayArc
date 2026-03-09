//
//  DayflowDatabase.swift
//  DayArc
//
//  SQLite interface to Dayflow chunks.sqlite database
//

import Foundation
import SQLite3

enum DatabaseError: Error {
    case openFailed(String)
    case queryFailed(String)
    case noData
    case invalidData
    case notFound(String)
}

// Provide human-readable messages
extension DatabaseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            return "Failed to open database: \(message)"
        case .queryFailed(let message):
            return "Database query failed: \(message)"
        case .noData:
            return "No data found in the database"
        case .invalidData:
            return "Invalid data encountered while reading the database"
        case .notFound(let path):
            return "Database not found at \(path)"
        }
    }
}

class DayflowDatabase {
    /// Remember where we searched for diagnostics
    static var lastSearchedPaths: [String] = []

    private var db: OpaquePointer?
    private let dbPath: String

    /// Initialize with path to chunks.sqlite
    init(dbPath: String) {
        self.dbPath = dbPath
    }

    deinit {
        close()
    }

    /// Open database connection
    func open() throws {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            let error = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.openFailed("Failed to open database: \(error)")
        }
    }

    /// Close database connection
    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    /// Fetch all activities for a specific date (timeline_cards table)
    func fetchActivities(for date: Date) throws -> [TimelineCard] {
        if db == nil {
            try open()
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let startTimestamp = Int(startOfDay.timeIntervalSince1970)
        let endTimestamp = Int(endOfDay.timeIntervalSince1970)

        // timeline_cards schema:
        // id, batch_id, start, end, start_ts, end_ts, day, title, summary, category,
        // subcategory, detailed_summary, metadata, video_summary_url, created_at, is_deleted
        let query = """
            SELECT id, start_ts, end_ts, title, category, metadata, summary, detailed_summary, subcategory
            FROM timeline_cards
            WHERE start_ts >= ? AND start_ts < ? AND is_deleted = 0
            ORDER BY start_ts ASC
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.queryFailed("Failed to prepare statement: \(error)")
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, Int64(startTimestamp))
        sqlite3_bind_int64(statement, 2, Int64(endTimestamp))

        var activities: [TimelineCard] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let rawId = sqlite3_column_int64(statement, 0)
            let startTs = sqlite3_column_int64(statement, 1)
            let endTs = sqlite3_column_int64(statement, 2)

            let title: String = {
                if let text = sqlite3_column_text(statement, 3) {
                    return String(cString: text)
                }
                return "Untitled"
            }()

            let category: String = {
                if let text = sqlite3_column_text(statement, 4) {
                    return String(cString: text)
                }
                return "Unknown"
            }()

            var appName = category
            var windowTitle: String? = title
            var url: String? = nil

            // Parse metadata JSON for app info if available
            if let metadataText = sqlite3_column_text(statement, 5) {
                let metadataString = String(cString: metadataText)
                if let data = metadataString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let appSites = json["appSites"] as? [String: Any],
                       let primary = appSites["primary"] as? String {
                        appName = primary
                    }
                    if let window = json["windowTitle"] as? String {
                        windowTitle = window
                    }
                    if let link = json["url"] as? String {
                        url = link
                    }
                }
            }

            // Extract summary, detailed_summary, subcategory
            let summary: String? = {
                if let text = sqlite3_column_text(statement, 6) {
                    return String(cString: text)
                }
                return nil
            }()

            let detailedSummary: String? = {
                if let text = sqlite3_column_text(statement, 7) {
                    return String(cString: text)
                }
                return nil
            }()

            let subcategory: String? = {
                if let text = sqlite3_column_text(statement, 8) {
                    return String(cString: text)
                }
                return nil
            }()

            let startAt = Date(timeIntervalSince1970: TimeInterval(startTs))
            let endAt = Date(timeIntervalSince1970: TimeInterval(endTs))
            let duration = endAt.timeIntervalSince(startAt)

            let card = TimelineCard(
                id: String(rawId),
                identifier: UUID().uuidString,
                createdAt: startAt,
                startAt: startAt,
                duration: duration,
                appName: appName,
                appIdentifier: "",
                windowTitle: windowTitle,
                url: url,
                summary: summary,
                detailedSummary: detailedSummary,
                subcategory: subcategory
            )

            activities.append(card)
        }

        return activities
    }

    /// Fetch activities for a date range using timeline_cards
    func fetchActivities(from startDate: Date, to endDate: Date) throws -> [TimelineCard] {
        if db == nil {
            try open()
        }

        // Query the whole range in one go for efficiency
        let startTs = Int(startDate.timeIntervalSince1970)
        let endTs = Int(endDate.timeIntervalSince1970)

        let query = """
            SELECT id, start_ts, end_ts, title, category, metadata, summary, detailed_summary, subcategory
            FROM timeline_cards
            WHERE start_ts >= ? AND start_ts < ? AND is_deleted = 0
            ORDER BY start_ts ASC
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.queryFailed("Failed to prepare range statement: \(error)")
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, Int64(startTs))
        sqlite3_bind_int64(statement, 2, Int64(endTs))

        var activities: [TimelineCard] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let rawId = sqlite3_column_int64(statement, 0)
            let startTs = sqlite3_column_int64(statement, 1)
            let endTs = sqlite3_column_int64(statement, 2)

            let title: String = {
                if let text = sqlite3_column_text(statement, 3) {
                    return String(cString: text)
                }
                return "Untitled"
            }()

            let category: String = {
                if let text = sqlite3_column_text(statement, 4) {
                    return String(cString: text)
                }
                return "Unknown"
            }()

            var appName = category
            var windowTitle: String? = title
            var url: String? = nil

            if let metadataText = sqlite3_column_text(statement, 5) {
                let metadataString = String(cString: metadataText)
                if let data = metadataString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let appSites = json["appSites"] as? [String: Any],
                       let primary = appSites["primary"] as? String {
                        appName = primary
                    }
                    if let window = json["windowTitle"] as? String {
                        windowTitle = window
                    }
                    if let link = json["url"] as? String {
                        url = link
                    }
                }
            }

            // Extract summary, detailed_summary, subcategory
            let summary: String? = {
                if let text = sqlite3_column_text(statement, 6) {
                    return String(cString: text)
                }
                return nil
            }()

            let detailedSummary: String? = {
                if let text = sqlite3_column_text(statement, 7) {
                    return String(cString: text)
                }
                return nil
            }()

            let subcategory: String? = {
                if let text = sqlite3_column_text(statement, 8) {
                    return String(cString: text)
                }
                return nil
            }()

            let startAt = Date(timeIntervalSince1970: TimeInterval(startTs))
            let endAt = Date(timeIntervalSince1970: TimeInterval(endTs))
            let duration = endAt.timeIntervalSince(startAt)

            let card = TimelineCard(
                id: String(rawId),
                identifier: UUID().uuidString,
                createdAt: startAt,
                startAt: startAt,
                duration: duration,
                appName: appName,
                appIdentifier: "",
                windowTitle: windowTitle,
                url: url,
                summary: summary,
                detailedSummary: detailedSummary,
                subcategory: subcategory
            )

            activities.append(card)
        }

        return activities
    }

    /// Check if database exists and is accessible
    static func isDatabaseAvailable(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    /// Find the DayArc recorder database in common locations (prefers new paths, falls back to legacy Dayflow locations)
    static func findDayflowDatabase() -> String? {
        lastSearchedPaths.removeAll()
        
        let defaults = UserDefaults.standard
        let overrideKeys = ["DayArcDatabasePath", "DayflowDatabasePath"]
        for key in overrideKeys {
            if let customPath = defaults.string(forKey: key) {
                lastSearchedPaths.append(customPath)
                if isDatabaseAvailable(at: customPath) {
                    return customPath
                }
            }
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dailyanalyzer.app"

        var possiblePaths: [String] = [
            homeDir.appendingPathComponent("Library/Application Support/DayArc/chunks.sqlite").path,
            homeDir.appendingPathComponent("Library/Application Support/DayArc/timeline.sqlite").path,
            homeDir.appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/DayArc/chunks.sqlite").path,
            homeDir.appendingPathComponent("Library/Group Containers/\(bundleID)/Library/Application Support/DayArc/chunks.sqlite").path,
            homeDir.appendingPathComponent("Library/Application Support/Dayflow/chunks.sqlite").path,
            homeDir.appendingPathComponent("Library/Containers/app.dayflow.macos/Data/Library/Application Support/Dayflow/chunks.sqlite").path,
            homeDir.appendingPathComponent("Library/Group Containers/app.dayflow.macos/Library/Application Support/Dayflow/chunks.sqlite").path
        ]

        lastSearchedPaths.append(contentsOf: possiblePaths)
        return possiblePaths.first { isDatabaseAvailable(at: $0) }
    }
}
