//
//  Models.swift
//  DayArc
//
//  Data models for Dayflow activities and statistics
//

import Foundation

/// Represents a single activity/chunk from Dayflow
struct TimelineCard: Identifiable, Codable {
    // Original DayArc properties
    let id: String
    let identifier: String
    let createdAt: Date
    let startAt: Date
    let duration: TimeInterval
    let appName: String
    let appIdentifier: String
    let windowTitle: String?
    let url: String?
    let summary: String?           // Activity summary from Dayflow
    let detailedSummary: String?   // Detailed summary from Dayflow
    let subcategory: String?       // Subcategory from Dayflow

    // Dayflow Internalization properties
    var category: String?
    var title: String?
    var distractions: [Distraction]?
    var appSites: AppSites?
    var videoSummaryURL: String?
    var otherVideoSummaryURLs: [String]?
    var batchId: Int64?
    var recordId: Int64?
    var startTimestamp: String?
    var endTimestamp: String?
    var day: String?

    // Initializer for Dayflow compatibility
    init(
        recordId: Int64? = nil,
        batchId: Int64? = nil,
        startTimestamp: String = "",
        endTimestamp: String = "",
        startTs: Int? = nil,
        endTs: Int? = nil,
        category: String? = nil,
        subcategory: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        detailedSummary: String? = nil,
        day: String? = nil,
        distractions: [Distraction]? = nil,
        videoSummaryURL: String? = nil,
        otherVideoSummaryURLs: [String]? = nil,
        appSites: AppSites? = nil
    ) {
        self.recordId = recordId
        self.batchId = batchId
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.category = category
        self.subcategory = subcategory
        self.title = title
        self.summary = summary
        self.detailedSummary = detailedSummary
        self.day = day
        self.distractions = distractions
        self.videoSummaryURL = videoSummaryURL
        self.otherVideoSummaryURLs = otherVideoSummaryURLs
        self.appSites = appSites
        
        // Default values for DayArc required properties
        self.id = UUID().uuidString
        self.identifier = UUID().uuidString
        self.createdAt = Date()
        
        if let startTs = startTs {
            let start = Date(timeIntervalSince1970: TimeInterval(startTs))
            let endDate: Date
            if let endTs = endTs, endTs >= startTs {
                endDate = Date(timeIntervalSince1970: TimeInterval(endTs))
            } else {
                endDate = start
            }
            self.startAt = start
            self.duration = max(0, endDate.timeIntervalSince(start))
        } else {
            // Parse start/end timestamps if possible, otherwise use current date
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            
            if let start = formatter.date(from: startTimestamp),
               let end = formatter.date(from: endTimestamp) {
                // Note: This only captures time; date will default to a placeholder.
                self.startAt = start
                self.duration = end.timeIntervalSince(start)
            } else {
                self.startAt = Date()
                self.duration = 0
            }
        }
        
        self.appName = category ?? "Unknown"
        self.appIdentifier = "com.dayflow.activity"
        self.windowTitle = title
        self.url = nil
    }

    // Compatibility Initializer for LegacyDayflowReader and other existing code
    init(
        id: String,
        identifier: String,
        createdAt: Date,
        startAt: Date,
        duration: TimeInterval,
        appName: String,
        appIdentifier: String,
        windowTitle: String?,
        url: String?,
        summary: String?,
        detailedSummary: String?,
        subcategory: String?
    ) {
        self.id = id
        self.identifier = identifier
        self.createdAt = createdAt
        self.startAt = startAt
        self.duration = duration
        self.appName = appName
        self.appIdentifier = appIdentifier
        self.windowTitle = windowTitle
        self.url = url
        self.summary = summary
        self.detailedSummary = detailedSummary
        self.subcategory = subcategory
        
        // Initialize new properties with nil/defaults
        self.category = nil
        self.title = windowTitle
        self.distractions = nil
        self.appSites = nil
        self.videoSummaryURL = nil
        self.otherVideoSummaryURLs = nil
        self.batchId = nil
        self.recordId = nil
        self.startTimestamp = nil
        self.endTimestamp = nil
        self.day = nil
    }

    var endAt: Date {
        startAt.addingTimeInterval(duration)
    }

    /// Original Python: Duration in seconds
    var durationSeconds: Int {
        Int(duration)
    }
}

