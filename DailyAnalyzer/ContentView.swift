//
//  ContentView.swift
//  DayArc
//
//  Created on 2025-11-17.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: SidebarItem? = .dashboard
    @AppStorage("reportLanguage") private var reportLanguageRaw = ReportLanguage.korean.rawValue
    
    private var language: ReportLanguage {
        ReportLanguage(rawValue: reportLanguageRaw) ?? .korean
    }
    
    private var isKorean: Bool {
        language == .korean
    }

    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SidebarItem.allCases, selection: $selectedTab) { item in
                NavigationLink(value: item) {
                    Label(item.localizedTitle(isKorean: isKorean), systemImage: item.icon)
                }
            }
            .navigationTitle("DayArc")
            .frame(minWidth: 200)
        } detail: {
            // Detail view based on selection
            Group {
                if let selectedTab = selectedTab {
                    switch selectedTab {
                    case .dashboard:
                        DashboardView()
                    case .timeline:
                        ActivityTimelineView()
                    case .analysis:
                        AnalysisView()
                    case .settings:
                        SettingsView()
                    case .logs:
                        LogsView()
                    }
                } else {
                    Text(isKorean ? "사이드바에서 항목을 선택하세요" : "Select an item from the sidebar")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $appState.isRecordingEnabled) {
                    Text(isKorean ? "화면 녹화 활성화" : "Screen Recording")
                        .font(.system(size: 13))
                }
                .toggleStyle(.switch)
                .help(isKorean ? "화면 녹화를 시작하거나 중지합니다" : "Start or stop screen recording")
            }
        }
    }
}

// Sidebar navigation items
enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case timeline = "Timeline"
    case analysis = "Analysis"
    case settings = "Settings"
    case logs = "Logs"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .timeline: return "Timeline"
        case .analysis: return "Analysis"
        case .settings: return "Settings"
        case .logs: return "Logs"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "chart.bar.fill"
        case .timeline: return "timeline.selection"
        case .analysis: return "doc.text.magnifyingglass"
        case .settings: return "gear"
        case .logs: return "list.bullet.rectangle"
        }
    }
    
    func localizedTitle(isKorean: Bool) -> String {
        guard isKorean else { return title }
        
        switch self {
        case .dashboard: return "대시보드"
        case .timeline: return "타임라인"
        case .analysis: return "분석"
        case .settings: return "설정"
        case .logs: return "로그"
        }
    }
}


// Placeholder managers (to be implemented)


#if DEBUG
#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
#endif
