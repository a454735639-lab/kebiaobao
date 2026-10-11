import SwiftUI
import Charts

// MARK: - 课程详情

struct CourseDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let course: Course

    @State private var edit = false
    @State private var addTemplate = false
    @State private var editingTemplate: LessonTemplate?
    @State private var deletingTemplate: LessonTemplate?
    @State private var confirmDelete = false
    @State private var renew = false
    @State private var shareItem: MeView.ShareItem?

    private var current: Course { store.course(course.id) ?? course }

    var body: some View {
        ZStack {
            KB.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    progressCard
                    infoCard
                    templateCard
                    ledgerCard
                    KBButton(title: "导出本课程 Excel", icon: "square.and.arrow.up",
                             filled: false) { exportCourse() }
                    KBButton(title: current.archived ? "恢复课程" : "结课归档",
                             icon: "archivebox",
                             filled: false) { store.setArchived(current.id, !current.archived) }
                    KBButton(title: "删除课程", filled: false, tint: KB.danger) {
                        confirmDelete = true
                    }
                    Color.clear.frame(height: 30)
                }
                .padding(16)
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { edit = true }
            }
        }
        .sheet(isPresented: $edit) { CourseEditorView(course: current) }
        .sheet(isPresented: $addTemplate) { TemplateEditorView(template: nil, courseID: current.id) }
        .sheet(item: $editingTemplate) { t in
            TemplateEditorView(template: t, courseID: current.id)
        }
        .sheet(isPresented: $renew) { RenewSheet(course: current) }
        .sheet(item: $shareItem) { item in ShareSheet(url: item.url) }
        .alert("删除这条排课？", isPresented: Binding(
            get: { deletingTemplate != nil },
            set: { if !$0 { deletingTemplate = nil } }
        )) {
            Button("取消", role: .cancel) { deletingTemplate = nil }
            Button("删除", role: .destructive) {
                if let t = deletingTemplate {
                    store.deleteTemplate(t.id)
                }
                deletingTemplate = nil
            }
        } message: {
            Text("已记过的流水不受影响。")
        }
        .alert("删除课程？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deleteCourse(current.id)
                dismiss()
            }
        } message: {
            Text("将同时删除该课程的排课与全部课时流水，不可恢复。删除前会自动备份，可在「我的 → 备份与恢复」里还原。")
        }
    }

    private var progressCard: some View {
        let used = store.consumed(current.id)
        let left = current.total - used
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("课时进度").font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                    Spacer()
                    Text("\(used)/\(current.total) 节")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(left <= 3 ? KB.warn : KB.accent)
                }
                KBProgress(value: used, total: current.total,
                           color: left <= 0 ? KB.accent : (left <= 3 ? KB.warn : KB.accent))
                HStack {
                    Text("剩余 \(max(0, left)) 节")
                        .font(.system(size: 13)).foregroundStyle(KB.dim)
                    Spacer()
                    Text("剩余价值 ¥\(String(format: "%.2f", store.remainingValue(current.id)))")
                        .font(.system(size: 13)).foregroundStyle(KB.dim)
                }
                HStack(spacing: 10) {
                    KBButton(title: "续费", filled: false) { renew = true }
                    KBButton(title: "加排课", icon: "calendar.badge.plus") { addTemplate = true }
                }
            }
        }
    }

    private var infoCard: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                row("类别标签", current.tag.isEmpty ? "—" : current.tag)
                Divider()
                row("单价", "¥\(String(format: "%g", current.pricePerLesson))/节")
                Divider()
                row("购买时间", KBDate.ymd.string(from: current.boughtAt))
                Divider()
                row("有效期至", KBDate.ymd.string(from: current.expiry))
                Divider()
                row("总费用", "¥\(String(format: "%.2f", current.totalFee))")
            }
            .padding(.horizontal, 16)
        }
    }

    private func exportCourse() {
        if let url = MeView.writeFile(store.exportXLSX(courseID: current.id), name: current.name) {
            shareItem = MeView.ShareItem(url: url)
        }
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack {
            Text(l).font(.system(size: 14)).foregroundStyle(KB.dim)
            Spacer()
            Text(v).font(.system(size: 14, weight: .medium)).foregroundStyle(KB.text)
        }
        .padding(.vertical, 12)
    }

    private var templateCard: some View {
        let items = store.templates(for: current.id)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("排课").font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                if items.isEmpty {
                    Text("暂无排课").font(.system(size: 13)).foregroundStyle(KB.dim)
                } else {
                    ForEach(items) { t in
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(t.orderedSlots) { s in
                                HStack(spacing: 10) {
                                    Text(s.dayName)
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(KB.text)
                                    Text(s.timeText)
                                        .font(.system(size: 13)).foregroundStyle(KB.accent)
                                    Spacer()
                                    Text("\(s.teacher.isEmpty ? "—" : s.teacher) · \(s.place.isEmpty ? "—" : s.place)")
                                        .font(.system(size: 12)).foregroundStyle(KB.dim)
                                }
                            }
                        }
                        HStack {
                            Text("每次划扣 \(t.deduct) 课时")
                                .font(.system(size: 11)).foregroundStyle(KB.dim)
                            Spacer()
                            Button {
                                editingTemplate = t
                            } label: {
                                Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(KB.accent)
                            }
                            .buttonStyle(.plain)
                            Button {
                                deletingTemplate = t
                            } label: {
                                Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(KB.danger)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var ledgerCard: some View {
        let items = Array(store.entries(current.id).prefix(6))
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("最近流水").font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                    Spacer()
                    NavigationLink("全部") { LedgerListView(courseID: current.id) }
                        .font(.system(size: 13))
                }
                if items.isEmpty {
                    Text("暂无记录").font(.system(size: 13)).foregroundStyle(KB.dim)
                } else {
                    ForEach(items) { e in LedgerRow(entry: e, showUndo: false) }
                }
            }
        }
    }
}

