//
//  DashboardView.swift
//  DayArc
//
//  Dashboard with Swift Charts visualization
//

import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var selectedDate = Date()
    @AppStorage("reportLanguage") private var reportLanguageRaw = ReportLanguage.korean.rawValue
    
    private var isKorean: Bool {
        (ReportLanguage(rawValue: reportLanguageRaw) ?? .korean) == .korean
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // Quick Stats Cards
                statsCardsSection

                // Productivity Score Chart
                productivityChartSection

                // Top Apps Chart
                topAppsChartSection

                // Activity Timeline
                timelineSection
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.loadData(for: selectedDate)
        }
        .modifier(DashboardKeyboardModifier(selectedDate: $selectedDate, isLoading: viewModel.isLoading, onDateChange: { date in
            viewModel.loadData(for: date)
        }))
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(isKorean ? "대시보드" : "Dashboard")
                    .font(.largeTitle)
                    .bold()

                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                // Previous Day Button
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                    viewModel.loadData(for: selectedDate)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(isKorean ? "어제" : "Previous Day")

                // Date Picker
                DatePicker(isKorean ? "날짜 선택" : "Select Date", selection: $selectedDate, displayedComponents: .date)
                    .labelsHidden()
                    .onChange(of: selectedDate) { newDate in
                        viewModel.loadData(for: newDate)
                    }

                // Next Day Button
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    viewModel.loadData(for: selectedDate)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(isKorean ? "내일" : "Next Day")

                Divider()
                    .frame(height: 20)

                // Today Button
                Button {
                    selectedDate = Date()
                    viewModel.loadData(for: selectedDate)
                } label: {
                    Text(isKorean ? "오늘" : "Today")
                        .font(.callout)
                }
                .buttonStyle(.bordered)

                // Refresh Button
                Button {
                    viewModel.loadData(for: selectedDate)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .help(isKorean ? "새로고침" : "Refresh")
            }
        }
    }

    // MARK: - Stats Cards

    private var statsCardsSection: some View {
        HStack(spacing: 16) {
            // Overall Score Card
            StatsCard(
                title: isKorean ? "생산성 점수" : "Productivity Score",
                value: "\(Int(viewModel.stats?.productivityScore.totalScore ?? 0))",
                subtitle: viewModel.stats?.productivityScore.category ?? "N/A",
                icon: "chart.bar.fill",
                color: scoreColor(viewModel.stats?.productivityScore.totalScore ?? 0)
            )

            // Active Time Card
            StatsCard(
                title: isKorean ? "활동 시간" : "Active Time",
                value: viewModel.stats?.formattedActiveTime ?? "0h 0m",
                subtitle: isKorean ? "\(viewModel.stats?.totalActivities ?? 0)개 활동" : "\(viewModel.stats?.totalActivities ?? 0) activities",
                icon: "clock.fill",
                color: .blue
            )

            // Apps Used Card
            StatsCard(
                title: isKorean ? "사용한 앱" : "Apps Used",
                value: "\(viewModel.stats?.uniqueApps ?? 0)",
                subtitle: isKorean ? "개의 앱" : "unique apps",
                icon: "app.fill",
                color: .purple
            )
        }
        .frame(height: 120)
    }

    // MARK: - Productivity Chart

    private var productivityChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isKorean ? "생산성 분석" : "Productivity Breakdown")
                .font(.headline)

            if let stats = viewModel.stats {
                Chart {
                    BarMark(
                        x: .value("Score", stats.productivityScore.deepWorkScore),
                        y: .value("Component", isKorean ? "딥워크" : "Deep Work")
                    )
                    .foregroundStyle(.green)

                    BarMark(
                        x: .value("Score", stats.productivityScore.diversityScore),
                        y: .value("Component", isKorean ? "다양성" : "Diversity")
                    )
                    .foregroundStyle(.blue)

                    BarMark(
                        x: .value("Score", stats.productivityScore.distractionScore),
                        y: .value("Component", isKorean ? "방해요소" : "Distraction")
                    )
                    .foregroundStyle(.red)

                    BarMark(
                        x: .value("Score", stats.productivityScore.consistencyScore),
                        y: .value("Component", isKorean ? "일관성" : "Consistency")
                    )
                    .foregroundStyle(.orange)
                }
                .chartXScale(domain: 0...100)
                .frame(height: 200)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            } else {
                emptyStateView
            }
        }
    }

    // MARK: - Top Apps Chart

    private var topAppsChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isKorean ? "주요 앱" : "Top Applications")
                .font(.headline)

            if let topApps = viewModel.stats?.topApps.prefix(10), !topApps.isEmpty {
                Chart(Array(topApps)) { app in
                    BarMark(
                        x: .value("Duration", app.duration / 3600),
                        y: .value("App", app.appName)
                    )
                    .foregroundStyle(by: .value("App", app.appName))
                }
                .chartXAxisLabel(isKorean ? "시간" : "Hours")
                .chartLegend(.hidden)
                .frame(height: 300)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            } else {
                emptyStateView
            }
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isKorean ? "활동 타임라인" : "Activity Timeline")
                .font(.headline)

            if let activities = viewModel.activities, !activities.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activities.prefix(20)) { activity in
                        HStack {
                            Text(activity.startAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)

                            Text(activity.appName)
                                .font(.body)

                            Spacer()

                            Text("\(Int(activity.duration / 60))m")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
            } else {
                emptyStateView
            }
        }
    }

    // MARK: - Helper Views

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(isKorean ? "사용 가능한 데이터 없음" : "No data available")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(isKorean ? "다른 날짜를 선택하거나 DayArc가 활동을 추적 중인지 확인하세요" : "Select a different date or ensure Dayflow is tracking activities")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 80...:
            return .green
        case 60..<80:
            return .blue
        case 40..<60:
            return .orange
        default:
            return .red
        }
    }
}

