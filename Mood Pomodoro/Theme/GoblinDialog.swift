//
//  GoblinDialog.swift
//  Mood Pomodoro
//
//  A themed stand-in for `.confirmationDialog` — the system action sheet
//  reads jarringly plain against the parchment/forest look, so destructive
//  confirmations (finish/cancel a session) get this instead: a small
//  parchment card over a dimmed backdrop.
//

import SwiftUI

private struct GoblinConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String?
    let confirmTitle: String
    let isDestructive: Bool
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented = false }

                    VStack(spacing: 18) {
                        Text("🍄")
                            .font(.system(size: 32))
                        Text(title)
                            .font(.lora(19, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .multilineTextAlignment(.center)
                        if let message {
                            Text(message)
                                .font(.lora(14))
                                .foregroundStyle(AppTheme.inkSoft)
                                .multilineTextAlignment(.center)
                        }
                        VStack(spacing: 10) {
                            Button(confirmTitle) {
                                isPresented = false
                                onConfirm()
                            }
                            .buttonStyle(isDestructive ? .goblinDestructive : .goblinPrimary)

                            Button("Отмена") { isPresented = false }
                                .buttonStyle(.goblinSecondary)
                        }
                    }
                    .padding(26)
                    .frame(maxWidth: 320)
                    .parchmentCard()
                    .padding(.horizontal, 32)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isPresented)
                .zIndex(10)
            }
        }
    }
}

extension View {
    /// A parchment-styled confirmation popup, in place of `.confirmationDialog`.
    func goblinConfirmation(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        confirmTitle: String,
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(
            GoblinConfirmationModifier(
                isPresented: isPresented,
                title: title,
                message: message,
                confirmTitle: confirmTitle,
                isDestructive: isDestructive,
                onConfirm: onConfirm
            )
        )
    }
}