/// AI-generated summary for a timeline group
struct TimelineSummary: Codable {
    let title: String           // Concise title (e.g., "결제 알림 조사 및 컨트롤러 리팩토링")
    let summary: String         // Translated and summarized content
    let category: String?       // Category (e.g., "Work > Development")
}

/// Daily statistics aggregated from timeline cards
struct DailyStats: Codable {
    let date: Date
    let totalActivities: Int
    let totalActiveTime: TimeInterval
    let uniqueApps: Int
    let topApps: [AppUsage]
    let productivityScore: ProductivityScore

    // Deep Work & Focus metrics
    let deepWorkHours: Double          // 실제 Deep Work 시간 (25분 기준)
    let deepWorkSessions: Int          // Deep Work 세션 수
    let contextSwitches: Int           // 앱 전환 횟수
    let shortSessionCount: Int         // 5분 미만 짧은 세션 수
    let averageSessionLength: Double   // 평균 세션 길이 (초)

    /// Formatted total active time
    var formattedActiveTime: String {
        let hours = Int(totalActiveTime) / 3600
        let minutes = (Int(totalActiveTime) % 3600) / 60
        return String(format: "%dh %dm", hours, minutes)
    }

    /// Formatted Deep Work time
    var formattedDeepWorkTime: String {
        let hours = Int(deepWorkHours)
        let minutes = Int((deepWorkHours - Double(hours)) * 60)
        return String(format: "%dh %dm", hours, minutes)
    }

    /// Deep Work percentage
    var deepWorkPercentage: Double {
        return totalActiveTime > 0 ? (deepWorkHours * 3600 / totalActiveTime) * 100 : 0
    }
}

/// App usage statistics
struct AppUsage: Codable, Identifiable {
    let appName: String
    let duration: TimeInterval
    let percentage: Double
    let sessionCount: Int

    var id: String { appName }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}

/// Productivity score components (ported from Python)
struct ProductivityScore: Codable {
    let deepWorkScore: Double      // 45% weight
    let diversityScore: Double     // 15% weight
    let distractionScore: Double   // 30% weight (as concentration)
    let consistencyScore: Double   // 10% weight
    let totalScore: Double

    /// Calculate total weighted score
    static func calculate(deepWork: Double, diversity: Double, distraction: Double, consistency: Double) -> ProductivityScore {
        // Convert distraction penalty to concentration score (higher is better)
        let concentrationScore = max(0, 100 - distraction)

        let total = (
            deepWork * 0.45 +           // 45% weight (increased from 40%)
            diversity * 0.15 +          // 15% weight (decreased from 20%)
            concentrationScore * 0.30 + // 30% weight (unchanged)
            consistency * 0.10          // 10% weight (unchanged)
        )

        return ProductivityScore(
            deepWorkScore: deepWork,
            diversityScore: diversity,
            distractionScore: distraction,  // Keep original for display
            consistencyScore: consistency,
            totalScore: max(0, min(100, total))
        )
    }

    /// Get score category (Excellent, Good, Fair, Poor)
    var category: String {
        switch totalScore {
        case 80...:
            return "Excellent"
        case 60..<80:
            return "Good"
        case 40..<60:
            return "Fair"
        default:
            return "Poor"
        }
    }
}

/// AI Analysis result from LLM
struct AnalysisResult: Codable {
    let summary: String
    let insights: [String]
    let recommendations: [String]
    let generatedAt: Date
    let provider: String
    let model: String
}

/// App configuration categories (for productivity classification)
enum AppCategory: String, Codable {
    case productive = "productive"
    case neutral = "neutral"
    case distracting = "distracting"

    /// Default categorization based on common apps
    static func categorize(_ appName: String) -> AppCategory {
        let productive = [
            "Xcode", "Visual Studio Code", "Terminal", "iTerm",
            "Notion", "Obsidian", "Pages", "Word", "Excel",
            "IntelliJ IDEA", "PyCharm", "Sublime Text", "Cursor"
        ]

        let distracting = [
            "Safari", "Chrome", "Firefox", "YouTube",
            "Twitter", "Facebook", "Instagram", "TikTok",
            "Netflix", "Slack", "Discord", "Messages",
            "KakaoTalk", "Reddit", "Disney", "Ott", "Game", "Steam", "X"
        ]

        if productive.contains(where: { appName.localizedCaseInsensitiveContains($0) }) {
            return .productive
        } else if distracting.contains(where: { appName.localizedCaseInsensitiveContains($0) }) {
            return .distracting
        } else {
            return .neutral
        }
    }
}

