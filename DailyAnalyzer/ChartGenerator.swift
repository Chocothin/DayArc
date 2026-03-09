//
//  ChartGenerator.swift
//  DayArc
//
//  Swift Charts quick-export for category/time-of-day/deep vs shallow.
//

import Foundation
import SwiftUI
import Charts
import AppKit

enum ChartType: String {
    case category
    case hourly
    case deepVsShallow
}

@available(macOS 14.0, *)
@MainActor
struct ChartGenerator {
    /// Replace path-unsafe characters in filenames (e.g., "/" from date strings)
    private static func safeFilename(_ name: String) -> String {
        return name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
    }

    static func chartsDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DayArcCharts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func generateCategoryPie(dailyStats: DailyStats, dateLabel: String) -> URL? {
        Logger.shared.debug("Generating category pie chart for \(dateLabel)", source: "Charts")
        let data = dailyStats.topApps.map { app in
            ChartData(id: app.appName, label: app.appName, value: app.duration / 3600.0)
        }
        let safeLabel = safeFilename(dateLabel)
        let result = renderDonut(title: "\(dateLabel) - Top Apps (hrs)", data: data, filename: "\(safeLabel)_category.png")
        if result != nil {
            Logger.shared.debug("Category pie chart saved: \(safeLabel)_category.png", source: "Charts")
        }
        return result
    }

    static func generateHourlyBar(activities: [TimelineCard], dateLabel: String) -> URL? {
        guard !activities.isEmpty else { return nil }

        let calendar = Calendar.current

        // 시간대별로 활동 분류 (0-23시)
        var hourlyData: [(hour: Int, totalMinutes: Double, deepWorkMinutes: Double)] = []

        for hour in 0...23 {
            let activitiesInHour = activities.filter { activity in
                calendar.component(.hour, from: activity.startAt) == hour
            }

            let totalMinutes = activitiesInHour.reduce(0.0) { $0 + $1.duration / 60.0 }

            // Deep work: 25분 이상 지속된 활동
            let deepWorkMinutes = activitiesInHour
                .filter { $0.duration >= 1500.0 } // 25 minutes
                .reduce(0.0) { $0 + $1.duration / 60.0 }

            if totalMinutes > 0 {
                hourlyData.append((hour, totalMinutes, deepWorkMinutes))
            }
        }

        guard !hourlyData.isEmpty else { return nil }

        // 집중도 비율 계산 (deep work / total)
        let data = hourlyData.map { item in
            let focusRatio = item.totalMinutes > 0 ? (item.deepWorkMinutes / item.totalMinutes) * 100 : 0
            return ChartData(
                id: "\(item.hour)",
                label: String(format: "%02d", item.hour),
                value: focusRatio
            )
        }

        let safeLabel = safeFilename(dateLabel)
        return renderFocusHeatmap(title: "\(dateLabel) - 시간대별 집중도 (%)", data: data, filename: "\(safeLabel)_hourly.png")
    }

    static func generateDeepVsShallow(activities: [TimelineCard], dateLabel: String, thresholdMinutes: Double = 25) -> URL? {
        let thresholdSeconds = thresholdMinutes * 60.0

        var deepWorkTime: Double = 0  // 시간 단위 (hours)
        var shallowWorkTime: Double = 0  // 시간 단위 (hours)

        for activity in activities {
            if activity.duration >= thresholdSeconds {
                deepWorkTime += activity.duration / 3600.0
            } else {
                shallowWorkTime += activity.duration / 3600.0
            }
        }

        // 데이터가 없으면 nil 반환
        guard deepWorkTime + shallowWorkTime > 0 else { return nil }

        let data = [
            ChartData(id: "deep", label: "Deep Work (≥\(Int(thresholdMinutes))분)", value: deepWorkTime),
            ChartData(id: "shallow", label: "Shallow Work (<\(Int(thresholdMinutes))분)", value: shallowWorkTime)
        ]

        let safeLabel = safeFilename(dateLabel)
        return renderDonut(title: "\(dateLabel) - Deep vs Shallow (hrs)", data: data, filename: "\(safeLabel)_deep_vs_shallow.png")
    }

