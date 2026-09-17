//
//  AppTheme.swift
//  Mood Pomodoro
//
//  Goblincore visual language: warm parchment, forest greens, mushroom
//  characters instead of emoji, Lora serif type. Centralized here so every
//  screen pulls from the same handful of tokens instead of re-deriving them.
//

import SwiftUI
import UIKit

enum AppTheme {
    // MARK: - Colors

    /// Page background — the warm tan the forest illustration sits on.
    static let parchment = Color(red: 0.925, green: 0.878, blue: 0.773)
    /// Card/sheet surface — a touch lighter than the page so content reads as raised.
    static let parchmentCard = Color(red: 0.965, green: 0.937, blue: 0.867)
    /// Primary text — bark brown, never pure black (keeps the cozy, hand-inked feel).
    static let ink = Color(red: 0.290, green: 0.220, blue: 0.149)
    static let inkSoft = Color(red: 0.290, green: 0.220, blue: 0.149).opacity(0.62)
    /// Primary action color — forest green.
    static let forest = Color(red: 0.310, green: 0.400, blue: 0.271)
    static let forestDeep = Color(red: 0.204, green: 0.271, blue: 0.180)
    /// Accent — the mushroom-cap rust/terracotta.
    static let rust = Color(red: 0.659, green: 0.365, blue: 0.208)
    static let rustDeep = Color(red: 0.518, green: 0.271, blue: 0.145)
    static let moss = Color(red: 0.486, green: 0.545, blue: 0.353)
    static let border = Color(red: 0.788, green: 0.722, blue: 0.576)
    static let borderSoft = Color(red: 0.788, green: 0.722, blue: 0.576).opacity(0.55)
    /// Opaque chip/field fill — slightly deeper than the card, never see-through.
    static let chipFill = Color(red: 0.945, green: 0.906, blue: 0.812)
}

extension View {
    /// Light parchment chrome so system controls never render white-on-cream
    /// and navigation/tab bars never sit as transparent glass over the forest.
    func goblinChrome() -> some View {
        self
            .preferredColorScheme(.light)
            .tint(AppTheme.forest)
            .toolbarBackground(AppTheme.parchmentCard, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(AppTheme.parchmentCard, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarColorScheme(.light, for: .tabBar)
    }

    /// Root tabs keep actions in the content, not in the system navigation bar.
    func hideRootNavigationBar() -> some View {
        self
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("")
    }
}

enum AppChrome {
    static func apply() {
        let ink = UIColor(AppTheme.ink)
        let inkSoft = UIColor(AppTheme.inkSoft)
        let forest = UIColor(AppTheme.forest)
        let card = UIColor(AppTheme.parchmentCard)
        let page = UIColor(AppTheme.parchment)
        let border = UIColor(AppTheme.border)

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = card
        nav.shadowColor = border
        nav.titleTextAttributes = [
            .foregroundColor: ink,
            .font: UIFont(name: "Lora-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = forest
        UINavigationBar.appearance().overrideUserInterfaceStyle = .light

        let item = UITabBarItemAppearance()
        item.normal.iconColor = inkSoft
        item.normal.titleTextAttributes = [.foregroundColor: inkSoft]
        item.selected.iconColor = forest
        item.selected.titleTextAttributes = [.foregroundColor: UIColor(AppTheme.forestDeep)]

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = card
        tab.shadowColor = border
        tab.stackedLayoutAppearance = item
        tab.inlineLayoutAppearance = item
        tab.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().overrideUserInterfaceStyle = .light

        UITextField.appearance().textColor = ink
        UITextView.appearance().textColor = ink
        UIDatePicker.appearance().overrideUserInterfaceStyle = .light
        UITableView.appearance().backgroundColor = page
        UISwitch.appearance().onTintColor = forest
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).overrideUserInterfaceStyle = .light
    }
}

// MARK: - Typography

extension Font {
    static func lora(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "Lora-Bold"
        case .semibold: name = "Lora-SemiBold"
        case .medium: name = "Lora-Medium"
        default: name = "Lora-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    static func loraItalic(_ size: CGFloat) -> Font {
        .custom("LoraItalic-Italic", size: size, relativeTo: .body)
    }
}

// MARK: - Backdrop

/// The illustrated forest frame, used full-bleed behind a screen with real
/// content floating over it in a `parchmentCard`. iPad gets its own wider
/// composition (`IpadBackground`) rather than a stretched phone frame.
struct ForestBackdrop: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { proxy in
            Image(horizontalSizeClass == .regular ? "IpadBackground" : "ForestBackground")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .background(AppTheme.parchment)
        .ignoresSafeArea()
    }
}

// MARK: - Card surface

private struct ParchmentCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.parchmentCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1.25)
            )
            .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func parchmentCard(padding: CGFloat = 20) -> some View {
        modifier(ParchmentCardModifier(padding: padding))
    }
}

// MARK: - Buttons

struct GoblinButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case destructive
    }

    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.lora(17, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Capsule(style: .continuous).fill(background))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(strokeColor, lineWidth: kind == .secondary ? 1.5 : 0)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary: AppTheme.forest
        case .secondary: AppTheme.parchmentCard
        case .destructive: AppTheme.rustDeep
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive: AppTheme.parchmentCard
        case .secondary: AppTheme.ink
        }
    }

    private var strokeColor: Color {
        AppTheme.border
    }
}

extension ButtonStyle where Self == GoblinButtonStyle {
    static var goblinPrimary: GoblinButtonStyle { GoblinButtonStyle(kind: .primary) }
    static var goblinSecondary: GoblinButtonStyle { GoblinButtonStyle(kind: .secondary) }
    static var goblinDestructive: GoblinButtonStyle { GoblinButtonStyle(kind: .destructive) }
}
