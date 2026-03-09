//
//  AIProvider.swift
//  DayArc
//
//  Protocol-based AI provider architecture supporting multiple LLM backends
//

import Foundation

/// AI Model configuration
struct AIModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let provider: AIProviderType
    let contextWindow: Int
    let maxOutputTokens: Int

    // OpenAI Models (2025 Latest)
    static let openAIGPT4o = AIModel(
        id: "gpt-4o",
        name: "GPT-4o",
        provider: .openai,
        contextWindow: 128000,
        maxOutputTokens: 4096
    )

    static let openAIGPT4oMini = AIModel(
        id: "gpt-4o-mini",
        name: "GPT-4o Mini",
        provider: .openai,
        contextWindow: 128000,
        maxOutputTokens: 16384
    )

    // Claude Models (2025 Latest - Claude 4.5 Line)
    static let claudeSonnet45 = AIModel(
        id: "claude-sonnet-4-5-20250929",
        name: "Claude Sonnet 4.5",
        provider: .claude,
        contextWindow: 200000,
        maxOutputTokens: 8192
    )

    static let claudeHaiku45 = AIModel(
        id: "claude-haiku-4-5-20251001",
        name: "Claude Haiku 4.5",
        provider: .claude,
        contextWindow: 200000,
        maxOutputTokens: 8192
    )

    static let claudeOpus41 = AIModel(
        id: "claude-opus-4-1-20250805",
        name: "Claude Opus 4.1",
        provider: .claude,
        contextWindow: 200000,
        maxOutputTokens: 8192
    )

    // Gemini Models (2025 Latest - Gemini 2.5)
    static let gemini25Pro = AIModel(
        id: "gemini-2.5-pro",
        name: "Gemini 2.5 Pro",
        provider: .gemini,
        contextWindow: 1000000,
        maxOutputTokens: 8192
    )

    static let gemini25Flash = AIModel(
        id: "gemini-2.5-flash",
        name: "Gemini 2.5 Flash",
        provider: .gemini,
        contextWindow: 1000000,
        maxOutputTokens: 8192
    )

    static let gemini25FlashLite = AIModel(
        id: "gemini-2.5-flash-lite",
        name: "Gemini Flash Lite",
        provider: .gemini,
        contextWindow: 1000000,
        maxOutputTokens: 8192
    )
}

/// AI Provider types
enum AIProviderType: String, Codable, CaseIterable {
    case openai = "OpenAI"
    case claude = "Claude"
    case gemini = "Gemini"
    case ollama = "Ollama"
    case lmstudio = "LM Studio"

    var displayName: String {
        return rawValue
    }

    /// Available models for this provider
    var availableModels: [AIModel] {
        switch self {
        case .openai:
            return [.openAIGPT4o, .openAIGPT4oMini]
        case .claude:
            return [.claudeSonnet45, .claudeOpus41, .claudeHaiku45]
        case .gemini:
            return [.gemini25Pro, .gemini25Flash, .gemini25FlashLite]
        case .ollama, .lmstudio:
            return [] // Dynamic - fetched from local server
        }
    }
}

/// Main AI Provider protocol
protocol AIProvider {
    /// Provider type
    var providerType: AIProviderType { get }

    /// Generate analysis from activities
    func analyze(activities: [TimelineCard], date: Date) async throws -> AnalysisResult

    /// Test connection and API key validity
    func testConnection() async throws -> Bool

    /// Get available models (for local LLMs, this fetches from server)
    func getAvailableModels() async throws -> [AIModel]
}

/// AI Provider errors
enum AIProviderError: Error, LocalizedError {
    case invalidAPIKey
    case networkError(String)
    case rateLimitExceeded
    case modelNotAvailable(String)
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid API key. Please check your settings."
        case .networkError(let message):
            return "Network error: \(message)"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .modelNotAvailable(let model):
            return "Model '\(model)' is not available."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}

/// AI Provider factory
class AIProviderFactory {
    static let shared = AIProviderFactory()

    private init() {}

    /// Create provider instance based on type
    func createProvider(
        type: AIProviderType,
        model: AIModel,
        apiKey: String?,
        endpoint: String? = nil
    ) -> AIProvider {
        switch type {
        case .openai:
            return OpenAIProvider(model: model, apiKey: apiKey ?? "")
        case .claude:
            return ClaudeProvider(model: model, apiKey: apiKey ?? "")
        case .gemini:
            return GeminiProvider(model: model, apiKey: apiKey ?? "")
        case .ollama:
            return LegacyOllamaProvider(model: model, endpoint: endpoint ?? "http://localhost:11434")
        case .lmstudio:
            return LMStudioProvider(model: model, endpoint: endpoint ?? "http://localhost:1234")
        }
    }
}

/// Provider configuration manager
class AIProviderConfig: ObservableObject, Codable {
    @Published var selectedProviderType: AIProviderType = .claude
    @Published var selectedModel: AIModel = .claudeSonnet45
    @Published var apiKeys: [AIProviderType: String] = [:]
    @Published var localEndpoints: [AIProviderType: String] = [
        .ollama: "http://localhost:11434",
        .lmstudio: "http://localhost:1234"
    ]

    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case selectedProviderType
        case selectedModel
        // case apiKeys // Removed for security - stored in Keychain
        case localEndpoints
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedProviderType = try container.decode(AIProviderType.self, forKey: .selectedProviderType)
        selectedModel = try container.decode(AIModel.self, forKey: .selectedModel)
        localEndpoints = try container.decode([AIProviderType: String].self, forKey: .localEndpoints)
        
