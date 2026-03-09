//
//  StoragePreferences.swift
//  DayArc
//
//  Created to satisfy dependency in TimelapseStorageManager
//

import Foundation

struct StoragePreferences: Codable, Sendable {
    var recordingPath: String = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first?.path ?? ""
    var maxDiskUsageGB: Int = 10
    var retentionDays: Int = 7
    
    static let shared = StoragePreferences() // Simple shared instance for now
    
    // Static configuration for TimelapseStorageManager
    static var timelapsesLimitBytes: Int64 = 10 * 1024 * 1024 * 1024 // 10 GB
    static var recordingsLimitBytes: Int64 = 10 * 1024 * 1024 * 1024 // 10 GB (reduced from 50 GB)
    static var retentionDays: Int = 3 // Days to keep recordings before cleanup
}
