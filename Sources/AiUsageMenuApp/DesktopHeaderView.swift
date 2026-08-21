import SwiftUI

/// The desktop dashboard title and primary controls.
struct DesktopHeaderView: View {
    let isRefreshing: Bool
    let isCheckingVersions: Bool
    let isInitialLoading: Bool
    let quickAccessShortcut: String
    let refresh: () -> Void
    let showQuickAccess: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: HappeningsTheme.Spacing.standard) {
            VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.compact) {
                Text("AI Usage")
                    .font(.largeTitle.bold())
                    .foregroundStyle(HappeningsTheme.textPrimary)

                Text(
                    isInitialLoading
                        ? "Loading local usage…"
                        : "Live Claude, Codex, Gemini, and Grok usage on this Mac"
                )
                    .font(.body)
                    .foregroundStyle(HappeningsTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Quick Look", systemImage: "bolt", action: showQuickAccess)
                .buttonStyle(.happeningsControl)
                .help("Show Quick Look (\(quickAccessShortcut))")

            Button(action: refresh) {
                Label {
                    Text(buttonTitle)
                } icon: {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .buttonStyle(.happeningsPrimary)
            .disabled(isBusy)
            .help("Refresh usage and check versions")
        }
    }

    private var isBusy: Bool {
        isRefreshing || isCheckingVersions
    }

    private var buttonTitle: String {
        if isRefreshing {
            "Refreshing"
        } else if isCheckingVersions {
            "Checking"
        } else {
            "Refresh"
        }
    }
}
