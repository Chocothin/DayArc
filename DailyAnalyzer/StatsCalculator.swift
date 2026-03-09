//
//  StatsCalculator.swift
//  DayArc
//
//  Statistics calculation and productivity scoring
//  Ported from Python version
//

import Foundation

class StatsCalculator {

    /// Calculate daily statistics from activities
    static func calculateDailyStats(from activities: [TimelineCard], date: Date) -> DailyStats {
        guard !activities.isEmpty else {
            return DailyStats(
                date: date,
                totalActivities: 0,
                totalActiveTime: 0,
                uniqueApps: 0,
                topApps: [],
                productivityScore: ProductivityScore(
                    deepWorkScore: 0,
                    diversityScore: 0,
                    distractionScore: 0,
                    consistencyScore: 0,
                    totalScore: 0
                ),
                deepWorkHours: 0,
                deepWorkSessions: 0,
                contextSwitches: 0,
                shortSessionCount: 0,
                averageSessionLength: 0
            )
        }

        let sortedActivities = activities.sorted { $0.startAt < $1.startAt }

        // Calculate total active time
        let totalActiveTime = sortedActivities.reduce(0) { $0 + $1.duration }

        // Group by app and calculate usage
        var appUsageDict: [String: TimeInterval] = [:]
        var appSessionCount: [String: Int] = [:]
        for activity in sortedActivities {
            appUsageDict[activity.appName, default: 0] += activity.duration
            appSessionCount[activity.appName, default: 0] += 1
        }

        // Calculate unique apps
        let uniqueApps = appUsageDict.count

        // Create top apps list sorted by duration
        let topApps = appUsageDict.map { appName, duration in
            let percentage = (duration / totalActiveTime) * 100
            return AppUsage(
                appName: appName,
                duration: duration,
                percentage: percentage,
                sessionCount: appSessionCount[appName] ?? 0
            )
        }.sorted { $0.duration > $1.duration }

        let deepWorkAnalysis = calculateDeepWorkAnalysis(from: sortedActivities, thresholdMinutes: 25)
        let distractionAnalysis = calculateDistractionAnalysis(from: sortedActivities)
        let contextSwitching = calculateContextSwitchingAnalysis(from: sortedActivities)

        // Calculate productivity score
        let productivityScore = calculateProductivityScore(
            activities: sortedActivities,
            appUsage: appUsageDict,
            totalActiveTime: totalActiveTime,
            deepWorkAnalysis: deepWorkAnalysis,
            distractionAnalysis: distractionAnalysis,
            contextSwitching: contextSwitching
        )

        return DailyStats(
            date: date,
            totalActivities: sortedActivities.count,
            totalActiveTime: totalActiveTime,
            uniqueApps: uniqueApps,
            topApps: Array(topApps.prefix(10)), // Top 10 apps
            productivityScore: productivityScore,
            deepWorkHours: deepWorkAnalysis.totalDeepWorkTime,
            deepWorkSessions: deepWorkAnalysis.sessions.count,
            contextSwitches: contextSwitching.totalSwitches,
            shortSessionCount: distractionAnalysis.shortSessionCount,
            averageSessionLength: totalActiveTime > 0 ? totalActiveTime / Double(sortedActivities.count) : 0
        )
    }

    /// Calculate productivity score using 4-component algorithm
    private static func calculateProductivityScore(
        activities: [TimelineCard],
        appUsage: [String: TimeInterval],
        totalActiveTime: TimeInterval,
        deepWorkAnalysis: DeepWorkAnalysis,
        distractionAnalysis: DistractionAnalysis,
        contextSwitching: ContextSwitchingAnalysis
    ) -> ProductivityScore {

        // 1. Deep Work Score (40% weight)
        let deepWorkScore = calculateDeepWorkScore(
            deepWorkAnalysis: deepWorkAnalysis,
            totalActiveTime: totalActiveTime
        )

        // 2. Diversity Score (20% weight)
        let diversityScore = calculateDiversityScore(appUsage: appUsage)

        // 3. Distraction Score (-30% weight, penalty)
        let distractionScore = calculateDistractionScore(
            distractionAnalysis: distractionAnalysis,
            totalActiveTime: totalActiveTime
        )

        // 4. Consistency Score (10% weight)
        let baseConsistency = calculateConsistencyScore(activities: activities)
        let switchPenalty = min(10, Double(contextSwitching.totalSwitches) * 0.2)
        let consistencyScore = max(0, baseConsistency - switchPenalty)

        return ProductivityScore.calculate(
            deepWork: deepWorkScore,
            diversity: diversityScore,
            distraction: distractionScore,
            consistency: consistencyScore
        )
    }

