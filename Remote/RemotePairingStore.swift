//
//  RemotePairingStore.swift
//  ParentLock
//
//  Persists which side of the pairing this device is and the shared code.
//  Lives in the App Group so extensions can tell a remotely-locked shield
//  apart from a locally-configured one.
//

import Foundation
import Observation

@MainActor
@Observable
final class RemotePairingStore {
    private(set) var role: DeviceRole
    private(set) var pairingCode: String?
    /// Friendly name of the device on the other end, once it has checked in.
    var pairedDeviceName: String?

    var isPaired: Bool { role != .unpaired && pairingCode != nil }

    init() {
        role = SharedStorage.loadCodable(DeviceRole.self, for: .deviceRole) ?? .unpaired
        pairingCode = SharedStorage.loadString(for: .pairingCode)
        pairedDeviceName = SharedStorage.loadString(for: .pairedDeviceName)
    }

    /// Claim the parent role and mint a fresh code for the child to enter.
    @discardableResult
    func becomeParent() -> String {
        let code = PairingCode.generate()
        apply(role: .parent, code: code)
        return code
    }

    /// Claim the child role using the code shown on the parent device.
    func becomeChild(code: String) throws {
        let normalized = PairingCode.normalize(code)
        guard PairingCode.isValid(normalized) else { throw RemoteControlError.invalidCode }
        apply(role: .child, code: normalized)
    }

    /// Drop the pairing on this device. The other side keeps its own copy
    /// until it is unpaired too — this is intentionally a local action so a
    /// child device can never unpair the parent.
    func unpair() {
        role = .unpaired
        pairingCode = nil
        pairedDeviceName = nil
        SharedStorage.remove(.deviceRole)
        SharedStorage.remove(.pairingCode)
        SharedStorage.remove(.pairedDeviceName)
    }

    func rememberPairedDevice(named name: String) {
        guard name != pairedDeviceName else { return }
        pairedDeviceName = name
        SharedStorage.saveString(name, for: .pairedDeviceName)
    }

    private func apply(role newRole: DeviceRole, code: String) {
        role = newRole
        pairingCode = code
        SharedStorage.saveCodable(newRole, for: .deviceRole)
        SharedStorage.saveString(code, for: .pairingCode)
    }
}
