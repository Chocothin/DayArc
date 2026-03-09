//
//  SettingsView.swift
//  DayArc
//
//  Settings UI with provider selection and configuration
//

import SwiftUI
import UserNotifications

struct SettingsView: View {
    @StateObject private var aiConfig = AIProviderConfig.load()
    @StateObject private var vaultConfig = VaultConfiguration.load()
    @State private var selectedTab: SettingsTab = .aiProvider
    @AppStorage("reportLanguage") private var reportLanguageRaw = ReportLanguage.korean.rawValue
    
    private var isKorean: Bool {
        (ReportLanguage(rawValue: reportLanguageRaw) ?? .korean) == .korean
    }

    var body: some View {
        HSplitView {
            // Sidebar
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.localizedTitle(isKorean: isKorean), systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180, maxWidth: 200)

            // Content with ScrollView
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .aiProvider:
                        AIProviderSettings(config: aiConfig, isKorean: isKorean)
                    case .recording:
                        RecordingSettings(isKorean: isKorean)
                    case .obsidianVault:
                        ObsidianVaultSettings(config: vaultConfig, isKorean: isKorean)
                    case .scheduler:
                        SchedulerSettings(isKorean: isKorean)
                    case .general:
                        GeneralSettings(isKorean: isKorean)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Settings Tabs

enum SettingsTab: String, CaseIterable, Identifiable {
    case aiProvider = "AI Provider"
    case recording = "Recording"
    case obsidianVault = "Obsidian Vault"
    case scheduler = "Scheduler"
    case general = "General"

    var id: String { rawValue }

    var title: String { rawValue }
    
    func localizedTitle(isKorean: Bool) -> String {
        guard isKorean else { return title }
        switch self {
        case .aiProvider: return "AI 공급자"
        case .recording: return "녹화 설정"
        case .obsidianVault: return "Obsidian 볼트"
        case .scheduler: return "스케줄러"
        case .general: return "일반"
        }
    }

    var icon: String {
        switch self {
        case .aiProvider: return "brain"
        case .recording: return "record.circle"
        case .obsidianVault: return "doc.text"
        case .scheduler: return "calendar"
        case .general: return "gearshape"
        }
    }
}

// MARK: - AI Provider Settings

struct AIProviderSettings: View {
    @ObservedObject var config: AIProviderConfig
    let isKorean: Bool
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var diagnostics: [ProviderDiagnosticsResult] = []
    @State private var isRunningDiagnostics = false
    
    // Validation
    @State private var showValidationError = false
    @State private var validationMessage = ""
    @State private var showSuccessAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isKorean ? "AI 공급자 설정" : "AI Provider Configuration")
                .font(.title)
                .bold()

            // Provider Selection
            GroupBox(isKorean ? "공급자" : "Provider") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(isKorean ? "AI 공급자" : "AI Provider", selection: $config.selectedProviderType) {
                        ForEach(AIProviderType.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.menu) // Changed to .menu to show all providers
                    .onChange(of: config.selectedProviderType) { newProvider in
                        // Auto-update model when provider changes
                        if let firstModel = newProvider.availableModels.first {
                            config.selectedModel = firstModel
                        }
                        // Auto-save when provider changes
                        config.save()
                    }

                    // Model Selection
                    if !config.selectedProviderType.availableModels.isEmpty {
                        Picker(isKorean ? "모델" : "Model", selection: $config.selectedModel) {
                            ForEach(config.selectedProviderType.availableModels, id: \.id) { model in
                                Text(model.name).tag(model)
                            }
                        }
                        .onChange(of: config.selectedModel) { _ in
                            // Auto-save when model changes
                            config.save()
                        }
                    }
                }
                .padding()
            }

