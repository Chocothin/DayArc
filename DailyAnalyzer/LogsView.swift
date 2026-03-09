//
//  LogsView.swift
//  DayArc
//
//  Logs viewer with filtering
//

import SwiftUI

struct LogsView: View {
    @ObservedObject private var viewModel = LogsViewModel.shared
    @State private var filterText = ""
    @State private var selectedLevel: LogLevel? = nil
    @AppStorage("reportLanguage") private var reportLanguageRaw = ReportLanguage.korean.rawValue
    
    private var isKorean: Bool {
        (ReportLanguage(rawValue: reportLanguageRaw) ?? .korean) == .korean
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(isKorean ? "애플리케이션 로그" : "Application Logs")
                    .font(.title)
                    .bold()

                Spacer()

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Button {
                    viewModel.clearLogs()
                } label: {
                    Text(isKorean ? "지우기" : "Clear")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            // Filters
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(isKorean ? "로그 필터링..." : "Filter logs...", text: $filterText)
                    .textFieldStyle(.roundedBorder)

                Picker(isKorean ? "레벨" : "Level", selection: $selectedLevel) {
                    Text(isKorean ? "전체" : "All").tag(nil as LogLevel?)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level as LogLevel?)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding(.horizontal)

            // Logs list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLogs) { log in
                            LogRow(log: log)
                                .id(log.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: viewModel.logs.count) { _ in
                    if let lastLog = viewModel.logs.last {
                        withAnimation {
                            proxy.scrollTo(lastLog.id, anchor: .bottom)
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)

            // Stats
            HStack {
                Text(isKorean ? "\(viewModel.logs.count)개 중 \(filteredLogs.count)개 항목" : "\(filteredLogs.count) of \(viewModel.logs.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let lastUpdate = viewModel.lastUpdate {
                    Text(isKorean ? "마지막 업데이트: \(lastUpdate.formatted(date: .omitted, time: .standard))" : "Last update: \(lastUpdate.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }

    private var filteredLogs: [LogEntry] {
        viewModel.logs.filter { log in
            // Level filter
            if let level = selectedLevel, log.level != level {
                return false
            }

            // Text filter
            if !filterText.isEmpty {
                let searchText = filterText.lowercased()
                return log.message.lowercased().contains(searchText) ||
                       log.source.lowercased().contains(searchText)
            }

            return true
        }
    }
}

// MARK: - Log Row

struct LogRow: View {
    let log: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(log.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            // Level badge
            Text(log.level.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(log.level.color.opacity(0.2))
                .foregroundStyle(log.level.color)
                .cornerRadius(4)
                .frame(width: 60)

            // Source
            Text(log.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            // Message
            Text(log.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Log Entry

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let source: String
    let message: String
}

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"

    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - ViewModel

@MainActor
class LogsViewModel: ObservableObject {
    static let shared = LogsViewModel()

    @Published var logs: [LogEntry] = []
    @Published var lastUpdate: Date?

    private var timer: Timer?

    private init() {
        // Start monitoring immediately
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLogNotification(_:)),
            name: NSNotification.Name("AppLogAdded"),
            object: nil
        )

        Logger.shared.info("LogsViewModel initialized and monitoring started", source: "LogsView")
        lastUpdate = Date()
    }

    func startMonitoring() {
        // Already monitoring from init
        lastUpdate = Date()
    }

    func stopMonitoring() {
        // Don't remove observer since we're a singleton
        timer?.invalidate()
        timer = nil
    }

    @objc private func handleLogNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let level = userInfo["level"] as? String,
              let source = userInfo["source"] as? String,
              let message = userInfo["message"] as? String else {
            return
        }

        let logLevel = LogLevel(rawValue: level) ?? .info
        let entry = LogEntry(
            timestamp: Date(),
            level: logLevel,
            source: source,
            message: message
        )

        // Ensure UI updates happen on main thread
        Task { @MainActor in
            logs.append(entry)
            lastUpdate = Date()

            // Limit to last 1000 entries
            if logs.count > 1000 {
                logs.removeFirst(logs.count - 1000)
            }
        }
    }

    func refresh() {
        lastUpdate = Date()
    }

    func clearLogs() {
        logs.removeAll()
        logs.append(LogEntry(timestamp: Date(), level: .info, source: "LogsView", message: "Logs cleared"))
        lastUpdate = Date()
    }
}

// MARK: - Logger

class Logger {
    static let shared = Logger()

    private init() {}

    func log(_ message: String, level: LogLevel = .info, source: String = "App") {
        print("[\(level.rawValue)] [\(source)] \(message)")

        // Post notification for LogsView on main thread
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name("AppLogAdded"),
                object: nil,
                userInfo: [
                    "level": level.rawValue,
                    "source": source,
                    "message": message
                ]
            )
        }
    }

    func debug(_ message: String, source: String = "App") {
        log(message, level: .debug, source: source)
    }

    func info(_ message: String, source: String = "App") {
        log(message, level: .info, source: source)
    }

    func warning(_ message: String, source: String = "App") {
        log(message, level: .warning, source: source)
    }

    func error(_ message: String, source: String = "App") {
        log(message, level: .error, source: source)
    }
}

#if DEBUG
#Preview {
    LogsView()
        .frame(width: 1000, height: 600)
}
#endif
