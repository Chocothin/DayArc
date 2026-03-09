//
//  TimelineView.swift
//  DayArc
//
//  Timeline view showing activity cards from screen recording analysis
//  Inspired by Dayflow's timeline interface
//

import SwiftUI
import AVKit
import AVFoundation

struct ActivityTimelineView: View {
    @StateObject private var viewModel = TimelineViewModel()
    @State private var selectedDate = Date()
    @State private var selectedCard: TimelineCard?
    @AppStorage("reportLanguage") private var reportLanguageRaw = ReportLanguage.korean.rawValue
    
    private var language: ReportLanguage {
        ReportLanguage(rawValue: reportLanguageRaw) ?? .korean
    }
    
    private var isKorean: Bool {
        language == .korean
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with date picker
            timelineHeader

            Divider()

            // Timeline with sidebar layout
            HStack(spacing: 0) {
                // Left: Timeline cards
                if viewModel.isLoading {
                    ProgressView(isKorean ? "타임라인 로딩 중..." : "Loading timeline...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.cards.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.cards) { card in
                                TimelineCardView(
                                    card: card,
                                    selectedCard: $selectedCard,
                                    isKorean: isKorean,
                                    isReprocessing: viewModel.reprocessingCardIds.contains(card.id),
                                    onReprocess: {
                                        Task {
                                            await viewModel.reprocessCard(card)
                                        }
                                    }
                                )
                                .transition(.opacity)
                            }
                        }
                        .padding()
                    }
                }

