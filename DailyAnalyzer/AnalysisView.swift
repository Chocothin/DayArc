//
//  AnalysisView.swift
//  DayArc
//
//  Analysis UI with report generation and preview
//

import SwiftUI

struct AnalysisView: View {
    @StateObject private var viewModel = AnalysisViewModel.shared
    @State private var selectedDate = Date()
    @State private var reportType: ReportType = .daily
    @AppStorage("reportLanguage") private var reportLanguageRaw = ReportLanguage.korean.rawValue
    
    private var isKorean: Bool {
        (ReportLanguage(rawValue: reportLanguageRaw) ?? .korean) == .korean
    }

    @State private var dailyBlocks = ReportTemplateConfig.load(for: "daily")
    @State private var weeklyBlocks = ReportTemplateConfig.load(for: "weekly")
    @State private var monthlyBlocks = ReportTemplateConfig.load(for: "monthly")

    private var reportTypeDescription: String {
        switch reportType {
        case .daily:
            return isKorean ? "상세 일간 활동 리포트 생성" : "Generate a detailed daily activity report"
        case .weekly:
            return isKorean ? "주간 요약 (7일) 생성" : "Generate a weekly summary (7 days)"
        case .monthly:
            return isKorean ? "월간 개요 생성" : "Generate a monthly overview"
        }
    }

    var body: some View {
        HSplitView {
            // Left Panel - Controls
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                Text(isKorean ? "리포트 생성" : "Generate Report")
                    .font(.title)
                    .bold()

                // Report Type Selection
                GroupBox(isKorean ? "리포트 유형" : "Report Type") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Type", selection: $reportType) {
                            Text(isKorean ? "일간" : "Daily").tag(ReportType.daily)
                            Text(isKorean ? "주간" : "Weekly").tag(ReportType.weekly)
                            Text(isKorean ? "월간" : "Monthly").tag(ReportType.monthly)
                        }
                        .pickerStyle(.segmented)

                        Text(reportTypeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }

                // Date Selection
                GroupBox(isKorean ? "날짜" : "Date") {
                    VStack(alignment: .leading, spacing: 12) {
                        if reportType == .daily {
                            // Daily: Standard graphical calendar
                            DatePicker(
                                "Select Date",
                                selection: $selectedDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .frame(maxWidth: 320, alignment: .leading)
                        } else if reportType == .weekly {
                            // Weekly: Custom week selector
                            WeekPickerView(selectedDate: $selectedDate)
                        } else if reportType == .monthly {
                            // Monthly: Month/Year picker only
                            MonthYearPickerView(selectedDate: $selectedDate, isKorean: isKorean)
                        }
                    }
                    .padding()
                }

                // AI Provider Status
                GroupBox(isKorean ? "AI 공급자" : "AI Provider") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "brain")
                                .foregroundStyle(.blue)
                            Text(viewModel.currentProvider)
                                .font(.body)
                            Spacer()
                            if viewModel.providerReady {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }

                        if !viewModel.providerReady {
                            Text(isKorean ? "설정에서 AI 공급자를 구성해 주세요" : "Please configure AI provider in Settings")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding()
                }

                // Language selection now in Settings > General

                GroupBox(isKorean ? "섹션 구성" : "Sections") {
                    let binding = blocksBinding(for: reportType)
                    VStack(alignment: .leading, spacing: 8) {
                        // Show different sections based on report type
                        if reportType == .daily {
                            Toggle("Start routine / prep", isOn: binding.includeStartRoutine)
                            Toggle("TODO block", isOn: binding.includeTodo)
                            Toggle("Focus blocks grid", isOn: binding.includeFocusBlocks)
                            Toggle("Emotion & recap", isOn: binding.includeEmotion)
                            Toggle("AI section", isOn: binding.includeAISection)
                            Toggle("Deep work analysis", isOn: binding.includeDeepWorkAnalysis)
                            Toggle("Distraction breakdown", isOn: binding.includeDistractionBreakdown)
                            Toggle("Context switching", isOn: binding.includeContextSwitching)
                            Toggle("Stats / tables", isOn: binding.includeStats)
                            Toggle("Timeline", isOn: binding.includeTimeline)
                            Toggle("Categories & apps", isOn: binding.includeCategoriesAndApps)
                            Toggle("Charts", isOn: binding.includeCharts)
                            Toggle("History / delta", isOn: binding.includeHistory)
                            Toggle("Scorecard", isOn: binding.includeScorecard)
                            Toggle("Footer", isOn: binding.includeFooter)
                        } else if reportType == .weekly {
                            Toggle("AI section", isOn: binding.includeAISection)
                            Toggle("Stats / tables", isOn: binding.includeStats)
                            Toggle("Categories & apps", isOn: binding.includeCategoriesAndApps)
                            Toggle("Charts", isOn: binding.includeCharts)
                            Toggle("Footer", isOn: binding.includeFooter)
                        } else if reportType == .monthly {
                            Toggle("AI section", isOn: binding.includeAISection)
                            Toggle("Stats / tables", isOn: binding.includeStats)
                            Toggle("Categories & apps", isOn: binding.includeCategoriesAndApps)
                            Toggle("Charts", isOn: binding.includeCharts)
                            Toggle("History / delta", isOn: binding.includeHistory)
                            Toggle("Footer", isOn: binding.includeFooter)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: reportType) { _ in
                        // refresh binding side-effects
                    }
                }

                // Generate Button
                Button {
                    let blocks = currentBlocks(for: reportType)
                    viewModel.generateReport(for: selectedDate, type: reportType, blocks: blocks)
                } label: {
                    HStack {
                        if viewModel.isGenerating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(viewModel.isGenerating ? (isKorean ? "생성 중..." : "Generating...") : (isKorean ? "생성" : "Generate"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isGenerating)
                .disabled(!viewModel.providerReady)

                // Status Messages
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                } else if let success = viewModel.successMessage {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal)
                }

                Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .frame(minWidth: 300, maxWidth: 400, maxHeight: .infinity)

            // Right Panel - Preview
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(isKorean ? "미리보기" : "Preview")
                        .font(.title2)
                        .bold()

                    Spacer()

                    if viewModel.generatedMarkdown != nil {
                        Button("Save to Vault") {
                            viewModel.saveToVault(for: selectedDate, type: reportType)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.isSaving)
                    }
                }

                if let markdown = viewModel.generatedMarkdown {
                    ScrollView {
                        Text(markdown)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)

                        Text(isKorean ? "생성된 리포트 없음" : "No report generated")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text(isKorean ? "옵션을 선택하고 생성을 클릭하여 리포트를 만드세요" : "Select options and click Generate to create a report")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
        }
        .onAppear {
            viewModel.checkProvider()
            // Default to yesterday for initial selection
            let cal = Calendar.current
            selectedDate = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            // Save initial blocks load
            saveBlocks(for: .daily, blocks: dailyBlocks)
            saveBlocks(for: .weekly, blocks: weeklyBlocks)
            saveBlocks(for: .monthly, blocks: monthlyBlocks)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AIProviderConfigDidChange"))) { _ in
            // Reload AI config when settings change
            viewModel.checkProvider()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenReportInAnalysis"))) { notification in
            guard let userInfo = notification.userInfo,
                  let reportTypeString = userInfo["reportType"] as? String,
                  let reportDate = userInfo["reportDate"] as? Date else {
                return
            }

            // Set the report type
            if reportTypeString == "daily" {
                reportType = .daily
            } else if reportTypeString == "weekly" {
                reportType = .weekly
            } else if reportTypeString == "monthly" {
                reportType = .monthly
            }

            // Set the date
            selectedDate = reportDate

            let blocks = currentBlocks(for: reportType)
            viewModel.generateReport(for: reportDate, type: reportType, blocks: blocks)

            Logger.shared.info("Opened \(reportTypeString) report from notification", source: "AnalysisView")
        }
        .alert("Permission Required", isPresented: $viewModel.showPermissionDialog) {
            Button("Grant Access") {
                viewModel.requestVaultAccess()
            }
            Button("Cancel", role: .cancel) {
                viewModel.showPermissionDialog = false
            }
        } message: {
            if let path = viewModel.permissionDeniedPath {
                Text("Cannot write to: \(path)\n\nPlease grant access to the Obsidian vault directory.")
            } else {
                Text("Please grant access to the Obsidian vault directory.")
            }
        }
        .onDisappear {
            viewModel.clearPreview()
        }
    }
}

// MARK: - Report Type

enum ReportType: String, CaseIterable {
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var description: String {
        switch self {
        case .daily:
            return "Generate a detailed daily activity report"
        case .weekly:
            return "Generate a weekly summary (7 days)"
        case .monthly:
            return "Generate a monthly overview"
        }
    }
}

// MARK: - ViewModel

@MainActor
class AnalysisViewModel: ObservableObject {
    static let shared = AnalysisViewModel()

