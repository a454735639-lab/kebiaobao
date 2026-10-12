import SwiftUI
import UIKit

enum KB {
    /// 跟随系统亮/暗自动切换
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let accent = dyn(0x37796D, 0x5FC4B3)
    static let accentSoft = dyn(0xE6F4F1, 0x1B3A35)
    static let bg = dyn(0xF7F7F9, 0x0B0B0D)
    static let card = dyn(0xFFFFFF, 0x1C1C1E)
    static let text = dyn(0x1C1C1E, 0xF2F2F5)
    static let dim = dyn(0x6E6E73, 0x9A9A9F)
    static let line = dyn(0xECECEF, 0x2C2C2E)
    static let warn = dyn(0xA06C17, 0xF5A524)
    static let danger = dyn(0xBB5858, 0xE88080)
    /// 强调色上的文字：亮色模式用白，暗色模式的 accent 变亮所以改用墨色
    static let onAccent = dyn(0xFFFFFF, 0x0B0B0D)
    /// 强调色上的警示数字（逾期/欠费）：跟 onAccent 反着来才在渐变两端都可读
    static let onAccentWarn = dyn(0xFFF0D8, 0x4A3200)
    /// 节假日 / 补班 / 节气徽章（文字在自身 0.14 淡底上也要过 4.5:1）
    static let holidayRed = dyn(0xA44F50, 0xE27676)
    static let makeupGold = dyn(0x7D6633, 0xC9A24D)
    static let termBlue = dyn(0x476A99, 0x6F9AD5)

    /// 强调色渐变（图标块 / 头像 / 主按钮）。顶端压暗，保证白/墨字在两端都过 4.5:1
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent.brightness(-0.06), accent],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// 课程色：作为文字/白字底色都要过 4.5:1
    /// 亮色向墨色混 46%，暗色向白混 28%（脚本按 10 色全表求解的最小值）
    static func course(_ hex: UInt32) -> Color {
        Color(UIColor { style in
            let c = UIColor(hex: hex)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            if style.userInterfaceStyle == .dark {
                return UIColor(red: r * 0.72 + 0.28,
                               green: g * 0.72 + 0.28,
                               blue: b * 0.72 + 0.28, alpha: 1)
            }
            return UIColor(red: r * 0.54 + 0.0198,
                           green: g * 0.54 + 0.0198,
                           blue: b * 0.54 + 0.0198, alpha: 1)
        })
    }

    /// 课程色的浅底（用于 chip / 徽章背景），跟 course() 同源保证文字可读
    static func courseSoft(_ hex: UInt32) -> Color { course(hex).opacity(0.16) }
}

/// 白色圆角卡片
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = 16
    var content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KB.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(KB.line, lineWidth: 1)
            )
            // 深色模式靠描边分层，浅色模式补一层极淡投影
            .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.045),
                    radius: 9, x: 0, y: 4)
    }
}

/// 进度条
struct KBProgress: View {
    let value: Int
    let total: Int
    var color: Color = KB.accent

    private var ratio: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(total)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(KB.line)
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * ratio))
            }
        }
        .frame(height: 8)
    }
}

/// 主按钮
struct KBButton: View {
    let title: String
    var icon: String? = nil
    var filled: Bool = true
    var tint: Color = KB.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.system(.subheadline, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(filled ? KB.onAccent : tint)
            .background(filled
                        ? AnyShapeStyle(LinearGradient(colors: [tint.brightness(-0.06), tint],
                                                       startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(KB.card))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(filled ? Color.clear : KB.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 统计格子
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = KB.accent

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(.caption))
                .foregroundStyle(KB.dim)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 行：左标题右内容
struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = KB.text

    var body: some View {
        HStack {
            Text(label).font(.system(.subheadline)).foregroundStyle(KB.dim)
            Spacer()
            Text(value).font(.system(.subheadline, weight: .medium)).foregroundStyle(valueColor)
        }
    }
}

/// 输入行
struct FieldRow: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack {
            Text(label)
                .font(.system(.subheadline))
                .foregroundStyle(KB.text)
                .frame(width: 96, alignment: .leading)
            TextField(placeholder, text: $text)
                .font(.system(.subheadline))
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }
}

// MARK: - 版式组件（v1.11.0）

/// 卡片小节标题：图标块 + 标题 + 右侧附加内容
struct SectionHeader<Trailing: View>: View {
    let icon: String
    let title: String
    var tint: Color = KB.accent
    let trailing: () -> Trailing

    init(icon: String, title: String, tint: Color = KB.accent,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.icon = icon
        self.title = title
        self.tint = tint
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 8) {
            IconBadge(icon: icon, tint: tint)
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(KB.text)
            Spacer(minLength: 6)
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(icon: String, title: String, tint: Color = KB.accent) {
        self.init(icon: icon, title: title, tint: tint) { EmptyView() }
    }
}

/// 小圆角图标块
struct IconBadge: View {
    let icon: String
    var tint: Color = KB.accent
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.56, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

/// 胶囊小标签（比裸 Text + background 少一层重复代码）
struct KBChip: View {
    let text: String
    var tint: Color = KB.accent
    var solid: Bool = false

    var body: some View {
        Text(text)
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(solid ? KB.onAccent : tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(solid ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)))
            .clipShape(Capsule())
    }
}

/// 课程色竖条 + 内容（首页课程行左侧色带）
struct ColorRail: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 3.5)
    }
}

/// 空态提示：图标 + 标题 + 说明
struct EmptyHint: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(.title, weight: .light))
                .foregroundStyle(KB.accent.opacity(0.45))
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(KB.text.opacity(0.75))
            if let message {
                Text(message)
                    .font(.system(.caption))
                    .foregroundStyle(KB.dim)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}