    // MARK: - Score Components

    /// Deep Work Score: 25분 이상 이어진 세션 비중 + 세션 수 가중치
    private static func calculateDeepWorkScore(
        deepWorkAnalysis: DeepWorkAnalysis,
        totalActiveTime: TimeInterval
    ) -> Double {
        // totalDeepWorkTime은 이미 시간(hours) 단위, totalActiveTime은 초(seconds) 단위
        // 따라서 totalDeepWorkTime에 3600을 곱해 초 단위로 변환해야 함
        let ratio = totalActiveTime > 0 ? (deepWorkAnalysis.totalDeepWorkTime * 3600) / totalActiveTime : 0
        let sessionScore = min(15, Double(deepWorkAnalysis.sessions.count) * 1.5) // Reduced bonus

        // Stricter thresholds:
        // 60% 이상 -> 90점 베이스
        // 50% 이상 -> 80점 베이스
        // 30% 이상 -> 60점 베이스
        if ratio >= 0.6 {
            return min(100, 90 + (ratio - 0.6) * 25 + sessionScore)
        } else if ratio >= 0.5 {
            return min(95, 80 + (ratio - 0.5) * 100 + sessionScore)
        } else if ratio >= 0.3 {
            return 60 + (ratio - 0.3) * 100 + sessionScore
        } else {
            return max(0, ratio * 200 + sessionScore)
        }
    }

    /// Diversity Score: Variety of apps used (prevents monotony)
    private static func calculateDiversityScore(appUsage: [String: TimeInterval]) -> Double {
        let appCount = appUsage.count

        // Calculate entropy (Shannon diversity)
        let totalTime = appUsage.values.reduce(0, +)
        var entropy: Double = 0

        for duration in appUsage.values {
            let p = duration / totalTime
            if p > 0 {
                entropy -= p * log2(p)
            }
        }

        // Normalize entropy
        // Maximum entropy occurs when all apps have equal time
        let maxEntropy = appCount > 1 ? log2(Double(appCount)) : 1
        let normalizedEntropy = maxEntropy > 0 ? entropy / maxEntropy : 0

        // Score based on app count and entropy
        // Ideal: 2-5 apps (User preference: fewer apps)
        var score: Double = 0

        if appCount >= 2 && appCount <= 5 {
            score = 80 + normalizedEntropy * 20 // 80-100
        } else if appCount < 2 {
            // Too few apps (1)
            score = 60 + normalizedEntropy * 20 // 60-80
        } else {
            // Too many apps (> 5)
            // Penalty: 10 points per excess app
            // Base: Calculated from entropy (max 100)
            // Example: 10 apps -> 5 excess -> 50 penalty. 100 - 50 = 50.
            let baseScore = 80 + normalizedEntropy * 20
            let penalty = Double(appCount - 5) * 10.0
            score = max(0, baseScore - penalty)
        }

        return min(100, max(0, score))
    }

    /// Distraction Score: 강화된 패널티 (방해 앱 + 잦은 인터럽션/짧은 세션)
    private static func calculateDistractionScore(
        distractionAnalysis: DistractionAnalysis,
        totalActiveTime: TimeInterval
    ) -> Double {
        // distractingAppTime은 이미 시간(hours) 단위, totalActiveTime은 초(seconds) 단위
        // 따라서 distractingAppTime에 3600을 곱해 초 단위로 변환해야 함
        let ratio = totalActiveTime > 0 ? (distractionAnalysis.distractingAppTime * 3600) / totalActiveTime : 0

        // 강화된 패널티: 방해 시간 비중 + 잦은 인터럽션/짧은 세션을 모두 반영
        let interruptionPenalty = min(30, Double(distractionAnalysis.interruptionCount) * 2.0) // Increased penalty
        let shortSessionPenalty = min(20, Double(distractionAnalysis.shortSessionCount) * 1.0)

        // Much stricter penalties for distraction ratio
        if ratio >= 0.5 {
            return min(100, 90 + (ratio - 0.5) * 20 + interruptionPenalty + shortSessionPenalty)
        } else if ratio >= 0.3 {
            return min(95, 75 + (ratio - 0.3) * 75 + interruptionPenalty + shortSessionPenalty)
        } else if ratio >= 0.1 {
            return 40 + (ratio - 0.1) * 175 + interruptionPenalty + shortSessionPenalty
        } else {
            return max(0, ratio * 500 + interruptionPenalty + shortSessionPenalty) // Steep penalty even for low ratio
        }
    }