        // Legacy Migration: Try to decode apiKeys if they exist in UserDefaults
        // We use a dynamic container to check for the key without it being in CodingKeys
        if let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self),
           let legacyKeys = try? legacyContainer.decode([AIProviderType: String].self, forKey: .apiKeys) {
            
            print("🔐 [AIProviderConfig] Migrating \(legacyKeys.count) API keys to Keychain...")
            for (provider, key) in legacyKeys {
                KeychainManager.shared.store(key, for: provider.rawValue)
            }
        }
        
        // Load keys from Keychain
        var loadedKeys: [AIProviderType: String] = [:]
        for provider in AIProviderType.allCases {
            if let key = KeychainManager.shared.retrieve(for: provider.rawValue) {
                loadedKeys[provider] = key
            }
        }
        apiKeys = loadedKeys
    }
    
    // Helper for migration
    enum LegacyCodingKeys: String, CodingKey {
        case apiKeys
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedProviderType, forKey: .selectedProviderType)
        try container.encode(selectedModel, forKey: .selectedModel)
        // try container.encode(apiKeys, forKey: .apiKeys) // Skip encoding keys to UserDefaults
        try container.encode(localEndpoints, forKey: .localEndpoints)
    }

    init() {
        // Load keys from Keychain for fresh init
        var loadedKeys: [AIProviderType: String] = [:]
        for provider in AIProviderType.allCases {
            if let key = KeychainManager.shared.retrieve(for: provider.rawValue) {
                loadedKeys[provider] = key
            }
        }
        apiKeys = loadedKeys
    }

    /// Get current provider instance
    func getCurrentProvider() -> AIProvider {
        let apiKey = apiKeys[selectedProviderType]
        let endpoint = localEndpoints[selectedProviderType]
        return AIProviderFactory.shared.createProvider(
            type: selectedProviderType,
            model: selectedModel,
            apiKey: apiKey,
            endpoint: endpoint
        )
    }

    /// Save to UserDefaults (and Keychain for keys)
    func save() {
        // 1. Save keys to Keychain
        for (provider, key) in apiKeys {
            if !key.isEmpty {
                KeychainManager.shared.store(key, for: provider.rawValue)
            } else {
                KeychainManager.shared.delete(for: provider.rawValue)
            }
        }
        
        // 2. Save non-sensitive config to UserDefaults
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self) {
            UserDefaults.standard.set(encoded, forKey: "AIProviderConfig")

            // Sync Gemini model selection with GeminiModelPreference for Dayflow compatibility
            if selectedProviderType == .gemini {
                syncGeminiModelPreference()
            }

            // Notify other views that config has changed
            NotificationCenter.default.post(name: NSNotification.Name("AIProviderConfigDidChange"), object: nil)
            Logger.shared.info("AI Provider config saved and notification sent", source: "Settings")
        }
    }

    /// Sync selected Gemini model to GeminiModelPreference (for Dayflow recording analysis)
    private func syncGeminiModelPreference() {
        // Map AIModel to GeminiModel
        let geminiModel: GeminiModel
        switch selectedModel.id {
        case "gemini-2.5-pro":
            geminiModel = .pro
        case "gemini-2.5-flash":
            geminiModel = .flash
        case "gemini-2.5-flash-lite":
            geminiModel = .flashLite
        default:
            geminiModel = .flash // Default to flash
        }

        let preference = GeminiModelPreference(primary: geminiModel)
        preference.save()
        print("✅ [AIProviderConfig] Synced Gemini model to GeminiModelPreference: \(geminiModel.displayName)")
    }

    /// Load from UserDefaults
    static func load() -> AIProviderConfig {
        let decoder = JSONDecoder()
        if let data = UserDefaults.standard.data(forKey: "AIProviderConfig"),
           let config = try? decoder.decode(AIProviderConfig.self, from: data) {

            // Sync from GeminiModelPreference if Gemini is selected
            if config.selectedProviderType == .gemini {
                config.loadGeminiModelPreference()
            }

            return config
        }
        return AIProviderConfig()
    }

    /// Load Gemini model from GeminiModelPreference (for Dayflow compatibility)
    private func loadGeminiModelPreference() {
        let preference = GeminiModelPreference.load()

        // Map GeminiModel to AIModel
        let aiModel: AIModel
        switch preference.primary {
        case .pro:
            aiModel = .gemini25Pro
        case .flash:
            aiModel = .gemini25Flash
        case .flashLite:
            aiModel = .gemini25FlashLite
        }

        // Update selected model if it's different
        if selectedModel.id != aiModel.id {
            selectedModel = aiModel
            print("✅ [AIProviderConfig] Loaded Gemini model from GeminiModelPreference: \(aiModel.name)")
        }
    }

    /// Build provider chain for fallback: selected first, then other configured providers.
    func providerChain() -> [AIProvider] {
        var chain: [AIProvider] = []

        let orderedProviders = [selectedProviderType] + AIProviderType.allCases.filter { $0 != selectedProviderType }

        for providerType in orderedProviders {
            let apiKey = apiKeys[providerType] ?? ""
            if apiKey.isEmpty && providerType != .ollama && providerType != .lmstudio {
                continue // skip cloud provider with no key
            }

            // Use selectedModel for the selected provider, first available for fallbacks
            let model = (providerType == selectedProviderType) ? selectedModel : (providerType.availableModels.first ?? selectedModel)
            let endpoint = localEndpoints[providerType]
            let provider = AIProviderFactory.shared.createProvider(
                type: providerType,
                model: model,
                apiKey: apiKey,
                endpoint: endpoint
            )
            chain.append(provider)
        }

        return chain
    }
}
