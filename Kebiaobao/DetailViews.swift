import SwiftUI

// MARK: - 课程详情

struct CourseDetailView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let course: Course

    @State private var edit = false
    @State private var addTemplate = false
    @State private var confirmDelete = false
    @State private var renew = false

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
        .sheet(isPresented: $renew) { RenewSheet(course: current) }
        .alert("删除课程？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                store.deleteCourse(current.id)
                dismiss()
            }
        } message: {
            Text("将同时删除该课程的排课与全部课时流水，不可恢复。")
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
                row("有效期至", KBDate.ymd.string(from: current.expiry))
                Divider()
                row("总费用", "¥\(String(format: "%.2f", current.totalFee))")
            }
            .padding(.horizontal, 16)
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
                                store.templates.removeAll { $0.id == t.id }
                                store.save()
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(store.course(entry.courseID)?.name ?? "课程")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(KB.text)
                Text("\(KBDate.mdhm.string(from: entry.date))  \(entry.note)")
                    .font(.system(size: 11)).foregroundStyle(KB.dim)
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
    }
}

struct LedgerListView: View {
    @EnvironmentObject var store: Store
    let courseID: UUID?
    @State private var filter: UUID?

    private var items: [LedgerEntry] {
        let all = store.ledger
            .filter { courseID == nil || $0.courseID == courseID }
            .filter { filter == nil || $0.courseID == filter }
        return all.sorted { $0.date > $1.date }
    }

    private var filterCourses: [Course] {
        store.courses(for: store.currentBabyID)
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
                .foregroundStyle(active ? .white : KB.text)
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

    private var list: [Course] { store.courses(for: store.currentBabyID) }

    private var totalSpent: Double {
        list.reduce(0) { $0 + store.spent($1.id) }
    }

    private var totalLessons: Int {
        list.reduce(0) { $0 + store.consumed($1.id) }
    }

    private var totalRemainValue: Double {
        list.reduce(0) { $0 + store.remainingValue($1.id) }
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
                                            Text(c.name).font(.system(size: 14, weight: .medium)).foregroundStyle(KB.text)
                                            Spacer()
                                            Text("\(used)/\(c.total)节")
                                                .font(.system(size: 12)).foregroundStyle(KB.dim)
                                        }
                                        KBProgress(value: used, total: c.total)
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
}
