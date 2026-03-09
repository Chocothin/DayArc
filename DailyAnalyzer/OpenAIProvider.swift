//
//  OpenAIProvider.swift
//  DayArc
//
//  OpenAI API implementation (GPT-4, GPT-3.5)
//

import Foundation

class OpenAIProvider: AIProvider {
    let providerType: AIProviderType = .openai
    private let model: AIModel
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"

    init(model: AIModel, apiKey: String) {
        self.model = model
        self.apiKey = apiKey
    }

    func analyze(activities: [TimelineCard], date: Date) async throws -> AnalysisResult {
        let prompt = buildPrompt(from: activities, date: date)

        Logger.shared.info("Starting OpenAI API call - Model: \(model.id), Prompt length: \(prompt.count) chars", source: "OpenAI")

        let requestBody: [String: Any] = [
            "model": model.id,
            "messages": [
                ["role": "system", "content": "You are a productivity analyst. Analyze the user's daily activities and provide insights."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2000
        ]

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            Logger.shared.error("Invalid OpenAI API URL", source: "OpenAI")
            throw AIProviderError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let responseTime = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.shared.error("Invalid HTTP response from OpenAI", source: "OpenAI")
            throw AIProviderError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            Logger.shared.error("OpenAI API key invalid (401)", source: "OpenAI")
            throw AIProviderError.invalidAPIKey
        }

        if httpResponse.statusCode == 429 {
            Logger.shared.warning("OpenAI rate limit exceeded (429)", source: "OpenAI")
            throw AIProviderError.rateLimitExceeded
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.shared.error("OpenAI API error (\(httpResponse.statusCode)): \(errorMessage)", source: "OpenAI")
            throw AIProviderError.serverError(httpResponse.statusCode, errorMessage)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            Logger.shared.error("Failed to parse OpenAI response", source: "OpenAI")
            throw AIProviderError.invalidResponse
        }

        // Extract token usage if available
        if let usage = json?["usage"] as? [String: Any],
           let totalTokens = usage["total_tokens"] as? Int {
            Logger.shared.info("OpenAI API success - Response time: \(String(format: "%.2f", responseTime))s, Tokens: \(totalTokens)", source: "OpenAI")
        } else {
            Logger.shared.info("OpenAI API success - Response time: \(String(format: "%.2f", responseTime))s", source: "OpenAI")
        }

        return parseAnalysisResult(from: content)
    }

    func testConnection() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/models") else {
            throw AIProviderError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    func getAvailableModels() async throws -> [AIModel] {
        return AIProviderType.openai.availableModels
    }

    // MARK: - Helper Methods

    private func buildPrompt(from activities: [TimelineCard], date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long

        // Calculate statistics
        let totalSeconds = activities.reduce(0.0) { $0 + $1.duration }
        let totalHours = totalSeconds / 3600.0

        // Group by app and calculate durations
        var appDurations: [String: Double] = [:]
        for activity in activities {
            appDurations[activity.appName, default: 0] += activity.duration / 60.0 // in minutes
        }
        let sortedApps = appDurations.sorted { $0.value > $1.value }
        let topApps = sortedApps.prefix(5)

        // Calculate Deep Work (sessions ≥ 25 minutes)
        let deepWorkSessions = activities.filter { $0.duration >= 1500 }.count // 25 min threshold
        let deepWorkTime = activities.filter { $0.duration >= 1500 }.reduce(0.0) { $0 + $1.duration } / 3600.0
        let deepWorkRatio = totalHours > 0 ? (deepWorkTime / totalHours * 100) : 0

        // Activity timeline (top 10 sessions)
        let topActivities = activities.sorted { $0.duration > $1.duration }.prefix(10)
        let timelineList = topActivities.map { activity in
            let duration = Int(activity.duration / 60)
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            let time = timeFormatter.string(from: activity.startAt)
            return "- \(time): \(activity.appName) (\(duration)분)"
        }.joined(separator: "\n")

        // Top apps summary
        let topAppsList = topApps.map { app, duration in
            "- \(app): \(String(format: "%.0f", duration))분"
        }.joined(separator: "\n")

        return """
        당신은 생산성 분석 전문가입니다. 다음 활동 데이터를 분석하고 구체적이고 실행 가능한 인사이트를 제공하세요.

        📅 **날짜**: \(formatter.string(from: date))

        📊 **핵심 통계**:
        - 총 활동 시간: \(String(format: "%.1f", totalHours))시간
        - 총 활동 수: \(activities.count)개
        - Deep Work 세션 (≥25분): \(deepWorkSessions)개 (\(String(format: "%.1f", deepWorkTime))시간, \(String(format: "%.0f", deepWorkRatio))%)
        - 앱 다양성: \(appDurations.count)개 앱 사용

        🏆 **상위 5개 앱**:
        \(topAppsList)

        📋 **주요 활동 타임라인** (상위 10개):
        \(timelineList)

        **분석 요청사항**:
        1. **요약**: 이 날의 생산성 패턴을 한 문장으로 요약하세요 (예: "오전 집중, 오후 분산" 또는 "지속적 Deep Work")

        2. **핵심 인사이트** (3-5개):
           - Deep Work 비율이 높은지/낮은지, 그 원인은?
           - 시간 사용 패턴에서 발견되는 특징 (예: 특정 앱 과다 사용, 작업 분산도)
           - 생산성을 높이거나 낮춘 요인
           - 개선이 필요한 영역
           각 인사이트는 구체적 수치와 함께 제시하세요.

        3. **실행 가능한 제안** (2-3개):
           - 즉시 적용 가능한 구체적 행동 (예: "오전 첫 90분은 Xcode에만 집중")
           - 시간대별 최적화 전략
           - 방해 요소 차단 방법
           각 제안은 "무엇을", "언제", "어떻게" 할지 명확히 하세요.

        **응답 형식**:
        SUMMARY: [한 문장 요약]
        INSIGHTS:
        - [구체적 수치 포함 인사이트 1]
        - [구체적 수치 포함 인사이트 2]
        - [구체적 수치 포함 인사이트 3]
        RECOMMENDATIONS:
        - [즉시 실행 가능한 제안 1]
        - [즉시 실행 가능한 제안 2]
        """
    }

    private func parseAnalysisResult(from content: String) -> AnalysisResult {
        var summary = ""
        var insights: [String] = []
        var recommendations: [String] = []

        let lines = content.components(separatedBy: "\n")
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("SUMMARY:") {
                summary = trimmed.replacingOccurrences(of: "SUMMARY:", with: "").trimmingCharacters(in: .whitespaces)
                currentSection = "summary"
            } else if trimmed.hasPrefix("INSIGHTS:") {
                currentSection = "insights"
            } else if trimmed.hasPrefix("RECOMMENDATIONS:") {
                currentSection = "recommendations"
            } else if trimmed.hasPrefix("- ") {
                let item = trimmed.replacingOccurrences(of: "- ", with: "")
                if currentSection == "insights" {
                    insights.append(item)
                } else if currentSection == "recommendations" {
                    recommendations.append(item)
                }
            } else if currentSection == "summary" && !trimmed.isEmpty {
                summary += " " + trimmed
            }
        }

        return AnalysisResult(
            summary: summary,
            insights: insights,
            recommendations: recommendations,
            generatedAt: Date(),
            provider: providerType.rawValue,
            model: model.name
        )
    }
}