    @Published var isGenerating = false
    @Published var isSaving = false
    @Published var generatedMarkdown: String?
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var currentProvider = "Not configured"
    @Published var providerReady = false
    @Published var showPermissionDialog = false
    @Published var permissionDeniedPath: String?

    private var aiConfig: AIProviderConfig?
    private var vaultConfig: VaultConfiguration?
    private var pendingSaveDate: Date?
    private var pendingSaveType: ReportType?

    private init() {
    }

    func checkProvider() {
        aiConfig = AIProviderConfig.load()
        vaultConfig = VaultConfiguration.load()

        if let config = aiConfig {
            currentProvider = config.selectedProviderType.displayName

            // Check if API key exists for cloud providers
            if config.selectedProviderType == .ollama || config.selectedProviderType == .lmstudio {
                providerReady = true
            } else {
                providerReady = config.apiKeys[config.selectedProviderType] != nil &&
                               !config.apiKeys[config.selectedProviderType]!.isEmpty
            }
        } else {
            providerReady = false
        }
    }

    func clearPreview() {
        generatedMarkdown = nil
    }

    func generateReport(for date: Date, type: ReportType, blocks: ReportBlocks) {
        // Get language from global settings
        let reportLanguageRaw = UserDefaults.standard.string(forKey: "reportLanguage") ?? ReportLanguage.korean.rawValue
        let language = ReportLanguage(rawValue: reportLanguageRaw) ?? .korean
        isGenerating = true
        errorMessage = nil
        successMessage = nil

        // Reload AI config to get latest settings
        aiConfig = AIProviderConfig.load()
        if let config = aiConfig {
            Logger.shared.info("Using AI Provider: \(config.selectedProviderType.displayName), Model: \(config.selectedModel.name)", source: "Analysis")
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        Logger.shared.info("User action: Generate Report - Type: \(type), Date: \(formatter.string(from: date)), Language: \(language)", source: "UserAction")

        Task {
            do {
                Logger.shared.debug("Searching for DayArc database...", source: "Analysis")
                guard let dbPath = DayflowDatabase.findDayflowDatabase() else {
                    let searched = DayflowDatabase.lastSearchedPaths.joined(separator: "\n")
                    errorMessage = "DayArc database not found.\nSearched:\n\(searched)"
                    Logger.shared.error("DayArc DB not found. Searched:\n\(searched)", source: "Analysis")
                    isGenerating = false
                    return
                }

                let db = DayflowDatabase(dbPath: dbPath)

                switch type {
                case .daily:
                    try await generateDailyReport(db: db, date: date, language: language, blocks: blocks)
                case .weekly:
                    try await generateWeeklyReport(db: db, startDate: date, language: language, blocks: blocks)
                case .monthly:
                    try await generateMonthlyReport(db: db, month: date, language: language, blocks: blocks)
                }

                successMessage = "Report generated successfully!"
                Logger.shared.info("Report generated successfully (type: \(type))", source: "Analysis")
                isGenerating = false

                // Auto-save to vault if enabled (reload config to get fresh setting)
                let freshVaultConfig = VaultConfiguration.load()
                if freshVaultConfig.autoSave {
                    Logger.shared.info("Auto-save enabled, saving \(type) report to vault...", source: "Analysis")
                    saveToVault(for: date, type: type)
                }

            } catch {
                errorMessage = "Failed to generate report: \(error.localizedDescription)"
                Logger.shared.error("Report generation failed: \(error)", source: "Analysis")
                isGenerating = false
            }
        }
    }

    private func generateDailyReport(db: DayflowDatabase, date: Date, language: ReportLanguage, blocks: ReportBlocks) async throws {
        // Fetch activities
        Logger.shared.debug("Fetching activities from database...", source: "Analysis")
        let activities = try db.fetchActivities(for: date)
        Logger.shared.info("Loaded \(activities.count) activities", source: "Analysis")

        guard !activities.isEmpty else {
            errorMessage = "No activities found for this date"
            Logger.shared.error("No activities found for \(date)", source: "Analysis")
            isGenerating = false
            return
        }

        // Calculate stats
        Logger.shared.debug("Calculating daily statistics...", source: "Analysis")
        let stats = StatsCalculator.calculateDailyStats(from: activities, date: date)
        Logger.shared.info("Stats calculated - Score: \(Int(stats.productivityScore.totalScore))/100, Hours: \(String(format: "%.1f", stats.totalActiveTime / 3600))", source: "Analysis")

        // Historical context (7/30 days)
        Logger.shared.debug("Computing historical context...", source: "Analysis")
        let history = try await computeHistoricalContext(db: db, targetDate: date)
        Logger.shared.debug("Historical context computed", source: "Analysis")

        // Charts (category/hourly/deep vs shallow) - macOS 14+
        var chartPaths: [URL] = []
        if #available(macOS 14.0, *) {
            Logger.shared.debug("Generating charts...", source: "Analysis")
            let dateLabel = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
            if let cat = ChartGenerator.generateCategoryPie(dailyStats: stats, dateLabel: dateLabel) {
                chartPaths.append(cat)
            }
            if let hourly = ChartGenerator.generateHourlyBar(activities: activities, dateLabel: dateLabel) {
                chartPaths.append(hourly)
            }
            if let deepVsShallow = ChartGenerator.generateDeepVsShallow(activities: activities, dateLabel: dateLabel) {
                chartPaths.append(deepVsShallow)
            }
            Logger.shared.info("Generated \(chartPaths.count) charts", source: "Analysis")

            // Copy charts to Obsidian vault charts folder
            let vaultConfig = VaultConfiguration.load()
            if !vaultConfig.vaultPath.isEmpty {
                let vaultURL = URL(fileURLWithPath: vaultConfig.vaultPath)
                let chartsFolder = vaultURL.appendingPathComponent("charts", isDirectory: true)
                try? FileManager.default.createDirectory(at: chartsFolder, withIntermediateDirectories: true)

                for chartPath in chartPaths {
                    let destPath = chartsFolder.appendingPathComponent(chartPath.lastPathComponent)
                    try? FileManager.default.removeItem(at: destPath) // Remove if exists
                    try? FileManager.default.copyItem(at: chartPath, to: destPath)
                    Logger.shared.debug("Copied chart to vault: \(chartPath.lastPathComponent)", source: "Analysis")
                }
            }
        }

        // Get AI analysis
        var analysis: AnalysisResult?
        if let config = aiConfig {
            Logger.shared.debug("Requesting AI analysis...", source: "Analysis")
            analysis = await AnalysisFallback.runAnalysis(
                config: config,
                activities: activities,
                date: date
            )

            if let result = analysis {
                Logger.shared.info("✅ AI analysis received - Provider: \(result.provider), Model: \(result.model)", source: "Analysis")
                Logger.shared.debug("✅ Analysis content - Summary: '\(result.summary.prefix(100))', Insights: \(result.insights.count), Recs: \(result.recommendations.count)", source: "Analysis")
            } else {
                Logger.shared.error("❌ AI analysis returned nil!", source: "Analysis")
            }
        }
        // Fallback analysis if AI unavailable
        if analysis == nil {
            Logger.shared.warning("AI analysis unavailable, using enhanced fallback", source: "Analysis")
            analysis = AnalysisFallback.buildEnhancedFallback(stats: stats, activities: activities, scope: "daily")
        }

        // Final check before markdown generation
        if let finalAnalysis = analysis {
            Logger.shared.info("📝 Passing analysis to markdown generator - Summary length: \(finalAnalysis.summary.count), Insights: \(finalAnalysis.insights.count), Recs: \(finalAnalysis.recommendations.count)", source: "Analysis")
        } else {
            Logger.shared.error("🚨 Analysis is still nil before markdown generation!", source: "Analysis")
        }

        // Generate timeline summaries if AI available
        var timelineSummaries: [TimelineSummary] = []
        Logger.shared.debug("🎯 Timeline summary check - aiConfig: \(aiConfig != nil ? "present" : "nil"), language: \(language)", source: "Analysis")

        if let config = aiConfig, language == .korean {
            Logger.shared.info("🎯 Starting timeline summary generation...", source: "Analysis")
            timelineSummaries = await generateTimelineSummaries(
                activities: activities,
                config: config,
                language: language
            )
            Logger.shared.info("🎯 Generated \(timelineSummaries.count) timeline summaries", source: "Analysis")
        } else {
            if aiConfig == nil {
                Logger.shared.warning("🎯 Timeline summary skipped: No AI config", source: "Analysis")
            } else if language != .korean {
                Logger.shared.warning("🎯 Timeline summary skipped: Language is \(language), not Korean", source: "Analysis")
            }
        }

        // Generate markdown
        Logger.shared.debug("Generating markdown report...", source: "Analysis")
        let markdown = MarkdownGeneratorV3.daily(
            date: date,
            stats: stats,
            analysis: analysis,
            activities: activities,
            history: history,
            chartPaths: chartPaths,
            language: language,
            blocks: blocks,
            timelineSummaries: timelineSummaries
        )
        Logger.shared.info("Markdown generated - Length: \(markdown.count) chars", source: "Analysis")

        generatedMarkdown = markdown
    }