            // API Key Configuration
            if config.selectedProviderType != .ollama && config.selectedProviderType != .lmstudio {
                GroupBox("API Key") {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("API Key", text: Binding(
                            get: { config.apiKeys[config.selectedProviderType] ?? "" },
                            set: { config.apiKeys[config.selectedProviderType] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            // Save when user presses Enter
                            config.save()
                        }

                        Text(isKorean ? "API 키는 안전하게 저장됩니다 (저장하려면 Enter 또는 저장 버튼을 누르세요)" : "Your API key is stored securely (press Enter or click Save to save)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }

            // Local LLM Endpoint
            if config.selectedProviderType == .ollama || config.selectedProviderType == .lmstudio {
                GroupBox(isKorean ? "엔드포인트" : "Endpoint") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(isKorean ? "엔드포인트 URL" : "Endpoint URL", text: Binding(
                            get: { config.localEndpoints[config.selectedProviderType] ?? "" },
                            set: { config.localEndpoints[config.selectedProviderType] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            // Save when user presses Enter
                            config.save()
                        }

                        Text("Default: \(config.selectedProviderType == .ollama ? "http://localhost:11434" : "http://localhost:1234")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }

            // Test Connection
            HStack {
                Button(isKorean ? "연결 테스트" : "Test Connection") {
                    testConnection()
                }
                .disabled(isTesting)

                if isTesting {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("✅") ? .green : .red)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button(isKorean ? "모든 공급자 진단 실행" : "Run All Provider Diagnostics") {
                        runDiagnostics()
                    }
                    .disabled(isRunningDiagnostics)

                    if isRunningDiagnostics {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }

                ForEach(diagnostics) { result in
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(result.success ? .green : .red)
                }
            }

            Divider()

            // Prompt Customization Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(isKorean ? "프롬프트 커스터마이징" : "Prompt Customization")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(isKorean ? "모두 초기화" : "Reset All") {
                        PromptManager.shared.resetAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                
                Text(isKorean ? "AI 분석에 사용되는 프롬프트를 커스터마이징할 수 있습니다. 기본 프롬프트 위에 사용자 지정 내용이 추가됩니다." : "Customize the prompts used for AI analysis. Your custom additions will be appended to the default prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                // Activity Cards
                DisclosureGroup(isKorean ? "활동 카드" : "Activity Cards") {
                    VStack(spacing: 8) {
                        PromptEditor(context: .activityCardTitle)
                        Divider()
                        PromptEditor(context: .activityCardSummary)
                        Divider()
                        PromptEditor(context: .activityCardDetailed)
                    }
                    .padding(.vertical, 8)
                }
                
                // Video Analysis
                DisclosureGroup(isKorean ? "비디오 분석" : "Video Analysis") {
                    VStack(spacing: 8) {
                        PromptEditor(context: .videoTranscription)
                    }
                    .padding(.vertical, 8)
                }
                
                // Report Generation
                DisclosureGroup(isKorean ? "리포트 생성" : "Report Generation") {
                    VStack(spacing: 8) {
                        PromptEditor(context: .dailyReportAnalysis)
                        Divider()
                        PromptEditor(context: .weeklyReportAnalysis)
                        Divider()
                        PromptEditor(context: .monthlyReportAnalysis)
                        Divider()
                        PromptEditor(context: .timelineSummary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .padding(.vertical, 8)

            Spacer()

            // Save Button
            // Save Button
            Button(isKorean ? "설정 저장" : "Save Settings") {
                validateAndSave()
            }
            .buttonStyle(.borderedProminent)
            .alert(isKorean ? "설정 오류" : "Configuration Error", isPresented: $showValidationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
            .alert(isKorean ? "설정 저장됨" : "Settings Saved", isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(isKorean ? "AI 공급자 설정이 저장되었습니다." : "AI provider settings have been saved.")
            }
        }
    }
    
    private func validateAndSave() {
        // 1. Validate API Key for cloud providers
        if config.selectedProviderType != .ollama && config.selectedProviderType != .lmstudio {
            let key = config.apiKeys[config.selectedProviderType] ?? ""
            if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationMessage = isKorean ? "API 키를 입력해주세요." : "Please enter an API key."
                showValidationError = true
                return
            }
        }
        
        // 2. Validate Endpoint for local providers
        if config.selectedProviderType == .ollama || config.selectedProviderType == .lmstudio {
            let endpoint = config.localEndpoints[config.selectedProviderType] ?? ""
            if URL(string: endpoint) == nil {
                validationMessage = isKorean ? "유효한 엔드포인트 URL을 입력해주세요." : "Please enter a valid endpoint URL."
                showValidationError = true
                return
            }
        }
        
        // Save if valid
        config.save()
        showSuccessAlert = true
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            do {
                let provider = config.getCurrentProvider()
                let success = try await provider.testConnection()

                await MainActor.run {
                    testResult = success ? (isKorean ? "✅ 연결 성공" : "✅ Connection successful") : (isKorean ? "❌ 연결 실패" : "❌ Connection failed")
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ Error: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }

    private func runDiagnostics() {
        isRunningDiagnostics = true
        diagnostics = []

        Task {
            let results = await ProviderDiagnostics.runAll(config: config)
            await MainActor.run {
                self.diagnostics = results
                self.isRunningDiagnostics = false
            }
        }
    }
}

// MARK: - Obsidian Vault Settings

struct ObsidianVaultSettings: View {
    @ObservedObject var config: VaultConfiguration
    let isKorean: Bool
    @State private var showingFilePicker = false
    @State private var showSaveAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isKorean ? "Obsidian 볼트 설정" : "Obsidian Vault Configuration")
                .font(.title)
                .bold()

            GroupBox(isKorean ? "볼트 경로" : "Vault Path") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        TextField(isKorean ? "볼트 경로" : "Vault Path", text: $config.vaultPath)
                            .textFieldStyle(.roundedBorder)
                            .disabled(true)

                        Button(isKorean ? "찾아보기..." : "Browse...") {
                            selectVaultPath()
                        }
                    }

                    if !config.vaultPath.isEmpty {
                        if ObsidianVault.isValidVaultPath(config.vaultPath) {
                            Label(isKorean ? "유효한 볼트 경로" : "Valid vault path", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label(isKorean ? "유효하지 않은 볼트 경로" : "Invalid vault path", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }

                    Text(isKorean ? "Obsidian 볼트 디렉토리를 선택하세요" : "Select your Obsidian vault directory")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            GroupBox(isKorean ? "옵션" : "Options") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isKorean ? "노트 자동 저장" : "Auto-save notes", isOn: $config.autoSave)
                    Toggle(isKorean ? "백업 생성" : "Create backups", isOn: $config.createBackups)
                }
                .padding()
            }

            Spacer()

            Button(isKorean ? "설정 저장" : "Save Settings") {
                config.save()
                showSaveAlert = true
            }
            .buttonStyle(.borderedProminent)
            .alert(isKorean ? "설정 저장됨" : "Settings Saved", isPresented: $showSaveAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(isKorean ? "Obsidian 볼트 설정이 저장되었습니다." : "Obsidian vault settings have been saved.")
            }
        }
    }

    private func selectVaultPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = isKorean ? "Obsidian 볼트 디렉토리를 선택하세요" : "Select your Obsidian vault directory"

        // Try to start at common Obsidian location
        if let iCloudPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/iCloud~md~obsidian/Documents").path as String? {
            panel.directoryURL = URL(fileURLWithPath: iCloudPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            config.vaultPath = url.path
        }
    }
}

// MARK: - Scheduler Settings

struct SchedulerSettings: View {
    @State private var scheduleConfig = ScheduleConfig.load()
    let isKorean: Bool
    @State private var showSaveAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isKorean ? "스케줄러 설정" : "Scheduler Configuration")
                .font(.title)
                .bold()

            GroupBox(isKorean ? "스케줄" : "Schedule") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isKorean ? "자동 스케줄링 활성화" : "Enable automatic scheduling", isOn: $scheduleConfig.isEnabled)

                    DatePicker(isKorean ? "일간 리포트 시간" : "Daily report time", selection: $scheduleConfig.dailyTime, displayedComponents: .hourAndMinute)

                    Toggle(isKorean ? "주간 리포트 생성" : "Generate weekly reports", isOn: $scheduleConfig.generateWeekly)
                    Toggle(isKorean ? "월간 리포트 생성" : "Generate monthly reports", isOn: $scheduleConfig.generateMonthly)
                }
                .padding()
            }

            GroupBox(isKorean ? "안정성" : "Reliability") {
                VStack(alignment: .leading, spacing: 8) {
                    Label(isKorean ? "10분 간격 폴링 활성화됨" : "10-minute polling enabled", systemImage: "clock.arrow.circlepath")
                        .font(.caption)

                    Text(isKorean ? "컴퓨터가 꺼져 있어 스케줄 시간을 놓치더라도 리포트가 생성됩니다" : "Reports will be generated even if the computer was off during the scheduled time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            Spacer()

            Button(isKorean ? "설정 저장" : "Save Settings") {
                scheduleConfig.save()
                showSaveAlert = true
            }
            .buttonStyle(.borderedProminent)
            .alert(isKorean ? "설정 저장됨" : "Settings Saved", isPresented: $showSaveAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(isKorean ? "스케줄러 설정이 저장되었습니다." : "Scheduler settings have been saved.")
            }
        }
    }
}

// MARK: - General Settings

struct GeneralSettings: View {
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("startAtLogin") private var startAtLogin = false
    @AppStorage("logLevel") private var logLevel = "info"
    @AppStorage("reportLanguage") private var reportLanguageRaw = ReportLanguage.korean.rawValue
    let isKorean: Bool

    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isKorean ? "일반 설정" : "General Settings")
                .font(.title)
                .bold()

            GroupBox(isKorean ? "알림" : "Notifications") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle(isKorean ? "알림 활성화" : "Enable notifications", isOn: $enableNotifications)

                        Spacer()

                        // Status indicator
                        if notificationAuthStatus == .authorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else if notificationAuthStatus == .denied {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }

                    Text(isKorean ? "리포트가 생성되면 알림을 표시합니다" : "Show notifications when reports are generated")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Show warning if permission denied
                    if notificationAuthStatus == .denied {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(isKorean ? "알림 권한이 거부되었습니다" : "Notification permission denied")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .bold()

                                Text(isKorean ? "시스템 설정에서 DayArc의 알림을 허용해 주세요" : "Please allow notifications for DayArc in System Settings")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)

                        Button(isKorean ? "시스템 설정 열기" : "Open System Settings") {
                            openSystemNotificationSettings()
                        }
                        .buttonStyle(.borderedProminent)
                    } else if notificationAuthStatus == .notDetermined {
                        Button(isKorean ? "알림 권한 요청" : "Request Permission") {
                            NotificationManager.shared.requestPermission()
                            checkNotificationStatus()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .onAppear {
                    checkNotificationStatus()
                }
            }

            GroupBox(isKorean ? "시작" : "Startup") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isKorean ? "로그인 시 시작" : "Start at login", isOn: $startAtLogin)

                    Text(isKorean ? "로그인할 때 자동으로 DayArc를 시작합니다" : "Automatically start DayArc when you log in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }

            GroupBox(isKorean ? "로깅" : "Logging") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(isKorean ? "로그 레벨" : "Log Level", selection: $logLevel) {
                        Text(isKorean ? "오류" : "Error").tag("error")
                        Text(isKorean ? "경고" : "Warning").tag("warning")
                        Text(isKorean ? "정보" : "Info").tag("info")
                        Text(isKorean ? "디버그" : "Debug").tag("debug")
                    }
                    .pickerStyle(.segmented)
                }
                .padding()
            }

            GroupBox(isKorean ? "리포트 언어" : "Report Language") {
                Picker(isKorean ? "언어" : "Language", selection: $reportLanguageRaw) {
                    ForEach(ReportLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                Text(isKorean ? "생성되는 모든 노트(템플릿 및 시스템 라벨)에 적용됩니다." : "Applied to all generated notes (templates and system labels).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationAuthStatus = settings.authorizationStatus
            }
        }
    }

    private func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Recording Settings

struct RecordingSettings: View {
    @StateObject private var appState = AppState.shared
    @AppStorage("recordingQuality") private var recordingQuality = 1080
    let isKorean: Bool
    
    @State private var recordingUsage: Int64 = 0
    @State private var timelapseUsage: Int64 = 0
    
    // Timer for periodic updates
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(isKorean ? "화면 녹화" : "Screen Recording")
                .font(.title)
                .bold()
            
            GroupBox(isKorean ? "녹화 제어" : "Recording Control") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isKorean ? "화면 녹화 활성화" : "Enable Screen Recording", isOn: $appState.isRecordingEnabled)
                        .toggleStyle(.switch)
                    
                    HStack(spacing: 8) {
                        Image(systemName: appState.recordingStatus.icon)
                            .foregroundStyle(appState.isRecordingEnabled ? .green : .secondary)
                        Text(appState.recordingStatus.displayString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !appState.hasScreenRecordingPermission {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(isKorean ? "화면 녹화 권한이 없습니다" : "Screen recording permission not granted")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            
                            Button(isKorean ? "시스템 설정 열기" : "Open System Preferences") {
                                PermissionsManager.shared.openSystemPreferences()
                            }
                            .font(.caption)
                        }
                    }
                    
                    Text(isKorean ? "활동 추적을 위한 1fps 화면 녹화" : "1fps screen recording for activity tracking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            
            GroupBox(isKorean ? "품질 설정" : "Quality Settings") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(isKorean ? "해상도" : "Resolution", selection: $recordingQuality) {
                        Text("720p").tag(720)
                        Text(isKorean ? "1080p (권장)" : "1080p (Recommended)").tag(1080)
                        Text(isKorean ? "네이티브" : "Native").tag(0)
                    }
                    .pickerStyle(.segmented)

                    Text(isKorean ? "높은 해상도는 AI 분석에 더 좋은 디테일을 제공합니다" : "Higher resolution provides better detail for AI analysis")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            
            GroupBox(isKorean ? "저장소" : "Storage") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isKorean ? "디스크 사용량" : "Disk Usage")
                                .font(.headline)
                            
                            // Recordings Usage
                            HStack {
                                Text(isKorean ? "녹화:" : "Recordings:")
                                    .frame(width: 80, alignment: .leading)
                                Text(formatBytes(recordingUsage))
                                    .bold()
                                Text("/")
                                    .foregroundStyle(.secondary)
                                Text(formatBytes(StoragePreferences.recordingsLimitBytes))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            
                            // Timelapses Usage
                            HStack {
                                Text(isKorean ? "타임랩스:" : "Timelapses:")
                                    .frame(width: 80, alignment: .leading)
                                Text(formatBytes(timelapseUsage))
                                    .bold()
                                Text("/")
                                    .foregroundStyle(.secondary)
                                Text(formatBytes(StoragePreferences.timelapsesLimitBytes))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(isKorean ? "자동 정리 활성화됨" : "Auto-cleanup enabled")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text(isKorean ? "오래된 파일부터 삭제됩니다" : "Oldest files deleted first")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    Text(isKorean ? "저장 위치:" : "Storage Location:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(StorageManager.shared.dbURL.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            
            Spacer()
        }
        .onAppear {
            updateUsage()
        }
        .onReceive(timer) { _ in
            updateUsage()
        }
    }
    
    private func updateUsage() {
        Task {
            let recUsage = StorageManager.shared.currentRecordingUsageBytes()
            let tlUsage = TimelapseStorageManager.shared.currentUsageBytes()
            
            await MainActor.run {
                self.recordingUsage = recUsage
                self.timelapseUsage = tlUsage
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .frame(width: 800, height: 600)
}
#endif