// MARK: - Stats Card Component

struct StatsCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }

            Text(value)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - ViewModel

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var stats: DailyStats?
    @Published var activities: [TimelineCard]?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadData(for date: Date) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                // Locate the DayArc recorder database
                guard let dbPath = DayflowDatabase.findDayflowDatabase() else {
                    errorMessage = "DayArc database not found"
                    isLoading = false
                    return
                }

                // Open database and fetch activities
                let db = DayflowDatabase(dbPath: dbPath)
                let fetchedActivities = try db.fetchActivities(for: date)

                // Calculate stats
                let calculatedStats = StatsCalculator.calculateDailyStats(
                    from: fetchedActivities,
                    date: date
                )

                // Update UI
                self.activities = fetchedActivities
                self.stats = calculatedStats
                self.isLoading = false

            } catch {
                errorMessage = "Failed to load data: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
}

// MARK: - Keyboard Modifier

struct DashboardKeyboardModifier: ViewModifier {
    @Binding var selectedDate: Date
    let isLoading: Bool
    let onDateChange: (Date) -> Void

    func body(content: Content) -> some View {
        content
            .background(KeyboardEventView(selectedDate: $selectedDate, isLoading: isLoading, onDateChange: onDateChange))
    }
}

struct KeyboardEventView: NSViewRepresentable {
    @Binding var selectedDate: Date
    let isLoading: Bool
    let onDateChange: (Date) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedDate: $selectedDate, isLoading: isLoading, onDateChange: onDateChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = KeyEventHandlingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyEventHandlingView {
            context.coordinator.isLoading = isLoading
            context.coordinator.selectedDate = selectedDate
        }
    }

    class Coordinator {
        @Binding var selectedDate: Date
        var isLoading: Bool
        let onDateChange: (Date) -> Void
        var monitor: Any?

        init(selectedDate: Binding<Date>, isLoading: Bool, onDateChange: @escaping (Date) -> Void) {
            _selectedDate = selectedDate
            self.isLoading = isLoading
            self.onDateChange = onDateChange

            // Setup local event monitor for arrow keys
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, !self.isLoading else { return event }

                switch Int(event.keyCode) {
                case 123: // Left arrow
                    if let newDate = Calendar.current.date(byAdding: .day, value: -1, to: self.selectedDate) {
                        DispatchQueue.main.async {
                            self.selectedDate = newDate
                            self.onDateChange(newDate)
                        }
                    }
                    return nil // Consume event
                case 124: // Right arrow
                    if let newDate = Calendar.current.date(byAdding: .day, value: 1, to: self.selectedDate) {
                        DispatchQueue.main.async {
                            self.selectedDate = newDate
                            self.onDateChange(newDate)
                        }
                    }
                    return nil // Consume event
                default:
                    return event // Pass through for up/down arrows and other keys
                }
            }
        }

        deinit {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    class KeyEventHandlingView: NSView {
        weak var coordinator: Coordinator?
    }
}

#if DEBUG
#Preview {
    DashboardView()
        .frame(width: 900, height: 700)
}
#endif