// MARK: - 续费

struct RenewSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let course: Course

    @State private var lessons = "24"
    @State private var price = ""
    @State private var note = "续费"

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                VStack(spacing: 14) {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            FieldRow(label: "新增课时", text: $lessons, placeholder: "24", keyboard: .numberPad)
                            Divider()
                            FieldRow(label: "本次单价", text: $price,
                                     placeholder: "留空沿用 ¥\(String(format: "%g", course.pricePerLesson))",
                                     keyboard: .decimalPad)
                            Divider()
                            FieldRow(label: "备注", text: $note, placeholder: "续费")
                        }
                        .padding(.horizontal, 16)
                    }
                    let n = Int(lessons) ?? 0
                    let p = Double(price) ?? course.pricePerLesson
                    HStack {
                        Text("本次支付：").font(.system(size: 14)).foregroundStyle(KB.dim)
                        Text("¥\(String(format: "%.2f", Double(n) * p))")
                            .font(.system(size: 17, weight: .bold)).foregroundStyle(KB.accent)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    KBButton(title: "确认续费") {
                        guard n > 0 else { return }
                        store.charge(course.id, lessons: n, price: Double(price) ?? 0, note: note)
                        dismiss()
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("续费")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

// MARK: - 流水

struct LedgerRow: View {
    @EnvironmentObject var store: Store
    let entry: LedgerEntry
    var showUndo: Bool = true

    @State private var editing = false
    @State private var draft = ""
    @State private var editingSummary = false
    @State private var sumDraft = ""
    @State private var viewing: LedgerEntry?

    private func editSummary(_ s: String) {
        sumDraft = s
        editingSummary = true
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.course(entry.courseID)?.name ?? "课程")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(KB.text)
                HStack(spacing: 4) {
                    Text(KBDate.mdhm.string(from: entry.date))
                        .font(.system(size: 11)).foregroundStyle(KB.dim)
                    if entry.note.isEmpty {
                        Text("加备注")
                            .font(.system(size: 11)).foregroundStyle(KB.accent.opacity(0.8))
                    } else {
                        Text(entry.note)
                            .font(.system(size: 11)).foregroundStyle(KB.dim)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    draft = entry.note
                    editing = true
                }
                if entry.kind == .consume {
                    HStack(spacing: 6) {
                        if let s = entry.summary, !s.isEmpty {
                            Text("小结：\(s)")
                                .font(.system(size: 11)).foregroundStyle(KB.text.opacity(0.75))
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { viewing = entry }
                            Button { editSummary(s) } label: {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 12))
                                    .foregroundStyle(KB.accent)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("加课后小结")
                                .font(.system(size: 11)).foregroundStyle(KB.accent.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { editSummary("") }
                        }
                    }
                }
            }
            Spacer()
            if entry.kind != .leave {
                Text("\(entry.delta > 0 ? "+" : "")\(entry.delta)节")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entry.delta > 0 ? KB.accent : KB.text)
            } else {
                Text("请假").font(.system(size: 13)).foregroundStyle(KB.warn)
            }
            if showUndo {
                Button {
                    store.undo(entry)
                } label: {
                    Text("撤销").font(.system(size: 12)).foregroundStyle(KB.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 9)
        .alert("备注", isPresented: $editing) {
            TextField("如：调课到周六", text: $draft)
            Button("取消", role: .cancel) {}
            Button("保存") { store.updateNote(entry, note: draft) }
        } message: {
            Text("\(store.course(entry.courseID)?.name ?? "课程") · \(KBDate.mdhm.string(from: entry.date))")
        }
        .alert("课后小结", isPresented: $editingSummary) {
            TextField("本节学了什么、表现如何", text: $sumDraft, axis: .vertical)
            Button("取消", role: .cancel) {}
            Button("保存") { store.updateSummary(entry, summary: sumDraft) }
        } message: {
            Text("\(store.course(entry.courseID)?.name ?? "课程") · \(KBDate.mdhm.string(from: entry.date))")
        }
        .sheet(item: $viewing) { e in
            NavigationStack {
                ZStack {
                    KB.bg.ignoresSafeArea()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(store.course(e.courseID)?.name ?? "课程") · \(KBDate.mdhm.string(from: e.date))")
                                .font(.system(size: 13)).foregroundStyle(KB.dim)
                            Text(e.summary ?? "")
                                .font(.system(size: 15)).foregroundStyle(KB.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(height: 20)
                        }
                        .padding(16)
                    }
                }
                .navigationTitle("课后小结")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { viewing = nil }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("编辑") {
                            let s = e.summary ?? ""
                            viewing = nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                editSummary(s)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct LedgerListView: View {
    @EnvironmentObject var store: Store
    let courseID: UUID?
    @State private var filter: UUID?
    @State private var kind: RecordKind?
    @State private var query = ""

    private var items: [LedgerEntry] {
        var all = store.ledger
            .filter { courseID == nil || $0.courseID == courseID }
            .filter { filter == nil || $0.courseID == filter }
            .filter { kind == nil || $0.kind == kind }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            all = all.filter { e in
                e.note.localizedCaseInsensitiveContains(q)
                    || (e.summary ?? "").localizedCaseInsensitiveContains(q)
                    || (store.course(e.courseID)?.name.localizedCaseInsensitiveContains(q) ?? false)
            }
        }
        return all.sorted { $0.date > $1.date }
    }

    private var filterCourses: [Course] {
        store.courses(for: store.scope)
    }

    var body: some View {
        ZStack {
            KB.bg.ignoresSafeArea()
            VStack(spacing: 12) {
                if courseID == nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("全部", active: filter == nil) { filter = nil }
                            ForEach(filterCourses) { c in
                                chip(c.name, active: filter == c.id) { filter = c.id }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 8)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("全部类型", active: kind == nil) { kind = nil }
                        ForEach(RecordKind.allCases, id: \.self) { k in
                            chip(k.label, active: kind == k) { kind = k }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13)).foregroundStyle(KB.dim)
                    TextField("搜备注／小结／课程", text: $query)
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14)).foregroundStyle(KB.dim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(KB.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(KB.line, lineWidth: 1))
                .padding(.horizontal, 16)
                if items.isEmpty {
                    Spacer()
                    Text("暂无流水").font(.system(size: 14)).foregroundStyle(KB.dim)
                    Spacer()
                } else {
                    ScrollView {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(items) { e in
                                    LedgerRow(entry: e)
                                        .padding(.horizontal, 16)
                                    if e.id != items.last?.id { Divider().padding(.leading, 16) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .navigationTitle("课时流水")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chip(_ t: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? KB.onAccent : KB.text)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(active ? KB.accent : KB.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : KB.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 数据分析

struct AnalyticsView: View {
    @EnvironmentObject var store: Store

    /// 统计范围：全部 / 本月
    @State private var monthOnly = false

    private var list: [Course] { store.courses(for: store.scope) }

    private var period: Date? { monthOnly ? Date() : nil }

    private var totalSpent: Double {
        list.reduce(0) { $0 + store.spent($1.id) }
    }

    private var totalLessons: Int {
        list.reduce(0) { $0 + store.consumed($1.id) }
    }

    private var totalRemainValue: Double {
        list.reduce(0) { $0 + store.remainingValue($1.id) }
    }

    /// 当期各课程消耗（用于环形图）
    private var slices: [Slice] {
        list.map { Slice(id: $0.id, name: $0.name, color: $0.color,
                         value: store.consumed($0.id, in: period)) }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
    }

    private var sliceTotal: Int { slices.reduce(0) { $0 + $1.value } }

    /// 当期消课类型分布
    private var kindSlices: [Slice] {
        RecordKind.allCases.compactMap { k in
            let v = store.ledger.filter { e in
                guard e.kind == k, e.delta < 0 else { return false }
                guard let p = period else { return true }
                return KBDate.cal.isDate(e.date, equalTo: p, toGranularity: .month)
            }.reduce(0) { $0 + abs($1.delta) }
            guard v > 0 else { return nil }
            return Slice(id: UUID(), name: k.label,
                         color: k == .consume ? KBPalette.colors[0] : KBPalette.colors[2],
                         value: v)
        }
    }

    struct Slice: Identifiable {
        let id: UUID
        let name: String
        let color: UInt32
        let value: Int
    }

    var body: some View {
        ZStack {
            KB.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("累计支出").font(.system(size: 13)).foregroundStyle(KB.dim)
                            Text("¥\(String(format: "%.2f", totalSpent))")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(KB.text)
                            Text("已上课时：\(totalLessons) 节")
                                .font(.system(size: 13)).foregroundStyle(KB.dim)
                        }
                    }

                    // 进度：全部 / 本月
                    Picker("", selection: $monthOnly) {
                        Text("全部").tag(false)
                        Text(monthLabel).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 2)

                    if !slices.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("上课进度").font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(KB.text)
                                    Spacer()
                                    Text("共 \(sliceTotal) 节")
                                        .font(.system(size: 12)).foregroundStyle(KB.dim)
                                }
                                DonutChart(slices: slices, total: sliceTotal)
                                VStack(spacing: 8) {
                                    ForEach(slices) { s in
                                        HStack(spacing: 8) {
                                            Circle().fill(Color.course(s.color))
                                                .frame(width: 9, height: 9)
                                            Text(s.name).font(.system(size: 13)).foregroundStyle(KB.text)
                                            Spacer()
                                            Text("\(s.value)节")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(KB.text)
                                            Text(pct(s.value))
                                                .font(.system(size: 12)).foregroundStyle(KB.dim)
                                                .frame(width: 46, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !kindSlices.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("消课类型").font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(KB.text)
                                KindBar(slices: kindSlices)
                                HStack(spacing: 14) {
                                    ForEach(kindSlices) { s in
                                        HStack(spacing: 5) {
                                            Circle().fill(Color.course(s.color))
                                                .frame(width: 8, height: 8)
                                            Text("\(s.name) \(s.value)")
                                                .font(.system(size: 12)).foregroundStyle(KB.dim)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("科目消耗统计").font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                            if list.isEmpty {
                                Text("暂无课程").font(.system(size: 13)).foregroundStyle(KB.dim)
                            } else {
                                ForEach(list) { c in
                                    let used = store.consumed(c.id)
                                    let sp = store.spent(c.id)
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack {
                                            Circle().fill(Color.course(c.color))
                                                .frame(width: 9, height: 9)
                                            Text(c.name).font(.system(size: 14, weight: .medium)).foregroundStyle(KB.text)
                                            Spacer()
                                            Text("\(used)/\(c.total)节")
                                                .font(.system(size: 12)).foregroundStyle(KB.dim)
                                        }
                                        KBProgress(value: used, total: c.total, color: Color.course(c.color))
                                        HStack {
                                            Text("已花费：¥\(String(format: "%.2f", sp))")
                                                .font(.system(size: 12)).foregroundStyle(KB.dim)
                                            Spacer()
                                            Text("剩余价值：¥\(String(format: "%.2f", store.remainingValue(c.id)))")
                                                .font(.system(size: 12)).foregroundStyle(KB.dim)
                                        }
                                    }
                                    .padding(12)
                                    .background(KB.bg)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("课程明细").font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                            ForEach(list) { c in
                                VStack(spacing: 0) {
                                    InfoRow(label: c.name, value: "剩余 \(store.remaining(c)) 节")
                                    Divider().padding(.vertical, 6)
                                    InfoRow(label: "单价", value: "¥\(String(format: "%g", c.pricePerLesson))")
                                    Divider().padding(.vertical, 6)
                                    InfoRow(label: "有效期至", value: KBDate.ymd.string(from: c.expiry),
                                            valueColor: c.expiry < Date() ? KB.danger : KB.text)
                                }
                            }
                            if list.isEmpty {
                                Text("暂无课程").font(.system(size: 13)).foregroundStyle(KB.dim)
                            }
                        }
                    }

                    Card {
                        InfoRow(label: "剩余课时总价值",
                                value: "¥\(String(format: "%.2f", totalRemainValue))",
                                valueColor: KB.accent)
                    }

                    Color.clear.frame(height: 30)
                }
                .padding(16)
            }
        }
        .navigationTitle("数据分析")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM月"
        return f.string(from: Date())
    }

    private func pct(_ v: Int) -> String {
        guard sliceTotal > 0 else { return "0%" }
        return String(format: "%.0f%%", Double(v) / Double(sliceTotal) * 100)
    }
}

/// 环形占比图（Swift Charts，iOS 17 SectorMark）
struct DonutChart: View {
    let slices: [AnalyticsView.Slice]
    let total: Int

    var body: some View {
        ZStack {
            Chart(slices) { s in
                SectorMark(
                    angle: .value("课时", s.value),
                    innerRadius: .ratio(0.64),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(Color.course(s.color))
            }
            .frame(height: 180)
            VStack(spacing: 2) {
                Text("\(total)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(KB.text)
                Text("总课时").font(.system(size: 11)).foregroundStyle(KB.dim)
            }
        }
    }
}

/// 横向堆叠条
struct KindBar: View {
    let slices: [AnalyticsView.Slice]

    var body: some View {
        GeometryReader { geo in
            let sum = max(1, slices.reduce(0) { $0 + $1.value })
            HStack(spacing: 2) {
                ForEach(slices) { s in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.course(s.color))
                        .frame(width: max(3, geo.size.width * CGFloat(s.value) / CGFloat(sum)))
                }
            }
        }
        .frame(height: 12)
    }
}