    /// Consistency Score: Even distribution of work throughout the day
    private static func calculateConsistencyScore(activities: [TimelineCard]) -> Double {
        guard !activities.isEmpty else { return 0 }

        // Divide day into 1-hour buckets (24 hours)
        var hourBuckets: [Int: TimeInterval] = [:]

        let calendar = Calendar.current
        for activity in activities {
            let hour = calendar.component(.hour, from: activity.startAt)
            hourBuckets[hour, default: 0] += activity.duration
        }

        // Calculate coefficient of variation (CV)
        // Lower CV = more consistent = higher score
        let values = Array(hourBuckets.values)
        guard values.count >= 2 else { return 50 } // Not enough data

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        let stdDev = sqrt(variance)

        let cv = mean > 0 ? stdDev / mean : 0

        // Stricter scoring:
        // CV of 0 = perfect consistency = 100
        // CV of 0.5 = moderate variation = 50
        // CV of 1.0+ = high variation = 0
        let score = max(0, min(100, 100 - cv * 100))

        return score
    }

    // MARK: - Deep Work / Distraction / Context Helpers

    static func calculateDeepWorkAnalysis(from activities: [TimelineCard], thresholdMinutes: Double = 25) -> DeepWorkAnalysis {
        guard !activities.isEmpty else {
            return DeepWorkAnalysis(totalDeepWorkTime: 0, sessions: [], hourlyDistribution: [:])
        }

        let thresholdSeconds = thresholdMinutes * 60.0
        var sessions: [DeepWorkSession] = []
        var hourlyDistribution: [Int: Double] = [:]
        let calendar = Calendar.current

        for activity in activities where activity.duration >= thresholdSeconds {
            let durationHours = activity.duration / 3600.0
            let startHour = calendar.component(.hour, from: activity.startAt)
            hourlyDistribution[startHour, default: 0] += durationHours

            // Focus score: longer uninterrupted sessions = higher score (capped at 100)
            let focusScore = min(100, (activity.duration / thresholdSeconds) * 65)
            sessions.append(
                DeepWorkSession(
                    startTime: activity.startAt,
                    duration: activity.duration,
                    appName: activity.appName,
                    focusScore: focusScore
                )
            )
        }

        let totalDeepWorkTime = sessions.reduce(0.0) { $0 + $1.duration } / 3600.0
        let peak = hourlyDistribution.max { $0.value < $1.value }
        let peakTuple = peak.map { ($0.key, ($0.key + 1) % 24, $0.value) }

        return DeepWorkAnalysis(
            totalDeepWorkTime: totalDeepWorkTime,
            sessions: sessions,
            hourlyDistribution: hourlyDistribution,
            peakHours: peakTuple
        )
    }

    static func calculateDistractionAnalysis(from activities: [TimelineCard], shortSessionMinutes: Double = 5) -> DistractionAnalysis {
        guard !activities.isEmpty else {
            return DistractionAnalysis(
                distractingAppTime: 0,
                interruptionCount: 0,
                shortSessionCount: 0,
                hourlyDistractionCount: [:]
            )
        }

        let shortThreshold = shortSessionMinutes * 60.0
        var distractingSeconds: Double = 0
        var interruptionCount = 0
        var shortSessionCount = 0
        var hourlyDistractionCount: [Int: Int] = [:]
        let calendar = Calendar.current

        for activity in activities {
            if activity.duration < shortThreshold {
                shortSessionCount += 1
            }
            if AppCategory.categorize(activity.appName) == .distracting {
                distractingSeconds += activity.duration
                interruptionCount += 1
                let hour = calendar.component(.hour, from: activity.startAt)
                hourlyDistractionCount[hour, default: 0] += 1
            }
        }

        let peak = hourlyDistractionCount.max { $0.value < $1.value }
        let peakTuple = peak.map { ($0.key, ($0.key + 1) % 24, $0.value) }

        return DistractionAnalysis(
            distractingAppTime: distractingSeconds / 3600.0,
            interruptionCount: interruptionCount,
            shortSessionCount: shortSessionCount,
            hourlyDistractionCount: hourlyDistractionCount,
            peakDistractionHours: peakTuple
        )
    }

