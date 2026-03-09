//
//  NotificationManager.swift
//  DayArc
//
//  Notification handling with click actions to open reports
//

import Foundation
import AppKit
import UserNotifications

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Permission

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        
        center.getNotificationSettings { settings in
            Logger.shared.info("Current notification settings: \(settings.authorizationStatus.rawValue)", source: "NotificationManager")
            
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    if granted {
                        Logger.shared.info("Notification permission granted", source: "NotificationManager")
                    } else if let error = error {
                        Logger.shared.error("Notification permission error: \(error)", source: "NotificationManager")
                    } else {
                        Logger.shared.warning("Notification permission denied by user", source: "NotificationManager")
                    }
                }
            } else if settings.authorizationStatus == .denied {
                Logger.shared.warning("Notification permission previously denied", source: "NotificationManager")
            } else {
                Logger.shared.info("Notification permission already granted", source: "NotificationManager")
            }
        }
    }

    // MARK: - Sending Notifications

    enum ReportType: String {
        case daily = "daily"
        case weekly = "weekly"
        case monthly = "monthly"
    }

    func sendReportNotification(
        type: ReportType,
        date: Date,
        success: Bool,
        error: Error? = nil,
        notePath: String? = nil
    ) {
        let content = UNMutableNotificationContent()

        if success {
            content.title = "\(type.rawValue.capitalized) Report Generated"
            content.body = "Your \(type.rawValue) report for \(formatDate(date, type: type)) has been saved to your vault."
            content.sound = .default

            // Add user info to identify the report when clicked
            var info: [String: Any] = [
                "reportType": type.rawValue,
                "reportDate": date.timeIntervalSince1970,
                "success": true
            ]
            if let notePath = notePath {
                info["notePath"] = notePath
            }
            content.userInfo = info

            // Add action to view the report
            content.categoryIdentifier = "REPORT_NOTIFICATION"
        } else {
            content.title = "\(type.rawValue.capitalized) Report Failed"
            content.body = "Failed to generate report: \(error?.localizedDescription ?? "Unknown error")"
            content.sound = .defaultCritical

            content.userInfo = [
                "reportType": type.rawValue,
                "reportDate": date.timeIntervalSince1970,
                "success": false
            ]
        }

        let request = UNNotificationRequest(
            identifier: "\(type.rawValue)_\(UUID().uuidString)",
            content: content,
            trigger: nil // Fire immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.shared.error("Failed to send notification: \(error)", source: "NotificationManager")
            }
        }
    }

    private func formatDate(_ date: Date, type: ReportType) -> String {
        let formatter = DateFormatter()
        switch type {
        case .daily:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
        case .weekly:
            formatter.dateFormat = "MMM d"
            return "week of \(formatter.string(from: date))"
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
        }
        return formatter.string(from: date)
    }

    // MARK: - Notification Categories and Actions

    func registerNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_REPORT",
            title: "View Report",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )

        let reportCategory = UNNotificationCategory(
            identifier: "REPORT_NOTIFICATION",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([reportCategory])
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification click
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard let reportTypeString = userInfo["reportType"] as? String,
              let reportType = ReportType(rawValue: reportTypeString),
              let reportTimestamp = userInfo["reportDate"] as? TimeInterval,
              let success = userInfo["success"] as? Bool else {
            completionHandler()
            return
        }

        let reportDate = Date(timeIntervalSince1970: reportTimestamp)

        // Only open report if it was generated successfully
        if success && (response.actionIdentifier == "VIEW_REPORT" ||
           response.actionIdentifier == UNNotificationDefaultActionIdentifier) {

            // If we know the file path, open it directly; otherwise fall back to in-app event
            if let notePath = userInfo["notePath"] as? String,
               !notePath.isEmpty,
               FileManager.default.fileExists(atPath: notePath) {
                NSWorkspace.shared.open(URL(fileURLWithPath: notePath))
                Logger.shared.info("Opening saved note at \(notePath)", source: "NotificationManager")
            } else {
                // Post notification to open Analysis tab with this report
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenReportInAnalysis"),
                    object: nil,
                    userInfo: [
                        "reportType": reportType.rawValue,
                        "reportDate": reportDate
                    ]
                )
                Logger.shared.info("Opening \(reportType.rawValue) report for \(reportDate)", source: "NotificationManager")
            }
        }

        completionHandler()
    }
}
