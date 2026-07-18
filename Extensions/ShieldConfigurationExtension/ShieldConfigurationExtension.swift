//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension target
//
//  Customizes the full-screen shield shown over blocked apps.
//  Friendly, non-scary language per product requirements.
//
//  ⚠️ This file belongs to a separate app-extension target of type
//  com.apple.ManagedSettingsUI.shield-configuration-service with the
//  Family Controls entitlement and the shared App Group.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private func friendlyShield(for displayName: String?) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: UIColor.systemIndigo.withAlphaComponent(0.15),
            icon: UIImage(systemName: "moon.stars.fill"),
            title: .init(
                text: String(localized: "Time for a break!"),
                color: .label
            ),
            subtitle: .init(
                text: String(localized: "This app is taking a rest right now. Please ask your parent if you need it."),
                color: .secondaryLabel
            ),
            primaryButtonLabel: .init(
                text: String(localized: "Request More Time"),
                color: .white
            ),
            primaryButtonBackgroundColor: .systemIndigo,
            secondaryButtonLabel: .init(
                text: String(localized: "Parent Unlock"),
                color: .systemIndigo
            )
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        friendlyShield(for: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        friendlyShield(for: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        friendlyShield(for: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        friendlyShield(for: webDomain.domain)
    }
}
