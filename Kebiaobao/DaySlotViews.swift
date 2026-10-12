import SwiftUI

/// 单行展示某天的安排，点击进入编辑
struct DaySlotRow: View {
    let slot: DaySlot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(slot.dayName.replacingOccurrences(of: "周", with: ""))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(KB.accent)
                    .frame(width: 34, height: 34)
                    .background(KB.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.timeText)
                        .font(.system(.callout, weight: .semibold)).foregroundStyle(KB.text)
                    HStack(spacing: 8) {
                        if !slot.teacher.isEmpty {
                            Label(slot.teacher, systemImage: "person")
                        }
                        if !slot.place.isEmpty {
                            Label(slot.place, systemImage: "mappin.and.ellipse")
                        }
                    }
                    .font(.system(.caption)).foregroundStyle(KB.dim)
                    .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption)).foregroundStyle(KB.dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 某一天的详细设置：时间 / 老师 / 地点
struct DaySlotEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let weekday: Int
    let slot: DaySlot
    let onSave: (DaySlot) -> Void

    @State private var time: Date
    @State private var teacher: String
    @State private var place: String

    init(weekday: Int, slot: DaySlot, onSave: @escaping (DaySlot) -> Void) {
        self.weekday = weekday
        self.slot = slot
        self.onSave = onSave
        _time = State(initialValue: Calendar.current.date(
            from: DateComponents(hour: slot.hour, minute: slot.minute)) ?? Date())
        _teacher = State(initialValue: slot.teacher)
        _place = State(initialValue: slot.place)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                VStack(spacing: 14) {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            DatePicker("上课时间", selection: $time,
                                       displayedComponents: .hourAndMinute)
                                .font(.system(.subheadline))
                                .padding(.vertical, 10)
                            Divider()
                            FieldRow(label: "老师", text: $teacher, placeholder: "老师姓名")
                            Divider()
                            FieldRow(label: "地点", text: $place, placeholder: "如：少年宫3楼")
                        }
                        .padding(.horizontal, 16)
                    }
                    KBButton(title: "保存这一天的设置") {
                        let c = Calendar.current
                        var s = slot
                        s.hour = c.component(.hour, from: time)
                        s.minute = c.component(.minute, from: time)
                        s.teacher = teacher
                        s.place = place
                        onSave(s)
                        dismiss()
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("\(KBDate.weekdayName(weekday))的安排")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}
