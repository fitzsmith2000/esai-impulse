// Adapted from Licoy/codex-runway, revision 411240f4bd758e8d5f788b94e4187ba161374ebb.
// AGPL-3.0; see THIRD_PARTY_NOTICES.md and Resources/Licenses/CodexRunway-AGPL-3.0.txt.
// Modified for esai: component names and visibility; upstream rendering behavior retained.

import AppKit
import SwiftUI

/// Design tokens for the popover panel. One radius scale, two surface levels,
/// hairline strokes and monochrome hover fills — every view must draw from here
/// instead of ad-hoc grays so light and dark stay tuned in one place.
enum EsaiSurface {
    // MARK: Radii (all continuous corners)

    /// Icon-button hover pills, segmented-tab thumb.
    static let radiusControl: CGFloat = 5
    /// Disclosure rows, date fields, buttons, row hover pills.
    static let radiusRow: CGFloat = 6
    /// Stat cards, table containers, hero card, account cards.
    static let radiusCard: CGFloat = 10
    /// Tier badge / expiry chip plates.
    static let radiusPlate: CGFloat = 5

    /// Legacy alias while non-panel views migrate.
    static let cornerRadius: CGFloat = 8

    // MARK: Surfaces

    /// Opaque panel fill when the user turns off popover translucency.
    static let panel = Color(nsColor: .windowBackgroundColor)

    /// Cards and interactive rows sitting on the panel.
    static let raised = dynamic(
        light: NSColor.black.withAlphaComponent(0.045),
        dark: NSColor.white.withAlphaComponent(0.065))
    /// Table containers, progress-bar tracks, segmented-tab well.
    static let sunken = dynamic(
        light: NSColor.black.withAlphaComponent(0.03),
        dark: NSColor.white.withAlphaComponent(0.045))
    /// Contrast band behind table column headers.
    static let tableHead = dynamic(
        light: NSColor.black.withAlphaComponent(0.04),
        dark: NSColor.white.withAlphaComponent(0.05))

    /// Legacy aliases (settings panes still use these).
    static let fill = raised
    static let subtleFill = sunken

    // MARK: Strokes

    /// Section separators, card strokes. `separatorColor` already carries its own
    /// low alpha — multiply it, never replace it (`withAlphaComponent` would paint
    /// a 60% black bar).
    static let hairline = Color(nsColor: .separatorColor)
    /// Table row separators.
    static let hairlineFaint = Color(nsColor: .separatorColor).opacity(0.55)

    // MARK: Hover fills (monochrome; accent hover is reserved for CTAs)

    static let hoverNeutral = dynamic(
        light: NSColor.black.withAlphaComponent(0.06),
        dark: NSColor.white.withAlphaComponent(0.09))
    static let hoverAccent = Color.accentColor.opacity(0.12)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        })
    }
}

/// Card chrome per scheme: light gets a translucent gray wash that blends into
/// the panel background — no outline, no shadow (both read as clutter there);
/// dark keeps translucent fills with a hairline stroke carrying the elevation.
struct EsaiCardSurface: ViewModifier {
    enum Kind {
        case raised
        case sunken
    }

    var kind: Kind
    var cornerRadius: CGFloat = EsaiSurface.radiusCard

    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(kind == .raised ? EsaiSurface.raised : EsaiSurface.sunken)
            }
            .overlay {
                if colorScheme == .dark {
                    shape.strokeBorder(EsaiSurface.hairline, lineWidth: 1)
                }
            }
    }
}

extension View {
    func esaiCard(
        _ kind: EsaiCardSurface.Kind = .raised,
        cornerRadius: CGFloat = EsaiSurface.radiusCard) -> some View
    {
        modifier(EsaiCardSurface(kind: kind, cornerRadius: cornerRadius))
    }
}

import AppKit
import SwiftUI

/// Balanced cursor for hoverable controls. `NSCursor.push/pop` is an
/// app-global stack, so every push must be matched even when the hovered view is
/// removed by its own click action (SwiftUI delivers no closing onHover then) or
/// the control becomes disabled mid-hover.
private struct EsaiCursor: ViewModifier {
    var cursor: NSCursor
    var isEnabled: Bool

    @State private var isHovering = false
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                sync()
            }
            .onChange(of: isEnabled) { _ in
                sync()
            }
            .onDisappear {
                isHovering = false
                sync()
            }
    }

    private func sync() {
        let wantsCursor = isHovering && isEnabled
        guard wantsCursor != pushed else { return }
        pushed = wantsCursor
        if wantsCursor {
            cursor.push()
        } else {
            NSCursor.pop()
        }
    }
}

extension View {
    /// Shows the pointing-hand cursor while hovered; pops it when the pointer
    /// leaves, the control disables, or the view unmounts.
    func pointingHandCursor(enabled: Bool = true) -> some View {
        modifier(EsaiCursor(cursor: .pointingHand, isEnabled: enabled))
    }

    /// Shows the vertical resize cursor while hovering a draggable panel edge.
    func verticalResizeCursor(enabled: Bool = true) -> some View {
        modifier(EsaiCursor(cursor: .resizeUpDown, isEnabled: enabled))
    }
}

struct EsaiHeaderActionButton<Icon: View>: View {
    var title: String
    var isLoading: Bool = false
    var action: () -> Void
    @ViewBuilder var icon: Icon

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    icon.frame(width: 14, height: 14)
                }
            }
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .frame(width: 26, height: 24)
            .background(
                isHovered ? EsaiSurface.hoverNeutral : Color.clear,
                in: RoundedRectangle(cornerRadius: EsaiSurface.radiusControl, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: EsaiSurface.radiusControl, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovered = $0 }
    }
}

/// Leading back affordance on detail pages (chevron + label, quiet until hovered).
struct EsaiDetailBackButton: View {
    var title: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(isHovered ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isHovered ? EsaiSurface.hoverNeutral : Color.clear,
                in: RoundedRectangle(cornerRadius: EsaiSurface.radiusRow, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: EsaiSurface.radiusRow, style: .continuous))
            .padding(.leading, -8)
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
    }
}

/// Quiet borderless footer button; destructive role surfaces red only on hover.
struct EsaiFooterGhostButton: View {
    enum Role {
        case normal
        case destructive
    }

    var title: String
    var systemImage: String
    var role: Role
    var help: String
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.medium))
                Text(title)
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                hoverFill,
                in: RoundedRectangle(cornerRadius: EsaiSurface.radiusRow, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: EsaiSurface.radiusRow, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isHovered)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        guard isHovered else { return .secondary }
        switch role {
        case .normal:
            return .primary
        case .destructive:
            return colorScheme == .light
                ? Color(red: 0.75, green: 0.12, blue: 0.15)
                : Color(nsColor: .systemRed)
        }
    }

    private var hoverFill: Color {
        guard isHovered else { return .clear }
        switch role {
        case .normal:
            return EsaiSurface.hoverNeutral
        case .destructive:
            return Color(nsColor: .systemRed).opacity(0.10)
        }
    }
}

struct EsaiHairline: View { var body: some View { Rectangle().fill(EsaiSurface.hairline).frame(height:1) } }

/// Keep switch alignment consistent across full-width settings rows.
struct EsaiSwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(spacing:12) {
            Text(title).font(.callout.weight(.medium))
            Spacer(minLength:12)
            Toggle(title,isOn:$isOn)
                .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
                .accessibilityLabel(title)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
