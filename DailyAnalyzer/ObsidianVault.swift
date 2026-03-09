//
//  ObsidianVault.swift
//  DayArc
//
//  Obsidian vault integration for saving notes
//

import Foundation

enum VaultError: Error, LocalizedError {
    case vaultNotFound
    case invalidPath
    case permissionDenied(path: String)
    case writeError(String)
    case readError(String)

    var errorDescription: String? {
        switch self {
        case .vaultNotFound:
            return "Obsidian vault not found. Please configure the vault path in Settings."
        case .invalidPath:
            return "Invalid vault path."
        case .permissionDenied(let path):
            return "Permission denied. Cannot write to: \(path)"
        case .writeError(let message):
            return "Failed to write note: \(message)"
        case .readError(let message):
            return "Failed to read file: \(message)"
        }
    }
}

class ObsidianVault {
    private let vaultPath: String
    private let fileManager = FileManager.default

    /// Initialize with vault path
    init(vaultPath: String) {
        self.vaultPath = vaultPath
    }

    // MARK: - Note Saving

    /// Save daily note
    @discardableResult
    func saveDailyNote(date: Date, markdown: String) throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = formatter.string(from: date) + ".md"

        let dailyPath = (vaultPath as NSString).appendingPathComponent("Periodic Note/Daily")
        let filePath = (dailyPath as NSString).appendingPathComponent(filename)

        try saveNote(at: filePath, content: markdown, createDirectories: true)
        return filePath
    }

    /// Save weekly note
    @discardableResult
    func saveWeeklyNote(startDate: Date, markdown: String) throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-'W'ww"
        let filename = formatter.string(from: startDate) + ".md"

        let weeklyPath = (vaultPath as NSString).appendingPathComponent("Periodic Note/Weekly")
        let filePath = (weeklyPath as NSString).appendingPathComponent(filename)

        try saveNote(at: filePath, content: markdown, createDirectories: true)
        return filePath
    }

    /// Save monthly note
    @discardableResult
    func saveMonthlyNote(month: Date, markdown: String) throws -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let filename = formatter.string(from: month) + ".md"

        let monthlyPath = (vaultPath as NSString).appendingPathComponent("Periodic Note/Monthly")
        let filePath = (monthlyPath as NSString).appendingPathComponent(filename)

        try saveNote(at: filePath, content: markdown, createDirectories: true)
        return filePath
    }

    // MARK: - File Operations

    /// Save note to file
    private func saveNote(at path: String, content: String, createDirectories: Bool = false) throws {
        // Create directories if needed
        if createDirectories {
            let directory = (path as NSString).deletingLastPathComponent
            if !fileManager.fileExists(atPath: directory) {
                do {
                    try fileManager.createDirectory(
                        atPath: directory,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                } catch let error as NSError {
                    // Check for permission errors
                    if error.code == NSFileWriteNoPermissionError || error.domain == NSPOSIXErrorDomain && (error.code == 13 || error.code == 1) {
                        throw VaultError.permissionDenied(path: directory)
                    }
                    throw VaultError.writeError(error.localizedDescription)
                }
            }
        }

        // Write file
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } catch let error as NSError {
            // Check for permission errors
            if error.code == NSFileWriteNoPermissionError || error.domain == NSPOSIXErrorDomain && (error.code == 13 || error.code == 1) {
                throw VaultError.permissionDenied(path: path)
            }
            throw VaultError.writeError(error.localizedDescription)
        }
    }

    /// Check if note exists
    func noteExists(for date: Date, type: NoteType) -> Bool {
        let path = notePath(for: date, type: type)
        return fileManager.fileExists(atPath: path)
    }

    /// Read existing note
    func readNote(for date: Date, type: NoteType) throws -> String {
        let path = notePath(for: date, type: type)

        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw VaultError.readError(error.localizedDescription)
        }
    }

    /// Delete note
    func deleteNote(for date: Date, type: NoteType) throws {
        let path = notePath(for: date, type: type)

        if fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }

    // MARK: - Path Helpers

    /// Get note path for a specific date and type
    func notePath(for date: Date, type: NoteType) -> String {
        let formatter = DateFormatter()
        let subdirectory: String
        let filename: String

        switch type {
        case .daily:
            formatter.dateFormat = "yyyy-MM-dd"
            filename = formatter.string(from: date) + ".md"
            subdirectory = "Periodic Note/Daily"

        case .weekly:
            formatter.dateFormat = "yyyy-'W'ww"
            filename = formatter.string(from: date) + ".md"
            subdirectory = "Periodic Note/Weekly"

        case .monthly:
            formatter.dateFormat = "yyyy-MM"
            filename = formatter.string(from: date) + ".md"
            subdirectory = "Periodic Note/Monthly"
        }

        let directory = (vaultPath as NSString).appendingPathComponent(subdirectory)
        return (directory as NSString).appendingPathComponent(filename)
    }

    /// Validate vault path
    static func isValidVaultPath(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Find Obsidian vault in common locations
    static func findObsidianVault() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let possiblePaths = [
            homeDir.appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents").path,
            homeDir.appendingPathComponent("Documents/Obsidian").path,
            homeDir.appendingPathComponent("iCloud Drive/Obsidian").path,
        ]

        // Check if any directory exists and contains typical Obsidian structure
        for path in possiblePaths {
            if isValidVaultPath(path) {
                // Check for .obsidian directory
                let obsidianDir = (path as NSString).appendingPathComponent(".obsidian")
                if FileManager.default.fileExists(atPath: obsidianDir) {
                    return path
                }
            }
        }

        return nil
    }

    /// List all vaults in a directory
    static func listVaults(in directory: String) -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }

        return contents.compactMap { item in
            let fullPath = (directory as NSString).appendingPathComponent(item)
            let obsidianDir = (fullPath as NSString).appendingPathComponent(".obsidian")

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory),
               isDirectory.boolValue,
               FileManager.default.fileExists(atPath: obsidianDir) {
                return fullPath
            }
            return nil
        }
    }
}

// MARK: - Note Type

enum NoteType {
    case daily
    case weekly
    case monthly
}

// MARK: - Vault Configuration

class VaultConfiguration: ObservableObject, Codable {
    @Published var vaultPath: String = ""
    @Published var autoSave: Bool = true
    @Published var createBackups: Bool = false

    enum CodingKeys: String, CodingKey {
        case vaultPath
        case autoSave
        case createBackups
    }

    init() {
        // Try to auto-detect vault
        if let detected = ObsidianVault.findObsidianVault() {
            self.vaultPath = detected
        }
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vaultPath = try container.decode(String.self, forKey: .vaultPath)
        autoSave = try container.decode(Bool.self, forKey: .autoSave)
        createBackups = try container.decode(Bool.self, forKey: .createBackups)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vaultPath, forKey: .vaultPath)
        try container.encode(autoSave, forKey: .autoSave)
        try container.encode(createBackups, forKey: .createBackups)
    }

    /// Save to UserDefaults
    func save() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self) {
            UserDefaults.standard.set(encoded, forKey: "VaultConfiguration")
        }
    }

    /// Load from UserDefaults
    static func load() -> VaultConfiguration {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "VaultConfiguration"),
           let config = try? decoder.decode(VaultConfiguration.self, from: data) {
            return config
        }
        return VaultConfiguration()
    }

    /// Get ObsidianVault instance
    func getVault() throws -> ObsidianVault {
        guard !vaultPath.isEmpty else {
            throw VaultError.vaultNotFound
        }

        guard ObsidianVault.isValidVaultPath(vaultPath) else {
            throw VaultError.invalidPath
        }

        return ObsidianVault(vaultPath: vaultPath)
    }
}
