//
//  GeminiProvider.swift
//  DayArc
//
//  Google Gemini API implementation
//

import Foundation

class GeminiProvider: AIProvider {
    let providerType: AIProviderType = .gemini
    private let model: AIModel
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"

    init(model: AIModel, apiKey: String) {
        self.model = model
        self.apiKey = apiKey
    }

    func analyze(activities: [TimelineCard], date: Date) async throws -> AnalysisResult {
        let prompt = buildPrompt(from: activities, date: date)

        Logger.shared.info("Starting Gemini API call - Model: \(model.id), Prompt length: \(prompt.count) chars", source: "Gemini")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 8192  // Increased to accommodate thinking tokens
            ]
        ]

        guard let url = URL(string: "\(baseURL)/models/\(model.id):generateContent?key=\(apiKey)") else {
            Logger.shared.error("Invalid Gemini API URL", source: "Gemini")
            throw AIProviderError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let startTime = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let responseTime = Date().timeIntervalSince(startTime)

        guard let httpResponse = response as? HTTPURLResponse else {
            Logger.shared.error("Invalid HTTP response from Gemini", source: "Gemini")
            throw AIProviderError.invalidResponse
        }

        if httpResponse.statusCode == 400 {
            Logger.shared.error("Gemini API key invalid (400)", source: "Gemini")
            throw AIProviderError.invalidAPIKey
        }

        if httpResponse.statusCode == 429 {
            Logger.shared.warning("Gemini rate limit exceeded (429)", source: "Gemini")
            throw AIProviderError.rateLimitExceeded
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            Logger.shared.error("Gemini API error (\(httpResponse.statusCode)): \(errorMessage)", source: "Gemini")
            throw AIProviderError.serverError(httpResponse.statusCode, errorMessage)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Log the full response for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            Logger.shared.debug("Gemini API full response: \(jsonString.prefix(1000))", source: "Gemini")
        }

        guard let candidates = json?["candidates"] as? [[String: Any]] else {
            Logger.shared.error("Failed to parse Gemini response: 'candidates' not found or invalid", source: "Gemini")
            Logger.shared.debug("Response keys: \(json?.keys.joined(separator: ", ") ?? "none")", source: "Gemini")
            throw AIProviderError.invalidResponse
        }

        guard let firstCandidate = candidates.first else {
            Logger.shared.error("Failed to parse Gemini response: candidates array is empty", source: "Gemini")
            throw AIProviderError.invalidResponse
        }

        guard let content = firstCandidate["content"] as? [String: Any] else {
            Logger.shared.error("Failed to parse Gemini response: 'content' not found", source: "Gemini")
            Logger.shared.debug("Candidate keys: \(firstCandidate.keys.joined(separator: ", "))", source: "Gemini")
            throw AIProviderError.invalidResponse
        }

        guard let parts = content["parts"] as? [[String: Any]] else {
            Logger.shared.error("Failed to parse Gemini response: 'parts' not found", source: "Gemini")
            Logger.shared.debug("Content keys: \(content.keys.joined(separator: ", "))", source: "Gemini")
            throw AIProviderError.invalidResponse
        }

        guard let firstPart = parts.first else {
            Logger.shared.error("Failed to parse Gemini response: parts array is empty", source: "Gemini")
            throw AIProviderError.invalidResponse
        }

        guard let text = firstPart["text"] as? String else {
            Logger.shared.error("Failed to parse Gemini response: 'text' not found in part", source: "Gemini")
            Logger.shared.debug("Part keys: \(firstPart.keys.joined(separator: ", "))", source: "Gemini")
            throw AIProviderError.invalidResponse
        }

        // Extract usage metadata if available
        if let usageMetadata = json?["usageMetadata"] as? [String: Any],
           let totalTokens = usageMetadata["totalTokenCount"] as? Int {
            Logger.shared.info("Gemini API success - Response time: \(String(format: "%.2f", responseTime))s, Tokens: \(totalTokens)", source: "Gemini")
        } else {
            Logger.shared.info("Gemini API success - Response time: \(String(format: "%.2f", responseTime))s", source: "Gemini")
        }

        // Log raw response for debugging
        Logger.shared.debug("Gemini raw response: \(text.prefix(500))...", source: "Gemini")

        return parseAnalysisResult(from: text)
    }

    func testConnection() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/models?key=\(apiKey)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    func getAvailableModels() async throws -> [AIModel] {
        return AIProviderType.gemini.availableModels
    }

    /// Simple text completion for general prompts
    func complete(prompt: String) async throws -> String {
        Logger.shared.debug("Gemini completion request - Prompt length: \(prompt.count)", source: "Gemini")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 2048
            ]
        ]

        guard let url = URL(string: "\(baseURL)/models/\(model.id):generateContent?key=\(apiKey)") else {
            throw AIProviderError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIProviderError.serverError(httpResponse.statusCode, errorMessage)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return text
    }

    // MARK: - Helper Methods

    private func buildPrompt(from activities: [TimelineCard], date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long

        // Detect if this is weekly/monthly data based on activity time range
        let calendar = Calendar.current
        let activityDates = activities.map { calendar.startOfDay(for: $0.startAt) }
        let uniqueDays = Set(activityDates).count
        let isWeeklyOrMore = uniqueDays >= 5  // 5+ days suggests weekly/monthly data

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

        // Date range string for weekly/monthly data
        let dateRangeStr: String
        if isWeeklyOrMore {
            let minDate = activityDates.min() ?? date
            let maxDate = activityDates.max() ?? date
            formatter.dateFormat = "yyyy-MM-dd"
            dateRangeStr = "\(formatter.string(from: minDate)) ~ \(formatter.string(from: maxDate)) (\(uniqueDays)일간의 누적 데이터)"
        } else {
            formatter.dateStyle = .long
            dateRangeStr = formatter.string(from: date)
        }

        let periodContext = isWeeklyOrMore ?
            "**중요**: 이 데이터는 \(uniqueDays)일간의 누적 활동 데이터입니다. 총 활동 시간이 하루 24시간을 초과하는 것은 정상입니다." :
            ""

        return """
        당신은 생산성 분석 전문가입니다. 다음 활동 데이터를 분석하고 구체적이고 실행 가능한 인사이트를 제공하세요.

        📅 **기간**: \(dateRangeStr)
        \(periodContext)

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

        Logger.shared.debug("Raw Gemini response length: \(content.count) chars", source: "Gemini")
        Logger.shared.debug("Raw response preview: \(content.prefix(500))", source: "Gemini")

        // Try JSON parsing first
        if let jsonData = extractJSON(from: content) {
            Logger.shared.debug("Extracted JSON: \(jsonData)", source: "Gemini")

            if let json = try? JSONSerialization.jsonObject(with: jsonData.data(using: .utf8)!, options: []) as? [String: Any] {
                summary = json["summary"] as? String ?? ""
                insights = json["insights"] as? [String] ?? []
                recommendations = json["recommendations"] as? [String] ?? []
                Logger.shared.debug("Parsed JSON successfully - Summary: '\(summary.prefix(100))', Insights: \(insights.count), Recommendations: \(recommendations.count)", source: "Gemini")
            } else {
                Logger.shared.error("JSON extracted but failed to parse as valid JSON", source: "Gemini")
                Logger.shared.debug("Failed JSON content: \(jsonData)", source: "Gemini")
            }
        } else {
            Logger.shared.error("Failed to extract JSON from response", source: "Gemini")
            // Fallback to text parsing
            Logger.shared.debug("JSON parsing failed, falling back to text parsing", source: "Gemini")

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
            Logger.shared.debug("Parsed text - Summary: '\(summary.prefix(100))', Insights: \(insights.count), Recommendations: \(recommendations.count)", source: "Gemini")
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

                // Try to find closing ``` tag
                let jsonBlock: String
                if let endRange = afterStart.range(of: "```") {
                    jsonBlock = String(afterStart[..<endRange.lowerBound])
                } else {
                    // No closing tag found - response might be truncated, use rest of content
                    Logger.shared.debug("No closing ``` tag found, using rest of content", source: "Gemini")
                    jsonBlock = String(afterStart)
                }

                let trimmedBlock = jsonBlock.trimmingCharacters(in: .whitespacesAndNewlines)

                // Find the actual JSON object within the block
                if let startIdx = trimmedBlock.firstIndex(of: "{"),
                   let endIdx = trimmedBlock.lastIndex(of: "}") {
                    let extracted = String(trimmedBlock[startIdx...endIdx])
                    if isValidJSON(extracted) {
                        return extracted
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
