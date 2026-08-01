//
//  RemotePushBridge.swift
//  ParentLock
//
//  UIApplicationDelegate glue for CloudKit silent pushes.
//
//  The delegate is created by UIKit, the coordinator by the SwiftUI
//  composition root; this bridge is the one place they meet. Pushes only ever
//  say "something changed" — the payload is never trusted or acted on
//  directly, the coordinator re-reads state from CloudKit instead.
//

import UIKit
import CloudKit
import os

@MainActor
final class RemotePushBridge {
    static let shared = RemotePushBridge()

    weak var coordinator: RemoteControlCoordinator?

    private init() {}

    func refresh() async {
        await coordinator?.handleRemoteNotification()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "com.gautam.parentlock", category: "push")

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Silent pushes need no user permission — the alert permission the app
        // asks for elsewhere is for local parent alerts only.
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Non-fatal: remote control falls back to foreground refresh + polling.
        logger.warning("Push registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            return .noData
        }
        await RemotePushBridge.shared.refresh()
        return .newData
    }
}