    static func calculateContextSwitchingAnalysis(from activities: [TimelineCard]) -> ContextSwitchingAnalysis {
        let sorted = activities.sorted { $0.startAt < $1.startAt }

        guard let first = sorted.first else {
            return ContextSwitchingAnalysis(
                totalSwitches: 0,
                averageSessionLength: 0,
                flowSessions: [],
                frequentSwitchPatterns: []
            )
        }

        var totalSwitches = 0
        var appPattern: [String: Int] = [:]
        var flowSessions: [FlowSession] = []

        var currentApp = first.appName
        var currentStart = first.startAt
        var currentDuration = first.duration
        var totalDuration: Double = 0

        for activity in sorted {
            totalDuration += activity.duration

            if activity.appName != currentApp {
                totalSwitches += 1
                let key = "\(currentApp)->\(activity.appName)"
                appPattern[key, default: 0] += 1

                let hours = currentDuration / 3600.0
                if hours >= 0.5 { // 30분 이상 흐름(Flow)
                    flowSessions.append(
                        FlowSession(
                            startTime: currentStart,
                            duration: hours,
                            appName: currentApp
                        )
                    )
                }

                currentApp = activity.appName
                currentStart = activity.startAt
                currentDuration = activity.duration
            } else {
                currentDuration += activity.duration
            }
        }

        // Append last aggregated run
        let lastHours = currentDuration / 3600.0
        if lastHours >= 0.5 {
            flowSessions.append(
                FlowSession(
                    startTime: currentStart,
                    duration: lastHours,
                    appName: currentApp
                )
            )
        }

        let frequentPatterns: [SwitchPattern] = appPattern
            .sorted { $0.value > $1.value }
            .prefix(5)
            .compactMap { key, count in
                let parts = key.split(separator: "->").map(String.init)
                guard parts.count == 2 else { return nil }
                return SwitchPattern(fromApp: parts[0], toApp: parts[1], count: count)
            }

        let averageSessionLength = totalDuration / Double(max(1, activities.count)) / 60.0

        return ContextSwitchingAnalysis(
            totalSwitches: totalSwitches,
            averageSessionLength: averageSessionLength,
            flowSessions: flowSessions.sorted { $0.startTime < $1.startTime },
            frequentSwitchPatterns: frequentPatterns
        )
    }