/// Schedule configuration
class ScheduleConfig: Codable {
    var isEnabled: Bool = true
    var dailyTime: Date = {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = 20 // 8 PM default
        components.minute = 0
        return calendar.date(from: components) ?? Date()
    }()
    var generateWeekly: Bool = true
    var generateMonthly: Bool = true

    static var `default`: ScheduleConfig {
        return ScheduleConfig()
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case dailyTime
        case generateWeekly
        case generateMonthly
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        dailyTime = try container.decode(Date.self, forKey: .dailyTime)
        generateWeekly = try container.decode(Bool.self, forKey: .generateWeekly)
        generateMonthly = try container.decode(Bool.self, forKey: .generateMonthly)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(dailyTime, forKey: .dailyTime)
        try container.encode(generateWeekly, forKey: .generateWeekly)
        try container.encode(generateMonthly, forKey: .generateMonthly)
    }

    init() {}

    func save() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self) {
            UserDefaults.standard.set(encoded, forKey: "ScheduleConfig")
        }
    }

    static func load() -> ScheduleConfig {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "ScheduleConfig"),
           let config = try? decoder.decode(ScheduleConfig.self, from: data) {
            return config
        }
        return ScheduleConfig.default
    }
}

// MARK: - Report Language & Blocks

enum ReportLanguage: String, Codable, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }
}

/// Optional block toggles for customizing report content
struct ReportBlocks: Codable {
    var includeStartRoutine: Bool
    var includeTodo: Bool
    var includeFocusBlocks: Bool
    var includeEmotion: Bool
    var includeInsights: Bool
    var includeRecap: Bool
    var includeAISection: Bool
    var includeStats: Bool
    var includeTimeline: Bool
    var includeCategoriesAndApps: Bool
    var includeCharts: Bool
    var includeHistory: Bool
    var includeRecommendations: Bool
    var includeScorecard: Bool
    var includeFooter: Bool

    // New Deep Work & Distraction analysis blocks
    var includeDeepWorkAnalysis: Bool
    var includeDistractionBreakdown: Bool
    var includeContextSwitching: Bool

    enum CodingKeys: String, CodingKey {
        case includeStartRoutine, includeTodo, includeFocusBlocks, includeEmotion, includeInsights, includeRecap
        case includeAISection, includeStats, includeTimeline, includeCategoriesAndApps, includeCharts
        case includeHistory, includeRecommendations, includeScorecard, includeFooter
        case includeDeepWorkAnalysis, includeDistractionBreakdown, includeContextSwitching
    }

