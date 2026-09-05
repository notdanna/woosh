// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Shared look & feel: brand colors, card styling and the brand mark.
enum Theme {
    /// Near-black background behind the brand mark. Neutral greys into black, no
    /// colour cast, with just a hint of depth so the badge does not read as flat.
    static let spaceGradient = LinearGradient(
        colors: [Color(white: 0.10),
                 Color(white: 0.04),
                 Color.black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Shared corner-radius scale. Using these instead of ad-hoc numbers keeps
/// nested shapes concentric, which matters for Liquid Glass: a card whose
/// radius does not relate to its container's radius looks visibly wrong
/// once the surface is refractive instead of a flat tint.
enum PanelRadius {
    /// Small chips, badges, tiny inline controls.
    static let chip: CGFloat = 6
    /// Buttons, list rows, small controls.
    static let control: CGFloat = 8
    /// Standard panel card (`panelCard()`).
    static let card: CGFloat = 10
    /// Secondary panels/inspectors (e.g. the clipboard preview sidebar).
    static let surface: CGFloat = 14
    /// Primary panel/HUD container (`panelGlassSurface()`'s default).
    static let panel: CGFloat = 18
    /// Spotlight-style floating windows (CommandBar, QuickLauncher, Switcher).
    static let window: CGFloat = 22
}

enum PanelMetricColor {
    static func green(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.18) : .green
    }

    static func cyan(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.43, blue: 0.54) : .cyan
    }

    static func mint(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.00, green: 0.44, blue: 0.40) : .mint
    }

    static func yellow(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.56, green: 0.36, blue: 0.00) : .yellow
    }

    static func red(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.08, blue: 0.10) : .red
    }

    static func orange(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.30, blue: 0.00) : .orange
    }

    static func pink(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.68, green: 0.06, blue: 0.34) : .pink
    }
}

enum PanelSurface {
    static func baseFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.48) : Color.black.opacity(0.62)
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.white.opacity(0.24) : Color.white.opacity(0.045)
    }

    static func controlFill(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.04) : Color.white.opacity(0.055)
    }

    static func border(for scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.07) : Color.white.opacity(0.085)
    }
}

func sectionTitle(_ text: String) -> some View {
    Text(text.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(.secondary)
}

extension View {
    /// The rounded card background used by every panel section. Cards live
    /// *inside* an already-glass container (`panelGlassSurface()`), so this
    /// intentionally stays a flat tint rather than glass of its own — two
    /// stacked glass layers double-refract and read as muddy.
    func panelCard() -> some View {
        modifier(PanelCardModifier())
    }

    /// A restrained glass base for the menu panel: still translucent, but with a
    /// stable tint so text and controls do not depend too much on the wallpaper.
    /// Real Liquid Glass (`.glassEffect`) on macOS 26+; falls back to the
    /// previous material-based look on older systems.
    func panelGlassSurface(cornerRadius: CGFloat = PanelRadius.panel) -> some View {
        modifier(PanelGlassSurfaceModifier(cornerRadius: cornerRadius))
    }

    /// Same treatment as `panelGlassSurface()` but for a container that owns
    /// an arbitrary `Shape` instead of always wanting a rounded rect — e.g. a
    /// full-bleed window background with square corners.
    func glassSurface<S: Shape>(in shape: S, tinted: Bool = true) -> some View {
        modifier(DynamicGlassSurfaceModifier(shape: shape, tinted: tinted))
    }

    /// Applies the centralized macOS 26 Liquid Glass button style.
    func panelGlassButton(
        isActive: Bool = false,
        isProminent: Bool = false,
        isDestructive: Bool = false,
        cornerRadius: CGFloat = PanelRadius.control,
        size: CGFloat? = nil
    ) -> some View {
        buttonStyle(PanelGlassButtonStyle(
            cornerRadius: cornerRadius,
            isActive: isActive,
            isProminent: isProminent,
            isDestructive: isDestructive,
            size: size
        ))
    }
}

/// Centralized macOS 26 Liquid Glass button style for compact, responsive,
/// translucent controls that adapt seamlessly to active/selected, hovered and pressed states.
struct PanelGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = PanelRadius.control
    var isActive: Bool = false
    var isProminent: Bool = false
    var isDestructive: Bool = false
    var size: CGFloat? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foregroundColor(isPressed: configuration.isPressed))
            .frame(width: size, height: size)
            .padding(size == nil ? 5 : 0)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor(isPressed: configuration.isPressed), lineWidth: 0.7)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        if isDestructive { return .red }
        if isProminent { return .white }
        if isActive { return .accentColor }
        return .primary.opacity(isPressed ? 0.7 : 0.9)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isProminent {
            return isDestructive
                ? Color.red.opacity(isPressed ? 0.75 : 0.9)
                : Color.accentColor.opacity(isPressed ? 0.75 : 0.9)
        }
        if isActive {
            return Color.accentColor.opacity(colorScheme == .light ? (isPressed ? 0.22 : 0.16) : (isPressed ? 0.30 : 0.22))
        }
        if isDestructive {
            return Color.red.opacity(colorScheme == .light ? (isPressed ? 0.15 : 0.08) : (isPressed ? 0.22 : 0.12))
        }
        let base = PanelSurface.controlFill(for: colorScheme)
        return isPressed ? base.opacity(1.5) : base
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isProminent { return Color.clear }
        if isActive { return Color.accentColor.opacity(0.4) }
        if isDestructive { return Color.red.opacity(0.35) }
        return PanelSurface.border(for: colorScheme)
    }
}