    private func generateWeeklyReport(db: DayflowDatabase, startDate: Date, language: ReportLanguage, blocks: ReportBlocks) async throws {
        let calendar = Calendar.current
        let weekStart = calendar.startOfDay(for: startDate)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        // Fetch week's activities
        let activities = try db.fetchActivities(from: weekStart, to: weekEnd)

        guard !activities.isEmpty else {
            errorMessage = "No activities found for this week"
            isGenerating = false
            return
        }

        // Calculate daily stats for each day first (always create entries for all 7 days)
        var dailyStats: [DailyStats] = []
        for day in 0..<7 {
            if let dayDate = calendar.date(byAdding: .day, value: day, to: weekStart) {
                let dayActivities = activities.filter { activity in
                    calendar.isDate(activity.startAt, inSameDayAs: dayDate)
                }
                // Always append stats, even if no activities (ensures we have all 7 days)
                let stats = StatsCalculator.calculateDailyStats(from: dayActivities, date: dayDate)
                dailyStats.append(stats)
            }
        }

        // Aggregate daily stats into weekly stats (excludes days with no activity from averages)
        guard let weeklyStats = StatsCalculator.calculateWeeklyStats(from: dailyStats) else {
            errorMessage = "Failed to calculate weekly stats"
            isGenerating = false
            return
        }

        // Charts for the week (using weekly-specific functions)
        var chartPaths: [URL] = []
        if #available(macOS 14.0, *) {
            let weekNumber = calendar.component(.weekOfYear, from: weekStart)

            // Generate 3 weekly-specific charts matching template
            if !dailyStats.isEmpty, let dailyTrend = ChartGenerator.generateWeeklyDailyTrend(dailyStats: dailyStats, weekNumber: weekNumber) {
                chartPaths.append(dailyTrend)
            }
            if let categoryBreakdown = ChartGenerator.generateWeeklyCategoryBreakdown(weeklyStats: weeklyStats, weekNumber: weekNumber) {
                chartPaths.append(categoryBreakdown)
            }
            if !dailyStats.isEmpty, let weekdayPattern = ChartGenerator.generateWeeklyWeekdayPattern(dailyStats: dailyStats, weekNumber: weekNumber) {
                chartPaths.append(weekdayPattern)
            }

            // Copy charts to Obsidian vault charts folder
            let vaultConfig = VaultConfiguration.load()
            if !vaultConfig.vaultPath.isEmpty {
                let vaultURL = URL(fileURLWithPath: vaultConfig.vaultPath)
                let chartsFolder = vaultURL.appendingPathComponent("charts", isDirectory: true)
                try? FileManager.default.createDirectory(at: chartsFolder, withIntermediateDirectories: true)

                for chartPath in chartPaths {
                    let destPath = chartsFolder.appendingPathComponent(chartPath.lastPathComponent)
                    try? FileManager.default.removeItem(at: destPath) // Remove if exists
                    try? FileManager.default.copyItem(at: chartPath, to: destPath)
                    Logger.shared.debug("Copied chart to vault: \(chartPath.lastPathComponent)", source: "Analysis")
                }
            }
        }

