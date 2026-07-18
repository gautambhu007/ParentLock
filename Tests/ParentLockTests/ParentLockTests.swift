//
//  ParentLockTests.swift
//  Unit tests using the Swift Testing framework.
//

import Testing
import Foundation
@testable import ParentLock

@Suite("Reward logic")
struct RewardTests {
    @Test func rewardExpiryIsComputedFromRedemption() {
        let reward = Reward(taskDescription: "Homework", unlockDescription: "Games", unlockMinutes: 30)
        #expect(reward.expiresAt == nil)
        #expect(!reward.isActive)

        reward.redeemedAt = .now
        let expiry = try! #require(reward.expiresAt)
        #expect(abs(expiry.timeIntervalSinceNow - 1800) < 2)
        #expect(reward.isActive)
    }

    @Test func expiredRewardIsInactive() {
        let reward = Reward(taskDescription: "Reading", unlockDescription: "YouTube", unlockMinutes: 20)
        reward.redeemedAt = .now.addingTimeInterval(-3600)
        #expect(!reward.isActive)
    }
}

@Suite("Schedule model")
struct ScheduleTests {
    @Test func timeRangeTextFormatsCorrectly() {
        let schedule = BlockSchedule(name: "Homework", startHour: 17, startMinute: 0, endHour: 19, endMinute: 30)
        #expect(schedule.timeRangeText == "17:00 – 19:30")
    }

    @Test func selectionsRoundTripThroughData() {
        let schedule = BlockSchedule(name: "Test", startHour: 9, startMinute: 0, endHour: 10, endMinute: 0)
        let selection = schedule.blockedSelection   // empty default
        schedule.blockedSelection = selection
        #expect(schedule.blockedSelectionData != nil)
    }
}

@Suite("Report ranges")
struct ReportRangeTests {
    @Test func dailyRangeStartsToday() {
        let start = ReportRange.daily.startDate
        #expect(Calendar.current.isDateInToday(start))
    }

    @Test func weeklyRangeSpansSevenDays() {
        let start = ReportRange.weekly.startDate
        let days = Calendar.current.dateComponents([.day], from: start, to: .now).day ?? 0
        #expect(days >= 6 && days <= 7)
    }
}
