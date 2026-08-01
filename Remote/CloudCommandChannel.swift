//
//  CloudCommandChannel.swift
//  ParentLock
//
//  The wire between the parent device and the child device.
//
//  Design notes
//  ------------
//  * Public database, because parent and child usually sign in with different
//    Apple IDs and the private database can't be read across accounts. The
//    pairing code is the shared secret; nothing personally identifying and no
//    ApplicationTokens are ever written here — only a device name, group
//    names, and lock/unlock instructions.
//  * Every record has a *deterministic* name derived from the pairing code, so
//    all reads and writes are `fetch(withRecordID:)` — no CKQuery, and
//    therefore no queryable-index setup needed for the app to work.
//  * Payload-heavy record types keep a single JSON `payload` field rather than
//    one record per item. One writer per side plus retry-on-conflict keeps
//    that safe and cuts the request count.
//  * Push is an optimisation layered on top (see `subscribe`). If subscription
//    setup fails — no indexes, no push entitlement, a simulator — the channel
//    still works via foreground refresh and polling.
//

import Foundation
import CloudKit
import os

actor CloudCommandChannel {
    /// ⚠️ Must match the iCloud container in the app's entitlements.
    static let containerID = "iCloud.com.gautam.parentlock"

    private let database: CKDatabase
    private let logger = Logger(subsystem: "com.gautam.parentlock", category: "remote")

    /// Newest commands kept in the shared queue record.
    private static let queueLimit = 50
    /// Retries for the optimistic-concurrency save loop.
    private static let maxSaveAttempts = 4

    init(container: CKContainer = CKContainer(identifier: CloudCommandChannel.containerID)) {
        self.database = container.publicCloudDatabase
    }

    // MARK: - Record naming

    private enum RecordType {
        static let pairing = "PLPairing"
        static let commands = "PLCommandQueue"
        static let groups = "PLGroups"
        static let status = "PLStatus"
    }

    private func recordID(_ prefix: String, _ code: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(prefix)-\(code)")
    }

    // MARK: - Account

    /// Whether iCloud is usable right now. Remote control is inert without it.
    func isAccountAvailable() async -> Bool {
        let status = try? await CKContainer(identifier: Self.containerID).accountStatus()
        return status == .available
    }

    // MARK: - Pairing

    /// Parent side: publish the pairing so a child device can find the code.
    func createPairing(code: String, parentDeviceName: String) async throws {
        try await mutateRecord(type: RecordType.pairing, id: recordID("pairing", code)) { record in
            record["code"] = code as CKRecordValue
            record["parentDeviceName"] = parentDeviceName as CKRecordValue
            if record["createdAt"] == nil {
                record["createdAt"] = Date.now as CKRecordValue
            }
        }
    }

    /// Child side: confirm the code exists and attach this device's name to it.
    /// Returns the parent device's name.
    func claimPairing(code: String, childDeviceName: String) async throws -> String {
        guard let record = try await fetchRecord(recordID("pairing", code)) else {
            throw RemoteControlError.pairingNotFound
        }
        let parentName = record["parentDeviceName"] as? String ?? String(localized: "Parent device")
        try await mutateRecord(type: RecordType.pairing, id: recordID("pairing", code)) { record in
            record["childDeviceName"] = childDeviceName as CKRecordValue
        }
        return parentName
    }

    /// Parent side: the child's device name once it has paired, if any.
    func pairedChildName(code: String) async throws -> String? {
        try await fetchRecord(recordID("pairing", code))?["childDeviceName"] as? String
    }

    // MARK: - Commands

    /// Parent side: enqueue an instruction for the child device.
    func send(_ command: RemoteCommand, code: String) async throws {
        try await mutatePayload(type: RecordType.commands,
                                id: recordID("commands", code),
                                code: code,
                                default: [RemoteCommand]()) { queue in
            queue.removeAll { $0.id == command.id }
            queue.append(command)
            queue.sort { $0.issuedAt < $1.issuedAt }
            if queue.count > Self.queueLimit {
                queue.removeFirst(queue.count - Self.queueLimit)
            }
        }
        logger.info("Queued remote command \(command.kind.rawValue, privacy: .public)")
    }

    /// Both sides: the full command history, newest last.
    func commands(code: String) async throws -> [RemoteCommand] {
        try await payload(type: RecordType.commands, id: recordID("commands", code)) ?? []
    }

    /// Child side: record the outcome of commands it just applied.
    func acknowledge(_ results: [RemoteCommand], code: String) async throws {
        guard !results.isEmpty else { return }
        let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.id, $0) })
        try await mutatePayload(type: RecordType.commands,
                                id: recordID("commands", code),
                                code: code,
                                default: [RemoteCommand]()) { queue in
            for index in queue.indices {
                if let updated = byID[queue[index].id] {
                    queue[index] = updated
                }
            }
        }
    }

    // MARK: - Lock groups

    /// Child side: publish group names so the parent has something to tap.
    func publishGroups(_ groups: [RemoteLockGroup], code: String) async throws {
        try await mutatePayload(type: RecordType.groups,
                                id: recordID("groups", code),
                                code: code,
                                default: [RemoteLockGroup]()) { stored in
            stored = groups
        }
    }

    /// Parent side: the groups the child device has configured.
    func groups(code: String) async throws -> [RemoteLockGroup] {
        try await payload(type: RecordType.groups, id: recordID("groups", code)) ?? []
    }

    // MARK: - Status

    /// Child side: heartbeat + what is actually shielded right now.
    func publishStatus(_ status: ChildDeviceStatus, code: String) async throws {
        try await mutatePayload(type: RecordType.status,
                                id: recordID("status", code),
                                code: code,
                                default: Optional<ChildDeviceStatus>.none) { stored in
            stored = status
        }
    }

    /// Parent side: the child's last reported state, or nil if it never checked in.
    func status(code: String) async throws -> ChildDeviceStatus? {
        try await payload(type: RecordType.status, id: recordID("status", code)) ?? nil
    }

    // MARK: - Push subscriptions

    /// Ask CloudKit to wake this device when the other side writes.
    ///
    /// Requires the `code` field to be marked **Queryable** on the record type
    /// in the CloudKit Dashboard. A failure here is non-fatal: the caller falls
    /// back to foreground refresh and polling, so it is logged, not thrown.
    func subscribe(code: String, role: DeviceRole) async {
        let recordType = role == .child ? RecordType.commands : RecordType.status
        let subscriptionID = "\(recordType)-\(code)"

        if let existing = try? await database.subscription(for: subscriptionID), existing.subscriptionID == subscriptionID {
            return
        }

        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: NSPredicate(format: "code == %@", code),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true   // silent push; we refresh, we don't alert
        subscription.notificationInfo = notification

        do {
            _ = try await database.save(subscription)
            logger.info("Subscribed to \(recordType, privacy: .public) push")
        } catch {
            logger.warning("Push subscription unavailable, falling back to polling: \(error.localizedDescription, privacy: .public)")
        }
    }

    func unsubscribeAll(code: String) async {
        for recordType in [RecordType.commands, RecordType.status] {
            _ = try? await database.deleteSubscription(withID: "\(recordType)-\(code)")
        }
    }

    // MARK: - Record plumbing

    private func fetchRecord(_ id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil   // never written yet — an empty state, not a failure
        } catch let error as CKError where error.code == .notAuthenticated {
            throw RemoteControlError.iCloudUnavailable
        }
    }

    /// Fetch-modify-save with retry, so two devices writing the same record
    /// can't clobber each other.
    private func mutateRecord(type: String,
                              id: CKRecord.ID,
                              _ transform: @Sendable (CKRecord) -> Void) async throws {
        for attempt in 1...Self.maxSaveAttempts {
            let record = try await fetchRecord(id) ?? CKRecord(recordType: type, recordID: id)
            transform(record)
            do {
                _ = try await database.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < Self.maxSaveAttempts {
                continue   // someone else won the race; re-read and re-apply
            } catch let error as CKError where error.code == .notAuthenticated {
                throw RemoteControlError.iCloudUnavailable
            }
        }
    }

    private func payload<T: Codable & Sendable>(type: String, id: CKRecord.ID) async throws -> T? {
        guard let record = try await fetchRecord(id),
              let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func mutatePayload<T: Codable & Sendable>(type: String,
                                                     id: CKRecord.ID,
                                                     code: String,
                                                     default defaultValue: T,
                                                     _ transform: @Sendable @escaping (inout T) -> Void) async throws {
        try await mutateRecord(type: type, id: id) { record in
            var value = (record["payload"] as? Data)
                .flatMap { try? JSONDecoder().decode(T.self, from: $0) } ?? defaultValue
            transform(&value)
            guard let data = try? JSONEncoder().encode(value) else { return }
            record["payload"] = data as CKRecordValue
            record["code"] = code as CKRecordValue
            record["updatedAt"] = Date.now as CKRecordValue
        }
    }
}