        // AI analysis for the week
        var analysis: AnalysisResult?
        if let config = aiConfig {
            analysis = await AnalysisFallback.runAnalysis(
                config: config,
                activities: activities,
                date: startDate
            )
        }
        if analysis == nil {
            analysis = AnalysisFallback.buildEnhancedFallback(stats: weeklyStats, activities: activities, scope: "weekly")
        }

        // Previous week comparison
        let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: startDate)!
        let prevWeekEnd = calendar.date(byAdding: .day, value: 7, to: prevWeekStart)!
        let prevActivities = try db.fetchActivities(from: prevWeekStart, to: prevWeekEnd)
        let previousWeekStats = prevActivities.isEmpty ? nil : StatsCalculator.calculateDailyStats(from: prevActivities, date: prevWeekStart)

        // Generate markdown
        let markdown = MarkdownGeneratorV3.weekly(
            startDate: weekStart,
            endDate: weekEnd,
            weeklyStats: weeklyStats,
            dailyStats: dailyStats,
            activities: activities,
            analysis: analysis,
            previousWeek: previousWeekStats,
            chartPaths: chartPaths,
            language: language,
            blocks: blocks
        )

        generatedMarkdown = markdown
    }

    private func generateMonthlyReport(db: DayflowDatabase, month: Date, language: ReportLanguage, blocks: ReportBlocks) async throws {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!

        // Fetch month's activities
        let activities = try db.fetchActivities(from: monthStart, to: monthEnd)

        guard !activities.isEmpty else {
            errorMessage = "No activities found for this month"
            isGenerating = false
            return
        }

        // Calculate daily stats for heatmap first
        var dailyStats: [DailyStats] = []
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        for day in 0..<daysInMonth {
            if let dayDate = calendar.date(byAdding: .day, value: day, to: monthStart) {
                let dayActivities = activities.filter { activity in
                    calendar.isDate(activity.startAt, inSameDayAs: dayDate)
                }
                // Always append stats, even if no activities (for complete heatmap)
                let stats = StatsCalculator.calculateDailyStats(from: dayActivities, date: dayDate)
                dailyStats.append(stats)
            }
        }

        // Aggregate daily stats into monthly stats (excludes days with no activity from averages)
        guard let monthlyStats = StatsCalculator.calculateWeeklyStats(from: dailyStats) else {
            errorMessage = "Failed to calculate monthly stats"
            isGenerating = false
            return
        }

        // Calculate weekly stats (proper week boundaries)
        var weeklyStats: [DailyStats] = []

        // Get the first day of the month and find its week start (Sunday)
        var currentDate = monthStart
        while currentDate < monthEnd {
            // Find the start of the week for current date (Sunday = 1 in Calendar)
            let weekday = calendar.component(.weekday, from: currentDate)
            let daysFromSunday = weekday - 1  // 0 = Sunday, 1 = Monday, etc.
            let weekStart = calendar.date(byAdding: .day, value: -daysFromSunday, to: currentDate)!
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

            // Filter activities that fall within this week AND this month
            let weekActivities = activities.filter { activity in
                activity.startAt >= max(weekStart, monthStart) &&
                activity.startAt < min(weekEnd, monthEnd)
            }

            if !weekActivities.isEmpty {
                let stats = StatsCalculator.calculateDailyStats(from: weekActivities, date: weekStart)
                weeklyStats.append(stats)
            } else if currentDate >= monthStart && currentDate < monthEnd {
                // Include weeks with no data if they're within the month
                let stats = StatsCalculator.calculateDailyStats(from: [], date: weekStart)
                weeklyStats.append(stats)
            }

            // Move to next week
            currentDate = weekEnd
        }

        // AI analysis for the month
        var analysis: AnalysisResult?
        if let config = aiConfig {
            analysis = await AnalysisFallback.runAnalysis(
                config: config,
                activities: activities,
                date: monthStart
            )
        }
        if analysis == nil {
            analysis = AnalysisFallback.buildEnhancedFallback(stats: monthlyStats, activities: activities, scope: "monthly")
        }

        // Previous month comparison
        let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
        let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart)!
        let prevActivities = try db.fetchActivities(from: prevMonthStart, to: prevMonthEnd)
        let previousMonthStats = prevActivities.isEmpty ? nil : StatsCalculator.calculateDailyStats(from: prevActivities, date: prevMonthStart)

        // Charts for the month (monthly-specific charts)
        var chartPaths: [URL] = []
        if #available(macOS 14.0, *) {
            let year = calendar.component(.year, from: monthStart)
            let monthNum = calendar.component(.month, from: monthStart)

            // 1. Monthly app usage pie chart (month-wide aggregation)
            if let appPie = ChartGenerator.generateMonthlyAppPie(monthlyStats: monthlyStats, year: year, month: monthNum) {
                chartPaths.append(appPie)
                Logger.shared.debug("Generated monthly app pie chart", source: "Analysis")
            }

            // 2. Monthly productivity heatmap (daily scores)
            if !dailyStats.isEmpty, let heatmap = ChartGenerator.generateMonthlyProductivityHeatmap(dailyStats: dailyStats, year: year, month: monthNum) {
                chartPaths.append(heatmap)
                Logger.shared.debug("Generated monthly productivity heatmap", source: "Analysis")
            }

            // 3. Weekly productivity trend
            if !weeklyStats.isEmpty, let weeklyTrend = ChartGenerator.generateMonthlyWeeklyTrend(weeklyStats: weeklyStats, year: year, month: monthNum) {
                chartPaths.append(weeklyTrend)
                Logger.shared.debug("Generated monthly weekly trend", source: "Analysis")
            }

            // Copy charts to Obsidian vault charts folder
            let vaultConfig = VaultConfiguration.load()
            if !vaultConfig.vaultPath.isEmpty {
                let vaultURL = URL(fileURLWithPath: vaultConfig.vaultPath)
                let chartsFolder = vaultURL.appendingPathComponent("charts", isDirectory: true)
                try? FileManager.default.createDirectory(at: chartsFolder, withIntermediateDirectories: true)

                for chartPath in chartPaths {
                    let destPath = chartsFolder.appendingPathComponent(chartPath.lastPathComponent)
                    try? FileManager.default.removeItem(at: destPath) // Remove if exists
                    try? FileManager.default.copyItem(at: chartPath, to: destPath)
                    Logger.shared.debug("Copied chart to vault: \(chartPath.lastPathComponent)", source: "Analysis")
                }
            }
        }

        // Generate markdown
        let markdown = MarkdownGeneratorV3.monthly(
            month: monthStart,
            monthlyStats: monthlyStats,
            weeklyStats: weeklyStats,
            activities: activities,
            analysis: analysis,
            previousMonth: previousMonthStats,
            chartPaths: chartPaths,
            language: language,
            blocks: blocks
        )

        generatedMarkdown = markdown
    }


    /// Compute historical context (last 7/30 days averages)
    private func computeHistoricalContext(db: DayflowDatabase, targetDate: Date) async throws -> MarkdownGenerator.HistoricalContext? {
        let calendar = Calendar.current

        func statsForDays(_ days: Int) throws -> [DailyStats] {
            var result: [DailyStats] = []
            for i in 1...days {
                guard let day = calendar.date(byAdding: .day, value: -i, to: targetDate) else { continue }
                let acts = try db.fetchActivities(for: day)
                if !acts.isEmpty {
                    let stats = StatsCalculator.calculateDailyStats(from: acts, date: day)
                    result.append(stats)
                }
            }
            return result
        }

        let last7 = try statsForDays(7)
        let last30 = try statsForDays(30)

        guard !last7.isEmpty || !last30.isEmpty else { return nil }

        func avgScore(_ arr: [DailyStats]) -> Double {
            guard !arr.isEmpty else { return 0 }
            return arr.reduce(0.0) { $0 + $1.productivityScore.totalScore } / Double(arr.count)
        }
        func avgHours(_ arr: [DailyStats]) -> Double {
            guard !arr.isEmpty else { return 0 }
            let totalSeconds = arr.reduce(0.0) { $0 + $1.totalActiveTime }
            return (totalSeconds / Double(arr.count)) / 3600.0
        }

        return MarkdownGenerator.HistoricalContext(
            last7AvgScore: avgScore(last7),
            last7AvgHours: avgHours(last7),
            last30AvgScore: avgScore(last30.isEmpty ? last7 : last30),
            last30AvgHours: avgHours(last30.isEmpty ? last7 : last30)
        )
    }

    func saveToVault(for date: Date, type: ReportType) {
        guard let markdown = generatedMarkdown else { return }

        isSaving = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                guard let vaultConfig = vaultConfig else {
                    errorMessage = "Vault not configured"
                    Logger.shared.error("Vault not configured when saving", source: "Analysis")
                    isSaving = false
                    return
                }

                let vault = try vaultConfig.getVault()

                switch type {
                case .daily:
                    let path = try vault.saveDailyNote(date: date, markdown: markdown)
                    successMessage = "Daily note saved to vault!"
                    Logger.shared.info("Saved daily note to \(path)", source: "Analysis")
                case .weekly:
                    let path = try vault.saveWeeklyNote(startDate: date, markdown: markdown)
                    successMessage = "Weekly note saved to vault!"
                    Logger.shared.info("Saved weekly note to \(path)", source: "Analysis")
                case .monthly:
                    let path = try vault.saveMonthlyNote(month: date, markdown: markdown)
                    successMessage = "Monthly note saved to vault!"
                    Logger.shared.info("Saved monthly note to \(path)", source: "Analysis")
                }

                isSaving = false

            } catch let vaultError as VaultError {
                if case .permissionDenied(let path) = vaultError {
                    // Store for retry
                    pendingSaveDate = date
                    pendingSaveType = type
                    permissionDeniedPath = path
                    showPermissionDialog = true
                    Logger.shared.warning("Permission denied for path: \(path)", source: "Analysis")
                } else {
                    errorMessage = "Failed to save: \(vaultError.localizedDescription)"
                }
                isSaving = false
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
                isSaving = false
            }
        }
    }

    func requestVaultAccess() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Grant access to Obsidian vault directory"
        panel.prompt = "Grant Access"

        if let vaultPath = vaultConfig?.vaultPath {
            panel.directoryURL = URL(fileURLWithPath: vaultPath)
        }

        panel.begin { [weak self] response in
            guard let self = self else { return }

            if response == .OK, let _ = panel.url {
                // User granted access - retry save
                if let date = self.pendingSaveDate, let type = self.pendingSaveType {
                    self.showPermissionDialog = false
                    self.saveToVault(for: date, type: type)
                }
            } else {
                self.showPermissionDialog = false
                self.errorMessage = "Permission not granted. Unable to save to vault."
            }
        }
    }

    // MARK: - Timeline Summaries

    /// Generate AI summaries for timeline groups
    private func generateTimelineSummaries(
        activities: [TimelineCard],
        config: AIProviderConfig,
        language: ReportLanguage
    ) async -> [TimelineSummary] {
        Logger.shared.info("🎯 generateTimelineSummaries called with \(activities.count) activities", source: "Analysis")

        // Group activities (same logic as in MarkdownGeneratorV3)
        struct ActivityGroup {
            var startTime: Date
            var endTime: Date
            var activities: [TimelineCard]
            var duration: Double
        }

        var activityGroups: [ActivityGroup] = []

        for activity in activities.sorted(by: { $0.startAt < $1.startAt }) {
            if let lastGroupIndex = activityGroups.indices.last,
               activity.startAt.timeIntervalSince(activityGroups[lastGroupIndex].endTime) < 300 {
                activityGroups[lastGroupIndex].endTime = activity.startAt.addingTimeInterval(activity.duration)
                activityGroups[lastGroupIndex].activities.append(activity)
                activityGroups[lastGroupIndex].duration += activity.duration
            } else {
                activityGroups.append(ActivityGroup(
                    startTime: activity.startAt,
                    endTime: activity.startAt.addingTimeInterval(activity.duration),
                    activities: [activity],
                    duration: activity.duration
                ))
            }
        }

        Logger.shared.info("🎯 Created \(activityGroups.count) activity groups", source: "Analysis")

        // Generate summaries for top 10 groups
        var summaries: [TimelineSummary] = []
        let languageCode = language == .korean ? "Korean" : "English"

        for (index, group) in activityGroups.prefix(10).enumerated() {
            Logger.shared.debug("🎯 Processing group \(index + 1)/\(min(10, activityGroups.count))", source: "Analysis")
            // Collect activity details
            var activityDetails: [String] = []
            for activity in group.activities {
                if let detailedSummary = activity.detailedSummary, !detailedSummary.isEmpty {
                    activityDetails.append(detailedSummary)
                } else if let summary = activity.summary, !summary.isEmpty {
                    activityDetails.append(summary)
                } else if let windowTitle = activity.windowTitle, !windowTitle.isEmpty {
                    activityDetails.append("\(activity.appName): \(windowTitle)")
                } else {
                    activityDetails.append(activity.appName)
                }
            }

            let combinedDetails = activityDetails.joined(separator: "\n")

            Logger.shared.debug("🎯 Combined details length: \(combinedDetails.count) chars", source: "Analysis")

            // Call AI to summarize and translate
            if let summary = await summarizeTimelineGroup(
                details: combinedDetails,
                config: config,
                targetLanguage: languageCode
            ) {
                Logger.shared.info("🎯 Successfully generated summary for group \(index + 1): \(summary.title)", source: "Analysis")
                summaries.append(summary)
            } else {
                Logger.shared.warning("🎯 Failed to generate summary for group \(index + 1)", source: "Analysis")
            }
        }

        Logger.shared.info("🎯 Total summaries generated: \(summaries.count)", source: "Analysis")
        return summaries
    }

    /// Call AI API to summarize and translate a timeline group
    private func summarizeTimelineGroup(
        details: String,
        config: AIProviderConfig,
        targetLanguage: String
    ) async -> TimelineSummary? {
        Logger.shared.debug("🎯 summarizeTimelineGroup called", source: "Analysis")

        // Use first provider in chain
        guard let provider = config.providerChain().first else {
            Logger.shared.error("🎯 No provider available in chain", source: "Analysis")
            return nil
        }

        Logger.shared.info("🎯 Using provider: \(provider.providerType.displayName)", source: "Analysis")

        // Build prompt
        let prompt = """
        Please analyze the following activity log and provide:
        1. A concise title (max 50 characters) summarizing the main work done
        2. A brief summary (2-3 sentences) explaining what was accomplished
        3. Infer a category (e.g., "Work > Development", "Personal > Learning", etc.)

        Activity details:
        \(details)

        IMPORTANT: Respond ONLY with a JSON object in this exact format, and translate everything to \(targetLanguage):
        ```json
        {
          "title": "Concise title in \(targetLanguage)",
          "summary": "Brief summary in \(targetLanguage)",
          "category": "Category > Subcategory in \(targetLanguage)"
        }
        ```
        """

        Logger.shared.debug("🎯 Prompt prepared, calling API...", source: "Analysis")

        do {
            // Make API call
            let result = try await callProviderAPI(provider: provider, prompt: prompt)
            Logger.shared.debug("🎯 API call successful, result length: \(result.count)", source: "Analysis")

            // Parse JSON
            if let jsonData = extractJSON(from: result) {
                Logger.shared.debug("🎯 JSON extracted: \(jsonData.prefix(200))...", source: "Analysis")
                if let data = jsonData.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let title = json["title"] as? String,
                   let summary = json["summary"] as? String {
                    let category = json["category"] as? String
                    Logger.shared.info("🎯 Successfully parsed timeline summary", source: "Analysis")
                    return TimelineSummary(title: title, summary: summary, category: category)
                } else {
                    Logger.shared.error("🎯 Failed to parse JSON to TimelineSummary", source: "Analysis")
                }
            } else {
                Logger.shared.error("🎯 Failed to extract JSON from result", source: "Analysis")
            }
        } catch {
            Logger.shared.error("🎯 Failed to generate timeline summary: \(error.localizedDescription)", source: "Analysis")
        }

        return nil
    }

    /// Make API call to provider
    private func callProviderAPI(provider: any AIProvider, prompt: String) async throws -> String {
        Logger.shared.debug("🎯 callProviderAPI - Provider type: \(provider.providerType)", source: "Analysis")

        // For Gemini, make direct API call
        if provider.providerType == .gemini {
            Logger.shared.debug("🎯 Provider is Gemini, calling Gemini API", source: "Analysis")
            if let geminiProvider = provider as? GeminiProvider {
                return try await callGeminiAPI(provider: geminiProvider, prompt: prompt)
            } else {
                Logger.shared.error("🎯 Failed to cast provider to GeminiProvider", source: "Analysis")
            }
        }

        Logger.shared.error("🎯 Provider \(provider.providerType) not supported for timeline summary", source: "Analysis")
        throw NSError(domain: "TimelineSummary", code: -1, userInfo: [NSLocalizedDescriptionKey: "Provider not supported for timeline summary"])
    }

    /// Direct Gemini API call for timeline summary
    private func callGeminiAPI(provider: GeminiProvider, prompt: String) async throws -> String {
        Logger.shared.info("🎯 Calling Gemini complete() method", source: "Analysis")
        let result = try await provider.complete(prompt: prompt)
        Logger.shared.debug("🎯 Gemini complete() returned \(result.count) chars", source: "Analysis")
        return result
    }

    /// Extract JSON from text (similar to provider implementation)
    private func extractJSON(from content: String) -> String? {
        // Try to extract from code blocks
        let codeBlockPatterns = ["```json", "```JSON", "```"]
        for pattern in codeBlockPatterns {
            if let startRange = content.range(of: pattern, options: .caseInsensitive) {
                let afterStart = content[startRange.upperBound...]
                if let endRange = afterStart.range(of: "```") {
                    var jsonBlock = String(afterStart[..<endRange.lowerBound])
                    jsonBlock = jsonBlock.trimmingCharacters(in: .whitespacesAndNewlines)

                    if let startIdx = jsonBlock.firstIndex(of: "{"),
                       let endIdx = jsonBlock.lastIndex(of: "}") {
                        return String(jsonBlock[startIdx...endIdx])
                    }
                }
            }
        }

        // Try to find raw JSON
        if let startIndex = content.firstIndex(of: "{"),
           let endIndex = content.lastIndex(of: "}") {
            return String(content[startIndex...endIndex])
        }

        return nil
    }
}

