//
//  LocalLLMProvider.swift
//  DayArc
//
//  Local LLM support (Ollama and LM Studio)
//

import Foundation

// MARK: - Ollama Provider

class LegacyOllamaProvider: AIProvider {
    let providerType: AIProviderType = .ollama
    private let model: AIModel
    private let endpoint: String

    init(model: AIModel, endpoint: String) {
        self.model = model
        self.endpoint = endpoint
    }

    func analyze(activities: [TimelineCard], date: Date) async throws -> AnalysisResult {
        let prompt = buildPrompt(from: activities, date: date)

        let requestBody: [String: Any] = [
            "model": model.id,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.7,
                "num_predict": 2048
            ]
        ]

        guard let url = URL(string: "\(endpoint)/api/generate") else {
            throw AIProviderError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120 // Local LLMs can be slow

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIProviderError.serverError(httpResponse.statusCode, errorMessage)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let responseText = json?["response"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return parseAnalysisResult(from: responseText)
    }

    func testConnection() async throws -> Bool {
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    func getAvailableModels() async throws -> [AIModel] {
        guard let url = URL(string: "\(endpoint)/api/tags") else {
            throw AIProviderError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIProviderError.networkError("Failed to fetch models")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["models"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { modelDict in
            guard let name = modelDict["name"] as? String else { return nil }
            return AIModel(
                id: name,
                name: name.capitalized,
                provider: .ollama,
                contextWindow: 4096, // Default, varies by model
                maxOutputTokens: 2048
            )
        }
    }

    // MARK: - Helper Methods

    private func buildPrompt(from activities: [TimelineCard], date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long

        let activityList = activities.map { activity in
            let duration = Int(activity.duration / 60)
            return "- \(activity.appName): \(duration) minutes"
        }.joined(separator: "\n")

        return """
        Analyze the following daily activities for \(formatter.string(from: date)):

        \(activityList)

        Please provide:
        1. A brief summary of the day
        2. 3-5 key insights about productivity patterns
        3. 2-3 actionable recommendations for improvement

        Format your response as:
        SUMMARY: [summary here]
        INSIGHTS:
        - [insight 1]
        - [insight 2]
        - [insight 3]
        RECOMMENDATIONS:
        - [recommendation 1]
        - [recommendation 2]
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

// MARK: - LM Studio Provider

class LMStudioProvider: AIProvider {
    let providerType: AIProviderType = .lmstudio
    private let model: AIModel
    private let endpoint: String

    init(model: AIModel, endpoint: String) {
        self.model = model
        self.endpoint = endpoint
    }

    func analyze(activities: [TimelineCard], date: Date) async throws -> AnalysisResult {
        let prompt = buildPrompt(from: activities, date: date)

        // LM Studio uses OpenAI-compatible API
        let requestBody: [String: Any] = [
            "model": model.id,
            "messages": [
                ["role": "system", "content": "You are a productivity analyst."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2048
        ]

        guard let url = URL(string: "\(endpoint)/v1/chat/completions") else {
            throw AIProviderError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIProviderError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIProviderError.serverError(httpResponse.statusCode, errorMessage)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIProviderError.invalidResponse
        }

        return parseAnalysisResult(from: content)
    }

    func testConnection() async throws -> Bool {
        guard let url = URL(string: "\(endpoint)/v1/models") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    func getAvailableModels() async throws -> [AIModel] {
        guard let url = URL(string: "\(endpoint)/v1/models") else {
            throw AIProviderError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIProviderError.networkError("Failed to fetch models")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let dataArray = json?["data"] as? [[String: Any]] else {
            return []
        }

        return dataArray.compactMap { modelDict in
            guard let id = modelDict["id"] as? String else { return nil }
            return AIModel(
                id: id,
                name: id,
                provider: .lmstudio,
                contextWindow: 4096,
                maxOutputTokens: 2048
            )
        }
    }

    // MARK: - Helper Methods

    private func buildPrompt(from activities: [TimelineCard], date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long

        let activityList = activities.map { activity in
            let duration = Int(activity.duration / 60)
            return "- \(activity.appName): \(duration) minutes"
        }.joined(separator: "\n")

        return """
        Analyze the following daily activities for \(formatter.string(from: date)):

        \(activityList)

        Please provide:
        1. A brief summary of the day
        2. 3-5 key insights about productivity patterns
        3. 2-3 actionable recommendations for improvement

        Format your response as:
        SUMMARY: [summary here]
        INSIGHTS:
        - [insight 1]
        - [insight 2]
        - [insight 3]
        RECOMMENDATIONS:
        - [recommendation 1]
        - [recommendation 2]
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
