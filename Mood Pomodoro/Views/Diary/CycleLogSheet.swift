//
//  CycleLogSheet.swift
//  Mood Pomodoro
//

import SwiftUI

/// Marks a cycle event on one day. Two options and a way to undo them —
/// nothing to predict, nothing to diagnose, and nothing that has to be
/// filled in for the rest of the app to work.
struct CycleLogSheet: View {
    @Environment(CycleStore.self) private var cycleStore
    @Environment(\.dismiss) private var dismiss

    let date: Date

    private var existing: [CycleEventKind] { cycleStore.events(on: date) }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.parchmentCard.ignoresSafeArea()

                VStack(spacing: 18) {
                    Text(DateFormatting.fullDate(date))
                        .font(.lora(15))
                        .foregroundStyle(AppTheme.inkSoft)

                    if let day = cycleStore.cycleDay(for: date) {
                        Text("День цикла: \(day)")
                            .font(.lora(17, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                    }

                    VStack(spacing: 12) {
                        ForEach(CycleEventKind.allCases, id: \.self) { kind in
                            Button {
                                cycleStore.log(kind, on: date)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Text(kind.icon)
                                        .font(.system(size: 22))
                                    Text(kind.label)
                                        .font(.lora(16, weight: .medium))
                                        .foregroundStyle(AppTheme.ink)
                                    Spacer()
                                    if existing.contains(kind) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AppTheme.forest)
                                    }
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(AppTheme.parchment.opacity(0.55))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(AppTheme.border, lineWidth: 1.25)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !existing.isEmpty {
                        Button("Убрать отметку", role: .destructive) {
                            cycleStore.clear(on: date)
                            dismiss()
                        }
                        .font(.lora(14))
                        .foregroundStyle(AppTheme.rustDeep)
                    }

                    Text("Это личный контекст для наблюдений. Приложение ничего не предсказывает и не ставит диагнозов.")
                        .font(.lora(12))
                        .foregroundStyle(AppTheme.inkSoft)
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("🌸 Цикл")
                        .font(.lora(17, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                        .font(.lora(15))
                        .foregroundStyle(AppTheme.forest)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
