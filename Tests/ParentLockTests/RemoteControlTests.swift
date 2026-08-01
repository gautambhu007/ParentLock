//
//  RemoteControlTests.swift
//  Covers the parts of remote control that don't need CloudKit or a device:
//  pairing-code handling, command encoding, and staleness rules.
//

import Testing
import Foundation
@testable import ParentLock

@Suite("Pairing codes")
struct PairingCodeTests {
    @Test func generatedCodesAreValidAndUnambiguous() {
        for _ in 0..<200 {
            let code = PairingCode.generate()
            #expect(code.count == 8)
            #expect(PairingCode.isValid(code))
            // 0/O and 1/I/L are excluded so a code can't be mistyped into
            // another family's pairing.
            #expect(!code.contains(where: { "01OIL".contains($0) }))
        }
    }

    @Test func normalizeAcceptsUserFormatting() {
        #expect(PairingCode.normalize("abcd-efgh") == "ABCDEFGH")
        #expect(PairingCode.normalize(" ABCD EFGH ") == "ABCDEFGH")
        #expect(PairingCode.normalize("ABCD-EFGH") == "ABCDEFGH")
    }

    @Test func normalizeDropsCharactersOutsideTheAlphabet() {
        // 0, 1 and O are not in the alphabet, so they are stripped rather than
        // silently mapped to a lookalike.
        #expect(PairingCode.normalize("A0B1CDEFGH") == "ABCDEFGH")
    }

    @Test func invalidCodesAreRejected() {
        #expect(!PairingCode.isValid("ABCD"))          // too short
        #expect(!PairingCode.isValid("ABCDEFGHI"))     // too long
        #expect(!PairingCode.isValid("ABCDEFG0"))      // excluded character
        #expect(!PairingCode.isValid("abcdefgh"))      // not normalized
    }

    @Test func formattedInsertsSeparatorForDisplayOnly() {
        #expect(PairingCode.formatted("ABCDEFGH") == "ABCD-EFGH")
        #expect(PairingCode.formatted("SHORT") == "SHORT")
    }
}

@Suite("Remote commands")
struct RemoteCommandTests {
    @Test func commandsRoundTripThroughJSON() throws {
        let groupID = UUID()
        let command = RemoteCommand(kind: .lockGroup, groupID: groupID)
        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(RemoteCommand.self, from: data)

        #expect(decoded.id == command.id)
        #expect(decoded.kind == .lockGroup)
        #expect(decoded.groupID == groupID)
        #expect(decoded.status == .pending)
    }

    @Test func timedUnlockCarriesItsDuration() throws {
        let command = RemoteCommand(kind: .unlockAll, durationMinutes: 30)
        let decoded = try JSONDecoder().decode(RemoteCommand.self,
                                               from: JSONEncoder().encode(command))
        #expect(decoded.durationMinutes == 30)
        #expect(!decoded.kind.isLock)
    }

    @Test func summaryNamesTheTargetedGroup() {
        let command = RemoteCommand(kind: .lockGroup, groupID: UUID())
        #expect(command.summary(groupName: "Games").contains("Games"))
    }
}

@Suite("Remote lock state")
struct RemoteLockStateTests {
    @Test func emptyStateMeansNothingIsShielded() {
        #expect(RemoteLockState.none.isEmpty)
    }

    @Test func lockingAGroupMakesTheStateNonEmpty() {
        var state = RemoteLockState()
        state.lockedGroupIDs.insert(UUID())
        #expect(!state.isEmpty)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        var state = RemoteLockState(isAllLocked: true)
        state.lockedGroupIDs = [UUID(), UUID()]
        let decoded = try JSONDecoder().decode(RemoteLockState.self,
                                               from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}

@Suite("Child status")
struct ChildDeviceStatusTests {
    private func status(lastSeen: Date) -> ChildDeviceStatus {
        ChildDeviceStatus(deviceName: "Child iPad",
                          lastSeen: lastSeen,
                          isAllLocked: false,
                          lockedGroupIDs: [])
    }

    @Test func recentCheckInCountsAsOnline() {
        #expect(status(lastSeen: .now).isOnline)
    }

    @Test func staleCheckInCountsAsOffline() {
        let stale = Date.now.addingTimeInterval(-ChildDeviceStatus.stalenessThreshold - 60)
        #expect(!status(lastSeen: stale).isOnline)
    }
}
