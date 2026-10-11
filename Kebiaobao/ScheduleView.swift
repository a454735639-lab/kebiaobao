import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var store: Store
    @State private var month = Date()
    @State private var selected = KBDate.day(Date())
    @State private var addSheet = false
    @State private var sheet: SchedSheet?
    @State private var mode: CalMode = .week

    enum CalMode { case week, month }

    enum SchedSheet: Identifiable {
        case checkIn(LessonTemplate)
        var id: String {
            switch self {
            case .checkIn(let t): return "ci-\(t.id)"
            }
        }
    }

    private let cal = KBDate.cal

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if mode == .month {
                            monthCard
                            monthDayCard
                        } else {
                            weekCard
                        }
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
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mode = mode == .week ? .month : .week
                        }
                    } label: {
                        Text(mode == .week ? "月" : "周")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KB.accent)
                            .frame(width: 34, height: 34)
                            .background(KB.accentSoft).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    Button { addSheet = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(KB.onAccent)
                            .frame(width: 34, height: 34)
                            .background(KB.accent).clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(KB.bg)
            }
            .sheet(isPresented: $addSheet) {
                TemplateEditorView(template: nil, courseID: store.courses(for: store.scope).first?.id)
            }
            .sheet(item: $sheet) { s in
                switch s {
                case .checkIn(let t): CheckInSheet(template: t, date: selected)
                }
            }
        }
    }

    // MARK: - 周视图（日程列表）

    /// 选中日期所在周的周一
    private var weekStart: Date {
        let wd = cal.component(.weekday, from: selected)   // 1=周日
        let back = (wd + 5) % 7                            // 周一=0
        return cal.date(byAdding: .day, value: -back, to: KBDate.day(selected)) ?? selected
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekCard: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(KB.text)
                }
                Text(weekTitle)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                    .frame(maxWidth: .infinity)
                Button { shift(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(KB.text)
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 2)

            ForEach(weekDays, id: \.self) { d in
                weekSection(d)
            }
        }
    }

    private var weekTitle: String {
        let end = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日"
        return "\(f.string(from: weekStart)) - \(f.string(from: end))"
    }

    private func weekSection(_ d: Date) -> some View {
        let items = store.lessons(on: d, babyID: store.scope)
        let isToday = KBDate.isSameDay(d, Date())
        let wd = cal.component(.weekday, from: d)
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M/d"
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("\(KBDate.weekdayName(wd)) \(df.string(from: d))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isToday ? KB.accent : KB.text)
                    if isToday {
                        Text("今天")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(KB.onAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(KB.accent).clipShape(Capsule())
                    }
                    if let label = Holiday.label(d) {
                        Text(label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Holiday.isHoliday(d) ? KB.danger : KB.warn)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((Holiday.isHoliday(d) ? KB.danger : KB.warn).opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Spacer()
                }
                if items.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: store.isSkipped(d) ? "calendar.badge.exclamationmark" : "calendar")
                            .font(.system(size: 12)).foregroundStyle(KB.dim)
                        Text(store.isSkipped(d) ? "法定节假日，不排课" : "暂无排课")
                            .font(.system(size: 13)).foregroundStyle(KB.dim)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                } else {
                    ForEach(items) { t in row(t, on: d) }
                }
            }
        }
    }

    private func shift(_ n: Int) {
        let unit: Calendar.Component = mode == .month ? .month : .weekOfYear
        if let d = cal.date(byAdding: unit, value: n, to: mode == .month ? month : selected) {
            if mode == .month { month = d } else { selected = KBDate.day(d) }
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

    /// 月视图下选中那天的排课
    private var monthDayCard: some View { weekSection(selected) }

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
            let items = store.lessons(on: d, babyID: store.scope)
            let isSel = KBDate.isSameDay(d, selected)
            let isToday = KBDate.isSameDay(d, Date())
            let wd = cal.component(.weekday, from: d)
            let term = Lunar.term(d)
            let lunar = Lunar.date(d)
            Button { selected = d } label: {
                VStack(spacing: 1) {
                    Text("\(cal.component(.day, from: d))")
                        .font(.system(size: 13, weight: isSel || isToday ? .semibold : .regular))
                        .foregroundStyle(isSel ? KB.onAccent : (isToday ? KB.accent : KB.text))
                        .frame(width: 24, height: 24)
                        .background(isSel ? KB.accent : Color.clear)
                        .clipShape(Circle())
                    // 农历 / 节气 / 休班，优先级：节日/补班 > 节气 > 农历初一 > 农历日
                    if let badge = Holiday.badge(d) {
                        Text(badge)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color(hex: Holiday.isHoliday(d) ? 0xE06A6A : 0xC9A24D))
                            .lineLimit(1)
                    } else if let term {
                        Text(term)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x5F8FD0))
                            .lineLimit(1)
                    } else if let lunar {
                        Text(lunar.day == 1 ? lunar.monthName + "月" : lunar.dayName)
                            .font(.system(size: 8))
                            .foregroundStyle(KB.dim)
                            .lineLimit(1)
                    }
                    ForEach(items.prefix(2)) { t in
                        let s = t.slot(for: wd)
                        let c = store.course(t.courseID)
                        let col = Color.course(c?.color ?? KBPalette.colors[0])
                        VStack(spacing: 0) {
                            Text(s.timeText).font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(col)
                            Text(s.teacher.isEmpty ? (c?.name ?? "") : s.teacher)
                                .font(.system(size: 8)).foregroundStyle(KB.dim)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 2).padding(.vertical, 1)
                        .background(Color.courseSoft(c?.color ?? KBPalette.colors[0]))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    if items.count > 2 {
                        Text("+\(items.count - 2)").font(.system(size: 8)).foregroundStyle(KB.dim)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 74, alignment: .top)
                .frame(maxWidth: .infinity)
                .background(isSel ? KB.accentSoft.opacity(0.5) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 74)
        }
    }

    // MARK: - 当天

    private func row(_ t: LessonTemplate, on day: Date) -> some View {
        let c = store.course(t.courseID)
        let s = t.slot(for: KBDate.cal.component(.weekday, from: day))
        let col = Color.course(c?.color ?? KBPalette.colors[0])
        return HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(s.timeText)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(col)
                Text("\(t.deduct)节").font(.system(size: 10)).foregroundStyle(KB.dim)
            }
            .frame(width: 52)
            Rectangle().fill(col).frame(width: 3, height: 34)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 3) {
                Text(c?.name ?? "课程")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(KB.text)
                Text([s.teacher, s.place].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
            }
            Spacer()
            Button { selected = day; sheet = .checkIn(t) } label: {
                Text("扣课")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KB.onAccent)
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
    /// 共用年卡：这条记录算在哪个宝宝头上
    @State private var ownerBabyID: UUID?
    @State private var expiredAlert = false

    /// 已选课程挂在多个宝贝下时才需要选归属
    private var ownerOptions: [Baby] {
        guard let id = courseID, let c = store.course(id), c.babyIDs.count > 1 else { return [] }
        return c.babyIDs.compactMap { store.baby($0) }
    }

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
                        if !ownerOptions.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("记在谁头上").font(.system(size: 14)).foregroundStyle(KB.text)
                                        Spacer()
                                        Text("共用课时")
                                            .font(.system(size: 11)).foregroundStyle(KB.dim)
                                    }
                                    HStack(spacing: 8) {
                                        ForEach(ownerOptions) { b in
                                            let on = (ownerBabyID ?? ownerOptions.first?.id) == b.id
                                            Button { ownerBabyID = b.id } label: {
                                                Text(b.name)
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(on ? KB.onAccent : KB.text)
                                                    .frame(maxWidth: .infinity)
                                                    .frame(height: 36)
                                                    .background(on ? KB.accent : KB.bg)
                                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
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
                    Text(currentCourseText)
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
                .background(KB.bg.ignoresSafeArea())
                .onAppear {
                    if let p = preset {
                        op = p.op; date = p.date; lessonsText = String(p.lessons)
                        if p.course != nil { courseID = p.course }
                        else { showPicker = true }
                    } else if let b = store.scope, store.courses(for: b).isEmpty == false {
                        showPicker = true
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("课程已过期", isPresented: $expiredAlert) {
                Button("好") { }
            } message: {
                Text("这门课的有效期已过，不能再扣课时。要续期请到课程编辑里改「有效期至」。")
            }
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
                .foregroundStyle(sel ? KB.onAccent : KB.text)
                .background(sel ? tint : KB.card)
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
                if store.courses(for: store.scope).isEmpty {
                    Text("还没有课程\n请先在「课程管理」里新增").multilineTextAlignment(.center)
                        .font(.system(size: 14)).foregroundStyle(KB.dim)
                } else {
                    List(store.courses(for: store.scope)) { c in
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
                                    Text("\(store.remaining(c))/\(store.pool(of: c.id)?.total ?? c.total) 节 · \(c.tag)")
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
                .background(KB.bg.ignoresSafeArea())
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// 底部当前课程提示（课程可能在 sheet 打开期间被归档/删除/被导入覆盖）
    private var currentCourseText: String {
        guard let id = courseID, let c = store.course(id) else { return "当前：—" }
        return "当前：\(c.name) · 剩余 \(store.remaining(c)) 课时"
    }

    private func save() {
        guard let id = courseID else { return }
        // 到期课程禁止再扣课（与打卡同一规则）；请假/加课时不受限
        if op == .consume && store.isExpired(id) { expiredAlert = true; return }
        let opts = ownerOptions
        let who = opts.isEmpty ? nil : (ownerBabyID.flatMap { p in opts.contains { $0.id == p } ? p : nil } ?? opts.first?.id)
        store.recordManual(op, courseID: id,
                           lessons: max(1, Int(lessonsText) ?? 1),
                           date: date,
                           note: note, price: Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0,
                           babyID: who)
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
    @State private var summary = ""
    @State private var alert: AlertKind?

    private enum AlertKind: Identifiable {
        case duplicate, expired
        var id: Int { self == .duplicate ? 0 : 1 }
    }

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
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("课后小结").font(.system(size: 15)).foregroundStyle(KB.text)
                            TextField("本节学了什么、表现如何", text: $summary, axis: .vertical)
                                .font(.system(size: 14))
                                .lineLimit(3...6)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(KB.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    KBButton(title: "确认扣课 \(deduct) 课时", icon: "checkmark.circle.fill") {
                        var t = template
                        t.deduct = deduct
                        switch store.checkIn(t, on: date) {
                        case .ok:
                            store.updateLastEntry(note: note, summary: summary)
                            dismiss()
                        case .duplicate: alert = .duplicate
                        case .expired: alert = .expired
                        }
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
            .alert(item: $alert) { kind in
                switch kind {
                case .duplicate:
                    return Alert(title: Text("今天已经打过卡"),
                                 message: Text("这门课今天已有扣课记录。如需调整，请到课时流水里撤销或改备注。"),
                                 dismissButton: .default(Text("好")) { dismiss() })
                case .expired:
                    return Alert(title: Text("课程已过期"),
                                 message: Text("这门课的有效期已过，不能再扣课时。要续期请到课程编辑里改「有效期至」。"),
                                 dismissButton: .default(Text("好")))
                }
            }
        }
        .onAppear { deduct = max(1, template.deduct) }
    }
}
