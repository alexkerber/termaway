import SwiftUI
import UIKit

// MARK: - Glass Circle Button (for icon buttons like +, gear, scroll)
/// A circular button with iOS 26 liquid glass effect
/// Use for: floating action buttons, icon-only buttons in custom overlays
struct GlassCircleButton: View {
    let icon: String
    let size: CGFloat
    var iconSize: CGFloat? = nil
    var color: Color = .primary
    let action: () -> Void

    init(
        icon: String,
        size: CGFloat = 38,
        iconSize: CGFloat? = nil,
        color: Color = .primary,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.iconSize = iconSize
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: iconSize ?? (size * 0.4), weight: .semibold))
                .foregroundStyle(color.opacity(0.9))
                .frame(width: size, height: size)
        }
        .background {
            if #available(iOS 26.0, *) {
                Circle().fill(.clear).glassEffect(.regular.interactive())
            } else {
                Circle().fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Glass Pill Button (for text buttons like "Connected", "Settings")
/// A pill-shaped button with iOS 26 liquid glass effect
/// Use for: status indicators, text buttons in custom overlays
struct GlassPillButton: View {
    let action: () -> Void
    let content: () -> AnyView

    init<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.action = action
        self.content = { AnyView(content()) }
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background {
            if #available(iOS 26.0, *) {
                Capsule().fill(.clear).glassEffect(.regular.interactive())
            } else {
                Capsule().fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Glass Rounded Button (for larger buttons like "Settings" with icon)
/// A rounded rectangle button with iOS 26 liquid glass effect
/// Use for: larger action buttons, settings buttons
struct GlassRoundedButton: View {
    let action: () -> Void
    var cornerRadius: CGFloat = 12
    let content: () -> AnyView

    init<Content: View>(
        cornerRadius: CGFloat = 12,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.action = action
        self.content = { AnyView(content()) }
    }

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            content()
        }
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular.interactive())
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Connection Status Pill
/// Shows connection status with green dot and "Connected" text
struct ConnectionStatusPill: View {
    var isConnected: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        if let action = action {
            GlassPillButton(action: action) {
                statusContent
            }
        } else {
            statusContent
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background {
                    if #available(iOS 26.0, *) {
                        Capsule().fill(.clear).glassEffect()
                    } else {
                        Capsule().fill(.ultraThinMaterial)
                    }
                }
        }
    }

    private var statusContent: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(isConnected ? "Connected" : "Disconnected")
                .font(.subheadline.weight(.medium))
        }
        .foregroundColor(isConnected ? .green : .red)
    }
}

// MARK: - Glass Settings Button
/// Settings button with gear icon and "Settings" text
struct GlassSettingsButton: View {
    let action: () -> Void

    var body: some View {
        GlassRoundedButton(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.subheadline)
                Text("Settings")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Glass Effect Container Wrapper
/// Wraps content in GlassEffectContainer on iOS 26, passes through on older versions
struct AdaptiveGlassContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Toolbar Glass Modifier
/// Enables glass effects for toolbar buttons in sheets on iOS 18+
struct ToolbarGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.toolbarBackgroundVisibility(.visible, for: .navigationBar)
        } else {
            content
        }
    }
}

// MARK: - Glass Pill Modifier (for shortcuts toolbar)
/// Applies iOS 26 liquid glass capsule effect with animation support
/// Use for: toolbar items that need coordinated glass transitions
struct GlassPillModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let iconColor: SwiftUI.Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID(id, in: namespace)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black.opacity(0.8).ignoresSafeArea()

        VStack(spacing: 20) {
            // Circle buttons
            HStack(spacing: 12) {
                GlassCircleButton(icon: "plus", action: {})
                GlassCircleButton(icon: "gearshape.fill", action: {})
                GlassCircleButton(icon: "arrow.down.to.line", size: 44, action: {})
            }

            // Pill buttons
            ConnectionStatusPill(action: {})

            // Settings button
            GlassSettingsButton(action: {})
        }
    }
}