    init(
        includeStartRoutine: Bool,
        includeTodo: Bool,
        includeFocusBlocks: Bool,
        includeEmotion: Bool,
        includeInsights: Bool,
        includeRecap: Bool,
        includeAISection: Bool,
        includeStats: Bool,
        includeTimeline: Bool,
        includeCategoriesAndApps: Bool,
        includeCharts: Bool,
        includeHistory: Bool,
        includeRecommendations: Bool,
        includeScorecard: Bool,
        includeFooter: Bool,
        includeDeepWorkAnalysis: Bool,
        includeDistractionBreakdown: Bool,
        includeContextSwitching: Bool
    ) {
        self.includeStartRoutine = includeStartRoutine
        self.includeTodo = includeTodo
        self.includeFocusBlocks = includeFocusBlocks
        self.includeEmotion = includeEmotion
        self.includeInsights = includeInsights
        self.includeRecap = includeRecap
        self.includeAISection = includeAISection
        self.includeStats = includeStats
        self.includeTimeline = includeTimeline
        self.includeCategoriesAndApps = includeCategoriesAndApps
        self.includeCharts = includeCharts
        self.includeHistory = includeHistory
        self.includeRecommendations = includeRecommendations
        self.includeScorecard = includeScorecard
        self.includeFooter = includeFooter
        self.includeDeepWorkAnalysis = includeDeepWorkAnalysis
        self.includeDistractionBreakdown = includeDistractionBreakdown
        self.includeContextSwitching = includeContextSwitching
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeStartRoutine = try c.decodeIfPresent(Bool.self, forKey: .includeStartRoutine) ?? true
        includeTodo = try c.decodeIfPresent(Bool.self, forKey: .includeTodo) ?? true
        includeFocusBlocks = try c.decodeIfPresent(Bool.self, forKey: .includeFocusBlocks) ?? true
        includeEmotion = try c.decodeIfPresent(Bool.self, forKey: .includeEmotion) ?? true
        includeInsights = try c.decodeIfPresent(Bool.self, forKey: .includeInsights) ?? true
        includeRecap = try c.decodeIfPresent(Bool.self, forKey: .includeRecap) ?? true
        includeAISection = try c.decodeIfPresent(Bool.self, forKey: .includeAISection) ?? true
        includeStats = try c.decodeIfPresent(Bool.self, forKey: .includeStats) ?? true
        includeTimeline = try c.decodeIfPresent(Bool.self, forKey: .includeTimeline) ?? true
        includeCategoriesAndApps = try c.decodeIfPresent(Bool.self, forKey: .includeCategoriesAndApps) ?? true
        includeCharts = try c.decodeIfPresent(Bool.self, forKey: .includeCharts) ?? true
        includeHistory = try c.decodeIfPresent(Bool.self, forKey: .includeHistory) ?? true
        includeRecommendations = try c.decodeIfPresent(Bool.self, forKey: .includeRecommendations) ?? true
        includeScorecard = try c.decodeIfPresent(Bool.self, forKey: .includeScorecard) ?? true
        includeFooter = try c.decodeIfPresent(Bool.self, forKey: .includeFooter) ?? true
        includeDeepWorkAnalysis = try c.decodeIfPresent(Bool.self, forKey: .includeDeepWorkAnalysis) ?? true
        includeDistractionBreakdown = try c.decodeIfPresent(Bool.self, forKey: .includeDistractionBreakdown) ?? true
        includeContextSwitching = try c.decodeIfPresent(Bool.self, forKey: .includeContextSwitching) ?? true
    }

    static var dailyDefault: ReportBlocks {
        ReportBlocks(
            includeStartRoutine: true,
            includeTodo: true,
            includeFocusBlocks: true,
            includeEmotion: true,
            includeInsights: true,
            includeRecap: true,
            includeAISection: true,
            includeStats: true,
            includeTimeline: true,
            includeCategoriesAndApps: true,
            includeCharts: true,
            includeHistory: true,
            includeRecommendations: true,
            includeScorecard: true,
            includeFooter: true,
            includeDeepWorkAnalysis: true,
            includeDistractionBreakdown: true,
            includeContextSwitching: true
        )
    }

    static var weeklyDefault: ReportBlocks {
        ReportBlocks(
            includeStartRoutine: false,
            includeTodo: true,
            includeFocusBlocks: false,
            includeEmotion: false,
            includeInsights: true,
            includeRecap: true,
            includeAISection: true,
            includeStats: true,
            includeTimeline: false,
            includeCategoriesAndApps: true,
            includeCharts: true,
            includeHistory: true,
            includeRecommendations: true,
            includeScorecard: true,
            includeFooter: true,
            includeDeepWorkAnalysis: true,
            includeDistractionBreakdown: true,
            includeContextSwitching: true
        )
    }

    static var monthlyDefault: ReportBlocks {
        ReportBlocks(
            includeStartRoutine: false,
            includeTodo: true,
            includeFocusBlocks: false,
            includeEmotion: false,
            includeInsights: true,
            includeRecap: true,
            includeAISection: true,
            includeStats: true,
            includeTimeline: false,
            includeCategoriesAndApps: true,
            includeCharts: true,
            includeHistory: true,
            includeRecommendations: true,
            includeScorecard: true,
            includeFooter: true,
            includeDeepWorkAnalysis: true,
            includeDistractionBreakdown: true,
            includeContextSwitching: true
        )
    }
}

/// Persisted template configuration per report type
struct ReportTemplateConfig {
    private static func key(_ type: String) -> String { "ReportBlocks_\(type)" }