    static func generateFocusBlocks(from activities: [TimelineCard], minimumMinutes: Double = 20) -> [FocusBlock] {
        guard let first = activities.sorted(by: { $0.startAt < $1.startAt }).first else { return [] }

        let sorted = activities.sorted { $0.startAt < $1.startAt }
        var blocks: [FocusBlock] = []
        var currentStart = first.startAt
        var currentEnd = first.endAt
        var apps: [String] = [first.appName]
        var distractionCount = AppCategory.categorize(first.appName) == .distracting ? 1 : 0
        let minSeconds = minimumMinutes * 60.0

        for activity in sorted.dropFirst() {
            let gap = activity.startAt.timeIntervalSince(currentEnd)
            if gap <= 5 * 60 { // allow small gap between merged activities
                currentEnd = max(currentEnd, activity.endAt)
                if !apps.contains(activity.appName) { apps.append(activity.appName) }
                if AppCategory.categorize(activity.appName) == .distracting { distractionCount += 1 }
            } else {
                let duration = currentEnd.timeIntervalSince(currentStart)
                if duration >= minSeconds {
                    let focusScore = max(30, 100 - Double(distractionCount * 10) - Double(max(0, apps.count - 1)) * 5)
                    blocks.append(
                        FocusBlock(
                            startTime: currentStart,
                            endTime: currentEnd,
                            apps: apps,
                            focusScore: focusScore,
                            distractionCount: distractionCount
                        )
                    )
                }

                currentStart = activity.startAt
                currentEnd = activity.endAt
                apps = [activity.appName]
                distractionCount = AppCategory.categorize(activity.appName) == .distracting ? 1 : 0
            }
        }

        let finalDuration = currentEnd.timeIntervalSince(currentStart)
        if finalDuration >= minSeconds {
            let focusScore = max(30, 100 - Double(distractionCount * 10) - Double(max(0, apps.count - 1)) * 5)
            blocks.append(
                FocusBlock(
                    startTime: currentStart,
                    endTime: currentEnd,
                    apps: apps,
                    focusScore: focusScore,
                    distractionCount: distractionCount
                )
            )
        }

        return blocks.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Weekly/Monthly Stats

    /// Calculate weekly statistics
    static func calculateWeeklyStats(from dailyStats: [DailyStats]) -> DailyStats? {
        guard !dailyStats.isEmpty else { return nil }

        let totalActivities = dailyStats.reduce(0) { $0 + $1.totalActivities }
        let totalActiveTime = dailyStats.reduce(0) { $0 + $1.totalActiveTime }

        // Merge top apps from all days
        var mergedAppUsage: [String: AppUsage] = [:]
        for stats in dailyStats {
            for app in stats.topApps {
                if var existing = mergedAppUsage[app.appName] {
                    existing = AppUsage(
                        appName: app.appName,
                        duration: existing.duration + app.duration,
                        percentage: 0, // Will recalculate
                        sessionCount: existing.sessionCount + app.sessionCount
                    )
                    mergedAppUsage[app.appName] = existing
                } else {
                    mergedAppUsage[app.appName] = app
                }
            }
        }

        // Recalculate percentages
        let topApps = mergedAppUsage.values.map { app in
            AppUsage(
                appName: app.appName,
                duration: app.duration,
                percentage: (app.duration / totalActiveTime) * 100,
                sessionCount: app.sessionCount
            )
        }.sorted { $0.duration > $1.duration }

        // Average productivity scores - only include days WITH actual active time
        let daysWithActivity = dailyStats.filter { $0.totalActiveTime > 0 }
        let activeDayCount = max(1, daysWithActivity.count)  // Avoid division by zero
        Logger.shared.debug("Aggregate stats: \(dailyStats.count) total days, \(activeDayCount) days with activity", source: "StatsCalculator")

        // Log each day's score for debugging
        for (index, day) in daysWithActivity.enumerated() {
            Logger.shared.debug("Day \(index + 1): activeTime=\(String(format: "%.1f", day.totalActiveTime/3600))h, totalScore=\(String(format: "%.1f", day.productivityScore.totalScore))", source: "StatsCalculator")
        }

        // Calculate average of total scores directly (simpler and more intuitive)
        let avgTotalScore = daysWithActivity.reduce(0.0) { $0 + $1.productivityScore.totalScore } / Double(activeDayCount)
        Logger.shared.debug("Average total score (direct): \(String(format: "%.1f", avgTotalScore))", source: "StatsCalculator")

        let avgDeepWork = daysWithActivity.reduce(0.0) { $0 + $1.productivityScore.deepWorkScore } / Double(activeDayCount)
        let avgDiversity = daysWithActivity.reduce(0.0) { $0 + $1.productivityScore.diversityScore } / Double(activeDayCount)
        let avgDistraction = daysWithActivity.reduce(0.0) { $0 + $1.productivityScore.distractionScore } / Double(activeDayCount)
        let avgConsistency = daysWithActivity.reduce(0.0) { $0 + $1.productivityScore.consistencyScore } / Double(activeDayCount)

        // Use direct average of total scores for more intuitive result
        let avgProductivityScore = ProductivityScore(
            deepWorkScore: avgDeepWork,
            diversityScore: avgDiversity,
            distractionScore: avgDistraction,
            consistencyScore: avgConsistency,
            totalScore: avgTotalScore
        )

        let totalDeepWork = dailyStats.reduce(0.0) { $0 + $1.deepWorkHours }
        let totalSessions = dailyStats.reduce(0) { $0 + $1.deepWorkSessions }
        let totalSwitches = dailyStats.reduce(0) { $0 + $1.contextSwitches }
        let totalShort = dailyStats.reduce(0) { $0 + $1.shortSessionCount }
        let avgSessionLength = daysWithActivity.reduce(0.0) { $0 + $1.averageSessionLength } / Double(activeDayCount)

        return DailyStats(
            date: dailyStats.first?.date ?? Date(),
            totalActivities: totalActivities,
            totalActiveTime: totalActiveTime,
            uniqueApps: mergedAppUsage.count,
            topApps: Array(topApps.prefix(10)),
            productivityScore: avgProductivityScore,
            deepWorkHours: totalDeepWork,
            deepWorkSessions: totalSessions,
            contextSwitches: totalSwitches,
            shortSessionCount: totalShort,
            averageSessionLength: avgSessionLength
        )
    }
}
