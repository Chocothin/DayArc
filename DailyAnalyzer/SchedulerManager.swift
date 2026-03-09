//
//  SchedulerManager.swift
//  DayArc
//
//  Background task scheduling with 10-minute polling reliability
//

import Foundation
import UserNotifications

class SchedulerManager {
    static let shared = SchedulerManager()

    private var timer: Timer?
    private let pollingInterval: TimeInterval = 600 // 10 minutes
    private let userDefaults = UserDefaults.standard

    private let lastDailyRunKey = "LastDailyReportRun"
    private let lastWeeklyRunKey = "LastWeeklyReportRun"
    private let lastMonthlyRunKey = "LastMonthlyReportRun"

    private init() {}

    // MARK: - Setup

    func setup() {
        Logger.shared.info("Setting up scheduler", source: "SchedulerManager")

        // Request notification permission and register categories
        NotificationManager.shared.requestPermission()
        NotificationManager.shared.registerNotificationCategories()

        // Start 10-minute polling timer
        startPolling()

        // Check immediately on startup
        checkAndRunScheduledTasks()
    }

    func shutdown() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private func startPolling() {
        // Run on main thread to ensure timer fires
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Initial check with delay to allow app to fully launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                self.checkAndRunScheduledTasks()
            }

            // Invalidate existing timer to prevent duplicates/leaks
            self.timer?.invalidate()
            
            self.timer = Timer.scheduledTimer(
                withTimeInterval: self.pollingInterval,
                repeats: true
            ) { [weak self] _ in
                self?.checkAndRunScheduledTasks()
            }

            // Ensure timer runs even when app is in background
            if let timer = self.timer {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    // MARK: - Task Checking

    @objc private func checkAndRunScheduledTasks() {
        let config = ScheduleConfig.load()

        guard config.isEnabled else {
            Logger.shared.debug("Scheduler check: disabled", source: "Scheduler")
            return
        }

        Logger.shared.debug("Scheduler check: running task evaluation", source: "Scheduler")
        let now = Date()
        let calendar = Calendar.current
        
        // 1. Check for missed Daily Reports (Yesterday)
        // If we haven't generated a report for yesterday, do it now (Catch-up)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now) {
            Logger.shared.debug("Checking catch-up for yesterday: \(yesterday)", source: "Scheduler")
            if shouldRunDailyReport(for: yesterday, config: config, isCatchUp: true) {
                Logger.shared.info("Scheduler triggered: Daily report (Catch-up for \(yesterday))", source: "Scheduler")
                runDailyReport(for: yesterday)
            } else {
                Logger.shared.debug("Catch-up for yesterday skipped (shouldRunDailyReport returned false)", source: "Scheduler")
            }
        }

        // 2. Check for Today's Daily Report
        // Only run if it's past the scheduled time
        // DISABLED: User requests only "Yesterday's Report" logic (Catch-up).
        // Generating today's report on the same day results in incomplete data.
        /*
        if shouldRunDailyReport(for: now, config: config, isCatchUp: false) {
            Logger.shared.info("Scheduler triggered: Daily report (Today)", source: "Scheduler")
            runDailyReport(for: now)
        }
        */

        // 3. Check for Weekly Report (Last Week)
        // If today is Monday or later, and we haven't generated last week's report
        if shouldRunWeeklyReport(at: now) {
            // Calculate last week's start date
            // If today is Monday (weekday 2), last week started 7 days ago
            // If today is Tuesday (weekday 3), last week started 8 days ago...
            // We just need a date *within* last week to identify it.
            // Let's use "last week's start date" as the identifier.
            
            let weekday = calendar.component(.weekday, from: now)
            // Calculate days to subtract to get to last week's Monday (assuming Monday start)
            // or Sunday. Let's stick to the existing logic: Weekly report covers Mon-Sun? 
            // The existing `runWeeklyReport` calculates `weekStart` from the passed date.
            // We should pass a date that belongs to the *previous* week.
            
            if let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now) {
                 Logger.shared.info("Scheduler triggered: Weekly report", source: "Scheduler")
                 runWeeklyReport(for: lastWeekDate)
            }
        }

