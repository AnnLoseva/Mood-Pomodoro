//
//  LevelPicker.swift
//  Mood Pomodoro
//

import SwiftUI

/// A `LevelScale`'s illustration at a consistent size — the generic twin of
/// `MoodImage`, used for energy and motivation.
struct LevelImage<Level: LevelScale>: View {
    let level: Level
    var size: CGFloat = 44

    var body: some View {
        Image(level.imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

/// One row of five illustrations, best first, for picking a level.
///
/// The selection is optional and stays that way: energy and motivation are
/// things she *may* note alongside a mood, never a second and third
/// question she has to answer to save one. Tapping the chosen one again
/// clears it back to "не отмечено".
struct LevelPickerRow<Level: LevelScale>: View {
    @Binding var selection: Level?
    var size: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Level.orderedCases) { level in
                    Button {
                        selection = selection == level ? nil : level
                    } label: {
                        LevelImage(level: level, size: size)
                            .padding(5)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selection == level ? AppTheme.forest.opacity(0.18) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        selection == level ? AppTheme.forest : AppTheme.border,
                                        lineWidth: selection == level ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(level.label)
                    .accessibilityAddTraits(selection == level ? [.isSelected] : [])
                }
            }
            Text(selection?.label ?? L("Не отмечено", "Not recorded"))
                .font(.lora(13, weight: selection == nil ? .regular : .medium))
                .foregroundStyle(selection == nil ? AppTheme.inkSoft : AppTheme.ink)
        }
    }
}
