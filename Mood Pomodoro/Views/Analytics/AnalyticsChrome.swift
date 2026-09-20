import SwiftUI

struct AnalyticsReliabilityBadge: View {
    let confidence: AnalyticsConfidence
    var extra: String?

    var body: some View {
        Text(extra.map { "\(confidence.shortLabel) · \($0)" } ?? confidence.shortLabel)
            .font(.lora(11))
            .foregroundStyle(AppTheme.inkSoft)
    }
}

struct AnalyticsEmptyCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.lora(17, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text(message)
                .font(.lora(13))
                .foregroundStyle(AppTheme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .parchmentCard(padding: 0)
    }
}

struct AnalyticsStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.lora(12))
                .foregroundStyle(AppTheme.inkSoft)
            Text(value)
                .font(.lora(18, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func analyticsFormat(_ value: Double?, suffix: String = " / 5") -> String {
    guard let value else { return "—" }
    let text = String(format: "%.1f", value)
    return (AppLanguage.current == .ru ? text.replacingOccurrences(of: ".", with: ",") : text) + suffix
}

func analyticsDuration(_ value: TimeInterval?) -> String {
    guard let value, value > 0 else { return "—" }
    return DurationFormatting.compact(value)
}

// MARK: - Period

/// The one period control: a single capsule that opens a menu. The choice is
/// the store's, so every screen reached from the analytics shows the same
/// window and none of them asks again.
struct AnalyticsPeriodMenu: View {
    @Bindable var store: AnalyticsStore
    @State private var showCustom = false

    var body: some View {
        Menu {
            ForEach(AnalyticsPeriodKind.allCases) { kind in
                Button {
                    if kind == .custom { showCustom = true } else { store.period.kind = kind }
                } label: {
                    if store.period.kind == kind {
                        Label(kind.title, systemImage: "checkmark")
                    } else {
                        Text(kind.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(store.period.kind.title)
                    .font(.lora(14, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(AppTheme.forestDeep)
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .background(Capsule().fill(AppTheme.parchmentCard))
            .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1.25))
        }
        .accessibilityLabel(L("Период", "Period"))
        .accessibilityValue(store.period.kind.title)
        .sheet(isPresented: $showCustom) {
            AnalyticsCustomDatesSheet(store: store)
        }
    }
}

struct AnalyticsCustomDatesSheet: View {
    @Bindable var store: AnalyticsStore
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date

    init(store: AnalyticsStore) {
        self.store = store
        let interval = store.period.interval()
        _start = State(initialValue: store.period.customStart ?? interval.start)
        _end = State(initialValue: store.period.customEnd ?? Date.now)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(L("С", "From"), selection: $start, in: ...Date.now, displayedComponents: .date)
                DatePicker(L("По", "To"), selection: $end, in: ...Date.now, displayedComponents: .date)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.parchmentCard)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Отмена", "Cancel")) { dismiss() }.foregroundStyle(AppTheme.inkSoft)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Готово", "Done")) {
                        // One assignment, so the engine rebuilds once.
                        var period = store.period
                        period.customStart = start
                        period.customEnd = end
                        period.kind = .custom
                        store.period = period
                        dismiss()
                    }
                    .foregroundStyle(AppTheme.forest)
                }
            }
        }
        .goblinChrome()
        .presentationDetents([.medium])
    }
}

// MARK: - Progressive disclosure

/// A titled section that stays closed until asked. Used wherever a screen
/// would otherwise stack every detail one after another.
struct AnalyticsDisclosure<Content: View>: View {
    let title: String
    var summary: String?
    @State private var isOpen: Bool
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, summary: String? = nil, open: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self._isOpen = State(initialValue: open)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.lora(15, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if let summary {
                        Text(summary)
                            .font(.lora(13))
                            .foregroundStyle(AppTheme.inkSoft)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.inkSoft)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? L("развёрнуто", "expanded") : L("свёрнуто", "collapsed"))
            .accessibilityHint(L("Показать или скрыть подробности", "Show or hide details"))

            if isOpen {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .padding(.bottom, isOpen ? 12 : 0)
        .parchmentCard(padding: 0)
    }
}

/// A small "i": the method behind a number, one tap away instead of a
/// paragraph under every figure.
struct AnalyticsInfoButton: View {
    let text: String
    @State private var isShown = false

    var body: some View {
        Button { isShown = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15))
                .foregroundStyle(AppTheme.inkSoft)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Как это считается", "How this is calculated"))
        .popover(isPresented: $isShown) {
            Text(text)
                .font(.lora(13))
                .foregroundStyle(AppTheme.ink)
                .padding(16)
                .frame(maxWidth: 320, alignment: .leading)
                .presentationCompactAdaptation(.popover)
                .background(AppTheme.parchmentCard)
        }
    }
}

/// A plain tappable row: title on the left, value and chevron on the right.
struct AnalyticsLinkRow: View {
    let title: String
    var subtitle: String?
    var value: String?
    var leading: AnyView?
    let action: () -> Void

    init(title: String, subtitle: String? = nil, value: String? = nil, leading: AnyView? = nil, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.leading = leading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let leading { leading }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.lora(14, weight: .medium))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(.lora(12))
                            .foregroundStyle(AppTheme.inkSoft)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.lora(14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.inkSoft)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail scaffold

/// The frame every pushed analytics screen shares: backdrop, a centred
/// column that never stretches across an iPad, the title, and the same
/// period menu — so the window chosen on the main screen carries through.
struct AnalyticsDetailScaffold<Content: View>: View {
    let title: String
    @Bindable var store: AnalyticsStore
    var showsPeriod = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            ForestBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if showsPeriod, !store.snapshot.overview.periodLabel.isEmpty {
                        Text(store.snapshot.overview.periodLabel)
                            .font(.lora(13))
                            .foregroundStyle(AppTheme.inkSoft)
                            .padding(.horizontal, 4)
                    }
                    content
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title)
                    .font(.lora(17, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
            }
            if showsPeriod {
                ToolbarItem(placement: .topBarTrailing) {
                    AnalyticsPeriodMenu(store: store)
                }
            }
        }
        .goblinChrome()
    }
}

/// A one-line "no data" note in place of a big empty card.
struct AnalyticsQuietNote: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.lora(13))
            .foregroundStyle(AppTheme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

/// A compact capsule button for the actions inside a card ("Записи дня"),
/// where the full-width `goblinSecondary` would shout.
struct AnalyticsSmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lora(13, weight: .semibold))
            .foregroundStyle(AppTheme.forestDeep)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Capsule().fill(AppTheme.parchmentCard))
            .overlay(Capsule().stroke(AppTheme.border, lineWidth: 1.25))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - Navigation hook

private struct AnalyticsOpenKey: EnvironmentKey {
    static let defaultValue: (AnalyticsRoute) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Pushes an analytics route. Set once by the analytics stack, so charts
    /// and rows deep inside a screen can lead on without threading a path
    /// (or the store) through every initializer.
    var analyticsOpen: (AnalyticsRoute) -> Void {
        get { self[AnalyticsOpenKey.self] }
        set { self[AnalyticsOpenKey.self] = newValue }
    }
}