    static func generateWeeklyTrend(dailyStats: [DailyStats], dateLabel: String) -> URL? {
        guard !dailyStats.isEmpty else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "E"  // Mon, Tue, Wed...

        let data = dailyStats.enumerated().map { (index, stats) in
            let dayLabel = dateFormatter.string(from: stats.date)
            return ChartData(
                id: "\(index)",
                label: dayLabel,
                value: stats.productivityScore.totalScore
            )
        }

        let safeLabel = safeFilename(dateLabel)
        return renderLine(title: "\(dateLabel) - 주간 생산성 추이", data: data, filename: "\(safeLabel)_weekly_trend.png", valueLabel: "점수")
    }

    // Weekly specific charts
    static func generateWeeklyDailyTrend(dailyStats: [DailyStats], weekNumber: Int) -> URL? {
        Logger.shared.debug("Generating weekly daily trend chart for week \(weekNumber)", source: "Charts")
        guard !dailyStats.isEmpty else {
            Logger.shared.debug("No daily stats for weekly daily trend chart", source: "Charts")
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.dateFormat = "EEE"  // Mon, Tue, Wed...

        let data = dailyStats.map { stats in
            let dayLabel = dateFormatter.string(from: stats.date)
            return ChartData(
                id: "\(stats.date.timeIntervalSince1970)",
                label: dayLabel,
                value: stats.productivityScore.totalScore
            )
        }

        Logger.shared.debug("Rendering weekly daily trend with \(data.count) days", source: "Charts")
        let result = renderLine(
            title: "Daily Productivity Trend",
            data: data,
            filename: "week_\(weekNumber)_daily_trend.png",
            valueLabel: "Score"
        )
        if result != nil {
            Logger.shared.debug("Weekly daily trend chart saved: week_\(weekNumber)_daily_trend.png", source: "Charts")
        } else {
            Logger.shared.error("Failed to render weekly daily trend chart", source: "Charts")
        }
        return result
    }

    static func generateWeeklyCategoryBreakdown(weeklyStats: DailyStats, weekNumber: Int) -> URL? {
        Logger.shared.debug("Generating weekly category breakdown for week \(weekNumber)", source: "Charts")
        guard !weeklyStats.topApps.isEmpty else {
            Logger.shared.debug("No apps for weekly category breakdown", source: "Charts")
            return nil
        }

        let data = weeklyStats.topApps.prefix(8).map { app in
            ChartData(
                id: app.appName,
                label: app.appName,
                value: app.duration / 3600.0  // hours
            )
        }

        Logger.shared.debug("Rendering category breakdown with \(data.count) apps", source: "Charts")
        let result = renderDonut(
            title: "Category Time Breakdown",
            data: data,
            filename: "week_\(weekNumber)_category_breakdown.png"
        )
        if result != nil {
            Logger.shared.debug("Weekly category breakdown chart saved: week_\(weekNumber)_category_breakdown.png", source: "Charts")
        } else {
            Logger.shared.error("Failed to render weekly category breakdown chart", source: "Charts")
        }
        return result
    }

    static func generateWeeklyWeekdayPattern(dailyStats: [DailyStats], weekNumber: Int) -> URL? {
        Logger.shared.debug("Generating weekly weekday pattern for week \(weekNumber)", source: "Charts")
        guard !dailyStats.isEmpty else {
            Logger.shared.debug("No daily stats for weekday pattern", source: "Charts")
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")
        dateFormatter.dateFormat = "EEE"

        let data = dailyStats.map { stats in
            let dayLabel = dateFormatter.string(from: stats.date)
            let workHours = stats.totalActiveTime / 3600.0
            return ChartData(
                id: "\(stats.date.timeIntervalSince1970)",
                label: dayLabel,
                value: workHours
            )
        }

        Logger.shared.debug("Rendering weekday pattern with \(data.count) days", source: "Charts")
        let result = renderBar(
            title: "Weekday Work Hours",
            data: data,
            filename: "week_\(weekNumber)_weekday_pattern.png",
            valueLabel: "Hours"
        )
        if result != nil {
            Logger.shared.debug("Weekly weekday pattern chart saved: week_\(weekNumber)_weekday_pattern.png", source: "Charts")
        } else {
            Logger.shared.error("Failed to render weekly weekday pattern chart", source: "Charts")
        }
        return result
    }

    static func generateMonthlyTrend(weeklyStats: [DailyStats], dateLabel: String) -> URL? {
        guard !weeklyStats.isEmpty else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd"

        let data = weeklyStats.enumerated().map { (index, stats) in
            let weekLabel = "Week \(index + 1)"
            return ChartData(
                id: "\(index)",
                label: weekLabel,
                value: stats.productivityScore.totalScore
            )
        }

        let safeLabel = safeFilename(dateLabel)
        return renderLine(title: "\(dateLabel) - 월간 생산성 추이", data: data, filename: "\(safeLabel)_monthly_trend.png", valueLabel: "점수")
    }

    // MARK: - Monthly-specific Charts

    /// Generate monthly app usage pie chart (month-wide aggregation)
    static func generateMonthlyAppPie(monthlyStats: DailyStats, year: Int, month: Int) -> URL? {
        Logger.shared.debug("Generating monthly app pie chart for \(year)-\(String(format: "%02d", month))", source: "Charts")

        let data = monthlyStats.topApps.prefix(8).map { app in
            ChartData(id: app.appName, label: app.appName, value: app.duration / 3600.0)
        }

        guard !data.isEmpty else {
            Logger.shared.debug("No app data for monthly pie chart", source: "Charts")
            return nil
        }

        let filename = "\(year)_\(String(format: "%02d", month))_app_breakdown.png"
        let result = renderDonut(title: "App Usage Breakdown", data: data, filename: filename)

        if result != nil {
            Logger.shared.debug("Monthly app pie chart saved: \(filename)", source: "Charts")
        }
        return result
    }

    /// Generate monthly productivity heatmap (daily productivity scores)
    /// Generate monthly productivity heatmap (daily productivity scores)
    static func generateMonthlyProductivityHeatmap(dailyStats: [DailyStats], year: Int, month: Int) -> URL? {
        Logger.shared.debug("Generating monthly productivity heatmap for \(year)-\(String(format: "%02d", month))", source: "Charts")

        guard !dailyStats.isEmpty else {
            Logger.shared.debug("No daily stats for heatmap", source: "Charts")
            return nil
        }

        let filename = "\(year)_\(String(format: "%02d", month))_heatmap.png"
        let url = chartsDirectory().appendingPathComponent(filename)

        // Create grid-style heatmap data
        struct HeatmapCell: Identifiable {
            let id = UUID()
            let day: Int
            let weekday: Int
            let weekOfMonth: Int
            let score: Double
        }

        let calendar = Calendar.current
        var cells: [HeatmapCell] = []

        // Get the first day of the month to align weeks correctly
        let dateComponents = DateComponents(year: year, month: month, day: 1)
        guard let firstDayOfMonth = calendar.date(from: dateComponents) else { return nil }
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth) // 1=Sun, 7=Sat

        // Calculate max weeks for Y axis domain
        var maxWeek = 0

        for stats in dailyStats {
            let day = calendar.component(.day, from: stats.date)
            let weekday = calendar.component(.weekday, from: stats.date)
            
            // Calculate visual row index (week of month)
            // Offset day by (firstWeekday - 1) to align with calendar grid
            let adjustedDayIndex = day + firstWeekday - 2
            let weekOfMonth = adjustedDayIndex / 7
            if weekOfMonth > maxWeek { maxWeek = weekOfMonth }

            cells.append(HeatmapCell(
                day: day,
                weekday: weekday,
                weekOfMonth: weekOfMonth,
                score: stats.productivityScore.totalScore
            ))
        }

        // Create grid layout using RectangleMark
        // Invert Y axis (weekOfMonth) so Week 0 is at the top
        let chartView = Chart(cells) { cell in
            RectangleMark(
                x: .value("Weekday", cell.weekday),
                y: .value("Week", cell.weekOfMonth),
                width: .fixed(50),
                height: .fixed(50)
            )
            .foregroundStyle(colorForProductivityScore(cell.score))
            .cornerRadius(8)
            .annotation(position: .overlay) {
                ZStack(alignment: .topLeading) {
                    // Transparent container to define size
                    Color.clear.frame(width: 50, height: 50)
                    
                    // Date at top-left
                    Text("\(cell.day)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding([.top, .leading], 4)
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    
                    // Score at center
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(String(format: "%.0f", cell.score))
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundColor(.white.opacity(0.95))
                                .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: [1, 2, 3, 4, 5, 6, 7]) { value in
                if let weekday = value.as(Int.self) {
                    AxisValueLabel(centered: true) {
                        Text(weekdayLabelShort(weekday))
                            .font(.headline)
                            .padding(.bottom, 5)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { _ in
                // Hide Y axis labels completely
                AxisGridLine()
            }
        }
        // Explicitly set domains to ensure grid shape
        .chartXScale(domain: 0.5...7.5) // 1 to 7 with padding
        .chartYScale(domain: .automatic(includesZero: true, reversed: true))
        .frame(width: 700, height: 800) // Further increased size to prevent overlap

        let view = AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Monthly Productivity Heatmap").font(.title2).bold()
                chartView
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red.opacity(0.6)).frame(width: 12, height: 12)
                        Text("Low (0-30)").font(.subheadline)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange.opacity(0.7)).frame(width: 12, height: 12)
                        Text("Medium (30-60)").font(.subheadline)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.green.opacity(0.8)).frame(width: 12, height: 12)
                        Text("High (60+)").font(.subheadline)
                    }
                }
            }
            .padding(30)
            .background(Color.white)
        )