// MARK: - AnalysisView helpers
extension AnalysisView {
    private func currentBlocks(for type: ReportType) -> ReportBlocks {
        switch type {
        case .daily: return dailyBlocks
        case .weekly: return weeklyBlocks
        case .monthly: return monthlyBlocks
        }
    }

    private func setBlocks(_ blocks: ReportBlocks, for type: ReportType) {
        switch type {
        case .daily: dailyBlocks = blocks
        case .weekly: weeklyBlocks = blocks
        case .monthly: monthlyBlocks = blocks
        }
        saveBlocks(for: type, blocks: blocks)
    }

    private func saveBlocks(for type: ReportType, blocks: ReportBlocks) {
        ReportTemplateConfig.save(blocks, for: type.rawValue)
    }

    private func binding(for keyPath: WritableKeyPath<ReportBlocks, Bool>) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                currentBlocks(for: reportType)[keyPath: keyPath]
            },
            set: { newValue in
                var updated = currentBlocks(for: reportType)
                updated[keyPath: keyPath] = newValue
                setBlocks(updated, for: reportType)
            }
        )
    }

    private func blocksBinding(for type: ReportType) -> (
        includeStartRoutine: Binding<Bool>,
        includeTodo: Binding<Bool>,
        includeFocusBlocks: Binding<Bool>,
        includeEmotion: Binding<Bool>,
        includeAISection: Binding<Bool>,
        includeDeepWorkAnalysis: Binding<Bool>,
        includeDistractionBreakdown: Binding<Bool>,
        includeContextSwitching: Binding<Bool>,
        includeStats: Binding<Bool>,
        includeTimeline: Binding<Bool>,
        includeCategoriesAndApps: Binding<Bool>,
        includeCharts: Binding<Bool>,
        includeHistory: Binding<Bool>,
        includeScorecard: Binding<Bool>,
        includeFooter: Binding<Bool>
    ) {
        return (
            includeStartRoutine: binding(for: \.includeStartRoutine),
            includeTodo: binding(for: \.includeTodo),
            includeFocusBlocks: binding(for: \.includeFocusBlocks),
            includeEmotion: binding(for: \.includeEmotion),
            includeAISection: binding(for: \.includeAISection),
            includeDeepWorkAnalysis: binding(for: \.includeDeepWorkAnalysis),
            includeDistractionBreakdown: binding(for: \.includeDistractionBreakdown),
            includeContextSwitching: binding(for: \.includeContextSwitching),
            includeStats: binding(for: \.includeStats),
            includeTimeline: binding(for: \.includeTimeline),
            includeCategoriesAndApps: binding(for: \.includeCategoriesAndApps),
            includeCharts: binding(for: \.includeCharts),
            includeHistory: binding(for: \.includeHistory),
            includeScorecard: binding(for: \.includeScorecard),
            includeFooter: binding(for: \.includeFooter)
        )
    }
}

