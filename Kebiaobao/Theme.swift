import SwiftUI
import UIKit

enum KB {
    /// 跟随系统亮/暗自动切换
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static let accent = dyn(0x53B4A4, 0x5FC4B3)
    static let accentSoft = dyn(0xE6F4F1, 0x1B3A35)
    static let bg = dyn(0xF7F7F9, 0x0B0B0D)
    static let card = dyn(0xFFFFFF, 0x1C1C1E)
    static let text = dyn(0x1C1C1E, 0xF2F2F5)
    static let dim = dyn(0x8A8A8E, 0x9A9A9F)
    static let line = dyn(0xECECEF, 0x2C2C2E)
    static let warn = dyn(0xF5A524, 0xF5A524)
    static let danger = dyn(0xE06A6A, 0xE88080)
    /// 强调色上的文字（两套主题下都用白字，accent 足够深）
    static let onAccent = Color.white
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// 白色圆角卡片
struct Card<Content: View>: View {
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
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(KB.line, lineWidth: 1)
            )
    }
}

/// 页面大标题
struct NavHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(KB.text)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
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
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(filled ? KB.onAccent : tint)
            .background(filled ? tint : KB.card)
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
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 12))
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
            Text(label).font(.system(size: 14)).foregroundStyle(KB.dim)
            Spacer()
            Text(value).font(.system(size: 14, weight: .medium)).foregroundStyle(valueColor)
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
                .font(.system(size: 15))
                .foregroundStyle(KB.text)
                .frame(width: 96, alignment: .leading)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }
}
