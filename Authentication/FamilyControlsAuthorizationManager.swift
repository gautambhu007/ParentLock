//
//  FamilyControlsAuthorizationManager.swift
//  ParentLock
//
//  Handles the FamilyControls authorization lifecycle, including revocation
//  detected when the app returns to the foreground.
//

import Foundation
import FamilyControls
import Observation

@MainActor
@Observable
final class FamilyControlsAuthorizationManager {
    private(set) var status: AuthorizationStatus = .notDetermined
    private(set) var lastError: String?

    var isAuthorized: Bool { status == .approved }

    /// Request Family Controls authorization.
    ///
    /// `.individual` authorizes restrictions on this device for the signed-in user.
    /// If the iPad is signed in to a child's Apple Account in Family Sharing,
    /// pass `.child` instead so the parent approves remotely.
    nonisolated func requestAuthorization(role: sending FamilyControlsMember = .individual) async {
        // `role` is created here in a nonisolated context, so handing it to
        // the @concurrent `requestAuthorization(for:)` no longer sends a
        // main-actor-isolated value across an isolation boundary.
        var errorText: String?
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: role)
        } catch {
            errorText = error.localizedDescription
        }
        let newStatus = AuthorizationCenter.shared.authorizationStatus
        await MainActor.run {
            status = newStatus
            lastError = errorText
        }
    }

    /// Re-read the status (call on foreground — authorization can be revoked
    /// in Settings at any time, and every restricted action must validate it).
    func refreshStatus() async {
        status = AuthorizationCenter.shared.authorizationStatus
    }

    /// Guard helper: throw if the app is no longer authorized.
    func validateAuthorized() throws {
        guard isAuthorized else {
            throw FamilyControlsError.authorizationCanceled
        }
    }
}
