import SwiftUI
import AppKit

// MARK: - Jetons de couleur
//
// Chaque couleur a sa valeur claire et sa valeur sombre : l'interface suit l'apparence choisie
// (Auto, Clair, Sombre) sans qu'aucune vue n'ait à tester le thème. Les couleurs d'état sont
// réservées au sens (faille, à trancher, sain) ; l'ambre de la tasse est le seul accent.

extension Color {
    /// Couleur qui se résout selon l'apparence effective de la vue (clair ou sombre).
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

public enum Palette {
    public static let background = Color(light: 0xF5F5F7, dark: 0x1C1C1E)
    public static let bar = Color(light: 0xFBFBFC, dark: 0x232325)
    public static let sidebar = Color(light: 0xEEEEF0, dark: 0x252527)
    public static let surface = Color(light: 0xFFFFFF, dark: 0x2C2C2E)
    public static let text = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    public static let textSecondary = Color(light: 0x6E6E73, dark: 0xA1A1A6)
    public static let textTertiary = Color(light: 0x3A3A3C, dark: 0xD1D1D6)
    public static let line = Color(light: 0xE3E3E6, dark: 0x3A3A3C)
    public static let lineStrong = Color(light: 0xDCDCE0, dark: 0x48484A)
    public static let fill = Color(light: 0xF0F0F2, dark: 0x3A3A3C)
    public static let field = Color(light: 0xEDEDF0, dark: 0x3A3A3C)

    /// Ambre de la marque : fonds de boutons principaux et du logo (texte blanc dessus).
    public static let accent = Color(light: 0xB45309, dark: 0xB45309)
    /// Ambre lisible comme texte ou icône sur la surface.
    public static let accentText = Color(light: 0x9A4508, dark: 0xF5C27A)
    public static let accentBackground = Color(light: 0xFDF3E7, dark: 0x4A2E12)
    public static let accentLine = Color(light: 0xF0D2AE, dark: 0x6B4518)

    public static let danger = Color(light: 0xB42318, dark: 0xFF8A80)
    public static let dangerBackground = Color(light: 0xFEF0EE, dark: 0x4A1F1C)
    public static let dangerLine = Color(light: 0xF1C8C2, dark: 0x6B2A24)
    /// Fond plein des pastilles de compteur (texte blanc dessus).
    public static let dangerBadge = Color(light: 0xB42318, dark: 0xD92D20)
    public static let warning = Color(light: 0xB54708, dark: 0xFDB022)
    public static let warningBackground = Color(light: 0xFFF6E5, dark: 0x45320F)
    public static let warningMark = Color(light: 0xF79009, dark: 0xF79009)
    public static let success = Color(light: 0x067647, dark: 0x6CE9A6)
    public static let successBackground = Color(light: 0xECFDF3, dark: 0x123A26)
    public static let successMark = Color(light: 0x12B76A, dark: 0x32D583)
    public static let info = Color(light: 0x175CD3, dark: 0x84ADFF)
    public static let infoBackground = Color(light: 0xEFF4FF, dark: 0x1A2C4F)
    public static let unknownMark = Color(light: 0xAEAEB2, dark: 0x636366)

    public static let console = Color(light: 0x1D1D1F, dark: 0x121214)
    public static let consoleText = Color(light: 0xE5E5EA, dark: 0xE5E5EA)
}

/// Ton d'une pastille ou d'un badge : ce qu'il signifie, pas sa couleur.
public enum Tone {
    case danger, warning, success, info, neutral, accent

    public var foreground: Color {
        switch self {
        case .danger: return Palette.danger
        case .warning: return Palette.warning
        case .success: return Palette.success
        case .info: return Palette.info
        case .neutral: return Palette.textTertiary
        case .accent: return Palette.accentText
        }
    }

    public var background: Color {
        switch self {
        case .danger: return Palette.dangerBackground
        case .warning: return Palette.warningBackground
        case .success: return Palette.successBackground
        case .info: return Palette.infoBackground
        case .neutral: return Palette.fill
        case .accent: return Palette.accentBackground
        }
    }

