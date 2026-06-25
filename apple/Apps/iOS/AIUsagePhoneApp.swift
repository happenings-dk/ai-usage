import Observation
import SwiftUI
import UniformTypeIdentifiers

@main
struct AIUsagePhoneApp: App {
    @State private var model = MobileUsageModel()

    var body: some Scene {
        WindowGroup {
            MobileUsageRootView(model: model)
                .tint(HapTheme.accent)
        }
    }
}

@MainActor
@Observable
final class MobileUsageModel {
    var snapshot = UsageSnapshot.empty
    var isRefreshing = false
    var lastError: String?
    var lastImportLabel = "Bundled snapshot"
    var syncURLString: String {
        didSet {
            UserDefaults.standard.set(syncURLString, forKey: syncURLDefaultsKey)
        }
    }

    @ObservationIgnored private let savedSnapshotDefaultsKey = "savedSnapshot"
    @ObservationIgnored private let syncURLDefaultsKey = "syncURLString"

    init() {
        syncURLString = UserDefaults.standard.string(forKey: syncURLDefaultsKey) ??
            Self.bundledDefaultBridgeURL() ??
            ""
        loadInitialSnapshot()
        if canRefresh {
            refreshFromSyncURL()
        }
    }

    var canRefresh: Bool {
        URL(string: syncURLString.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }

    var currentWindowBillableTotal: Int {
        snapshot.summaries.reduce(0) { $0 + $1.currentWindowUsage.billableApproximation }
    }

    var weekBillableTotal: Int {
        snapshot.summaries.reduce(0) { $0 + $1.weekUsage.billableApproximation }
    }

    var activeSummaries: [SourceUsageSummary] {
        snapshot.summaries.filter(\.hasActivity) + snapshot.summaries.filter { !$0.hasActivity }
    }

    func refreshFromSyncURL() {
        let trimmed = syncURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            lastError = "Invalid sync URL"
            return
        }

        isRefreshing = true
        lastError = nil
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try applySnapshotData(data, label: url.host ?? url.lastPathComponent)
            } catch {
                lastError = error.localizedDescription
            }
            isRefreshing = false
        }
    }

    func importClipboardText(_ text: String?) {
        guard let data = text?.data(using: .utf8) else {
            lastError = "Clipboard did not contain JSON"
            return
        }

        do {
            try applySnapshotData(data, label: "Clipboard")
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importFile(_ result: Result<URL, Error>) {
        Task {
            do {
                let url = try result.get()
                let isScoped = url.startAccessingSecurityScopedResource()
                defer {
                    if isScoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let data = try Data(contentsOf: url)
                try applySnapshotData(data, label: url.lastPathComponent)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func loadInitialSnapshot() {
        if let saved = UserDefaults.standard.data(forKey: savedSnapshotDefaultsKey),
           let decoded = try? decodeSnapshot(from: saved) {
            snapshot = decoded
            lastImportLabel = "Saved snapshot"
            return
        }

        guard let url = Bundle.main.url(forResource: "SeedSnapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? decodeSnapshot(from: data) else {
            return
        }

        snapshot = decoded
    }

    private func applySnapshotData(_ data: Data, label: String) throws {
        let decoded = try decodeSnapshot(from: data)
        snapshot = decoded
        lastImportLabel = label
        lastError = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        UserDefaults.standard.set(try encoder.encode(decoded), forKey: savedSnapshotDefaultsKey)
    }

    private func decodeSnapshot(from data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UsageSnapshot.self, from: data)
    }

    private static func bundledDefaultBridgeURL() -> String? {
        guard let url = Bundle.main.url(forResource: "DefaultBridgeURL", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct MobileUsageRootView: View {
    @Bindable var model: MobileUsageModel
    @State private var isShowingImporter = false
    @State private var isShowingSyncSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: HapTheme.Space.md) {
                    HeroSummaryView(model: model)

                    HapSectionHeader(title: "Sources")
                        .padding(.top, HapTheme.Space.xs)

                    ForEach(model.activeSummaries, id: \.source) { summary in
                        MobileSourceCard(summary: summary)
                    }

                    HapSectionHeader(title: "Sync")
                        .padding(.top, HapTheme.Space.xs)
                    SnapshotFooterView(model: model)
                }
                .padding(.horizontal, HapTheme.Space.lg)
                .padding(.vertical, HapTheme.Space.md)
            }
            .background(HapTheme.background)
            .navigationTitle("AI Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.refreshFromSyncURL()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!model.canRefresh || model.isRefreshing)
                    .accessibilityLabel("Refresh")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        PasteButton(payloadType: String.self) { values in
                            model.importClipboardText(values.first)
                        }

                        Button {
                            isShowingImporter = true
                        } label: {
                            Label("Import JSON", systemImage: "doc.badge.arrow.up")
                        }

                        Button {
                            isShowingSyncSettings = true
                        } label: {
                            Label("Sync Settings", systemImage: "link")
                        }

                        ShareLink(item: model.snapshot.plainTextSummary()) {
                            Label("Share Summary", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                model.importFile(result.map { urls in
                    urls.first ?? URL(fileURLWithPath: "")
                })
            }
            .sheet(isPresented: $isShowingSyncSettings) {
                SyncSettingsSheet(model: model)
                    .presentationDetents([.medium])
            }
        }
    }
}

private struct HeroSummaryView: View {
    let model: MobileUsageModel

    var body: some View {
        HapCard(padding: HapTheme.Space.lg) {
            VStack(alignment: .leading, spacing: HapTheme.Space.md) {
                header
                totalRow
                HStack(spacing: HapTheme.Space.sm) {
                    SummaryTile(title: "Today", value: NumberFormat.compact(todayTotal))
                    SummaryTile(title: "7 days", value: NumberFormat.compact(model.weekBillableTotal))
                    SummaryTile(title: "Active", value: "\(model.snapshot.summaries.filter(\.hasActivity).count)")
                }

                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: HapTheme.Space.sm) {
            Image(systemName: "chart.bar.xaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HapTheme.accent)
                .frame(width: 32, height: 32)
                .background(HapTheme.surfaceInset, in: RoundedRectangle(cornerRadius: HapTheme.Radius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("AI Usage")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(HapTheme.textPrimary)
                Text("Claude, Codex, Gemini, and Grok")
                    .font(.caption)
                    .foregroundStyle(HapTheme.textSecondary)
            }

            Spacer(minLength: HapTheme.Space.sm)

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else if let tightest = model.snapshot.tightestLimit {
                LimitBadge(source: tightest.source, window: tightest.window)
            }
        }
    }

    private var totalRow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current window")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(HapTheme.textSecondary)
                    Text(NumberFormat.compact(model.currentWindowBillableTotal))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(HapTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            Spacer()
        }
    }

    private var todayTotal: Int {
        model.snapshot.summaries.reduce(0) { $0 + $1.todayUsage.billableApproximation }
    }
}

private struct LimitBadge: View {
    let source: UsageSource
    let window: RateLimitWindow

    var body: some View {
        HStack(spacing: HapTheme.Space.xs) {
            Image(systemName: source.symbolName)
                .font(.caption2)
            HStack(spacing: 5) {
                Text(window.name)
                Text(NumberFormat.percent(window.usedPercent))
                    .fontWeight(.bold)
            }
            .font(.caption2.weight(.medium))
            .monospacedDigit()
        }
        .foregroundStyle(limitColor)
        .padding(.horizontal, HapTheme.Space.sm)
        .padding(.vertical, 5)
        .background(limitColor.opacity(0.12), in: Capsule())
    }

    private var limitColor: Color {
        if window.usedPercent >= 85 {
            return .red
        }
        if window.usedPercent >= 65 {
            return .orange
        }
        return .green
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(HapTheme.textSecondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(HapTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HapTheme.Space.sm)
        .padding(.vertical, HapTheme.Space.sm)
        .background(HapTheme.surfaceInset, in: RoundedRectangle(cornerRadius: HapTheme.Radius.row, style: .continuous))
    }
}

private struct MobileSourceCard: View {
    let summary: SourceUsageSummary

    var body: some View {
        HapCard(padding: HapTheme.Space.md) {
            VStack(alignment: .leading, spacing: HapTheme.Space.sm) {
            HStack(spacing: 10) {
                Image(systemName: summary.source.symbolName)
                    .font(.headline)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(sourceColor)
                    .background(sourceColor.opacity(0.12), in: RoundedRectangle(cornerRadius: HapTheme.Radius.control, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.source.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HapTheme.textPrimary)
                    Text(summary.latestProject.map(projectName) ?? "No active project")
                        .font(.caption)
                        .foregroundStyle(HapTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(NumberFormat.compact(summary.currentWindowUsage.billableApproximation))
                    .font(.headline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(HapTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            HStack(spacing: HapTheme.Space.sm) {
                MetricBlock(title: "5h", value: summary.currentWindowUsage.billableApproximation)
                MetricBlock(title: "Today", value: summary.todayUsage.billableApproximation)
                MetricBlock(title: "7d", value: summary.weekUsage.billableApproximation)
            }

            TokenStrip(source: summary.source, usage: summary.currentWindowUsage)

            if summary.rateLimits.isEmpty {
                ResetRows(summary: summary)
            } else {
                VStack(spacing: 8) {
                    ForEach(summary.rateLimits, id: \.name) { window in
                        LimitProgressRow(window: window)
                    }
                }
            }

            TopProjectsStrip(projects: summary.topProjects)

            HStack {
                Text("Last \(TimeFormat.relative(summary.lastEventAt))")
                Spacer()
                Text("\(summary.currentWindowEventCount)/\(summary.eventCount) events")
            }
            .font(.caption)
            .foregroundStyle(HapTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sourceColor: Color {
        switch summary.source {
        case .claude:
            .pink
        case .codex:
            .indigo
        case .gemini:
            .teal
        case .grok:
            .orange
        }
    }

    private func projectName(_ value: String) -> String {
        let name = URL(fileURLWithPath: value).lastPathComponent
        return name.isEmpty ? value : name
    }
}

private struct MetricBlock: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(HapTheme.textSecondary)
            Text(NumberFormat.compact(value))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(HapTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HapTheme.Space.sm)
        .padding(.vertical, HapTheme.Space.sm)
        .background(HapTheme.surfaceInset, in: RoundedRectangle(cornerRadius: HapTheme.Radius.row, style: .continuous))
    }
}

private struct TokenStrip: View {
    let source: UsageSource
    let usage: TokenUsage

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                TokenCell(title: "Input", value: usage.input)
                TokenCell(title: "Output", value: usage.output)
                TokenCell(title: "Cached", value: usage.cachedInput)
                TokenCell(title: reasoningTitle, value: reasoningValue)
            }
        }
    }

    private var reasoningTitle: String {
        source == .gemini ? "Thoughts" : "Reason"
    }

    private var reasoningValue: String {
        switch source {
        case .claude, .grok:
            "N/A"
        case .codex, .gemini:
            NumberFormat.compact(usage.reasoningOutput)
        }
    }
}

private struct TokenCell: View {
    let title: String
    let value: String

    init(title: String, value: Int) {
        self.title = title
        self.value = NumberFormat.compact(value)
    }

    init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(HapTheme.textSecondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(HapTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResetRows: View {
    let summary: SourceUsageSummary

    var body: some View {
        VStack(spacing: 6) {
            ResetRow(title: "5h reset", date: summary.estimatedResetAt)
            ResetRow(title: "Weekly reset", date: summary.estimatedWeeklyResetAt)
        }
    }
}

private struct ResetRow: View {
    let title: String
    let date: Date?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(TimeFormat.reset(date))
                .monospacedDigit()
                .foregroundStyle(HapTheme.textSecondary)
        }
        .font(.caption)
        .foregroundStyle(HapTheme.textPrimary)
    }
}

private struct LimitProgressRow: View {
    let window: RateLimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(window.name)
                Spacer()
                Text("\(NumberFormat.percent(window.usedPercent)) used")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(HapTheme.textPrimary)

            ProgressView(value: min(max(window.usedPercent, 0), 100), total: 100)
                .tint(tint)

            HStack {
                Text("\(NumberFormat.percent(max(0, 100 - window.usedPercent))) left")
                Spacer()
                Text("Resets \(TimeFormat.remaining(until: window.resetsAt))")
            }
            .font(.caption2)
            .foregroundStyle(HapTheme.textSecondary)
        }
    }

    private var tint: Color {
        if window.usedPercent >= 85 {
            return .red
        }
        if window.usedPercent >= 65 {
            return .orange
        }
        return .green
    }
}

private struct TopProjectsStrip: View {
    let projects: [ProjectUsage]

    var body: some View {
        if !projects.isEmpty {
            VStack(spacing: 6) {
                ForEach(Array(projects.prefix(3))) { project in
                    HStack {
                        Text(project.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 12)
                        Text(NumberFormat.compact(project.usage.billableApproximation))
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(HapTheme.textPrimary)
                }
            }
            .padding(.top, 2)
        }
    }
}

private struct SnapshotFooterView: View {
    let model: MobileUsageModel

    var body: some View {
        HapCard(padding: HapTheme.Space.md) {
            VStack(alignment: .leading, spacing: HapTheme.Space.sm) {
            HStack {
                Text("Snapshot")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(HapTheme.textPrimary)
                Spacer()
                Text(TimeFormat.exact(model.snapshot.generatedAt))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(HapTheme.textSecondary)
            }

            HStack {
                Text(model.lastImportLabel)
                    .font(.caption)
                    .foregroundStyle(HapTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text("\(model.snapshot.summaries.reduce(0) { $0 + $1.scannedFiles }) files")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(HapTheme.textSecondary)
            }
            }
        }
    }
}

private struct SyncSettingsSheet: View {
    @Bindable var model: MobileUsageModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("JSON Feed") {
                    TextField("https://example.com/ai-usage.json", text: $model.syncURLString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section {
                    Button {
                        model.refreshFromSyncURL()
                        dismiss()
                    } label: {
                        Label("Refresh Now", systemImage: "arrow.clockwise")
                    }
                    .disabled(!model.canRefresh || model.isRefreshing)
                }
            }
            .navigationTitle("Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
