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

/// The same five-step row for a `ScaleStep` that has no artwork — hunger,
/// appetite and fullness. Emoji and the step's position stand in for the
/// illustration, and the chosen step's name is spelled out underneath, so
/// the number never has to be read as a score.
///
/// Optional in exactly the way `LevelPickerRow` is: tapping the chosen step
/// again clears it back to "не отмечено", which is not the middle of the
/// scale and is never stored as one.
struct ScaleStepPickerRow<Step: ScaleStep>: View {
    @Binding var selection: Step?
    var accentColor: Color = AppTheme.forest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Step.orderedCases.reversed(), id: \.id) { step in
                    let isSelected = selection == step
                    Button {
                        selection = isSelected ? nil : step
                    } label: {
                        VStack(spacing: 2) {
                            Text(step.emoji)
                                .font(.system(size: 20))
                            Text("\(Int(step.scale))")
                                .font(.lora(12, weight: isSelected ? .semibold : .regular).monospacedDigit())
                                .foregroundStyle(isSelected ? accentColor : AppTheme.inkSoft)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? accentColor.opacity(0.18) : AppTheme.chipFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? accentColor : AppTheme.border, lineWidth: isSelected ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(step.label)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            Text(selection?.label ?? L("Не отмечено", "Not recorded"))
                .font(.lora(13, weight: selection == nil ? .regular : .medium))
                .foregroundStyle(selection == nil ? AppTheme.inkSoft : AppTheme.ink)
        }
    }
}
