//
//  ConditionChip.swift
//  Mood Pomodoro
//

import SwiftUI

/// Display-only value for a condition, shared by the New Session picker and
/// the active-session summary — both just need an icon + name to render.
struct ConditionChip: Identifiable, Hashable {
    let id: UUID
    let icon: String
    let iconImageName: String?
    let name: String

    init(id: UUID, icon: String, iconImageName: String? = nil, name: String) {
        self.id = id
        self.icon = icon
        self.iconImageName = iconImageName
        self.name = name
    }

    init(category: FactorCategory, option: FactorOption) {
        self.id = category.id
        self.icon = category.icon
        self.iconImageName = option.iconImageName ?? category.iconImageName
        self.name = option.name
    }
}

extension ConditionSnapshotEntry {
    var asChip: ConditionChip {
        ConditionChip(id: categoryID, icon: categoryIcon, iconImageName: resolvedIconImageName, name: optionName)
    }
}

/// A condition's icon — the illustrated artwork when available, else the emoji.
struct FactorIconView: View {
    let icon: String
    let iconImageName: String?
    var size: CGFloat = 20

    var body: some View {
        if let iconImageName {
            Image(iconImageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Text(icon).font(.system(size: size * 0.85))
        }
    }
}

/// The compact "🎧 Lo-fi  ☕ Пуэр  🌙 Недосып" row + action button, used both
/// when picking conditions for a new session and when reviewing/changing
/// them mid-session. Deliberately terse — conditions are meant to take
/// seconds to set, not a form to fill out.
struct ConditionsSummaryView: View {
    let title: String
    let chips: [ConditionChip]
    let actionTitle: String
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.lora(14, weight: .medium))
                .foregroundStyle(AppTheme.inkSoft)

            if !chips.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(chips) { chip in
                        HStack(spacing: 5) {
                            FactorIconView(icon: chip.icon, iconImageName: chip.iconImageName, size: 18)
                            Text(chip.name)
                                .font(.lora(13, weight: .medium))
                                .foregroundStyle(AppTheme.ink)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous).fill(AppTheme.parchment.opacity(0.6))
                        )
                        .overlay(Capsule(style: .continuous).stroke(AppTheme.border, lineWidth: 1))
                    }
                }
            }

            Button(action: onTap) {
                Text(actionTitle)
                    .font(.lora(13, weight: .medium))
                    .foregroundStyle(AppTheme.forest)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Minimal wrapping HStack — condition chips vary a lot in width and a plain
/// HStack would just run off-screen.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