    static func load(for type: String) -> ReportBlocks {
        let defaults = UserDefaults.standard
        let k = key(type.lowercased())
        if let data = defaults.data(forKey: k),
           let decoded = try? JSONDecoder().decode(ReportBlocks.self, from: data) {
            return decoded
        }
        if type.lowercased().contains("weekly") { return ReportBlocks.weeklyDefault }
        if type.lowercased().contains("monthly") { return ReportBlocks.monthlyDefault }
        return ReportBlocks.dailyDefault
    }

    static func save(_ blocks: ReportBlocks, for type: String) {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(blocks) {
            defaults.set(data, forKey: key(type.lowercased()))
        }
    }
}

// MARK: - Deep Work & Focus Analysis Models

/// Deep Work session
struct DeepWorkSession: Codable {
    let startTime: Date
    let duration: Double           // in seconds
    let appName: String
    let focusScore: Double         // 0-100
}

/// Deep Work analysis result
struct DeepWorkAnalysis: Codable {
    let totalDeepWorkTime: Double  // in hours
    let sessions: [DeepWorkSession]
    let hourlyDistribution: [Int: Double]  // hour -> hours of deep work
    let peakHours: (start: Int, end: Int, score: Double)?

    enum CodingKeys: String, CodingKey {
        case totalDeepWorkTime, sessions, hourlyDistribution
    }

    init(totalDeepWorkTime: Double, sessions: [DeepWorkSession], hourlyDistribution: [Int: Double], peakHours: (Int, Int, Double)? = nil) {
        self.totalDeepWorkTime = totalDeepWorkTime
        self.sessions = sessions
        self.hourlyDistribution = hourlyDistribution
        self.peakHours = peakHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalDeepWorkTime = try container.decode(Double.self, forKey: .totalDeepWorkTime)
        sessions = try container.decode([DeepWorkSession].self, forKey: .sessions)
        hourlyDistribution = try container.decode([Int: Double].self, forKey: .hourlyDistribution)
        peakHours = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalDeepWorkTime, forKey: .totalDeepWorkTime)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(hourlyDistribution, forKey: .hourlyDistribution)
    }
}

/// Distraction analysis result
struct DistractionAnalysis: Codable {
    let distractingAppTime: Double         // in hours
    let interruptionCount: Int
    let shortSessionCount: Int
    let hourlyDistractionCount: [Int: Int] // hour -> count
    let peakDistractionHours: (start: Int, end: Int, count: Int)?

    enum CodingKeys: String, CodingKey {
        case distractingAppTime, interruptionCount, shortSessionCount, hourlyDistractionCount
    }

    init(distractingAppTime: Double, interruptionCount: Int, shortSessionCount: Int, hourlyDistractionCount: [Int: Int], peakDistractionHours: (Int, Int, Int)? = nil) {
        self.distractingAppTime = distractingAppTime
        self.interruptionCount = interruptionCount
        self.shortSessionCount = shortSessionCount
        self.hourlyDistractionCount = hourlyDistractionCount
        self.peakDistractionHours = peakDistractionHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        distractingAppTime = try container.decode(Double.self, forKey: .distractingAppTime)
        interruptionCount = try container.decode(Int.self, forKey: .interruptionCount)
        shortSessionCount = try container.decode(Int.self, forKey: .shortSessionCount)
        hourlyDistractionCount = try container.decode([Int: Int].self, forKey: .hourlyDistractionCount)
        peakDistractionHours = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(distractingAppTime, forKey: .distractingAppTime)
        try container.encode(interruptionCount, forKey: .interruptionCount)
        try container.encode(shortSessionCount, forKey: .shortSessionCount)
        try container.encode(hourlyDistractionCount, forKey: .hourlyDistractionCount)
    }
}

/// Flow session (30분+ 단일 앱 사용)
struct FlowSession: Codable {
    let startTime: Date
    let duration: Double    // in hours
    let appName: String
}

/// Context switching pattern
struct SwitchPattern: Codable {
    let fromApp: String
    let toApp: String
    let count: Int
}

/// Context switching analysis result
struct ContextSwitchingAnalysis: Codable {
    let totalSwitches: Int
    let averageSessionLength: Double  // in minutes
    let flowSessions: [FlowSession]
    let frequentSwitchPatterns: [SwitchPattern]
}

/// Focus block (연속된 활동 그룹)
struct FocusBlock: Codable {
    let startTime: Date
    let endTime: Date
    let apps: [String]
    let focusScore: Double
    let distractionCount: Int
}
