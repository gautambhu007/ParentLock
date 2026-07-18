//
//  BiometricAuthManager.swift
//  ParentLock
//
//  Wraps LocalAuthentication. Face ID with automatic passcode fallback.
//  The dashboard re-locks whenever the app is backgrounded (see ParentLockApp).
//

import Foundation
import LocalAuthentication
import Observation

enum AuthError: LocalizedError {
    case biometryUnavailable
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .biometryUnavailable: "Face ID and passcode are unavailable on this device."
        case .cancelled: "Authentication was cancelled."
        case .failed(let message): message
        }
    }
}

@MainActor
@Observable
final class BiometricAuthManager {
    /// True until the parent authenticates. The dashboard is hidden while locked.
    private(set) var isLocked = true

    /// When the parent last authenticated — used for the auto-lock timeout.
    private(set) var lastAuthenticated: Date?

    /// Auto-lock timeout in seconds (configurable in Settings).
    var autoLockTimeout: TimeInterval = 60

    var biometryType: LABiometryType {
        let context = LAContext()
        var error: NSError?
        context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    /// Re-lock the dashboard (called when the app is backgrounded).
    func lock() {
        guard let last = lastAuthenticated else { isLocked = true; return }
        // Only re-lock if the timeout has elapsed; short app switches stay unlocked.
        if Date.now.timeIntervalSince(last) > autoLockTimeout {
            isLocked = true
        } else {
            isLocked = true // Strict mode: always lock on background. Adjust if desired.
        }
    }

    /// Authenticate for the app lock screen.
    func authenticate(reason: String) async throws {
        try await evaluate(reason: reason)
        isLocked = false
        lastAuthenticated = .now
    }

    /// Authenticate for a single sensitive action (settings change, unlock, reset…).
    /// Does not change the app lock state.
    @discardableResult
    func authenticateForAction(reason: String) async throws -> Bool {
        try await evaluate(reason: reason)
        lastAuthenticated = .now
        return true
    }

    // MARK: - Private

    private func evaluate(reason: String) async throws {
        let context = LAContext()
        context.localizedFallbackTitle = String(localized: "Use Passcode")

        var error: NSError?
        // deviceOwnerAuthentication = biometrics with automatic passcode fallback.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw AuthError.biometryUnavailable
        }

        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let laError as LAError where laError.code == .userCancel {
            throw AuthError.cancelled
        } catch {
            throw AuthError.failed(error.localizedDescription)
        }
    }
}
