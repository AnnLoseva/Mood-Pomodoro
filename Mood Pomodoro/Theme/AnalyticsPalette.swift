//
//  AnalyticsPalette.swift
//  Mood Pomodoro
//
//  One colour per measured thing, used the same way in the diary chart, the
//  analytics charts, the comparison and the metric details. Colour here
//  *names a series*; it never says "good" or "bad". (The mood-level scale in
//  `MoodColorScale` is the other thing — colour of a level — and stays apart.)
//

import SwiftUI
import Charts

/// The shape a series is marked with, so two series never differ by colour
/// alone. Drawn by the diary's canvas and mirrored by Swift Charts symbols.
enum SeriesShape: String, Sendable, CaseIterable {
    case circle, square, triangle, diamond, plus

    var chartSymbol: BasicChartSymbolShape {
        switch self {
        case .circle: return .circle
        case .square: return .square
        case .triangle: return .triangle
        case .diamond: return .diamond
        case .plus: return .plus
        }
    }

    /// SF Symbol for legends and chips (filled when `filled`).
    func symbolName(filled: Bool) -> String {
        switch self {
        case .circle: return filled ? "circle.fill" : "circle"
        case .square: return filled ? "square.fill" : "square"
        case .triangle: return filled ? "triangle.fill" : "triangle"
        case .diamond: return filled ? "diamond.fill" : "diamond"
        case .plus: return "plus"
        }
    }

    func path(center: CGPoint, radius r: CGFloat) -> Path {
        switch self {
        case .circle:
            return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        case .square:
            let s = r * 0.9
            return Path(CGRect(x: center.x - s, y: center.y - s, width: s * 2, height: s * 2))
        case .triangle:
            var p = Path()
            p.move(to: CGPoint(x: center.x, y: center.y - r * 1.1))
            p.addLine(to: CGPoint(x: center.x + r * 1.05, y: center.y + r * 0.85))
            p.addLine(to: CGPoint(x: center.x - r * 1.05, y: center.y + r * 0.85))
            p.closeSubpath()
            return p
        case .diamond:
            var p = Path()
            p.move(to: CGPoint(x: center.x, y: center.y - r * 1.2))
            p.addLine(to: CGPoint(x: center.x + r * 1.2, y: center.y))
            p.addLine(to: CGPoint(x: center.x, y: center.y + r * 1.2))
            p.addLine(to: CGPoint(x: center.x - r * 1.2, y: center.y))
            p.closeSubpath()
            return p
        case .plus:
            let t = r * 0.42
            var p = Path()
            p.addRect(CGRect(x: center.x - r, y: center.y - t, width: r * 2, height: t * 2))
            p.addRect(CGRect(x: center.x - t, y: center.y - r, width: t * 2, height: r * 2))
            return p
        }
    }
}

enum AnalyticsPalette {
    /// sRGB components, kept as plain numbers so contrast can be checked
    /// without a UI context (see `AnalyticsPaletteTests`).
    struct RGB: Sendable, Equatable {
        let r: Double, g: Double, b: Double

        init(hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }

        var color: Color { Color(red: r, green: g, blue: b) }

        /// WCAG relative luminance.
        var luminance: Double {
            func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }

        func darkened(_ factor: Double) -> RGB {
            RGB(r: r * factor, g: g * factor, b: b * factor)
        }

        private init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

        func contrast(against other: RGB) -> Double {
            let a = luminance, b = other.luminance
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }

    /// The card surface every chart sits on (`AppTheme.parchmentCard`).
    static let surface = RGB(hex: 0xF6EFDD)

    // Starting hues from the brief, nudged only where a 3 pt line on the
    // parchment card fell under 3:1 (energy, satiety, appetite).
    static let mood = RGB(hex: 0x438F84)
    static let energy = RGB(hex: 0xA47C33)
    static let motivation = RGB(hex: 0x9666AD)
    static let hunger = RGB(hex: 0xB57038)
    static let appetite = RGB(hex: 0xC4608A)
    static let sleep = RGB(hex: 0x6578B1)
    static let activity = RGB(hex: 0x70865A)

    /// Text in a series colour: the same hue, darkened until it reads at 4.5:1.
    static func text(_ rgb: RGB) -> RGB { rgb.darkened(0.66) }
}
