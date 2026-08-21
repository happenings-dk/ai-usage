import SwiftUI

/// One CLI version row with an optional update command action.
struct DesktopVersionRow: View {
    let status: CLIVersionStatus
    let isChecking: Bool
    let isCheckDisabled: Bool
    let copyUpdateCommand: (CLIVersionStatus) -> Void
    let checkVersion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.compact) {
            HStack(spacing: HappeningsTheme.Spacing.control) {
                Label(status.source.rawValue, systemImage: status.source.symbolName)
                    .font(.body)
                    .foregroundStyle(HappeningsTheme.textPrimary)
                    .frame(minWidth: 112, alignment: .leading)

                Text(status.installedVersion ?? "Missing")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(status.installedVersion == nil ? .orange : HappeningsTheme.textPrimary)

                if let latestVersion = status.latestVersion {
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

                if status.isOutdated {
                    Button("Copy update", systemImage: "doc.on.doc") {
                        copyUpdateCommand(status)
                    }
                    .buttonStyle(.happeningsControl)
                    .help(status.updateCommand)
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
                .help("Check \(status.source.rawValue) again")
            }

            if let error = status.error {
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
        if status.isOutdated {
            "Update available"
        } else if status.installedVersion == nil || status.latestVersion == nil {
            "Unavailable"
        } else {
            "Current"
        }
    }

    private var badgeSystemImage: String {
        if status.isOutdated {
            "arrow.up.circle"
        } else if status.installedVersion == nil || status.latestVersion == nil {
            "exclamationmark"
        } else {
            "checkmark"
        }
    }

    private var badgeColor: Color {
        if status.isOutdated || status.installedVersion == nil || status.latestVersion == nil {
            .orange
        } else {
            .green
        }
    }
}
