//
//  SentryMock.swift
//  DayArc
//
//  Created to replace external Sentry dependency with local logging.
//

import Foundation
import OSLog

// MARK: - Sentry Types Mock

enum SentryLevel {
    case debug, info, warning, error, fatal
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .fatal: return .fault
        }
    }
}

class Breadcrumb {
    var level: SentryLevel = .info
    var category: String = "default"
    var message: String?
    var data: [String: Any]?
    var type: String = "default"
    
    init(level: SentryLevel, category: String) {
        self.level = level
        self.category = category
    }
}

class Transaction {
    var name: String
    var operation: String
    var data: [String: Any] = [:]
    
    init(name: String, operation: String) {
        self.name = name
        self.operation = operation
    }
    
    func setData(value: Any, key: String) {
        data[key] = value
    }
    
    func finish(status: SpanStatus) {
        Logger.shared.debug("Transaction finished: \(name) (\(operation)) - Status: \(status) - Data: \(data)", source: "SentryMock")
    }
}

enum SpanStatus {
    case ok
    case internalError
    case unknownError
}

// MARK: - SentrySDK Mock

class SentrySDK {
    static func startTransaction(name: String, operation: String) -> Transaction {
        let transaction = Transaction(name: name, operation: operation)
        Logger.shared.debug("Transaction started: \(name) (\(operation))", source: "SentryMock")
        return transaction
    }
    
    static func addBreadcrumb(_ breadcrumb: Breadcrumb) {
        SentryHelper.addBreadcrumb(breadcrumb)
    }
    
    static func capture(message: String) {
        Logger.shared.error("Capture Message: \(message)", source: "SentryMock")
    }
    
    static func capture(error: Error) {
        Logger.shared.error("Capture Error: \(error.localizedDescription)", source: "SentryMock")
    }
}

// MARK: - SentryHelper Mock

class SentryHelper {
    static func addBreadcrumb(_ breadcrumb: Breadcrumb) {
        let msg = breadcrumb.message ?? "No message"
        let dataStr = breadcrumb.data?.description ?? ""
        
        switch breadcrumb.level {
        case .error, .fatal:
            Logger.shared.error("[\(breadcrumb.category)] \(msg) \(dataStr)", source: "Breadcrumb")
        case .warning:
            Logger.shared.error("[\(breadcrumb.category)] \(msg) \(dataStr)", source: "Breadcrumb") // Use error for visibility
        default:
            Logger.shared.debug("[\(breadcrumb.category)] \(msg) \(dataStr)", source: "Breadcrumb")
        }
    }
}