        // 4. Check for Monthly Report (Last Month)
        // If today is 1st or later, and we haven't generated last month's report
        if shouldRunMonthlyReport(at: now) {
            if let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now) {
                Logger.shared.info("Scheduler triggered: Monthly report", source: "Scheduler")
                runMonthlyReport(for: lastMonthDate)
            }
        }
    }

    private func shouldRunDailyReport(for targetDate: Date, config: ScheduleConfig, isCatchUp: Bool) -> Bool {
        let calendar = Calendar.current
        
        Logger.shared.debug("Evaluating shouldRunDailyReport for targetDate: \(targetDate), isCatchUp: \(isCatchUp)", source: "Scheduler")

        // 1. Check File Existence (Primary Source of Truth)
        let vaultConfig = VaultConfiguration.load()
        do {
            let vault = try vaultConfig.getVault()
            if vault.noteExists(for: targetDate, type: .daily) {
                Logger.shared.debug("Daily note file already exists for \(targetDate). Skipping.", source: "Scheduler")
                return false
            }
        } catch {
            Logger.shared.error("Failed to check vault for daily note: \(error)", source: "Scheduler")
            // If we can't check the vault, fall back to UserDefaults or fail safe?
            // Failing safe (return false) might be better to avoid spamming errors, 
            // but for catch-up we might want to try?
            // Let's fall back to UserDefaults check if vault check fails.
        }

        // 2. Check UserDefaults (Secondary/Legacy Check)
        // Check if we already ran for this specific date (in case file check failed or for double safety)
        let lastTargetDateKey = "LastDailyReportTargetDate"
        if let lastTargetDate = userDefaults.object(forKey: lastTargetDateKey) as? Date {
            if calendar.isDate(lastTargetDate, inSameDayAs: targetDate) {
                // If file check passed (meaning file doesn't exist) but this key says we ran it,
                // it means the user deleted the file. We SHOULD run it again.
                // So we ignore this key if the file is missing.
                // But if we couldn't check the file (error above), we respect this key.
                Logger.shared.debug("UserDefaults says we ran for \(targetDate), but file check implies it's missing (or failed).", source: "Scheduler")
            }
        }
        
        if isCatchUp {
            // For catch-up (yesterday), if file is missing, we run.
            Logger.shared.debug("Catch-up mode: File missing, returning true", source: "Scheduler")
            return true
        } else {
            // For today, we also need to check the time
            let targetHour = calendar.component(.hour, from: config.dailyTime)
            let targetMinute = calendar.component(.minute, from: config.dailyTime)
            let currentHour = calendar.component(.hour, from: Date())
            let currentMinute = calendar.component(.minute, from: Date())
            
            let isPastTargetTime = (currentHour > targetHour) ||
                                   (currentHour == targetHour && currentMinute >= targetMinute)
            
            Logger.shared.debug("Standard mode: isPastTargetTime = \(isPastTargetTime)", source: "Scheduler")
            return isPastTargetTime
        }
    }

    private func shouldRunWeeklyReport(at date: Date) -> Bool {
        let calendar = Calendar.current

        // Weekly report is for the *previous* week.
        // We should run it if:
        // 1. It's Monday (or later in the week, for catch-up)
        // 2. We haven't generated a report for *last week* yet.

        // Calculate start of *last* week (the target of the report)
        guard let lastWeekDate = calendar.date(byAdding: .weekOfYear, value: -1, to: date) else { return false }
        let lastWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: lastWeekDate))!

        // 1. Check if we already attempted this week (includes noActivities case)
        if let lastAttemptedWeekStart = userDefaults.object(forKey: "LastWeeklyReportTargetWeekStart") as? Date {
            let lastAttemptedWeekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: lastAttemptedWeekStart)
            let targetWeekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: lastWeekStart)

            if lastAttemptedWeekComponents.yearForWeekOfYear == targetWeekComponents.yearForWeekOfYear &&
               lastAttemptedWeekComponents.weekOfYear == targetWeekComponents.weekOfYear {
                Logger.shared.debug("Weekly report already attempted for week of \(lastWeekStart). Skipping.", source: "Scheduler")
                return false
            }
        }

        // 2. Check File Existence (backup check)
        let vaultConfig = VaultConfiguration.load()
        do {
            let vault = try vaultConfig.getVault()
            if vault.noteExists(for: lastWeekStart, type: .weekly) {
                Logger.shared.debug("Weekly note file already exists for week of \(lastWeekStart). Skipping.", source: "Scheduler")
                return false
            }
        } catch {
            Logger.shared.error("Failed to check vault for weekly note: \(error)", source: "Scheduler")
        }

        return true
    }

    private func shouldRunMonthlyReport(at date: Date) -> Bool {
        let calendar = Calendar.current

        // Monthly report is for the *previous* month.
        // Run if:
        // 1. It's the 1st of the month (or later, for catch-up)
        // 2. We haven't generated a report for *last month* yet.

        // Calculate start of *last* month
        guard let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: date) else { return false }
        let lastMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: lastMonthDate))!

        // 1. Check if we already attempted this month (includes noActivities case)
        if let lastAttemptedMonth = userDefaults.object(forKey: "LastMonthlyReportTargetMonth") as? Date {
            let lastAttemptedComponents = calendar.dateComponents([.year, .month], from: lastAttemptedMonth)
            let targetComponents = calendar.dateComponents([.year, .month], from: lastMonthStart)

            if lastAttemptedComponents.year == targetComponents.year &&
               lastAttemptedComponents.month == targetComponents.month {
                Logger.shared.debug("Monthly report already attempted for \(lastMonthStart). Skipping.", source: "Scheduler")
                return false
            }
        }

        // 2. Check File Existence (backup check)
        let vaultConfig = VaultConfiguration.load()
        do {
            let vault = try vaultConfig.getVault()
            if vault.noteExists(for: lastMonthStart, type: .monthly) {
                Logger.shared.debug("Monthly note file already exists for \(lastMonthStart). Skipping.", source: "Scheduler")
                return false
            }
        } catch {
            Logger.shared.error("Failed to check vault for monthly note: \(error)", source: "Scheduler")
        }

        return true
    }

    private func loadLanguage() -> ReportLanguage {
        let raw = UserDefaults.standard.string(forKey: "reportLanguage") ?? ReportLanguage.korean.rawValue
        return ReportLanguage(rawValue: raw) ?? .korean
    }

    // MARK: - Report Generation

    private func runDailyReport(for date: Date) {
        Logger.shared.info("Running daily report for \(date)", source: "SchedulerManager")

        Task {
            do {
                let path = try await generateAndSaveDailyReport(for: date)

                // Update both legacy and new keys
                userDefaults.set(Date(), forKey: lastDailyRunKey)
                userDefaults.set(date, forKey: "LastDailyReportTargetDate") // Save the target date

                NotificationManager.shared.sendReportNotification(
                    type: .daily,
                    date: date,
                    success: true,
                    notePath: path
                )
            } catch SchedulerError.noActivities {
                // No activities for this period - this is expected, skip notification
                // (Same handling as weekly/monthly reports)
                Logger.shared.info("Daily report skipped: no activities for \(date)", source: "SchedulerManager")
                userDefaults.set(Date(), forKey: lastDailyRunKey)
                userDefaults.set(date, forKey: "LastDailyReportTargetDate")
            } catch let vaultError as VaultError {
                // Handle permission denied specifically
                if case .permissionDenied(let path) = vaultError {
                    Logger.shared.error("Permission denied for daily report at: \(path)", source: "SchedulerManager")
                    let permError = NSError(
                        domain: "VaultPermission",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Permission denied to write to \(path). Please open DayArc, go to Analysis tab, try saving a report manually, and grant access when prompted."
                        ]
                    )
                    NotificationManager.shared.sendReportNotification(
                        type: .daily,
                        date: date,
                        success: false,
                        error: permError
                    )
                } else {
                    Logger.shared.error("Failed to generate daily report: \(vaultError)", source: "SchedulerManager")
                    NotificationManager.shared.sendReportNotification(
                        type: .daily,
                        date: date,
                        success: false,
                        error: vaultError
                    )
                }
            } catch {
                Logger.shared.error("Failed to generate daily report: \(error)", source: "SchedulerManager")
                NotificationManager.shared.sendReportNotification(
                    type: .daily,
                    date: date,
                    success: false,
                    error: error
                )
            }
        }
    }

    private func runWeeklyReport(for date: Date) {
        Logger.shared.info("Running weekly report for week of \(date)", source: "SchedulerManager")

        let calendar = Calendar.current
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!

        Task {
            do {
                let path = try await generateAndSaveWeeklyReport(for: weekStart)
                
                userDefaults.set(Date(), forKey: lastWeeklyRunKey)
                userDefaults.set(weekStart, forKey: "LastWeeklyReportTargetWeekStart") // Save target week start
                
                NotificationManager.shared.sendReportNotification(
                    type: .weekly,
                    date: weekStart,
                    success: true,
                    notePath: path
                )
            } catch SchedulerError.noActivities {
                // No activities for this period - this is expected, skip notification
                Logger.shared.info("Weekly report skipped: no activities for week of \(weekStart)", source: "SchedulerManager")
                userDefaults.set(Date(), forKey: lastWeeklyRunKey)
                userDefaults.set(weekStart, forKey: "LastWeeklyReportTargetWeekStart")
            } catch let vaultError as VaultError {
                // Save target week to prevent infinite retry
                userDefaults.set(Date(), forKey: lastWeeklyRunKey)
                userDefaults.set(weekStart, forKey: "LastWeeklyReportTargetWeekStart")
                // Handle permission denied specifically
                if case .permissionDenied(let path) = vaultError {
                    Logger.shared.error("Permission denied for weekly report at: \(path)", source: "SchedulerManager")
                    let permError = NSError(
                        domain: "VaultPermission",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Permission denied to write to \(path). Please open DayArc, go to Analysis tab, try saving a report manually, and grant access when prompted."
                        ]
                    )
                    NotificationManager.shared.sendReportNotification(
                        type: .weekly,
                        date: weekStart,
                        success: false,
                        error: permError
                    )
                } else {
                    Logger.shared.error("Failed to generate weekly report: \(vaultError)", source: "SchedulerManager")
                    NotificationManager.shared.sendReportNotification(
                        type: .weekly,
                        date: weekStart,
                        success: false,
                        error: vaultError
                    )
                }
            } catch {
                Logger.shared.error("Failed to generate weekly report: \(error)", source: "SchedulerManager")
                // Save target week to prevent infinite retry on persistent errors
                userDefaults.set(Date(), forKey: lastWeeklyRunKey)
                userDefaults.set(weekStart, forKey: "LastWeeklyReportTargetWeekStart")
                NotificationManager.shared.sendReportNotification(
                    type: .weekly,
                    date: weekStart,
                    success: false,
                    error: error
                )
            }
        }
    }

    private func runMonthlyReport(for date: Date) {
        Logger.shared.info("Running monthly report for \(date)", source: "SchedulerManager")

        let calendar = Calendar.current
        // target previous month
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        // If 'date' is already in the previous month (passed from checkAndRunScheduledTasks), use it directly
        // But let's be safe and ensure we get the start of the month for the passed date
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!

        Task {
            do {
                let path = try await generateAndSaveMonthlyReport(for: monthStart)
                
                userDefaults.set(Date(), forKey: lastMonthlyRunKey)
                userDefaults.set(monthStart, forKey: "LastMonthlyReportTargetMonth") // Save target month start
                
                NotificationManager.shared.sendReportNotification(
                    type: .monthly,
                    date: monthStart,
                    success: true,
                    notePath: path
                )
            } catch SchedulerError.noActivities {
                // No activities for this period - this is expected, skip notification
                Logger.shared.info("Monthly report skipped: no activities for month of \(monthStart)", source: "SchedulerManager")
                userDefaults.set(Date(), forKey: lastMonthlyRunKey)
                userDefaults.set(monthStart, forKey: "LastMonthlyReportTargetMonth")
            } catch let vaultError as VaultError {
                // Save target month to prevent infinite retry
                userDefaults.set(Date(), forKey: lastMonthlyRunKey)
                userDefaults.set(monthStart, forKey: "LastMonthlyReportTargetMonth")
                // Handle permission denied specifically
                if case .permissionDenied(let path) = vaultError {
                    Logger.shared.error("Permission denied for monthly report at: \(path)", source: "SchedulerManager")
                    let permError = NSError(
                        domain: "VaultPermission",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Permission denied to write to \(path). Please open DayArc, go to Analysis tab, try saving a report manually, and grant access when prompted."
                        ]
                    )
                    NotificationManager.shared.sendReportNotification(
                        type: .monthly,
                        date: monthStart,
                        success: false,
                        error: permError
                    )
                } else {
                    Logger.shared.error("Failed to generate monthly report: \(vaultError)", source: "SchedulerManager")
                    NotificationManager.shared.sendReportNotification(
                        type: .monthly,
                        date: monthStart,
                        success: false,
                        error: vaultError
                    )
                }
            } catch {
                Logger.shared.error("Failed to generate monthly report: \(error)", source: "SchedulerManager")
                // Save target month to prevent infinite retry on persistent errors
                userDefaults.set(Date(), forKey: lastMonthlyRunKey)
                userDefaults.set(monthStart, forKey: "LastMonthlyReportTargetMonth")
                NotificationManager.shared.sendReportNotification(
                    type: .monthly,
                    date: monthStart,
                    success: false,
                    error: error
                )
            }
        }
    }

    // MARK: - Report Generation Logic

    private func generateAndSaveDailyReport(for date: Date) async throws -> String {
        guard let dbPath = DayflowDatabase.findDayflowDatabase() else {
            let searched = DayflowDatabase.lastSearchedPaths.joined(separator: ", ")
            throw SchedulerError.databaseNotFoundAlongPaths(searched)
        }
        let language = loadLanguage()
        let blocks = ReportTemplateConfig.load(for: "daily")

        let db = DayflowDatabase(dbPath: dbPath)
        let activities = try db.fetchActivities(for: date)

        guard !activities.isEmpty else {
            throw SchedulerError.noActivities
        }

        let stats = StatsCalculator.calculateDailyStats(from: activities, date: date)

        // Historical context (7/30 days)
        let history = try await computeHistoricalContext(db: db, targetDate: date)

        // Charts (category/hourly/deep vs shallow) - macOS 14+
        var chartPaths: [URL] = []
        if #available(macOS 14.0, *) {
            let dateLabel = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
            if let cat = await ChartGenerator.generateCategoryPie(dailyStats: stats, dateLabel: dateLabel) {
                chartPaths.append(cat)
            }
            if let hourly = await ChartGenerator.generateHourlyBar(activities: activities, dateLabel: dateLabel) {
                chartPaths.append(hourly)
            }
            if let deepVsShallow = await ChartGenerator.generateDeepVsShallow(activities: activities, dateLabel: dateLabel) {
                chartPaths.append(deepVsShallow)
            }
            
            // Copy charts to Obsidian vault charts folder (matching AnalysisView)
            let vaultConfig = VaultConfiguration.load()
            if !vaultConfig.vaultPath.isEmpty {
                let vaultURL = URL(fileURLWithPath: vaultConfig.vaultPath)
                let chartsFolder = vaultURL.appendingPathComponent("charts", isDirectory: true)
                try? FileManager.default.createDirectory(at: chartsFolder, withIntermediateDirectories: true)

                for chartPath in chartPaths {
                    let destPath = chartsFolder.appendingPathComponent(chartPath.lastPathComponent)
                    try? FileManager.default.removeItem(at: destPath) // Remove if exists
                    try? FileManager.default.copyItem(at: chartPath, to: destPath)
                    Logger.shared.debug("Copied chart to vault: \(chartPath.lastPathComponent)", source: "Scheduler")
                }
            }
        }

        // Try to get AI analysis
        let aiConfig: AIProviderConfig? = AIProviderConfig.load()
        let analysis = await AnalysisFallback.runAnalysis(
            config: aiConfig,
            activities: activities,
            date: date
        )
        
        // Generate timeline summaries if AI available (matching AnalysisView)
        var timelineSummaries: [TimelineSummary] = []
        Logger.shared.debug("🎯 Timeline summary check - aiConfig: \(aiConfig != nil ? "present" : "nil"), language: \(language)", source: "Scheduler")

        if let config = aiConfig, language == .korean {
            Logger.shared.info("🎯 Starting timeline summary generation...", source: "Scheduler")
            timelineSummaries = await generateTimelineSummaries(
                activities: activities,
                config: config,
                language: language
            )
            Logger.shared.info("🎯 Generated \(timelineSummaries.count) timeline summaries", source: "Scheduler")
        } else {
            if aiConfig == nil {
                Logger.shared.warning("🎯 Timeline summary skipped: No AI config", source: "Scheduler")
            } else if language != .korean {
                Logger.shared.warning("🎯 Timeline summary skipped: Language is \(language), not Korean", source: "Scheduler")
            }
        }

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

        let vaultConfig = VaultConfiguration.load()
        let vault = try vaultConfig.getVault()
        return try vault.saveDailyNote(date: date, markdown: markdown)
    }

    private func generateAndSaveWeeklyReport(for startDate: Date) async throws -> String {
        guard let dbPath = DayflowDatabase.findDayflowDatabase() else {
            let searched = DayflowDatabase.lastSearchedPaths.joined(separator: ", ")
            throw SchedulerError.databaseNotFoundAlongPaths(searched)
        }
        let language = loadLanguage()
        let blocks = ReportTemplateConfig.load(for: "weekly")

        let calendar = Calendar.current
        let weekStart = calendar.startOfDay(for: startDate)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!

        let db = DayflowDatabase(dbPath: dbPath)
        let activities = try db.fetchActivities(from: weekStart, to: weekEnd)

        guard !activities.isEmpty else {
            throw SchedulerError.noActivities
        }

        // Calculate daily stats for each day first (include all 7 days for display)
        var dailyStats: [DailyStats] = []
        for day in 0..<7 {
            if let dayDate = calendar.date(byAdding: .day, value: day, to: weekStart) {
                let dayActivities = activities.filter { activity in
                    calendar.isDate(activity.startAt, inSameDayAs: dayDate)
                }
                let stats = StatsCalculator.calculateDailyStats(from: dayActivities, date: dayDate)
                dailyStats.append(stats)
            }
        }

        // Aggregate daily stats into weekly stats (excludes days with no activity from averages)
        guard let weeklyStats = StatsCalculator.calculateWeeklyStats(from: dailyStats) else {
            throw SchedulerError.noActivities
        }

        // Charts for the week (category/hourly/deep vs shallow/trend)
        var chartPaths: [URL] = []
        if #available(macOS 14.0, *) {
            let dateLabel = DateFormatter.localizedString(from: weekStart, dateStyle: .short, timeStyle: .none)
            if let cat = await ChartGenerator.generateCategoryPie(dailyStats: weeklyStats, dateLabel: dateLabel) {
                chartPaths.append(cat)
            }
            if let hourly = await ChartGenerator.generateHourlyBar(activities: activities, dateLabel: dateLabel) {
                chartPaths.append(hourly)
            }
            if let deepVsShallow = await ChartGenerator.generateDeepVsShallow(activities: activities, dateLabel: dateLabel) {
                chartPaths.append(deepVsShallow)
            }
            if !dailyStats.isEmpty, let trend = await ChartGenerator.generateWeeklyTrend(dailyStats: dailyStats, dateLabel: dateLabel) {
                chartPaths.append(trend)
            }
        }

        // AI analysis for the week
        let aiConfig: AIProviderConfig? = AIProviderConfig.load()
        let analysis = await AnalysisFallback.runAnalysis(
            config: aiConfig,
            activities: activities,
            date: weekStart
        )

        // Previous week comparison
        let prevWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart)!
        let prevWeekEnd = calendar.date(byAdding: .day, value: 7, to: prevWeekStart)!
        let prevActivities = try db.fetchActivities(from: prevWeekStart, to: prevWeekEnd)
        let previousWeekStats = prevActivities.isEmpty ? nil : StatsCalculator.calculateDailyStats(from: prevActivities, date: prevWeekStart)

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

        let vaultConfig = VaultConfiguration.load()
        let vault = try vaultConfig.getVault()
        return try vault.saveWeeklyNote(startDate: weekStart, markdown: markdown)
    }

    private func generateAndSaveMonthlyReport(for month: Date) async throws -> String {
        guard let dbPath = DayflowDatabase.findDayflowDatabase() else {
            let searched = DayflowDatabase.lastSearchedPaths.joined(separator: ", ")
            throw SchedulerError.databaseNotFoundAlongPaths(searched)
        }
        let language = loadLanguage()
        let blocks = ReportTemplateConfig.load(for: "monthly")

        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart)!

        let db = DayflowDatabase(dbPath: dbPath)
        let activities = try db.fetchActivities(from: monthStart, to: monthEnd)

        guard !activities.isEmpty else {
            throw SchedulerError.noActivities
        }

        // Calculate daily stats for each day first
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        var dailyStats: [DailyStats] = []
        for day in 0..<daysInMonth {
            if let dayDate = calendar.date(byAdding: .day, value: day, to: monthStart) {
                let dayActivities = activities.filter { activity in
                    calendar.isDate(activity.startAt, inSameDayAs: dayDate)
                }
                let stats = StatsCalculator.calculateDailyStats(from: dayActivities, date: dayDate)
                dailyStats.append(stats)
            }
        }

        // Aggregate daily stats into monthly stats (excludes days with no activity from averages)
        guard let monthlyStats = StatsCalculator.calculateWeeklyStats(from: dailyStats) else {
            throw SchedulerError.noActivities
        }

        // Calculate weekly stats for weekly breakdown in monthly report
        var weeklyStats: [DailyStats] = []
        var currentWeekStart = monthStart
        while currentWeekStart < monthEnd {
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: currentWeekStart)!
            // Get daily stats for this week
            let weekDailyStats = dailyStats.filter { stat in
                stat.date >= currentWeekStart && stat.date < min(weekEnd, monthEnd)
            }
            if !weekDailyStats.isEmpty, let stats = StatsCalculator.calculateWeeklyStats(from: weekDailyStats) {
                weeklyStats.append(stats)
            }
            currentWeekStart = weekEnd
        }

        // Charts for the month (category/hourly/deep vs shallow/trend)
        var chartPaths: [URL] = []
        if #available(macOS 14.0, *) {
            let dateLabel = DateFormatter.localizedString(from: monthStart, dateStyle: .short, timeStyle: .none)
            if let cat = await ChartGenerator.generateCategoryPie(dailyStats: monthlyStats, dateLabel: dateLabel) {
                chartPaths.append(cat)
            }
            if let hourly = await ChartGenerator.generateHourlyBar(activities: activities, dateLabel: dateLabel) {
                chartPaths.append(hourly)
            }
            if let deepVsShallow = await ChartGenerator.generateDeepVsShallow(activities: activities, dateLabel: dateLabel) {
                chartPaths.append(deepVsShallow)
            }
            if !weeklyStats.isEmpty, let trend = await ChartGenerator.generateMonthlyTrend(weeklyStats: weeklyStats, dateLabel: dateLabel) {
                chartPaths.append(trend)
            }
        }

        // AI analysis for the month
        let aiConfig: AIProviderConfig? = AIProviderConfig.load()
        let analysis = await AnalysisFallback.runAnalysis(
            config: aiConfig,
            activities: activities,
            date: monthStart
        )

        // Previous month comparison
        let prevMonthStart = calendar.date(byAdding: .month, value: -1, to: monthStart)!
        let prevMonthEnd = calendar.date(byAdding: .month, value: 1, to: prevMonthStart)!
        let prevActivities = try db.fetchActivities(from: prevMonthStart, to: prevMonthEnd)
        let previousMonthStats = prevActivities.isEmpty ? nil : StatsCalculator.calculateDailyStats(from: prevActivities, date: prevMonthStart)

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

        let vaultConfig = VaultConfiguration.load()
        let vault = try vaultConfig.getVault()
        return try vault.saveMonthlyNote(month: monthStart, markdown: markdown)
    }

    // MARK: - Helper Functions

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
    
    // MARK: - Timeline Summaries

    /// Generate AI summaries for timeline groups (matching AnalysisView)
    private func generateTimelineSummaries(
        activities: [TimelineCard],
        config: AIProviderConfig,
        language: ReportLanguage
    ) async -> [TimelineSummary] {
        Logger.shared.info("🎯 generateTimelineSummaries called with \(activities.count) activities", source: "Scheduler")

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

        Logger.shared.info("🎯 Created \(activityGroups.count) activity groups", source: "Scheduler")

        // Generate summaries for top 10 groups
        var summaries: [TimelineSummary] = []
        let languageCode = language == .korean ? "Korean" : "English"

        for (index, group) in activityGroups.prefix(10).enumerated() {
            Logger.shared.debug("🎯 Processing group \(index + 1)/\(min(10, activityGroups.count))", source: "Scheduler")
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

            Logger.shared.debug("🎯 Combined details length: \(combinedDetails.count) chars", source: "Scheduler")

            // Call AI to summarize and translate
            if let summary = await summarizeTimelineGroup(
                details: combinedDetails,
                config: config,
                targetLanguage: languageCode
            ) {
                Logger.shared.info("🎯 Successfully generated summary for group \(index + 1): \(summary.title)", source: "Scheduler")
                summaries.append(summary)
            } else {
                Logger.shared.warning("🎯 Failed to generate summary for group \(index + 1)", source: "Scheduler")
            }
        }

        Logger.shared.info("🎯 Total summaries generated: \(summaries.count)", source: "Scheduler")
        return summaries
    }

    /// Call AI API to summarize and translate a timeline group
    private func summarizeTimelineGroup(
        details: String,
        config: AIProviderConfig,
        targetLanguage: String
    ) async -> TimelineSummary? {
        Logger.shared.debug("🎯 summarizeTimelineGroup called", source: "Scheduler")

        // Use first provider in chain
        guard let provider = config.providerChain().first else {
            Logger.shared.error("🎯 No provider available in chain", source: "Scheduler")
            return nil
        }

        Logger.shared.info("🎯 Using provider: \(provider.providerType.displayName)", source: "Scheduler")

        // Get prompt from PromptManager
        let basePrompt = PromptManager.shared.getPrompt(for: .timelineSummary)

        // Build prompt
        let prompt = """
        Please analyze the following activity log and provide:
        1. A concise title (max 50 characters) summarizing the main work done
        2. A brief summary (2-3 sentences) explaining what was accomplished
        3. Infer a category (e.g., "Work > Development", "Personal > Learning", etc.)
        
        \(basePrompt)

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

        Logger.shared.debug("🎯 Prompt prepared, calling API...", source: "Scheduler")

        do {
            // Make API call
            let result = try await callProviderAPI(provider: provider, prompt: prompt)
            Logger.shared.debug("🎯 API call successful, result length: \(result.count)", source: "Scheduler")

            // Parse JSON
            if let jsonData = extractJSON(from: result) {
                Logger.shared.debug("🎯 JSON extracted: \(jsonData.prefix(200))...", source: "Scheduler")
                if let data = jsonData.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let title = json["title"] as? String,
                   let summary = json["summary"] as? String {
                    let category = json["category"] as? String
                    Logger.shared.info("🎯 Successfully parsed timeline summary", source: "Scheduler")
                    return TimelineSummary(title: title, summary: summary, category: category)
                } else {
                    Logger.shared.error("🎯 Failed to parse JSON to TimelineSummary", source: "Scheduler")
                }
            } else {
                Logger.shared.error("🎯 Failed to extract JSON from result", source: "Scheduler")
            }
        } catch {
            Logger.shared.error("🎯 Failed to generate timeline summary: \(error.localizedDescription)", source: "Scheduler")
        }

        return nil
    }

    /// Make API call to provider
    private func callProviderAPI(provider: any AIProvider, prompt: String) async throws -> String {
        Logger.shared.debug("🎯 callProviderAPI - Provider type: \(provider.providerType)", source: "Scheduler")

        // For Gemini, make direct API call
        if provider.providerType == .gemini {
            Logger.shared.debug("🎯 Provider is Gemini, calling Gemini API", source: "Scheduler")
            if let geminiProvider = provider as? GeminiProvider {
                return try await callGeminiAPI(provider: geminiProvider, prompt: prompt)
            } else {
                Logger.shared.error("🎯 Failed to cast provider to GeminiProvider", source: "Scheduler")
            }
        }

        Logger.shared.error("🎯 Provider \(provider.providerType) not supported for timeline summary", source: "Scheduler")
        throw NSError(domain: "TimelineSummary", code: -1, userInfo: [NSLocalizedDescriptionKey: "Provider not supported for timeline summary"])
    }

    /// Direct Gemini API call for timeline summary
    private func callGeminiAPI(provider: GeminiProvider, prompt: String) async throws -> String {
        Logger.shared.info("🎯 Calling Gemini complete() method", source: "Scheduler")
        let result = try await provider.complete(prompt: prompt)
        Logger.shared.debug("🎯 Gemini complete() returned \(result.count) chars", source: "Scheduler")
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

// MARK: - Errors

enum SchedulerError: Error, LocalizedError {
    case databaseNotFound
    case databaseNotFoundAlongPaths(String)
    case vaultNotConfigured
    case noActivities

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            return "DayArc database not found"
        case .databaseNotFoundAlongPaths(let paths):
            return "DayArc database not found. Searched: \(paths)"
        case .vaultNotConfigured:
            return "Obsidian vault not configured"
        case .noActivities:
            return "No activities found for the selected period"
        }
    }
}
