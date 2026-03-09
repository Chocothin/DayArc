import Foundation

enum StoragePathMigrator {
    private static let migrationFlagKey = "didMigrateStorageToDayArc"

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationFlagKey) {
            print("ℹ️ StoragePathMigrator: skipping – already migrated")
            return
        }

        let fileManager = FileManager.default

        guard let bundleID = Bundle.main.bundleIdentifier else {
            print("⚠️ StoragePathMigrator: missing bundle identifier, marking migration as complete")
            defaults.set(true, forKey: migrationFlagKey)
            return
        }

        guard let newSupport = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            print("⚠️ StoragePathMigrator: unable to resolve unsandboxed Application Support directory")
            return
        }

        let destinationBase = newSupport.appendingPathComponent("DayArc", isDirectory: true)
        var migrated = false

        // 1. Move data from the old sandbox container (if we were previously sandboxed)
        let legacySandbox = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Application Support/Dayflow", isDirectory: true)

        if fileManager.fileExists(atPath: legacySandbox.path) {
            do {
                try fileManager.createDirectory(at: destinationBase, withIntermediateDirectories: true)
                try relocateDirectoryContents(from: legacySandbox, to: destinationBase, fileManager: fileManager)
                try? fileManager.removeItem(at: legacySandbox)
                migrated = true
                print("ℹ️ StoragePathMigrator: migrated sandbox data to \(destinationBase.path)")
            } catch {
                print("⚠️ StoragePathMigrator: sandbox migration failed with error: \(error)")
            }
        } else {
            print("ℹ️ StoragePathMigrator: sandbox container absent at \(legacySandbox.path)")
        }

        // 2. Move legacy unsandboxed Dayflow folder (if it exists) into the new DayArc folder
        let legacyDayflowFolder = newSupport.appendingPathComponent("Dayflow", isDirectory: true)
        if fileManager.fileExists(atPath: legacyDayflowFolder.path) {
            do {
                try fileManager.createDirectory(at: destinationBase, withIntermediateDirectories: true)
                try relocateDirectoryContents(from: legacyDayflowFolder, to: destinationBase, fileManager: fileManager)
                try? fileManager.removeItem(at: legacyDayflowFolder)
                migrated = true
                print("ℹ️ StoragePathMigrator: migrated legacy Dayflow folder to \(destinationBase.path)")
            } catch {
                print("⚠️ StoragePathMigrator: legacy folder migration failed with error: \(error)")
            }
        }

        defaults.set(true, forKey: migrationFlagKey)
        if !migrated {
            print("ℹ️ StoragePathMigrator: no legacy data detected for migration")
        }
    }

    private static func relocateDirectoryContents(from source: URL, to destination: URL, fileManager: FileManager) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        for item in contents {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])

            if values.isDirectory == true {
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                }
                try relocateDirectoryContents(from: item, to: target, fileManager: fileManager)
                try? fileManager.removeItem(at: item)
                continue
            }

            if fileManager.fileExists(atPath: target.path) {
                let existingSize = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let incomingSize = values.fileSize ?? 0

                if existingSize < incomingSize {
                    try fileManager.removeItem(at: target)
                    try fileManager.moveItem(at: item, to: target)
                } else {
                    try fileManager.removeItem(at: item)
                }
            } else {
                let parent = target.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parent.path) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
                try fileManager.moveItem(at: item, to: target)
            }
        }
    }
}