        let result = renderView(view, to: url)
        if result != nil {
            Logger.shared.debug("Monthly heatmap saved: \(filename)", source: "Charts")
        }
        return result
    }

    /// Generate weekly productivity trend for monthly report
    static func generateMonthlyWeeklyTrend(weeklyStats: [DailyStats], year: Int, month: Int) -> URL? {
        Logger.shared.debug("Generating monthly weekly trend for \(year)-\(String(format: "%02d", month))", source: "Charts")

        guard !weeklyStats.isEmpty else {
            Logger.shared.debug("No weekly stats for trend chart", source: "Charts")
            return nil
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"

        let data = weeklyStats.enumerated().map { (index, stats) in
            let start = stats.date
            let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
            let rangeStr = "\(fmt.string(from: start))-\(fmt.string(from: end))"
            let weekLabel = "W\(index + 1)\n\(rangeStr)"
            
            return ChartData(
                id: "\(index)",
                label: weekLabel,
                value: stats.productivityScore.totalScore
            )
        }

        let filename = "\(year)_\(String(format: "%02d", month))_weekly_trend.png"
        let result = renderLine(title: "Weekly Productivity Trend", data: data, filename: filename, valueLabel: "Score")

        if result != nil {
            Logger.shared.debug("Monthly weekly trend saved: \(filename)", source: "Charts")
        }
        return result
    }

    // Helper function for productivity score color
    private static func colorForProductivityScore(_ score: Double) -> Color {
        if score < 30 {
            return Color.red.opacity(0.6)
        } else if score < 60 {
            return Color.orange.opacity(0.7)
        } else {
            return Color.green.opacity(0.8)
        }
    }

    // Helper function for weekday labels
    private static func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return ""
        }
    }

    // Helper function for short weekday labels
    private static func weekdayLabelShort(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "S"
        case 2: return "M"
        case 3: return "T"
        case 4: return "W"
        case 5: return "T"
        case 6: return "F"
        case 7: return "S"
        default: return ""
        }
    }

    private static func renderDonut(title: String, data: [ChartData], filename: String) -> URL? {
        guard !data.isEmpty else { return nil }
        let url = chartsDirectory().appendingPathComponent(filename)

        // Calculate total for percentage
        let total = data.reduce(0.0) { $0 + $1.value }

        let view = AnyView(
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Chart(data) { item in
                    let percentage = total > 0 ? (item.value / total) * 100 : 0
                    SectorMark(
                        angle: .value("value", item.value),
                        innerRadius: .ratio(0.4),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("label", item.label))
                    .annotation(position: .overlay) {
                        if percentage > 5 {  // Only show % if segment is large enough
                            Text(String(format: "%.1f%%", percentage))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 420, height: 300)
            }
            .padding()
            .background(Color.white)
        )
        return renderView(view, to: url)
    }

    private static func renderBar(title: String, data: [ChartData], filename: String, valueLabel: String) -> URL? {
        guard !data.isEmpty else { return nil }
        let url = chartsDirectory().appendingPathComponent(filename)
        let view = AnyView(
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Chart(data) { item in
                    BarMark(
                        x: .value("label", item.label),
                        y: .value(valueLabel, item.value)
                    )
                    .annotation(position: .top) {
                        Text(String(format: "%.0f", item.value))
                            .font(.caption)
                    }
                }
                .frame(width: 480, height: 320)
            }
            .padding()
            .background(Color.white)
        )
        return renderView(view, to: url)
    }

    private static func renderFocusHeatmap(title: String, data: [ChartData], filename: String) -> URL? {
        guard !data.isEmpty else { return nil }
        let url = chartsDirectory().appendingPathComponent(filename)

        // Build chart with simplified expression
        let chartView = Chart(data) { item in
            BarMark(
                x: .value("시간", item.label),
                y: .value("집중도", item.value)
            )
            .foregroundStyle(colorForFocusLevel(item.value))
            .annotation(position: .top) {
                Text(String(format: "%.0f%%", item.value))
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 12))
        }
        .frame(width: 600, height: 320)

        let view = AnyView(
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                chartView
            }
            .padding()
            .background(Color.white)
        )
        return renderView(view, to: url)
    }

    // Helper to determine color based on focus level
    private static func colorForFocusLevel(_ level: Double) -> Color {
        if level < 30 {
            return Color.red.opacity(0.5)
        } else if level < 60 {
            return Color.orange.opacity(0.7)
        } else {
            return Color.green.opacity(0.8)
        }
    }

    private static func renderLine(title: String, data: [ChartData], filename: String, valueLabel: String) -> URL? {
        guard !data.isEmpty else { return nil }
        let url = chartsDirectory().appendingPathComponent(filename)
        let view = AnyView(
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Chart(data) { item in
                    LineMark(
                        x: .value("label", item.label),
                        y: .value(valueLabel, item.value)
                    )
                    .symbol(Circle())
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("label", item.label),
                        y: .value(valueLabel, item.value)
                    )
                    .annotation(position: .top) {
                        Text(String(format: "%.0f", item.value))
                            .font(.caption2)
                    }
                }
                .chartYScale(domain: 0...100)
                .frame(width: 480, height: 320)
            }
            .padding()
            .background(Color.white)
        )
        return renderView(view, to: url)
    }

    @MainActor
    private static func renderView(_ view: AnyView, to url: URL) -> URL? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        guard let nsImage = renderer.nsImage else {
            Logger.shared.error("Failed to create NSImage from renderer", source: "Charts")
            return nil
        }

        guard let tiff = nsImage.tiffRepresentation else {
            Logger.shared.error("Failed to create TIFF representation", source: "Charts")
            return nil
        }

        guard let bitmap = NSBitmapImageRep(data: tiff) else {
            Logger.shared.error("Failed to create bitmap from TIFF", source: "Charts")
            return nil
        }

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            Logger.shared.error("Failed to create PNG representation", source: "Charts")
            return nil
        }

        do {
            try png.write(to: url)
            Logger.shared.debug("Chart file written successfully to: \(url.path)", source: "Charts")

            // Verify file exists
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            } else {
                Logger.shared.error("Chart file was written but doesn't exist: \(url.path)", source: "Charts")
                return nil
            }
        } catch {
            Logger.shared.error("Failed to write chart file: \(error.localizedDescription)", source: "Charts")
            return nil
        }
    }
}

struct ChartData: Identifiable {
    let id: String
    let label: String
    let value: Double
}
