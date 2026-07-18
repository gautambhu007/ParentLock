//
//  DashboardCard.swift
//  ParentLock
//
//  Reusable rounded glass card following the HIG.
//

import SwiftUI

struct DashboardCard: View {
    let title: LocalizedStringKey
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.15), in: .rect(cornerRadius: 12))
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
        .hoverEffect(.lift)
        .accessibilityElement(children: .combine)
    }
}

/// Large capsule button used across the app.
struct BigButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}
