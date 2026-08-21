import SwiftUI

/// The stable content hierarchy inside the quick-access material surface.
struct QuickPanelContent: View {
    let model: UsageViewModel
    let shortcutName: String
    let openDashboard: () -> Void
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.standard) {
            HStack(spacing: HappeningsTheme.Spacing.control) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(HappeningsTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(HappeningsTheme.surfaceInset, in: .rect(cornerRadius: HappeningsTheme.Radius.control))
                    .overlay {
                        RoundedRectangle(cornerRadius: HappeningsTheme.Radius.control)
                            .stroke(HappeningsTheme.border, lineWidth: 1)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.compact) {
                    Text("AI Usage")
                        .font(.title2.bold())
                        .foregroundStyle(HappeningsTheme.textPrimary)

                    Text("Quick Look")
                        .font(.callout)
                        .foregroundStyle(HappeningsTheme.textSecondary)
                }

                Spacer(minLength: HappeningsTheme.Spacing.small)

                Button("Open Dashboard", systemImage: "macwindow", action: openDashboard)
                    .buttonStyle(.happeningsPrimary)

                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.happeningsControl)
                    .help("Close Quick Look")
            }

            VStack(alignment: .leading, spacing: HappeningsTheme.Spacing.small) {
                Text("Live limits")
                    .font(.caption.bold())
                    .foregroundStyle(HappeningsTheme.textSecondary)

                if model.snapshot.allRateLimits.isEmpty {
                    Label("No live rate limits yet", systemImage: "gauge.with.dots.needle.0percent")
                        .font(.callout)
                        .foregroundStyle(HappeningsTheme.textSecondary)
                        .padding(HappeningsTheme.Spacing.control)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            HappeningsTheme.surface,
                            in: .rect(cornerRadius: HappeningsTheme.Radius.control)
                        )
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: HappeningsTheme.Spacing.small),
                            GridItem(.flexible(), spacing: HappeningsTheme.Spacing.small)
                        ],
                        spacing: HappeningsTheme.Spacing.small
                    ) {
                        ForEach(model.snapshot.allRateLimits) { item in
                            QuickLimitCard(item: item)
                        }
                    }
                }
            }

            Text("Token activity")
                .font(.caption.bold())
                .foregroundStyle(HappeningsTheme.textSecondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: HappeningsTheme.Spacing.small),
                    GridItem(.flexible(), spacing: HappeningsTheme.Spacing.small)
                ],
                spacing: HappeningsTheme.Spacing.small
            ) {
                ForEach(UsageSource.allCases) { source in
                    QuickSourceRow(summary: model.snapshot.summary(for: source))
                }
            }

                HStack {
                    Text("Updated \(TimeFormat.relative(model.snapshot.generatedAt))")
                    Spacer()
                    Text("Toggle anytime with \(shortcutName)")
                }
                .font(.caption)
                .foregroundStyle(HappeningsTheme.textSecondary)
            }
            .padding(HappeningsTheme.Spacing.generous)
        }
        .frame(
            width: HappeningsTheme.Layout.quickPanelWidth,
            height: HappeningsTheme.Layout.quickPanelHeight
        )
        .background(HappeningsTheme.background.opacity(0.36))
    }
}
