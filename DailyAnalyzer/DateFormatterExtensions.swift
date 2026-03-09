//
//  DateFormatterExtensions.swift
//  DailyAnalyzer
//
//  Created to optimize DateFormatter usage across the app.
//  DateFormatter creation is expensive, so we use static cached instances.
//

import Foundation

extension DateFormatter {
    /// Format: "yyyy-MM-dd" (e.g., "2025-12-08")
    /// Use for standard date formatting
    static let yyyyMMdd: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Format: "h:mm a" (e.g., "11:37 AM")
    /// Use for 12-hour clock time display
    static let hmmA: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Format: "EEEE, MMMM d, yyyy" (e.g., "Sunday, December 8, 2025")
    /// Use for full date display
    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale.current
        return formatter
    }()

    /// Format: "MMM d" (e.g., "Dec 8")
    /// Use for short date display
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale.current
        return formatter
    }()

    /// Format: "MMMM yyyy" (e.g., "December 2025")
    /// Use for month and year display
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale.current
        return formatter
    }()

    /// Format: "yyyy년 MM월 dd일" (e.g., "2025년 12월 08일")
    /// Use for Korean date display
    static let koreanDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy년 MM월 dd일"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter
    }()

    /// Format: "yyyyMMdd_HHmmssSSS" (e.g., "20251208_113745123")
    /// Use for timestamp-based filenames
    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
