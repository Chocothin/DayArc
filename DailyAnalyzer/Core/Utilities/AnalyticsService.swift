//
//  AnalyticsService.swift
//  DayArc
//
//  Created to replace external Analytics dependency with local logging.
//

import Foundation

final class AnalyticsService: Sendable {
    static let shared = AnalyticsService()
    
    private init() {}
    
    func capture(_ event: String, _ properties: [String: Any] = [:]) {
        Logger.shared.info("Analytics Event: \(event) - \(properties)", source: "Analytics")
    }
    
    func withSampling(probability: Double, block: () -> Void) {
        // For local debugging, we might want to log everything, or respect sampling.
        // Let's respect sampling to avoid console spam for high-frequency events.
        if Double.random(in: 0...1) < probability {
            block()
        }
    }
    
    func secondsBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case 0..<15: return "<15s"
        case 15..<60: return "15s-1m"
        case 60..<300: return "1m-5m"
        case 300..<900: return "5m-15m"
        default: return "15m+"
        }
    }
}
