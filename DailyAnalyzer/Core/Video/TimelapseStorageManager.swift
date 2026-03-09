import Foundation

final class TimelapseStorageManager {
    static let shared = TimelapseStorageManager()

    private let fileMgr = FileManager.default
    private let root: URL
    private let queue = DispatchQueue(label: "com.dayflow.timelapse.purge", qos: .utility)

    private init() {
        let appSupport = fileMgr.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let path = appSupport.appendingPathComponent("DayArc/timelapses", isDirectory: true)
        root = path
        try? fileMgr.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var rootURL: URL { root }

    func currentUsageBytes() -> Int64 {
        (try? fileMgr.allocatedSizeOfDirectory(at: root)) ?? 0
    }

    func updateLimit(bytes: Int64) {
        let previous = StoragePreferences.timelapsesLimitBytes
        StoragePreferences.timelapsesLimitBytes = bytes
        if bytes < previous {
            purgeIfNeeded(limit: bytes)
        }
    }

    func purgeIfNeeded(limit: Int64? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            let limitBytes = limit ?? StoragePreferences.timelapsesLimitBytes
            guard limitBytes < Int64.max else { return }

            do {
                var usage = (try? self.fileMgr.allocatedSizeOfDirectory(at: self.root)) ?? 0
                
                print("🎬 [TimelapsePurge] Current usage: \(usage / 1024 / 1024)MB, Limit: \(limitBytes / 1024 / 1024)MB")
                
                if usage <= limitBytes {
                    print("✅ [TimelapsePurge] Storage within limit, no cleanup needed")
                    return
                }

                let excessMB = Double(usage - limitBytes) / 1024 / 1024
                print("⚠️ [TimelapsePurge] Exceeded limit by \(String(format: "%.2f", excessMB))MB, cleaning up...")

                let entries = try self.fileMgr.contentsOfDirectory(
                    at: self.root,
                    includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                .sorted { lhs, rhs in
                    // Use creation date only for consistency
                    let lDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let rDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return lDate < rDate
                }

                var deletedCount = 0
                var freedSpace: Int64 = 0
                
                for entry in entries {
                    if usage <= limitBytes { break }
                    let size = (try? self.entrySize(entry)) ?? 0
                    do {
                        try self.fileMgr.removeItem(at: entry)
                        usage -= size
                        freedSpace += size
                        deletedCount += 1
                    } catch {
                        print("⚠️ [TimelapsePurge] Failed to delete entry at \(entry.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                
                let freedMB = Double(freedSpace) / 1024 / 1024
                print("✅ [TimelapsePurge] Deleted \(deletedCount) entries, freed \(String(format: "%.2f", freedMB))MB")
            } catch {
                print("❌ [TimelapsePurge] Purge error: \(error)")
            }
        }
    }

    private func entrySize(_ url: URL) throws -> Int64 {
        var isDir: ObjCBool = false
        if fileMgr.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return (try? fileMgr.allocatedSizeOfDirectory(at: url)) ?? 0
        }
        let attrs = try fileMgr.attributesOfItem(atPath: url.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }
}
