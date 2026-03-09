//
//  ClaudeProvider.swift
//  DayArc
//
//  Anthropic Claude API implementation
//

import Foundation

class ClaudeProvider: AIProvider {
    let providerType: AIProviderType = .claude
    private let model: AIModel
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1"

    init(model: AIModel, apiKey: String) {
        self.model = model
        self.apiKey = apiKey
    }

    func analyze(activities: [TimelineCard], date: Date) async throws -> AnalysisResult {
        let prompt = buildPrompt(from: activities, date: date)

        Logger.shared.info("Starting Claude API call - Model: \(model.id), Prompt length: \(prompt.count) chars", source: "Claude")

        let requestBody: [String: Any] = [
            "model": model.id,
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let url = URL(string: "\(baseURL)/messages") else {
            Logger.shared.error("Invalid Claude API URL", source: "Claude")
            throw AIProviderError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let responseTime = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.shared.error("Invalid HTTP response from Claude", source: "Claude")
            throw AIProviderError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            Logger.shared.error("Claude API key invalid (401)", source: "Claude")
            throw AIProviderError.invalidAPIKey
        }

        if httpResponse.statusCode == 429 {
            Logger.shared.warning("Claude rate limit exceeded (429)", source: "Claude")
            throw AIProviderError.rateLimitExceeded
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.shared.error("Claude API error (\(httpResponse.statusCode)): \(errorMessage)", source: "Claude")
            throw AIProviderError.serverError(httpResponse.statusCode, errorMessage)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            Logger.shared.error("Failed to parse Claude response", source: "Claude")
            throw AIProviderError.invalidResponse
        }

        // Extract usage info if available
        if let usage = json?["usage"] as? [String: Any],
           let inputTokens = usage["input_tokens"] as? Int,
           let outputTokens = usage["output_tokens"] as? Int {
            Logger.shared.info("Claude API success - Response time: \(String(format: "%.2f", responseTime))s, Tokens: \(inputTokens + outputTokens) (in:\(inputTokens) out:\(outputTokens))", source: "Claude")
        } else {
            Logger.shared.info("Claude API success - Response time: \(String(format: "%.2f", responseTime))s", source: "Claude")
        }

        // Log raw response for debugging
        Logger.shared.debug("Claude raw response: \(text.prefix(500))...", source: "Claude")

        return parseAnalysisResult(from: text)
    }

    func testConnection() async throws -> Bool {
        // Claude doesn't have a simple ping endpoint, so we'll make a minimal request
        let requestBody: [String: Any] = [
            "model": model.id,
            "max_tokens": 1,
            "messages": [
                ["role": "user", "content": "Hi"]
            ]
        ]

        guard let url = URL(string: "\(baseURL)/messages") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    func getAvailableModels() async throws -> [AIModel] {
        return AIProviderType.claude.availableModels
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

        **IMPORTANT: 반드시 아래 JSON 형식으로만 응답하세요. 다른 텍스트 없이 JSON만 출력하세요:**
        ```json
        {
          "summary": "한 문장 요약",
          "insights": [
            "구체적 수치 포함 인사이트 1",
            "구체적 수치 포함 인사이트 2",
            "구체적 수치 포함 인사이트 3"
          ],
          "recommendations": [
            "즉시 실행 가능한 제안 1",
            "즉시 실행 가능한 제안 2"
          ]
        }
        ```
        """
    }

    private func parseAnalysisResult(from content: String) -> AnalysisResult {
        var summary = ""
        var insights: [String] = []
        var recommendations: [String] = []

        // Try JSON parsing first
        if let jsonData = extractJSON(from: content),
           let json = try? JSONSerialization.jsonObject(with: jsonData.data(using: .utf8)!, options: []) as? [String: Any] {
            summary = json["summary"] as? String ?? ""
            insights = json["insights"] as? [String] ?? []
            recommendations = json["recommendations"] as? [String] ?? []
            Logger.shared.debug("Parsed JSON successfully - Summary: '\(summary.prefix(100))', Insights: \(insights.count), Recommendations: \(recommendations.count)", source: "Claude")
        } else {
            // Fallback to text parsing
            Logger.shared.debug("JSON parsing failed, falling back to text parsing", source: "Claude")

            let lines = content.components(separatedBy: "\n")
            var currentSection = ""

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("SUMMARY:") || trimmed.hasPrefix("**SUMMARY**:") || trimmed.uppercased().hasPrefix("SUMMARY:") {
                    summary = trimmed.replacingOccurrences(of: "SUMMARY:", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "**SUMMARY**:", with: "")
                        .replacingOccurrences(of: "**", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    currentSection = "summary"
                } else if trimmed.hasPrefix("INSIGHTS:") || trimmed.hasPrefix("**INSIGHTS**:") || trimmed.uppercased().hasPrefix("INSIGHTS:") {
                    currentSection = "insights"
                } else if trimmed.hasPrefix("RECOMMENDATIONS:") || trimmed.hasPrefix("**RECOMMENDATIONS**:") || trimmed.uppercased().hasPrefix("RECOMMENDATIONS:") {
                    currentSection = "recommendations"
                } else if trimmed.hasPrefix("- ") {
                    let item = trimmed.replacingOccurrences(of: "- ", with: "")
                    if currentSection == "insights" {
                        insights.append(item)
                    } else if currentSection == "recommendations" {
                        recommendations.append(item)
                    }
                } else if currentSection == "summary" && !trimmed.isEmpty && !trimmed.hasPrefix("INSIGHTS") && !trimmed.hasPrefix("RECOMMENDATIONS") {
                    summary += " " + trimmed
                }
            }
            Logger.shared.debug("Parsed text - Summary: '\(summary.prefix(100))', Insights: \(insights.count), Recommendations: \(recommendations.count)", source: "Claude")
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

    private func extractJSON(from content: String) -> String? {
        // Method 1: Try to extract JSON from code blocks (```json ... ``` or ``` ... ```)
        let codeBlockPatterns = ["```json", "```JSON", "```"]
        for pattern in codeBlockPatterns {
            if let startRange = content.range(of: pattern, options: .caseInsensitive) {
                let afterStart = content[startRange.upperBound...]
                if let endRange = afterStart.range(of: "```") {
                    var jsonBlock = String(afterStart[..<endRange.lowerBound])
                    jsonBlock = jsonBlock.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Find the actual JSON object within the block
                    if let startIdx = jsonBlock.firstIndex(of: "{"),
                       let endIdx = jsonBlock.lastIndex(of: "}") {
                        let extracted = String(jsonBlock[startIdx...endIdx])
                        if isValidJSON(extracted) {
                            return extracted
                        }
                    }
                }
            }
        }

        // Method 2: Try to find raw JSON (starts with { and ends with })
        // Use a more sophisticated approach to find matching braces
        if let startIndex = content.firstIndex(of: "{") {
            var braceCount = 0
            var inString = false
            var escapeNext = false

            for (idx, char) in content[startIndex...].enumerated() {
                let actualIndex = content.index(startIndex, offsetBy: idx)

                if escapeNext {
                    escapeNext = false
                    continue
                }

                if char == "\\" {
                    escapeNext = true
                    continue
                }

                if char == "\"" {
                    inString.toggle()
                    continue
                }

                if !inString {
                    if char == "{" {
                        braceCount += 1
                    } else if char == "}" {
                        braceCount -= 1
                        if braceCount == 0 {
                            let extracted = String(content[startIndex...actualIndex])
                            if isValidJSON(extracted) {
                                return extracted
                            }
                            break
                        }
                    }
                }
            }
        }

        return nil
    }

    private func isValidJSON(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
            return true
        } catch {
            return false
        }
    }
}
