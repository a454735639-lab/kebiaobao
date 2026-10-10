import SwiftUI
import UIKit

struct TemplateEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let template: LessonTemplate?
    var courseID: UUID?

    @State private var selectedCourse: UUID?
    @State private var weekdays: Set<Int> = []
    @State private var slots: [Int: DaySlot] = [:]   // weekday -> 该天安排
    @State private var defaultTime = Calendar.current.date(
        from: DateComponents(hour: 16, minute: 0))!
    @State private var defaultTeacher = ""
    @State private var defaultPlace = ""
    @State private var editingDay: Int?
    @State private var deduct = 1
    @State private var remind = 30

    private var list: [Course] { store.courses(for: store.currentBabyID) }

    /// 每个选中星期，各自的安排
    private var orderedSlots: [DaySlot] {
        weekdays.sorted().map { w in
            slots[w] ?? DaySlot(weekday: w,
                                hour: hour(defaultTime), minute: minute(defaultTime),
                                teacher: defaultTeacher, place: defaultPlace)
        }
    }

    private func hour(_ d: Date) -> Int { Calendar.current.component(.hour, from: d) }
    private func minute(_ d: Date) -> Int { Calendar.current.component(.minute, from: d) }

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                Menu {
                                    ForEach(list) { c in
                                        Button(c.name) { selectedCourse = c.id }
                                    }
                                } label: {
                                    HStack {
                                        Text("选择课程*").font(.system(size: 15)).foregroundStyle(KB.text)
                                        Spacer()
                                        Text(store.course(selectedCourse ?? UUID())?.name ?? "请选择")
                                            .font(.system(size: 15)).foregroundStyle(KB.dim)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 11)).foregroundStyle(KB.dim)
                                    }
                                    .padding(.vertical, 13)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("星期*（可多选，选完逐天设置时间／老师）")
                                    .font(.system(size: 14)).foregroundStyle(KB.text)
                                HStack(spacing: 6) {
                                    ForEach(1...7, id: \.self) { w in
                                        let on = weekdays.contains(w)
                                        Button {
                                            if on {
                                                weekdays.remove(w)
                                                slots[w] = nil
                                            } else {
                                                weekdays.insert(w)
                                            }
                                        } label: {
                                            Text(KBDate.weekdayName(w).replacingOccurrences(of: "周", with: ""))
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(on ? .white : KB.text)
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

                        if !weekdays.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("各天安排（点开单独设置）")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(KB.dim)
                                    .padding(.leading, 4)
                                Card(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(orderedSlots.enumerated()), id: \.element.id) { idx, s in
                                            if idx > 0 { Divider().padding(.leading, 58) }
                                            DaySlotRow(slot: s) { editingDay = s.weekday }
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("未单独设置的天，沿用下面的默认值")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(KB.dim)
                                    .padding(.leading, 4)
                                Card(padding: 0) {
                                    VStack(spacing: 0) {
                                        DatePicker("默认时间", selection: $defaultTime,
                                                   displayedComponents: .hourAndMinute)
                                            .font(.system(size: 15)).padding(.vertical, 10)
                                        Divider()
                                        FieldRow(label: "默认老师", text: $defaultTeacher,
                                                 placeholder: "老师姓名")
                                        Divider()
                                        FieldRow(label: "默认地点", text: $defaultPlace,
                                                 placeholder: "如：少年宫3楼")
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("每次划扣课时").font(.system(size: 15)).foregroundStyle(KB.text)
                                    Spacer()
                                    Stepper("", value: $deduct, in: 1...10).labelsHidden()
                                    Text("\(deduct) 课时")
                                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.accent)
                                        .frame(width: 64, alignment: .trailing)
                                }
                                .padding(.vertical, 10)
                                Divider()
                                HStack {
                                    Text("提前提醒").font(.system(size: 15)).foregroundStyle(KB.text)
                                    Spacer()
                                    Picker("", selection: $remind) {
                                        Text("不提醒").tag(0)
                                        Text("提前 10 分钟").tag(10)
                                        Text("提前 30 分钟").tag(30)
                                        Text("提前 1 小时").tag(60)
                                    }
                                    .labelsHidden()
                                }
                                .padding(.vertical, 6)
                            }
                            .padding(.horizontal, 16)
                        }

                        KBButton(title: template == nil ? "添加排课" : "保存排课") { commit() }
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .navigationTitle(template == nil ? "添加排课" : "编辑排课")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .sheet(item: Binding(
                get: { editingDay.map { DayBox(weekday: $0) } },
                set: { if $0 == nil { editingDay = nil } }
            )) { box in
                DaySlotEditorView(weekday: box.weekday,
                                  slot: currentSlot(box.weekday)) { updated in
                    slots[box.weekday] = updated
                }
            }
            .onAppear(perform: load)
        }
    }

    struct DayBox: Identifiable { let weekday: Int; var id: Int { weekday } }

    private func currentSlot(_ w: Int) -> DaySlot {
        slots[w] ?? DaySlot(weekday: w,
                            hour: hour(defaultTime), minute: minute(defaultTime),
                            teacher: defaultTeacher, place: defaultPlace)
    }

    private func load() {
        guard let t = template else {
            selectedCourse = courseID ?? list.first?.id
            return
        }
        selectedCourse = t.courseID
        weekdays = Set(t.weekdays)
        defaultTime = Calendar.current.date(
            from: DateComponents(hour: t.hour, minute: t.minute)) ?? defaultTime
        defaultTeacher = t.teacher
        defaultPlace = t.place
        deduct = t.deduct
        remind = t.remindMinutes
        for s in t.slots { slots[s.weekday] = s }
        // 旧数据：没有 slots 时，把默认值固化到每一天
        if t.slots.isEmpty {
            for w in t.weekdays {
                slots[w] = DaySlot(weekday: w, hour: t.hour, minute: t.minute,
                                   teacher: t.teacher, place: t.place)
            }
        }
    }

    private func commit() {
        guard let cid = selectedCourse, !weekdays.isEmpty else { return }
        let days = weekdays.sorted()
        let all = orderedSlots
        let first = all.first
        let t = LessonTemplate(
            courseID: cid,
            weekdays: days,
            hour: first?.hour ?? hour(defaultTime),
            minute: first?.minute ?? minute(defaultTime),
            place: first?.place ?? defaultPlace,
            teacher: first?.teacher ?? defaultTeacher,
            deduct: deduct,
            remindMinutes: remind,
            slots: all
        )
        if let old = template, let i = store.templates.firstIndex(where: { $0.id == old.id }) {
            var n = t; n.id = old.id
            store.templates[i] = n
        } else {
            store.templates.append(t)
        }
        store.save()
        dismiss()
    }
}
