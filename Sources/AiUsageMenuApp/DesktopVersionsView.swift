import SwiftUI

/// Installed CLI and app version status.
struct DesktopVersionsView: View {
    let cliVersions: [CLIVersionStatus]
    let appUpdate: AppUpdateStatus
    let isInstallingAppUpdate: Bool
    let isCheckingVersions: Bool
    let isCheckingAppVersion: Bool
    let isCheckingVersion: (UsageSource) -> Bool
    let copyUpdateCommand: (CLIVersionStatus) -> Void
    let installAppUpdate: () -> Void
    let openAppRelease: () -> Void
    let checkAllVersions: () -> Void
    let checkVersion: (UsageSource) -> Void
    let checkAppVersion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.control) {
            HStack {
                Text("Versions")
                    .font(.headline)
                    .foregroundStyle(HappeningsTheme.textPrimary)

                Spacer()

                if !isCheckingVersions,
                   let checkedAt = cliVersions.compactMap(\.checkedAt).max() ?? appUpdate.checkedAt {
                    Text("Checked \(TimeFormat.relative(checkedAt))")
                        .font(.caption)
                        .foregroundStyle(HappeningsTheme.textSecondary)
                }

                Button(action: checkAllVersions) {
                    Label {
                        Text(isCheckingVersions ? "Checking" : "Check all")
                    } icon: {
                        if isCheckingVersions {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .buttonStyle(.happeningsControl)
                .disabled(isCheckingVersions)
            }

            HappeningsCard(padding: HappeningsTheme.Spacing.small) {
                VStack(spacing: HappeningsTheme.Spacing.compact) {
                    ForEach(cliVersions) { status in
                        DesktopVersionRow(
                            status: status,
                            isChecking: isCheckingVersion(status.source),
                            isCheckDisabled: isCheckingVersions,
                            copyUpdateCommand: copyUpdateCommand,
                            checkVersion: { checkVersion(status.source) }
                        )
                    }

                    DesktopAppVersionRow(
                        update: appUpdate,
                        isInstallingUpdate: isInstallingAppUpdate,
                        isChecking: isCheckingAppVersion,
                        isCheckDisabled: isCheckingVersions,
                        installUpdate: installAppUpdate,
                        openRelease: openAppRelease,
                        checkVersion: checkAppVersion
                    )
                }
            }
        }
    }

}
