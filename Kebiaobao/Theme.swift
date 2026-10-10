import SwiftUI
import UIKit

enum KB {
    static let accent = Color(red: 0x53 / 255, green: 0xB4 / 255, blue: 0xA4 / 255)
    static let accentSoft = Color(red: 0xE6 / 255, green: 0xF4 / 255, blue: 0xF1 / 255)
    static let bg = Color(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF9 / 255)
    static let card = Color.white
    static let text = Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
    static let dim = Color(red: 0x8A / 255, green: 0x8A / 255, blue: 0x8E / 255)
    static let line = Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xEF / 255)
    static let warn = Color(red: 0xF5 / 255, green: 0xA5 / 255, blue: 0x24 / 255)
    static let danger = Color(red: 0xE0 / 255, green: 0x6A / 255, blue: 0x6A / 255)
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
            .foregroundStyle(filled ? Color.white : tint)
            .background(filled ? tint : Color.white)
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