// MARK: - Custom Week Picker

struct WeekPickerView: View {
    @Binding var selectedDate: Date
    @State private var displayedMonth: Date
    
    private let calendar = Calendar.current
    
    // Initialize displayedMonth from selectedDate
    init(selectedDate: Binding<Date>) {
        self._selectedDate = selectedDate
        // Initialize displayedMonth to the month of selectedDate
        let components = Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue)
        self._displayedMonth = State(initialValue: Calendar.current.date(from: components) ?? Date())
    }
    
    // Get all weeks in the displayed month
    private var weeksInMonth: [WeekRange] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)),
              let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
            Logger.shared.error("Failed to calculate month range", source: "WeekPicker")
            return []
        }
        
        var weeks: [WeekRange] = []
        var currentDate = monthStart
        
        while currentDate <= monthEnd {
            // Find Monday of current week
            let weekday = calendar.component(.weekday, from: currentDate)
            let daysFromMonday = (weekday == 1) ? 6 : weekday - 2 // Sunday = 1, Monday = 2
            guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: currentDate),
                  let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
                break
            }
            
            weeks.append(WeekRange(start: weekStart, end: weekEnd))
            
            // Move to next week
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: currentDate) else { break }
            currentDate = nextWeek
        }
        
        Logger.shared.debug("Generated \(weeks.count) weeks for month \(displayedMonth.formatted(.dateTime.year().month()))", source: "WeekPicker")
        return weeks
    }
    
    // Get currently selected week
    private var selectedWeek: WeekRange? {
        let weekday = calendar.component(.weekday, from: selectedDate)
        let daysFromMonday = (weekday == 1) ? 6 : weekday - 2
        guard let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: selectedDate),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) else {
            return nil
        }
        return WeekRange(start: weekStart, end: weekEnd)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Month navigation
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(.headline)
                
                Spacer()
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            Divider()
            
            // Week list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(weeksInMonth) { week in
                        WeekRowView(
                            week: week,
                            isSelected: selectedWeek?.id == week.id,
                            action: {
                                Logger.shared.info("Week selected: \(week.displayText)", source: "WeekPicker")
                                selectedDate = week.start
                                Logger.shared.info("selectedDate updated to: \(selectedDate)", source: "WeekPicker")
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)
        }
        .onAppear {
            Logger.shared.info("WeekPickerView appeared - selectedDate: \(selectedDate), displayedMonth: \(displayedMonth)", source: "WeekPicker")
            // Align selectedDate to Monday of its week to ensure consistent selection
            let weekday = calendar.component(.weekday, from: selectedDate)
            let daysFromMonday = (weekday == 1) ? 6 : weekday - 2  // Sunday = 1, Monday = 2
            if daysFromMonday != 0 {
                if let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: selectedDate) {
                    Logger.shared.info("Aligning selectedDate from \(selectedDate) to Monday: \(weekStart)", source: "WeekPicker")
                    selectedDate = weekStart
                }
            }
        }
    }
    
    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = newMonth
            Logger.shared.debug("Previous month: \(displayedMonth.formatted(.dateTime.year().month()))", source: "WeekPicker")
        }
    }
    
    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = newMonth
            Logger.shared.debug("Next month: \(displayedMonth.formatted(.dateTime.year().month()))", source: "WeekPicker")
        }
    }
}

