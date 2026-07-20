//
//  HomeHeader.swift
//  ParentLock
//
//  Branded hero header + live protection-status banner + quick stats
//  for the parent home page.
//

import SwiftUI

/// The brand mark (asset if present, SF-symbol fallback) inside a soft disc.
struct BrandBadge: View {
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Circle().fill(.white.opacity(0.22))
            if UIImage(named: "BrandMark") != nil {
                Image("BrandMark")
                    .resizable().scaledToFit()
                    .frame(width: size * 0.66, height: size * 0.66)
            } else {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Gradient hero with logo, app name, and a time-of-day greeting.
struct HomeHeader: View {
    var childName: String?

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12:  return String(localized: "Good morning")
        case 12..<17: return String(localized: "Good afternoon")
        case 17..<22: return String(localized: "Good evening")
        default:      return String(localized: "Good night")
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            BrandBadge(size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text("ParentLock")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                Text(childName.map { "\(greeting) · \($0)" } ?? greeting)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Color(red: 0.36, green: 0.29, blue: 0.88),
                                    Color(red: 0.61, green: 0.42, blue: 0.93)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white.opacity(0.08))
                    .frame(width: 220, height: 220)
                    .offset(x: 70, y: -90)
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }
}

/// Big banner telling the parent, at a glance, whether protection is on.
struct ProtectionStatusBanner: View {
    enum State { case active, attention, unlocked }
    let state: State
    let detail: String

    private var color: Color {
        switch state {
        case .active:    return .green
        case .attention: return .orange
        case .unlocked:  return .pink
        }
    }
    private var symbol: String {
        switch state {
        case .active:    return "checkmark.shield.fill"
        case .attention: return "exclamationmark.shield.fill"
        case .unlocked:  return "lock.open.fill"
        }
    }
    private var headline: String {
        switch state {
        case .active:    return String(localized: "Protection is active")
        case .attention: return String(localized: "Action needed")
        case .unlocked:  return String(localized: "Temporarily unlocked")
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(detail)")
    }
}

/// A compact metric chip used in the quick-stats row.
struct StatChip: View {
    let value: String
    let label: LocalizedStringKey
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

/// A small left-aligned section title.
struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 4)
    }
}
