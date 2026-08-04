import SwiftUI

// MARK: - App Design Tokens & Styling
public enum DesignSystem {
    // Colors
    public enum Colors {
        public static let primaryGradient = LinearGradient(
            gradient: Gradient(colors: [Color(hue: 0.58, saturation: 0.85, brightness: 0.95), Color(hue: 0.65, saturation: 0.90, brightness: 0.85)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        public static let amberGradient = LinearGradient(
            gradient: Gradient(colors: [Color.orange, Color.red]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        public static let greenGradient = LinearGradient(
            gradient: Gradient(colors: [Color.green, Color.mint]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        public static let purpleGradient = LinearGradient(
            gradient: Gradient(colors: [Color.purple, Color.indigo]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        public static let cardBackground = Color(NSColor.controlBackgroundColor).opacity(0.6)
        public static let sidebarBackground = Color(NSColor.underPageBackgroundColor).opacity(0.8)
    }
    
    // Typography
    public enum Typography {
        public static let title = Font.system(size: 26, weight: .bold, design: .rounded)
        public static let sectionHeader = Font.system(size: 18, weight: .semibold, design: .rounded)
        public static let body = Font.system(size: 13, weight: .regular, design: .default)
        public static let monospace = Font.system(size: 12, weight: .medium, design: .monospaced)
    }
}

// MARK: - Reusable UI Components

public struct GlassCard<Content: View>: View {
    let content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        content
            .padding(16)
            .background(.regularMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

public struct StatusBadge: View {
    let text: String
    let color: Color
    let icon: String?
    
    public init(text: String, color: Color, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .foregroundColor(color)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.4), lineWidth: 0.5)
        )
    }
}

public struct ActionButton: View {
    let title: String
    let icon: String
    let gradient: LinearGradient
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    public init(title: String, icon: String, gradient: LinearGradient = DesignSystem.Colors.primaryGradient, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.gradient = gradient
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(gradient)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.1), radius: isHovered ? 6 : 3, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovered = hover
        }
    }
}