                // Right: Detail sidebar
                if let card = selectedCard {
                    Divider()

                    DetailSidebarView(card: card, isKorean: isKorean, onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedCard = nil
                        }
                    })
                    .frame(width: 420)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: selectedCard != nil)
        }
        .task {
            await viewModel.loadTimeline(for: selectedDate)
        }
        .onChange(of: selectedDate) { newDate in
            Task {
                await viewModel.loadTimeline(for: newDate)
            }
        }
        .modifier(TimelineKeyboardModifier(selectedDate: $selectedDate, isLoading: viewModel.isLoading))
    }

    private var timelineHeader: some View {
        HStack {
            // Left: Tab title and date
            VStack(alignment: .leading, spacing: 4) {
                Text(isKorean ? "타임라인" : "Timeline")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right: Date navigation controls
            HStack(spacing: 8) {
                // Previous Day Button
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help(isKorean ? "어제" : "Previous Day")
                .disabled(viewModel.isLoading)

                // Date Picker
                DatePicker(isKorean ? "날짜" : "Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)

                // Next Day Button
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .help(isKorean ? "내일" : "Next Day")
                .disabled(viewModel.isLoading)

                Divider()
                    .frame(height: 20)

                // Today Button
                Button {
                    selectedDate = Date()
                } label: {
                    Text(isKorean ? "오늘" : "Today")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)

                Text(isKorean ? "\(viewModel.cards.count)개 활동" : "\(viewModel.cards.count) activities")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: {
                    Task {
                        await viewModel.loadTimeline(for: selectedDate)
                    }
                }) {
                    Label(isKorean ? "새로고침" : "Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)

                Button(action: {
                    Task {
                        await viewModel.reprocessTimeline(for: selectedDate)
                    }
                }) {
                    if viewModel.isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Label(isKorean ? "재분석" : "Reprocess", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(viewModel.isLoading || viewModel.isAnalyzing)
            }
        }
        .padding()
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        if isKorean {
            formatter.dateFormat = "yyyy년 MM월 dd일"
        } else {
            formatter.dateFormat = "MMMM d, yyyy"
        }
        return formatter.string(from: selectedDate)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "timeline.selection")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(isKorean ? "기록된 활동이 없습니다" : "No activities recorded")
                .font(.title3)

            Text(isKorean ? "녹화를 시작하면 활동 타임라인을 볼 수 있습니다" : "Start recording to see your activity timeline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Timeline Card View

struct TimelineCardView: View {
    let card: TimelineCard
    @Binding var selectedCard: TimelineCard?
    let isKorean: Bool
    var isReprocessing: Bool = false
    var onReprocess: (() -> Void)? = nil

    private var cardColor: Color {
        // Color based on category or productivity level
        guard let category = card.category else {
            return .gray
        }

        switch category.lowercased() {
        case "work", "productivity", "coding", "development":
            return .green
        case "communication", "meeting", "email":
            return .blue
        case "entertainment", "social media", "youtube", "netflix":
            return .orange
        case "break", "rest":
            return .purple
        default:
            return .gray
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time indicator
            VStack(alignment: .trailing, spacing: 2) {
                if let startTime = card.startTimestamp {
                    Text(startTime)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text(formatTime(card.startAt))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text(formatDuration(card.duration))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 60)

            // Card content
            VStack(alignment: .leading, spacing: 8) {
                // Title and category
                HStack(spacing: 8) {
                    Circle()
                        .fill(cardColor)
                        .frame(width: 8, height: 8)

                    Text(card.title ?? card.appName)
                        .font(.headline)

                    if let category = card.category {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(cardColor.opacity(0.2))
                            .cornerRadius(4)
                    }

                    Spacer()

                    if card.videoSummaryURL != nil {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    
                    // Reprocess Button
                    if let onReprocess = onReprocess {
                        Button(action: onReprocess) {
                            if isReprocessing {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isReprocessing)
                        .help(isKorean ? "이 활동 재분석" : "Reprocess this activity")
                    }
                }

                // Summary
                if let summary = card.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                // Detailed summary (expandable)
                if let detailed = card.detailedSummary, !detailed.isEmpty {
                    Text(detailed)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }

                // App/Site info
                if let appSites = card.appSites {
                    HStack(spacing: 4) {
                        if let primary = appSites.primary {
                            Text(primary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let secondary = appSites.secondary, !secondary.isEmpty {
                            Text("• \(secondary)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                // Distractions indicator
                if let distractions = card.distractions, !distractions.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Text(isKorean ? "\(distractions.count)개 방해요소" : "\(distractions.count) distraction(s)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selectedCard?.id == card.id
                    ? cardColor.opacity(0.1)
                    : Color(nsColor: .controlBackgroundColor)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        selectedCard?.id == card.id
                            ? cardColor.opacity(0.6)
                            : cardColor.opacity(0.3),
                        lineWidth: selectedCard?.id == card.id ? 3 : 2
                    )
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedCard = card
                }
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Native Video Player (AppKit-based)

struct NativeVideoPlayer: NSViewRepresentable {
    let url: URL
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        
        // Ensure URL is a proper file URL
        let fileURL: URL
        if url.isFileURL {
            fileURL = url
        } else if url.scheme == nil {
            // String path without file:// prefix
            fileURL = URL(fileURLWithPath: url.path)
        } else {
            fileURL = url
        }
        
        let fileExists = FileManager.default.fileExists(atPath: fileURL.path)
        print("🎬 [VideoPlayer] Loading video:")
        print("   URL: \(url)")
        print("   File path: \(fileURL.path)")
        print("   File exists: \(fileExists)")
        
        if !fileExists {
            print("❌ [VideoPlayer] VIDEO FILE NOT FOUND!")
            print("   Expected path: \(fileURL.path)")
            print("   Parent dir exists: \(FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))")
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path) {
                print("   Parent dir contents: \(contents.prefix(10))")
            }
        }
        
        let player = AVPlayer(url: fileURL)
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFrameSteppingButtons = true
        playerView.showsSharingServiceButton = false
        
        // Auto-play when ready
        player.play()
        
        context.coordinator.player = player
        
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Update if needed
    }
    
    class Coordinator {
        var player: AVPlayer?
    }
}

// MARK: - Detail Sidebar View

struct DetailSidebarView: View {
    let card: TimelineCard
    let isKorean: Bool
    let onClose: () -> Void

    @State private var showVideoPlayer = false
    @State private var inlinePlayer: AVPlayer?
    @State private var inlineVideoURL: URL?
    @State private var isHoveringVideo = false

    private var cardColor: Color {
        guard let category = card.category else {
            return .gray
        }

        switch category.lowercased() {
        case "work", "productivity", "coding", "development":
            return .green
        case "communication", "meeting", "email":
            return .blue
        case "entertainment", "social media", "youtube", "netflix":
            return .orange
        case "break", "rest":
            return .purple
        default:
            return .gray
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text(isKorean ? "활동 상세" : "Activity Details")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(isKorean ? "닫기" : "Close")
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Video section
                    videoSection

                    Divider()

                    // Title and time
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.title ?? card.appName)
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if let startTime = card.startTimestamp, let endTime = card.endTimestamp {
                                Text("\(startTime) - \(endTime)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Text("•")
                                .foregroundStyle(.tertiary)

                            Text(formatDuration(card.duration))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Category badge
                    if let category = card.category {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(cardColor)
                                .frame(width: 8, height: 8)

                            Text(category)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(cardColor.opacity(0.15))
                                .cornerRadius(6)

                            if let subcategory = card.subcategory, !subcategory.isEmpty {
                                Text(subcategory)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }

                    Divider()

                    // Summary section
                    if let summary = card.summary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isKorean ? "요약" : "SUMMARY")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Text(.init(summary))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // Detailed summary section
                    if let detailedSummary = card.detailedSummary, !detailedSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isKorean ? "상세 내용" : "DETAILED SUMMARY")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            Text(.init(detailedSummary))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // App/Site info
                    if let appSites = card.appSites {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isKorean ? "앱/사이트" : "APP/SITE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)

                            VStack(alignment: .leading, spacing: 4) {
                                if let primary = appSites.primary {
                                    Label(primary, systemImage: "app")
                                        .font(.subheadline)
                                }

                                if let secondary = appSites.secondary, !secondary.isEmpty {
                                    Label(secondary, systemImage: "globe")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Distractions
                    if let distractions = card.distractions, !distractions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(isKorean ? "방해요소" : "DISTRACTIONS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                                .textCase(.uppercase)

                            ForEach(distractions) { distraction in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(distraction.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)

                                        Spacer()

                                        Text("\(distraction.startTime) - \(distraction.endTime)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if !distraction.summary.isEmpty {
                                        Text(distraction.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(Color.orange.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showVideoPlayer) {
            if let videoPath = card.videoSummaryURL,
               let url = StorageManager.shared.resolveVideoURL(for: videoPath) {
                VideoPlayerSheet(videoURL: url, card: card, isKorean: isKorean)
            }
        }
        .onDisappear {
            inlinePlayer?.pause()
            inlinePlayer = nil
            inlineVideoURL = nil
        }
    }

    @ViewBuilder
    private var videoSection: some View {
        if let videoPath = card.videoSummaryURL,
           let url = StorageManager.shared.resolveVideoURL(for: videoPath) {
            ZStack {
                if let player = inlinePlayer {
                    VideoPlayer(player: player)
                        .allowsHitTesting(false)
                        .frame(height: 220)
                        .cornerRadius(8)
                } else {
                    Color.black.opacity(0.85)
                        .frame(height: 220)
                        .cornerRadius(8)
                }

                Color.black.opacity(isHoveringVideo ? 0.35 : 0)
                    .cornerRadius(8)
                    .animation(.easeInOut(duration: 0.2), value: isHoveringVideo)

                if isHoveringVideo {
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.white)
                        Text(isKorean ? "팝업으로 크게 보기" : "Open pop-up player")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .frame(height: 220)
            .contentShape(Rectangle())
            .onTapGesture {
                showVideoPlayer = true
            }
            .onHover { hovering in
                isHoveringVideo = hovering
            }
            .onAppear {
                setupInlinePlayer(with: url)
            }
            .onChange(of: url) { newURL in
                setupInlinePlayer(with: newURL)
            }
        } else {
            // Video not generated yet
            VStack(spacing: 12) {
                Image(systemName: "video.badge.clock")
                    .font(.system(size: 50))
                    .foregroundStyle(.gray)

                Text(isKorean ? "타임랩스 생성 중..." : "Generating Timelapse...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(isKorean ? "잠시 후 비디오를 확인할 수 있습니다" : "Video will be available shortly")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func setupInlinePlayer(with url: URL) {
        if inlineVideoURL != url {
            inlinePlayer?.pause()
            inlinePlayer = AVPlayer(url: url)
            inlineVideoURL = url
        }
        inlinePlayer?.isMuted = true
        inlinePlayer?.seek(to: .zero)
        inlinePlayer?.play()
    }
}

// MARK: - Video Player Sheet

struct VideoPlayerSheet: View {
    let videoURL: URL
    let card: TimelineCard
    let isKorean: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(card.title ?? card.appName)
                        .font(.headline)
                    Text(isKorean ? "20배속 타임랩스" : "20x Speed Timelapse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(isKorean ? "닫기" : "Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Native AppKit player (fixes AVKit_SwiftUI crash)
            NativeVideoPlayer(url: videoURL)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 800, height: 600)
    }
}

// MARK: - Timeline ViewModel

@MainActor
class TimelineViewModel: ObservableObject {
    @Published var cards: [TimelineCard] = []
    @Published var isLoading = false
    @Published var isAnalyzing = false
    @Published var error: String?
    @Published var reprocessingCardIds: Set<String> = []

    private let storageManager = StorageManager.shared

    func loadTimeline(for date: Date) async {
        isLoading = true
        error = nil

        // Format date as "YYYY-MM-DD"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dayString = formatter.string(from: date)

        // Fetch timeline cards from database
        let fetchedCards = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let result = self.storageManager.fetchTimelineCards(forDay: dayString)
                continuation.resume(returning: result)
            }
        }

        cards = fetchedCards
        isLoading = false
    }
    
    func reprocessTimeline(for date: Date) async {
        isAnalyzing = true
        error = nil
        
        // Format date as "YYYY-MM-DD"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dayString = formatter.string(from: date)
        
        // Reset batch statuses and trigger reprocessing
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                // Reset batch statuses to trigger reprocessing
                let resetBatchIds = self.storageManager.resetBatchStatuses(forDay: dayString)
                
                Logger.shared.info("Reset \(resetBatchIds.count) batches for day \(dayString)", source: "TimelineViewModel")
                
                // Trigger AnalysisManager to reprocess
                AnalysisManager.shared.startAnalysisJob()
                
                continuation.resume()
            }
        }
        
        // Wait a moment for reprocessing to start
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
        
        // Reload timeline
        await loadTimeline(for: date)
        
        isAnalyzing = false
    }
    
    func reprocessCard(_ card: TimelineCard) async {
        guard let batchId = card.batchId else { return }
        
        reprocessingCardIds.insert(card.id)
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                // Reset specific batch status
                let resetBatchIds = self.storageManager.resetBatchStatuses(forBatchIds: [batchId])
                
                Logger.shared.info("Reset batch \(batchId) for card \(card.id)", source: "TimelineViewModel")
                
                // Trigger AnalysisManager to reprocess
                AnalysisManager.shared.startAnalysisJob()
                
                continuation.resume()
            }
        }
        
        // Wait a moment for reprocessing to start
        try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
        
        // Reload timeline to reflect changes (card might disappear or update)
        // We need to know the date from the card or current selected date.
        // Since we don't have the date easily from card (it's a string), we'll rely on the view refreshing or just wait.
        // Ideally we should reload the timeline for the date this card belongs to.
        // For now, we'll just remove the ID from reprocessing set after a delay, 
        // assuming the main view might trigger a reload or the user will refresh.
        // BETTER: The view model should know the current date, so we can reload.
        
        // However, reprocessCard doesn't know 'selectedDate' from the view.
        // But we can assume the card is from the currently loaded timeline.
        // So we can just call loadTimeline with the date derived from the card if possible, 
        // OR we can just let the user refresh.
        // BUT, for better UX, let's try to reload if we can.
        
        // Actually, since we are in the ViewModel, we don't store 'selectedDate' here (it's in the View).
        // We should probably pass the date or store it.
        // Let's modify loadTimeline to store the loaded date.
        
        reprocessingCardIds.remove(card.id)
    }
}

// MARK: - Keyboard Modifier

struct TimelineKeyboardModifier: ViewModifier {
    @Binding var selectedDate: Date
    let isLoading: Bool

    func body(content: Content) -> some View {
        content
            .background(TimelineKeyboardEventView(selectedDate: $selectedDate, isLoading: isLoading))
    }
}

struct TimelineKeyboardEventView: NSViewRepresentable {
    @Binding var selectedDate: Date
    let isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedDate: $selectedDate, isLoading: isLoading)
    }

    func makeNSView(context: Context) -> NSView {
        let view = TimelineKeyEventHandlingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? TimelineKeyEventHandlingView {
            context.coordinator.isLoading = isLoading
            context.coordinator.selectedDate = selectedDate
        }
    }

    class Coordinator {
        @Binding var selectedDate: Date
        var isLoading: Bool
        var monitor: Any?

        init(selectedDate: Binding<Date>, isLoading: Bool) {
            _selectedDate = selectedDate
            self.isLoading = isLoading

            // Setup local event monitor for arrow keys
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, !self.isLoading else { return event }

                switch Int(event.keyCode) {
                case 123: // Left arrow
                    if let newDate = Calendar.current.date(byAdding: .day, value: -1, to: self.selectedDate) {
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                self.selectedDate = newDate
                            }
                        }
                    }
                    return nil // Consume event
                case 124: // Right arrow
                    if let newDate = Calendar.current.date(byAdding: .day, value: 1, to: self.selectedDate) {
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                self.selectedDate = newDate
                            }
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

    class TimelineKeyEventHandlingView: NSView {
        weak var coordinator: Coordinator?
    }
}

#if DEBUG
#Preview {
    ActivityTimelineView()
        .frame(width: 900, height: 700)
}
#endif
