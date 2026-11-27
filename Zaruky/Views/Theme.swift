import SwiftUI

/// Design tokens shared by every screen. Brand green lives in the asset catalog (AccentColor);
/// the status colours carry meaning (green = covered, orange = act now, grey = over).
enum Theme {
    static let cardRadius: CGFloat = 22
    static let tileRadius: CGFloat = 14
    static let pagePadding: CGFloat = 16

    static let brand = Color.accentColor
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.16)
}

extension WarrantyStatus {
    var color: Color {
        switch self {
        case .expiringSoon: .orange
        case .active: Theme.brand
        case .expired: .gray
        }
    }

    var symbol: String {
        switch self {
        case .expiringSoon: "exclamationmark.circle.fill"
        case .active: "checkmark.shield.fill"
        case .expired: "clock.badge.xmark"
        }
    }
}

/// Content-layer card: a solid, slightly raised surface on the grouped background. No glass.
struct CardBackground: ViewModifier {
    var radius: CGFloat = Theme.cardRadius

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

extension View {
    func card(radius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardBackground(radius: radius))
    }
}

/// Guesses a fitting SF Symbol for a product from its name, so every receipt gets a
/// recognisable picture without the user doing anything. Czech and English keywords.
enum ProductIcon {
    private static let table: [(String, [String])] = [
        ("iphone", ["iphone", "telefon", "mobil", "phone", "galaxy", "pixel", "xiaomi", "smartphone"]),
        ("laptopcomputer", ["macbook", "notebook", "laptop", "thinkpad", "chromebook"]),
        ("desktopcomputer", ["imac", "počítač", "pocitac", "computer", "pc ", "monitor"]),
        ("ipad", ["ipad", "tablet"]),
        ("applewatch", ["watch", "hodinky"]),
        ("headphones", ["sluchátk", "sluchatk", "airpods", "headphone", "earbuds", "buds", "wh-1000", "wf-1000", "bose", "jbl"]),
        ("tv", ["televiz", "tv", "oled", "qled"]),
        ("hifispeaker.fill", ["reprodukt", "speaker", "soundbar", "repro"]),
        ("camera.fill", ["fotoaparát", "fotoaparat", "camera", "kamera", "gopro", "objektiv"]),
        ("gamecontroller.fill", ["playstation", "xbox", "nintendo", "switch", "konzole", "ps5", "gamepad"]),
        ("washer.fill", ["pračk", "prack", "washer", "washing"]),
        ("dishwasher.fill", ["myčk", "myck", "dishwasher"]),
        ("refrigerator.fill", ["lednic", "chladni", "fridge", "refrigerator", "mrazák", "mrazak"]),
        ("oven.fill", ["trouba", "sporák", "sporak", "oven", "mikrovl", "microwave"]),
        ("cup.and.saucer.fill", ["kávovar", "kavovar", "espresso", "coffee", "nespresso", "delonghi"]),
        ("fanblades.fill", ["vysavač", "vysavac", "vacuum", "dyson", "roomba"]),
        ("bicycle", ["kolo", "bike", "bicycle", "koloběž", "kolobez", "scooter"]),
        ("car.fill", ["auto", "pneu", "car ", "tyre", "tire"]),
        ("sofa.fill", ["gauč", "gauc", "sedačk", "sedack", "sofa", "nábytek", "nabytek", "postel", "matrace", "ikea"]),
        ("tshirt.fill", ["bunda", "boty", "tričk", "trick", "oblečen", "obleceni", "jacket", "shoes", "sneakers"]),
        ("hammer.fill", ["vrtačk", "vrtack", "drill", "nářad", "narad", "bosch", "makita", "šroubov", "sroubov"]),
        ("printer.fill", ["tiskárn", "tiskarn", "printer"]),
        ("wifi.router.fill", ["router", "wifi", "mesh"]),
        ("lightbulb.fill", ["lampa", "světlo", "svetlo", "lamp", "light", "hue"]),
        ("stroller.fill", ["kočár", "kocar", "stroller", "autosedačk"]),
    ]

    static func symbol(for name: String) -> String {
        let n = " " + name.lowercased() + " "
        for (symbol, keys) in table where keys.contains(where: { n.contains($0) }) {
            return symbol
        }
        return "bag.fill"
    }
}

/// Rounded square with the product's symbol, tinted with the warranty status.
struct ProductTile: View {
    let name: String
    let status: WarrantyStatus
    var size: CGFloat = 46

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(status.color.opacity(status == .expired ? 0.14 : 0.16).gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: ProductIcon.symbol(for: name))
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(status == .expired ? Color.secondary : status.color)
            }
            .accessibilityHidden(true)
    }
}

/// Ring that empties as the warranty runs out.
struct WarrantyRing: View {
    let remaining: Double   // 0...1
    let color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(remaining, 0.001))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
