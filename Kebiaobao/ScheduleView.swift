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
        let s = t.slot(for: KBDate.cal.component(.weekday, from: selected))
        return HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(s.timeText)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(KB.accent)
                Text("\(t.deduct)节").font(.system(size: 10)).foregroundStyle(KB.dim)
            }
            .frame(width: 52)
            Rectangle().fill(KB.accent).frame(width: 3, height: 34)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 3) {
                Text(c?.name ?? "课程")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(KB.text)
                Text([s.teacher, s.place].filter { !$0.isEmpty }.joined(separator: " · "))
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
struct ManualEntryEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    /// 预填：课程、操作类型、课时数、日期。任一为 nil 则用默认
    var preset: (course: UUID?, op: Store.ManualOp, lessons: Int, date: Date)?

    let onDone: () -> Void

    @State private var op: Store.ManualOp = .consume
    @State private var courseID: UUID?
    @State private var lessonsText = "1"
    @State private var date = Date()
    @State private var price = ""
    @State private var note = ""
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("操作").font(.system(size: 15, weight: .semibold))
                                HStack(spacing: 8) {
                                    opChip(.consume, "扣课时", KB.warn)
                                    opChip(.leave, "请假", KB.dim)
                                    opChip(.charge, "加课时", KB.accent)
                                }
                            }
                        }
                        Card {
                            Button { showPicker = true } label: {
                                HStack {
                                    Text("选择课程").font(.system(size: 15))
                                        .foregroundStyle(courseID == nil ? KB.dim : KB.text)
                                    Spacer()
                                    if let id = courseID {
                                        Text(store.course(id)?.name ?? "—")
                                            .font(.system(size: 15, weight: .medium))
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 12))
                                        .foregroundStyle(KB.dim)
                                }
                                .padding(.vertical, 11)
                            }
                            .buttonStyle(.plain)
                        }
                        Card {
                            HStack(alignment: .center) {
                                Text("课时数").font(.system(size: 15))
                                Spacer()
                                HStack(spacing: 14) {
                                    stepBtn("minus", -1)
                                    TextField("1", text: $lessonsText)
                                        .keyboardType(.numberPad)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .multilineTextAlignment(.center)
                                        .frame(width: 56)
                                    stepBtn("plus", 1)
                                }
                            }
                        }
                        Card {
                            HStack {
                                Text("日期").font(.system(size: 15))
                                Spacer()
                                DatePicker("", selection: $date, displayedComponents: .date)
                                    .labelsHidden()
                            }
                        }
                        if op == .charge {
                            Card {
                                HStack {
                                    Text("单价").font(.system(size: 15))
                                    Spacer()
                                    HStack(spacing: 6) {
                                        Image(systemName: "yensign").foregroundStyle(KB.dim)
                                        TextField("沿用原单价", text: $price)
                                            .keyboardType(.decimalPad)
                                            .font(.system(size: 15))
                                            .multilineTextAlignment(.trailing)
                                    }
                                    .frame(width: 130)
                                }
                            }
                        }
                        Card {
                            HStack(alignment: .top) {
                                Text("备注").font(.system(size: 15))
                                Spacer()
                                TextField(Store.manualDefaultNote(op), text: $note)
                                    .font(.system(size: 15))
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 200)
                            }
                        }
                        KBButton(title: "保存", icon: "checkmark") { save() }
                            .disabled(courseID == nil)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                if let id = courseID {
                    Text("当前：\(store.course(id)?.name ?? "") · 剩余 \(store.remaining(store.course(id)!)) 课时")
                        .font(.system(size: 12)).foregroundStyle(KB.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Button { dismiss(); onDone() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(KB.dim)
                            .frame(width: 32, height: 32)
                    }
                    Spacer()
                    Text("手动记账").font(.system(size: 17, weight: .bold)).foregroundStyle(KB.text)
                    Spacer()
                    Color.clear.frame(width: 32, height: 32)
                }
                .padding(.horizontal, 12)
                .background(Color.white.ignoresSafeArea())
                .onAppear {
                    if let p = preset {
                        op = p.op; date = p.date; lessonsText = String(p.lessons)
                        if p.course != nil { courseID = p.course }
                        else { showPicker = true }
                    } else if let b = store.currentBabyID, store.courses(for: b).isEmpty == false {
                        showPicker = true
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showPicker) { coursePicker }
        }
    }

    private func stepBtn(_ icon: String, _ delta: Int) -> some View {
        Button {
            let n = max(1, (Int(lessonsText) ?? 1) + delta)
            lessonsText = String(n)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KB.text)
                .frame(width: 34, height: 34)
                .background(KB.accentSoft)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func opChip(_ op2: Store.ManualOp, _ title: String, _ tint: Color) -> some View {
        let sel = op == op2
        return Button { op = op2 } label: {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(sel ? Color.white : KB.text)
                .background(sel ? tint : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(sel ? Color.clear : KB.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var coursePicker: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                if store.courses(for: store.currentBabyID).isEmpty {
                    Text("还没有课程\n请先在「课程管理」里新增").multilineTextAlignment(.center)
                        .font(.system(size: 14)).foregroundStyle(KB.dim)
                } else {
                    List(store.courses(for: store.currentBabyID)) { c in
                        Button {
                            courseID = c.id
                            if op == .charge {
                                price = String(format: "%.2f", c.pricePerLesson)
                            }
                            showPicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).font(.system(size: 15, weight: .medium))
                                    Text("\(store.remaining(c))/\(c.total) 节 · \(c.tag)")
                                        .font(.system(size: 12)).foregroundStyle(KB.dim)
                                }
                                Spacer()
                                if courseID == c.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(KB.accent)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    Text("选择课程").font(.system(size: 17, weight: .bold)).foregroundStyle(KB.text)
                    Spacer()
                    Button("关闭") { showPicker = false }
                        .font(.system(size: 15)).foregroundStyle(KB.dim)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func save() {
        guard let id = courseID else { return }
        store.recordManual(op, courseID: id,
                           lessons: max(1, Int(lessonsText) ?? 1),
                           date: date,
                           note: note, price: Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0)
        dismiss(); onDone()
    }
}

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
                    let sl = template.slot(for: KBDate.cal.component(.weekday, from: date))
                    Card {
                        VStack(spacing: 12) {
                            InfoRow(label: "课程", value: store.course(template.courseID)?.name ?? "—")
                            InfoRow(label: "时间", value: "\(KBDate.mdhm.string(from: date).prefix(10)) \(sl.timeText)")
                            InfoRow(label: "老师", value: sl.teacher.isEmpty ? "—" : sl.teacher)
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
