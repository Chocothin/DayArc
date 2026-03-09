//
//  ProviderDiagnostics.swift
//  DayArc
//
//  Quick end-to-end tests for all configured AI providers and fallback order.
//

import Foundation

struct ProviderDiagnosticsResult: Identifiable {
    let id = UUID()
    let provider: AIProviderType
    let success: Bool
    let message: String
}

class ProviderDiagnostics {
    static func runAll(config: AIProviderConfig) async -> [ProviderDiagnosticsResult] {
        var results: [ProviderDiagnosticsResult] = []

        for providerType in AIProviderType.allCases {
            let apiKey = config.apiKeys[providerType] ?? ""
            let model = providerType.availableModels.first ?? config.selectedModel
            let endpoint = config.localEndpoints[providerType]

            // Only test providers that have credentials or are local
            if apiKey.isEmpty && providerType != .ollama && providerType != .lmstudio {
                continue
            }

            let provider = AIProviderFactory.shared.createProvider(
                type: providerType,
                model: model,
                apiKey: apiKey,
                endpoint: endpoint
            )

            do {
                let ok = try await provider.testConnection()
                let message = ok ? "✅ \(providerType.displayName) reachable" : "⚠️ \(providerType.displayName) responded but needs attention"
                results.append(ProviderDiagnosticsResult(provider: providerType, success: ok, message: message))
            } catch {
                results.append(ProviderDiagnosticsResult(
                    provider: providerType,
                    success: false,
                    message: "❌ \(providerType.displayName) failed: \(error.localizedDescription)"
                ))
            }
        }

        if results.isEmpty {
            results.append(ProviderDiagnosticsResult(
                provider: config.selectedProviderType,
                success: false,
                message: "No providers configured with credentials to test."
            ))
        }

        // Log summary for debugging/fallback
        let summary = results.map { "\($0.provider.displayName): \($0.message)" }.joined(separator: " | ")
        Logger.shared.info("Provider diagnostics -> \(summary)", source: "Diagnostics")

        return results
    }
}
