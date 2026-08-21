import SwiftUI

/// The full, resizable macOS usage dashboard.
struct DesktopDashboardView: View {
    let model: UsageViewModel
    let quickAccessShortcut: String
    let showQuickAccess: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HappeningsTheme.Spacing.section) {
                DesktopHeaderView(
                    isRefreshing: model.isRefreshing,
                    isCheckingVersions: model.isCheckingVersions,
                    isInitialLoading: isInitialLoading,
                    quickAccessShortcut: quickAccessShortcut,
                    refresh: model.refresh,
                    showQuickAccess: showQuickAccess
                )

                UsageOverviewView(snapshot: model.snapshot)
                    .redacted(reason: isInitialLoading ? .placeholder : [])

                Text("Sources")
                    .font(.headline)
                    .foregroundStyle(HappeningsTheme.textPrimary)

                Grid(
                    alignment: .topLeading,
                    horizontalSpacing: HappeningsTheme.Spacing.standard
                ) {
                    GridRow(alignment: .top) {
                        ForEach(UsageSource.allCases) { source in
                            UsageSourceCard(summary: model.snapshot.summary(for: source))
                        }
                    }
                }
                .redacted(reason: isInitialLoading ? .placeholder : [])

                DesktopVersionsView(
                    cliVersions: model.snapshot.cliVersions,
                    appUpdate: model.snapshot.appUpdate,
                    isInstallingAppUpdate: model.isInstallingUpdate,
                    isCheckingVersions: model.isCheckingVersions,
                    isCheckingAppVersion: model.isCheckingAppVersion,
                    isCheckingVersion: model.isCheckingVersion,
                    copyUpdateCommand: model.copyUpdateCommand,
                    installAppUpdate: model.installAppUpdate,
                    openAppRelease: model.openAppUpdateDownload,
                    checkAllVersions: model.checkVersions,
                    checkVersion: model.checkVersion,
                    checkAppVersion: model.checkAppVersion
                )
                .redacted(reason: isInitialLoading ? .placeholder : [])

                if let lastError = model.lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(HappeningsTheme.Spacing.standard)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.10), in: .rect(cornerRadius: HappeningsTheme.Radius.control))
                        .overlay {
                            RoundedRectangle(cornerRadius: HappeningsTheme.Radius.control)
                                .stroke(.red.opacity(0.24), lineWidth: 1)
                        }
                }

                DesktopFooterView(
                    updatedAt: model.snapshot.generatedAt,
                    isInitialLoading: isInitialLoading,
                    quickAccessShortcut: quickAccessShortcut
                )
            }
            .padding(HappeningsTheme.Spacing.section)
        }
        .scrollContentBackground(.visible)
        .background(HappeningsTheme.background.ignoresSafeArea())
        .frame(minWidth: 1_040, minHeight: 520)
    }

    private var isInitialLoading: Bool {
        model.isRefreshing && model.snapshot.generatedAt == .distantPast
    }
}