    /// Couleur pleine, pour un point ou un segment de barre.
    public var mark: Color {
        switch self {
        case .danger: return Palette.dangerBadge
        case .warning: return Palette.warningMark
        case .success: return Palette.successMark
        case .info: return Palette.info
        case .neutral: return Palette.unknownMark
        case .accent: return Palette.accent
        }
    }
}

// MARK: - Apparence

/// Réglage d'apparence de l'application. « Auto » suit macOS.
public enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    public static let storageKey = "BrewHelper.Appearance"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    public var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// Appliqué à toute l'application : les couleurs dynamiques, les matériaux et les
    /// contrôles système basculent ensemble. `preferredColorScheme(nil)` ne revient pas
    /// toujours au réglage système sur macOS ; `NSApp.appearance = nil`, si.
    @MainActor
    public func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Typographie

public enum DesignSystem {
    // Les anciens dégradés deviennent des aplats : un seul accent, et les couleurs d'état
    // gardent leur sens. Les noms restent pour les vues qui les emploient.
    public enum Colors {
        public static let primaryGradient = LinearGradient(colors: [Palette.accent, Palette.accent], startPoint: .top, endPoint: .bottom)
        public static let amberGradient = LinearGradient(colors: [Palette.accent, Palette.accent], startPoint: .top, endPoint: .bottom)
        public static let greenGradient = LinearGradient(colors: [Palette.successMark, Palette.successMark], startPoint: .top, endPoint: .bottom)
        public static let purpleGradient = LinearGradient(colors: [Palette.textTertiary, Palette.textTertiary], startPoint: .top, endPoint: .bottom)

        public static let cardBackground = Palette.surface
        public static let sidebarBackground = Palette.sidebar
    }

    public enum Typography {
        public static let largeTitle = Font.system(size: 26, weight: .bold)
        public static let title = Font.system(size: 22, weight: .bold)
        public static let sectionHeader = Font.system(size: 15, weight: .bold)
        public static let body = Font.system(size: 13)
        public static let caption = Font.system(size: 11)
        public static let monospace = Font.system(size: 12, weight: .medium, design: .monospaced)
        public static let packageName = Font.system(size: 13, weight: .semibold, design: .monospaced)
    }
}

// MARK: - Composants

/// Carte de surface : fond plein, filet discret. Remplace le verre dépoli, illisible en sombre.
public struct GlassCard<Content: View>: View {
    let padding: CGFloat
    let content: Content

    public init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.line, lineWidth: 1))
    }
}

/// Pastille d'état, ton sémantique.
public struct Pill: View {
    let text: String
    let tone: Tone
    var icon: String? = nil

    public init(_ text: String, tone: Tone, icon: String? = nil) {
        self.text = text
        self.tone = tone
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .bold))
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundColor(tone.foreground)
        .background(tone.background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// « CLI » / « App » devant un nom de paquet.
public struct KindTag: View {
    let type: PackageType

    public init(_ type: PackageType) { self.type = type }

    public var body: some View {
        Text(type == .cask ? "App" : "CLI")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundColor(Palette.textTertiary)
            .background(Palette.fill)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// Pastille de compteur pleine (barre latérale, onglets).
public struct CountBadge: View {
    let count: Int
    let color: Color

    public init(_ count: Int, color: Color) {
        self.count = count
        self.color = color
    }

    public var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(color)
            .clipShape(Capsule())
    }
}

/// Bouton principal : aplat ambre, texte blanc.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundColor(.white)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Bouton secondaire : surface et filet. `destructive` le passe en rouge.
public struct SecondaryButtonStyle: ButtonStyle {
    var destructive: Bool = false
    public init(destructive: Bool = false) { self.destructive = destructive }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundColor(destructive ? Palette.danger : Palette.text)
            .background(configuration.isPressed ? Palette.fill : Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(destructive ? Palette.dangerLine : Palette.lineStrong, lineWidth: 1))
    }
}

/// Puce de filtre : noire (ou blanche en sombre) quand elle est active.
public struct FilterChip: View {
    let label: String
    let count: Int?
    let isOn: Bool
    let action: () -> Void

    public init(_ label: String, count: Int? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.label = label
        self.count = count
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 12, weight: .semibold))
                if let count = count {
                    Text("\(count)").font(.system(size: 12)).opacity(0.7)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(isOn ? Palette.background : Palette.text)
            .background(isOn ? Palette.text : Palette.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isOn ? Palette.text : Palette.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// En-tête de section : titre et précision sur la même ligne.
public struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(DesignSystem.Typography.sectionHeader).foregroundColor(Palette.text)
            if let subtitle = subtitle {
                Text(subtitle).font(DesignSystem.Typography.caption).foregroundColor(Palette.textSecondary)
            }
        }
    }
}

/// Ancien badge capsule, gardé pour les vues de détail : il prend la couleur qu'on lui donne.
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
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.16))
        .foregroundColor(color)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Bouton d'action d'origine : il garde son nom, prend le style du bouton principal.
public struct ActionButton: View {
    let title: String
    let icon: String
    let gradient: LinearGradient
    let action: () -> Void

    public init(title: String, icon: String, gradient: LinearGradient = DesignSystem.Colors.primaryGradient, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.gradient = gradient
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundColor(.white)
                .background(gradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
