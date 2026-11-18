import SwiftUI
import UIKit

extension Color {
    /// A colour with separate light and dark values.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Theme {
    static let bg        = Color.dyn(0xFFF2F7, 0x22131B)
    static let dot       = Color.dyn(0xFFD9E8, 0x33192A)
    static let surface   = Color.dyn(0xFFFFFF, 0x2E1925)
    static let surface2  = Color.dyn(0xFFE6F0, 0x3B2030)
    static let line      = Color.dyn(0xF7CBDC, 0x583246)
    static let ink       = Color.dyn(0x4A2236, 0xFFE6F1)
    static let muted     = Color.dyn(0xA06483, 0xD79BB9)
    static let accent    = Color.dyn(0xE0528B, 0xFF8FBD)
    static let accent2   = Color.dyn(0xFF9FC3, 0xC4558A)
    static let shelf     = Color.dyn(0xF3A8C4, 0x8A3D61)
    static let shelfEdge = Color.dyn(0xD97CA1, 0x6A2C4A)
    static let read      = Color.dyn(0x2F8A63, 0x8FE0BB)
    static let readBg    = Color.dyn(0xDCF5E8, 0x1C3A2D)
    static let reading   = Color.dyn(0xA8600C, 0xFFCF80)
    static let readingBg = Color.dyn(0xFFEDCF, 0x3D2C14)
    static let loan      = Color.dyn(0x7B4FC4, 0xCBB0FF)
    static let loanBg    = Color.dyn(0xEEE4FD, 0x30254A)
    static let unread    = Color.dyn(0xB2457A, 0xF8B9D6)
    static let unreadBg  = Color.dyn(0xFFE3EE, 0x3B2030)

    static let spines: [Color] = [
        Color(UIColor(hex: 0xE0528B)), Color(UIColor(hex: 0xC2709B)), Color(UIColor(hex: 0x9B6FD0)),
        Color(UIColor(hex: 0xEF8AA8)), Color(UIColor(hex: 0xD4789B)), Color(UIColor(hex: 0xB85C8E)),
        Color(UIColor(hex: 0xE9A07A)), Color(UIColor(hex: 0x7F8FD6)),
    ]

    static func spine(for title: String) -> Color {
        var h = 0
        for u in title.unicodeScalars { h = (h &* 31 &+ Int(u.value)) % 360 }
        return spines[abs(h) % spines.count]
    }

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// Polka-dot paper background.
struct DotBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 22
            var y: CGFloat = 0
            while y < size.height + step {
                var x: CGFloat = 0
                while x < size.width + step {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3.2, height: 3.2)), with: .color(Theme.dot))
                    x += step
                }
                y += step
            }
        }
        .background(Theme.bg)
        .ignoresSafeArea()
    }
}

struct Pill: View {
    let text: String
    let fg: Color
    let bg: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(bg, in: Capsule())
            .lineLimit(1)
    }
}

struct StatusPill: View {
    let status: ReadStatus
    var body: some View {
        switch status {
        case .read: Pill(text: "Read", fg: Theme.read, bg: Theme.readBg)
        case .reading: Pill(text: "Reading", fg: Theme.reading, bg: Theme.readingBg)
        case .unread: Pill(text: "To be read", fg: Theme.unread, bg: Theme.unreadBg)
        }
    }
}

/// A book cover, or a coloured spine with the title when there's no photo.
struct CoverView: View {
    let book: Book
    var width: CGFloat = 46

    var body: some View {
        let h = width * 1.45
        ZStack(alignment: .topTrailing) {
            Group {
                if let data = book.coverData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ZStack(alignment: .bottomLeading) {
                        Theme.spine(for: book.title)
                        Text(book.title.split(separator: " ").prefix(3).joined(separator: " "))
                            .font(.system(size: width * 0.24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .padding(4)
                    }
                }
            }
            .frame(width: width, height: h)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 8, topTrailingRadius: 8))
            .overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.15)).frame(width: 3) }

            if book.status == .reading {
                Ribbon().fill(Theme.accent).frame(width: 9, height: 18).offset(x: -6, y: -2)
            }
        }
        .frame(width: width, height: h)
    }
}

struct Ribbon: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY - r.height * 0.25))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Small stack-of-books logo with a heart.
struct BookStackLogo: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.loan.opacity(0.75)).frame(width: 38, height: 10).padding(.leading, 2)
                RoundedRectangle(cornerRadius: 3).fill(Theme.accent2).frame(width: 42, height: 10).padding(.leading, 4)
                RoundedRectangle(cornerRadius: 3).fill(Theme.accent).frame(width: 48, height: 10)
            }
            .padding(.top, 16)
            Image(systemName: "heart.fill").font(.system(size: 15)).foregroundStyle(Theme.accent).offset(x: 2, y: 0)
        }
        .frame(width: 54, height: 50)
        .accessibilityHidden(true)
    }
}