struct WeekRange: Identifiable {
    let start: Date
    let end: Date
    
    var id: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }
    
    var displayText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
    
    var weekNumber: String {
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: start)
        let year = calendar.component(.year, from: start)
        return "Week \(weekOfYear), \(year)"
    }
}

struct WeekRowView: View {
    let week: WeekRange
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(week.weekNumber)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(week.displayText)
                        .font(.body)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
            .contentShape(Rectangle()) // Make entire area clickable
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Month/Year Picker

struct MonthYearPickerView: View {
    @Binding var selectedDate: Date
    let isKorean: Bool
    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    private let calendar = Calendar.current
    private let currentYear = Calendar.current.component(.year, from: Date())
    
    init(selectedDate: Binding<Date>, isKorean: Bool) {
        self._selectedDate = selectedDate
        self.isKorean = isKorean
        let components = Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue)
        self._selectedYear = State(initialValue: components.year ?? Calendar.current.component(.year, from: Date()))
        self._selectedMonth = State(initialValue: components.month ?? Calendar.current.component(.month, from: Date()))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Year Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text(isKorean ? "연도" : "Year")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedYear) {
                        ForEach((currentYear - 5)...(currentYear + 1), id: \.self) { year in
                            Text(String(year))
                                .monospacedDigit()
                                .tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel(isKorean ? "연도" : "Year")
                    .frame(width: 110)
                }

                // Month Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text(isKorean ? "월" : "Month")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedMonth) {
                        ForEach(1...12, id: \.self) { month in
                            Text(monthName(month)).tag(month)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel(isKorean ? "월" : "Month")
                    .frame(width: 130)
                }
            }
            
        // Display selected month
        Text(displaySelectedMonth())
            .font(.title3)
            .foregroundStyle(.primary)
            .padding(.top, 8)
    }
        .frame(maxWidth: .infinity)
        .onChange(of: selectedYear) { _ in updateSelectedDate() }
        .onChange(of: selectedMonth) { _ in updateSelectedDate() }
    }
    
    private func monthName(_ month: Int) -> String {
        if isKorean {
            return "\(month)월"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM"
        return formatter.monthSymbols[month - 1]
    }
    
    private func displaySelectedMonth() -> String {
        if isKorean {
            return "\(selectedYear)년 \(selectedMonth)월"
        }

        // English string without comma
        let englishMonths = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        let monthIndex = max(1, min(12, selectedMonth)) - 1
        let monthString = englishMonths[monthIndex]
        return "\(monthString) \(selectedYear)"
    }
    
    private func updateSelectedDate() {
        var components = DateComponents()
        components.year = selectedYear
        components.month = selectedMonth
        components.day = 1
        
        if let newDate = calendar.date(from: components) {
            selectedDate = newDate
        }
    }
}

#if DEBUG
#Preview {
    AnalysisView()
        .frame(width: 1000, height: 700)
}
#endif
