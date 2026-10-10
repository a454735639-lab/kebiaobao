import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var store: Store
    @State private var month = Date()
    @State private var selected = KBDate.day(Date())
    @State private var addSheet = false

    private let cal = KBDate.cal

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        monthCard
                        dayCard
                        Color.clear.frame(height: 80)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HStack {
                    Text("课表日程")
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(KB.text)
                    Spacer()
                    Button { addSheet = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(KB.accent).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(KB.bg)
            }
            .sheet(isPresented: $addSheet) {
                TemplateEditorView(template: nil, courseID: store.courses(for: store.currentBabyID).first?.id)
            }
        }
    }

    // MARK: - 月历

    private var monthCard: some View {
        Card(padding: 14) {
            VStack(spacing: 12) {
                HStack {
                    Button { shift(-1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KB.text)
                    }
                    Text(monthTitle)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(KB.text)
                        .frame(maxWidth: .infinity)
                    Button { shift(1) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KB.text)
                    }
                }
                HStack(spacing: 0) {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { w in
                        Text(w).font(.system(size: 12)).foregroundStyle(KB.dim)
                            .frame(maxWidth: .infinity)
                    }
                }
                grid
            }
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: month)
    }

    private func shift(_ n: Int) {
        if let d = cal.date(byAdding: .month, value: n, to: month) { month = d }
    }

    /// 周一起始的 6 行网格
    private var gridDays: [Date?] {
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = 1
        guard let first = cal.date(from: comps),
              let count = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        // 周一=1 … 周日=7
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        var arr: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count {
            arr.append(cal.date(byAdding: .day, value: i, to: first))
        }
        while arr.count % 7 != 0 { arr.append(nil) }
        return arr
    }

    private var grid: some View {
        let days = gridDays
        let rows = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, d in
                        dayCell(d).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ d: Date?) -> some View {
        if let d {
            let has = !store.lessons(on: d, babyID: store.currentBabyID).isEmpty
            let isSel = KBDate.isSameDay(d, selected)
            let isToday = KBDate.isSameDay(d, Date())
            Button { selected = d } label: {
                VStack(spacing: 3) {
                    Text("\(cal.component(.day, from: d))")
                        .font(.system(size: 14, weight: isSel || isToday ? .semibold : .regular))
                        .foregroundStyle(isSel ? .white : (isToday ? KB.accent : KB.text))
                        .frame(width: 30, height: 30)
                        .background(isSel ? KB.accent : Color.clear)
                        .clipShape(Circle())
                    Circle()
                        .fill(has ? (isSel ? Color.clear : KB.accent) : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .frame(height: 40)
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 40)
        }
    }

    // MARK: - 当天

    private var dayCard: some View {
        let items = store.lessons(on: selected, babyID: store.currentBabyID)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(selected, format: .dateTime.month().day())\(KBDate.weekdayName(cal.component(.weekday, from: selected)))")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                if items.isEmpty {
                    Text("当天暂无排课")
                        .font(.system(size: 13)).foregroundStyle(KB.dim)
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                } else {
                    ForEach(items) { t in row(t) }
                }
            }
        }
    }

    private func row(_ t: LessonTemplate) -> some View {
        let c = store.course(t.courseID)
        return HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(t.timeText)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(KB.accent)
                Text("\(t.deduct)节").font(.system(size: 10)).foregroundStyle(KB.dim)
            }
            .frame(width: 52)
            Rectangle().fill(KB.accent).frame(width: 3, height: 34)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 3) {
                Text(c?.name ?? "课程")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(KB.text)
                Text([t.teacher, t.place].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
            }
            Spacer()
            Button {
                store.checkIn(t, on: selected)
            } label: {
                Text("扣课")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(KB.accent).clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(KB.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 打卡确认
struct CheckInSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let template: LessonTemplate
    let date: Date

    @State private var deduct: Int = 1
    @State private var note = "正常上课"

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                VStack(spacing: 14) {
                    Card {
                        VStack(spacing: 12) {
                            InfoRow(label: "课程", value: store.course(template.courseID)?.name ?? "—")
                            InfoRow(label: "时间", value: "\(KBDate.mdhm.string(from: date).prefix(10)) \(template.timeText)")
                            InfoRow(label: "老师", value: template.teacher.isEmpty ? "—" : template.teacher)
                            InfoRow(label: "剩余",
                                    value: "\(store.course(template.courseID).map { store.remaining($0) } ?? 0) 节")
                        }
                    }
                    Card {
                        VStack(spacing: 0) {
                            HStack {
                                Text("本次划扣").font(.system(size: 15)).foregroundStyle(KB.text)
                                Spacer()
                                Stepper("\(deduct) 课时", value: $deduct, in: 1...10)
                                    .labelsHidden()
                                Text("\(deduct) 课时")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(KB.accent).frame(width: 62, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            Divider()
                            FieldRow(label: "备注", text: $note, placeholder: "正常上课")
                        }
                    }
                    KBButton(title: "确认扣课 \(deduct) 课时", icon: "checkmark.circle.fill") {
                        var t = template
                        t.deduct = deduct
                        store.checkIn(t, on: date)
                        if !note.isEmpty, note != "正常上课",
                           let i = store.ledger.indices.last {
                            store.ledger[i].note = note
                            store.save()
                        }
                        dismiss()
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("课时打卡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .onAppear { deduct = max(1, template.deduct) }
    }
}
