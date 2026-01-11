# iOS 26 Liquid Glass - SwiftUI Reference

A comprehensive guide for implementing Apple's Liquid Glass design system in SwiftUI.

## Overview

Liquid Glass is Apple's new design language introduced in iOS 26 (WWDC 2025). It features:

- Real-time light bending (lensing)
- Specular highlights responding to device motion
- Adaptive shadows
- Interactive behaviors (scale, bounce, shimmer on press)

## Core Principle

**Liquid Glass is for the navigation layer, NOT content.**

Glass controls float on top of your app's content. Your main app content should NOT use glass styling.

Good use cases:

- Toolbars and navigation bars
- Tab bars
- Floating action buttons
- Modal overlays
- Floating menus

Bad use cases:

- Main content areas
- List items
- Text content

## Toolbar Buttons (Automatic Glass)

**iOS 26 automatically applies glass styling to toolbar buttons.** Don't add custom backgrounds!

```swift
// CORRECT - System applies glass automatically
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button("Done") {
            dismiss()
        }
    }

    ToolbarItem(placement: .topBarLeading) {
        Button {
            // action
        } label: {
            Image(systemName: "plus")
        }
    }
}
```

```swift
// WRONG - Custom backgrounds interfere with system glass
Button("Done") { }
    .background {
        Capsule().fill(.clear).glassEffect() // DON'T DO THIS
    }
```

## Button Styles

For buttons outside of toolbars, use the built-in glass button styles:

```swift
// Glass button style (standard)
Button("Action") { }
    .buttonStyle(.glass)

// Prominent glass button style
Button("Primary Action") { }
    .buttonStyle(.glassProminent)
```

**Note:** `.buttonStyle(.glass)` applies its own sizing and padding. Don't combine with custom frames.

## The glassEffect Modifier

For custom views (not buttons), use the `glassEffect` modifier:

```swift
// Basic glass effect (capsule shape by default)
Text("Label")
    .padding()
    .glassEffect()

// With specific shape
Text("Label")
    .padding()
    .glassEffect(in: .circle)
    .glassEffect(in: .capsule)
    .glassEffect(in: RoundedRectangle(cornerRadius: 12))
```

## Glass Variants

```swift
// Regular (default) - medium transparency, full adaptivity
.glassEffect(.regular)

// Clear - high transparency for media-rich backgrounds
.glassEffect(.clear)

// With tint color
.glassEffect(.regular.tint(.purple.opacity(0.8)))
```

## Interactive Glass

For custom controls that need press feedback (scale, bounce, shimmer):

```swift
// Interactive - responds to touch with shimmer effect
.glassEffect(.regular.interactive())

// Combining options
.glassEffect(.regular.tint(.blue).interactive())
```

## Custom Buttons with Glass Background

When you need custom-sized buttons outside toolbars:

```swift
// Custom button with glass background
Button(action: { /* action */ }) {
    Image(systemName: "gearshape.fill")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 38, height: 38)
}
.background {
    if #available(iOS 26.0, *) {
        Circle().fill(.clear).glassEffect(.regular.interactive())
    } else {
        Circle().fill(.ultraThinMaterial)
    }
}
```

## GlassEffectContainer

Groups multiple glass elements so they blend together and can morph:

```swift
GlassEffectContainer {
    HStack(spacing: 8) {
        Button("Home") { }.glassEffect()
        Button("Settings") { }.glassEffect()
        Button("Profile") { }.glassEffect()
    }
}
```

**Why use it:**

- Glass cannot sample other glass
- Container lets elements share sampling region
- Enables morphing transitions between states
- Consistent visual behavior

## Morphing Transitions

Create fluid animations between glass elements:

```swift
@Namespace private var glassNamespace

GlassEffectContainer {
    if isExpanded {
        HStack {
            Button("A") { }
                .glassEffect()
                .glassEffectID("buttonA", in: glassNamespace)
            Button("B") { }
                .glassEffect()
                .glassEffectID("buttonB", in: glassNamespace)
        }
    } else {
        Button("Menu") { }
            .glassEffect()
            .glassEffectID("buttonA", in: glassNamespace)
    }
}
```

## Pre-iOS 26 Fallback Pattern

```swift
@ViewBuilder
func glassButton(action: @escaping () -> Void, icon: String) -> some View {
    Button(action: action) {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 44, height: 44)
    }
    .background {
        if #available(iOS 26.0, *) {
            Circle().fill(.clear).glassEffect(.regular.interactive())
        } else {
            Circle().fill(.ultraThinMaterial)
        }
    }
}
```

## Common Mistakes

### 1. Using buttonStyle(.glass) with custom frames

```swift
// WRONG - buttonStyle(.glass) has its own sizing
Button { } label: {
    Image(systemName: "plus")
        .frame(width: 38, height: 38) // Ignored or conflicts
}
.buttonStyle(.glass)

// CORRECT - use background with glassEffect instead
Button { } label: {
    Image(systemName: "plus")
        .frame(width: 38, height: 38)
}
.background {
    Circle().fill(.clear).glassEffect(.regular.interactive())
}
```

### 2. Adding backgrounds to toolbar buttons

```swift
// WRONG - interferes with system styling
.toolbar {
    ToolbarItem {
        Button("Done") { }
            .background { Capsule().glassEffect() } // Don't!
    }
}

// CORRECT - let system handle it
.toolbar {
    ToolbarItem {
        Button("Done") { }
    }
}
```

### 3. Overusing glass on content

```swift
// WRONG - glass is for navigation, not content
List {
    ForEach(items) { item in
        Text(item.name)
            .glassEffect() // Don't do this!
    }
}

// CORRECT - glass for floating controls only
ZStack {
    List { /* content */ }

    VStack {
        Spacer()
        GlassEffectContainer {
            floatingToolbar
        }
    }
}
```

## Summary

| Context                | Approach                                               |
| ---------------------- | ------------------------------------------------------ |
| Toolbar buttons        | Plain `Button()` - system applies glass                |
| Custom overlay buttons | `.background { .glassEffect(.regular.interactive()) }` |
| Standard glass buttons | `.buttonStyle(.glass)`                                 |
| Grouped glass elements | Wrap in `GlassEffectContainer`                         |
| Pre-iOS 26             | Fallback to `.ultraThinMaterial`                       |

## References

- [Apple Developer Documentation - Applying Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [WWDC25 - Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Apple Newsroom - Liquid Glass Announcement](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
