//
//  AnalysisFallback.swift
//  DayArc
//
//  Shared helper to run AI analysis with provider fallback.
//

import Foundation

enum AnalysisFallback {
    static func runAnalysis(
        config: AIProviderConfig?,
        activities: [TimelineCard],
        date: Date
    ) async -> AnalysisResult? {
        guard let config = config else {
            Logger.shared.warning("No AI config provided, using enhanced fallback", source: "AI")
            let stats = StatsCalculator.calculateDailyStats(from: activities, date: date)
            return buildEnhancedFallback(stats: stats, activities: activities, scope: "daily")
        }

        Logger.shared.debug("Starting AI analysis with provider chain...", source: "AI")

        for provider in config.providerChain() {
            do {
                Logger.shared.debug("Trying provider: \(provider.providerType.displayName)", source: "AI")
                let result = try await provider.analyze(activities: activities, date: date)
                Logger.shared.info("Analysis succeeded with \(provider.providerType.displayName)", source: "AI")
                Logger.shared.debug("Result - Summary: '\(result.summary.prefix(100))', Insights: \(result.insights.count), Recs: \(result.recommendations.count)", source: "AI")
                return result
            } catch {
                Logger.shared.warning("Provider \(provider.providerType.displayName) failed: \(error.localizedDescription)", source: "AI")
                continue
            }
        }

        Logger.shared.error("All AI providers failed; using enhanced fallback analysis", source: "AI")
        let stats = StatsCalculator.calculateDailyStats(from: activities, date: date)
        return buildEnhancedFallback(stats: stats, activities: activities, scope: "daily")
    }

    /// Enhanced rule-based fallback analysis with specific, actionable insights
    static func buildEnhancedFallback(stats: DailyStats, activities: [TimelineCard], scope: String) -> AnalysisResult {
        let hours = stats.totalActiveTime / 3600.0
        let score = Int(stats.productivityScore.totalScore)
        let topApp = stats.topApps.first?.appName ?? "N/A"
        let topAppHours = (stats.topApps.first?.duration ?? 0) / 3600.0

        // Deep Work analysis
        let deepWorkScore = stats.productivityScore.deepWorkScore
        let deepWorkRatio = Int((deepWorkScore / 40.0) * 100)  // 40점 만점

        // Distraction analysis
        let distractionScore = stats.productivityScore.distractionScore
        let distractionPenalty = Int(abs(distractionScore))

        // Consistency analysis
        let consistencyScore = Int(stats.productivityScore.consistencyScore)

        // Generate summary
        let hoursText = String(format: "%.1f", hours)
        let summary = "\(scope) 활동 분석: 총 \(hoursText)시간 활동, 생산성 점수 \(score)/100."

        // Generate insights based on score breakdown
        var insights: [String] = []

        // Deep Work insight
        if deepWorkScore >= 30 {
            insights.append("Deep Work 비중이 높습니다 (\(deepWorkRatio)%). 집중 작업 패턴이 우수합니다.")
        } else if deepWorkScore >= 20 {
            insights.append("Deep Work 비중이 보통입니다 (\(deepWorkRatio)%). 집중 시간을 늘릴 여지가 있습니다.")
        } else {
            insights.append("Deep Work 비중이 낮습니다 (\(deepWorkRatio)%). 방해 요소를 줄이고 집중 블록을 확보하세요.")
        }

        // Top app insight
        if topAppHours > 2 {
            insights.append("\(topApp)에 가장 많은 시간(\(String(format: "%.1f", topAppHours))시간)을 투자했습니다. 이 앱 사용의 가치를 재평가하세요.")
        } else {
            insights.append("상위 앱 \(topApp) 사용 시간: \(String(format: "%.1f", topAppHours))시간. 활동이 다양하게 분산되어 있습니다.")
        }

        // Distraction insight
        if distractionPenalty > 20 {
            insights.append("방해 요소가 많습니다 (-\(distractionPenalty)점). 알림 차단 및 집중 모드를 활성화하세요.")
        } else if distractionPenalty > 10 {
            insights.append("일부 방해 요소가 있습니다 (-\(distractionPenalty)점). 집중 시간대를 정해 운영하세요.")
        }

        // Generate recommendations
        var recommendations: [String] = []

        if deepWorkScore < 25 {
            recommendations.append("집중 블록 늘리기: 25분 이상 지속되는 작업을 하루 3회 이상 배치하세요.")
        }

        if distractionPenalty > 15 {
            recommendations.append("방해 앱 차단: 업무 시간대에 SNS, 메신저 알림을 끄고 배치 처리하세요.")
        }

        if consistencyScore < 7 {
            recommendations.append("일정 리듬 만들기: 매일 비슷한 시간대에 핵심 작업을 배치해 루틴을 형성하세요.")
        }

        if topAppHours > 4 {
            recommendations.append("\(topApp) 사용 시간 점검: 하루 \(String(format: "%.1f", topAppHours))시간이 너무 많습니다. 목적 없는 사용을 줄이세요.")
        }

        if stats.totalActivities < 10 {
            recommendations.append("활동 다양성 확대: 한 가지 도구에만 집중하지 말고 다양한 도구를 활용하세요.")
        }

        // Ensure we have at least 2 recommendations
        if recommendations.count < 2 {
            recommendations.append("현재 패턴을 유지하되, 집중 시간을 점진적으로 늘려보세요.")
        }

        return AnalysisResult(
            summary: summary,
            insights: insights,
            recommendations: recommendations,
            generatedAt: Date(),
            provider: "enhanced-fallback",
            model: "rule-based-v2"
        )
    }
}