/// Reusable icon-only button with full Liquid Glass styling, standard tooltips and accessibility.
struct PanelIconButton: View {
    let icon: String
    var title: String? = nil
    let help: String
    var isActive: Bool = false
    var isProminent: Bool = false
    var isDestructive: Bool = false
    var size: CGFloat = 24
    var iconSize: CGFloat = 11.5
    var cornerRadius: CGFloat = PanelRadius.control
    var symbolWeight: Font.Weight = .semibold
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: symbolWeight))
                .frame(width: size, height: size)
        }
        .buttonStyle(PanelGlassButtonStyle(
            cornerRadius: cornerRadius,
            isActive: isActive,
            isProminent: isProminent,
            isDestructive: isDestructive,
            size: size
        ))
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
        .help(help)
        .accessibilityLabel(title ?? help)
    }
}

private struct PanelCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: PanelRadius.card, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PanelRadius.card, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            )
    }
}

private struct PanelGlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.fill(PanelSurface.baseFill(for: colorScheme).opacity(0.35)))
                        .glassEffect(.regular, in: shape)
                }
        } else {
            content.background(LegacyPanelGlassSurface(cornerRadius: cornerRadius))
        }
    }
}

private struct DynamicGlassSurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let shape: S
    let tinted: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(tinted ? shape.fill(PanelSurface.baseFill(for: colorScheme).opacity(0.35)) : nil)
                        .glassEffect(.regular, in: shape)
                }
        } else {
            content.modifier(LegacyGlassSurfaceModifier(shape: shape, tinted: tinted))
        }
    }
}

/// Pre-macOS 26 fallback: the original hand-built vibrancy (regularMaterial
/// + tint + manual border), kept byte-for-byte so older systems don't
/// regress while newer ones get real Liquid Glass.
private struct LegacyPanelGlassSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PanelSurface.baseFill(for: colorScheme).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
            )
    }
}

private struct LegacyGlassSurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let shape: S
    let tinted: Bool

    func body(content: Content) -> some View {
        content.background(
            shape
                .fill(.regularMaterial)
                .overlay(tinted ? shape.fill(PanelSurface.baseFill(for: colorScheme).opacity(0.5)) : nil)
        )
    }
}

func appDelegate() -> AppDelegate? {
    NSApp.delegate as? AppDelegate
}

/// The official mark (Resources/Brand/logo.png, trimmed at build time),
/// tintable for light or dark surfaces.
struct BrandMark: View {
    var width: CGFloat
    var tint: Color = .white

    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "BrandMark", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let mark = Self.mark {
            Image(nsImage: mark)
                .renderingMode(.template)
                .interpolation(.high)
                .antialiased(true)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width)
        } else {
            Image(systemName: "circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: width * 0.5)
        }
    }
}

struct DiscordMark: View {
    var width: CGFloat

    private static let mark: NSImage? = {
        guard let url = Bundle.main.url(forResource: "discord-symbol",
                                        withExtension: "svg",
                                        subdirectory: "Images") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let mark = Self.mark {
            Image(nsImage: mark)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: width)
        }
    }
}

/// Squircle badge with the mark on the space gradient — the app's face in the
/// About tab and onboarding.
struct BrandBadge: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.spaceGradient)
            BrandMark(width: size * 0.8)
        }
        .frame(width: size, height: size)
    }
}
