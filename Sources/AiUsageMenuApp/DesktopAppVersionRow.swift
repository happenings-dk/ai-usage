import SwiftUI

/// The macOS app version row and update action.
struct DesktopAppVersionRow: View {
    let update: AppUpdateStatus
    let isInstallingUpdate: Bool
    let isChecking: Bool
    let isCheckDisabled: Bool
    let installUpdate: () -> Void
    let openRelease: () -> Void
    let checkVersion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.compact) {
            HStack(spacing: HappeningsTheme.Spacing.control) {
                Label("AI Usage", systemImage: "app.badge")
                    .font(.body)
                    .foregroundStyle(HappeningsTheme.textPrimary)
                    .frame(minWidth: 112, alignment: .leading)

                Text(update.currentVersion)
                    .font(.body.monospacedDigit())
                    .foregroundStyle(HappeningsTheme.textPrimary)

                if let latestVersion = update.latestVersion {
                    Text("Latest \(latestVersion)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(HappeningsTheme.textSecondary)
                }

                Spacer(minLength: HappeningsTheme.Spacing.small)

                HappeningsStatusBadge(
                    text: badgeText,
                    systemImage: badgeSystemImage,
                    color: badgeColor
                )

                if update.canInstallAutomatically {
                    Button(action: installUpdate) {
                        Label {
                            Text(isInstallingUpdate ? "Installing" : "Install update")
                        } icon: {
                            if isInstallingUpdate {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.app")
                            }
                        }
                    }
                    .buttonStyle(.happeningsControl)
                    .disabled(isInstallingUpdate)
                } else if update.isUpdateAvailable,
                          update.releasePageURL != nil || update.downloadURL != nil {
                    Button("Open release", systemImage: "arrow.up.right.square", action: openRelease)
                        .buttonStyle(.happeningsControl)
                }

                Button(action: checkVersion) {
                    Label {
                        Text(isChecking ? "Checking" : "Check")
                    } icon: {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .buttonStyle(.happeningsControl)
                .disabled(isCheckDisabled)
                .help("Check AI Usage again")
            }

            if let error = update.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, HappeningsTheme.Spacing.control)
        .padding(.vertical, HappeningsTheme.Spacing.compact)
        .frame(minHeight: 52)
        .background(HappeningsTheme.surfaceInset, in: .rect(cornerRadius: HappeningsTheme.Radius.control))
    }

    private var badgeText: String {
        if update.isUpdateAvailable {
            "Update available"
        } else if update.latestVersion == nil {
            "Unavailable"
        } else {
            "Current"
        }
    }

    private var badgeSystemImage: String {
        if update.isUpdateAvailable {
            "arrow.up.circle"
        } else if update.latestVersion == nil {
            "exclamationmark"
        } else {
            "checkmark"
        }
    }

    private var badgeColor: Color {
        if update.isUpdateAvailable || update.latestVersion == nil {
            .orange
        } else {
            .green
        }
    }
}
