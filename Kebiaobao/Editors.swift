import SwiftUI

// MARK: - 宝贝档案

struct BabyEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let baby: Baby?

    @State private var name = ""
    @State private var hasBirthday = false
    @State private var birthday = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                FieldRow(label: "姓名", text: $name, placeholder: "如：乐橙")
                                Divider()
                                HStack {
                                    Text("生日").font(.system(size: 15)).foregroundStyle(KB.text)
                                    Spacer()
                                    Toggle("", isOn: $hasBirthday).labelsHidden()
                                }
                                .padding(.vertical, 8)
                                if hasBirthday {
                                    Divider()
                                    DatePicker("选择生日", selection: $birthday, displayedComponents: .date)
                                        .font(.system(size: 15))
                                        .padding(.vertical, 6)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        if store.babies.count > 1, let b = baby {
                            KBButton(title: "删除该宝贝及其数据", filled: false, tint: KB.danger) {
                                store.babies.removeAll { $0.id == b.id }
                                store.courses.removeAll { $0.babyID == b.id }
                                if store.currentBabyID == b.id { store.currentBabyID = store.babies.first?.id }
                                store.save()
                                dismiss()
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .navigationTitle(baby == nil ? "添加宝贝" : "编辑宝贝")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { commit() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                if let b = baby {
                    name = b.name
                    hasBirthday = b.birthday != nil
                    birthday = b.birthday ?? Date()
                }
            }
        }
    }

    private func commit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let bd: Date? = hasBirthday ? KBDate.day(birthday) : nil
        if let b = baby, let i = store.babies.firstIndex(where: { $0.id == b.id }) {
            store.babies[i].name = n
            store.babies[i].birthday = bd
        } else {
            let b = Baby(name: n, birthday: bd)
            store.babies.append(b)
            store.currentBabyID = b.id
        }
        store.save()
        dismiss()
    }
}

// MARK: - 课程编辑

struct CourseEditorView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let course: Course?

    @State private var name = ""
    @State private var tag = ""
    @State private var total = "12"
    @State private var price = ""
    @State private var expiry = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
    @State private var purchased = Date()
    @State private var babyID: UUID?
    @State private var advance = false
    @State private var advanceLessons = ""
    @State private var advancePrice = ""

    private var totalFee: Double {
        (Double(total) ?? 0) * (Double(price) ?? 0)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                FieldRow(label: "课程名称*", text: $name, placeholder: "如：钢琴课")
                                Divider()
                                FieldRow(label: "类别标签", text: $tag, placeholder: "如：音乐、运动、美术")
                                Divider()
                                if store.babies.count > 1 {
                                    HStack {
                                        Text("所属宝贝").font(.system(size: 15)).foregroundStyle(KB.text)
                                        Spacer()
                                        Picker("", selection: $babyID) {
                                            ForEach(store.babies) { b in
                                                Text(b.name).tag(Optional(b.id))
                                            }
                                        }
                                        .labelsHidden()
                                        .tint(KB.accent)
                                    }
                                    .padding(.vertical, 6)
                                    Divider()
                                }
                                FieldRow(label: "总课时*", text: $total, placeholder: "12", keyboard: .numberPad)
                                Divider()
                                FieldRow(label: "单价（元/节）*", text: $price, placeholder: "90", keyboard: .decimalPad)
                                Divider()
                                DatePicker("购买时间*", selection: $purchased, displayedComponents: .date)
                                    .font(.system(size: 15))
                                    .padding(.vertical, 8)
                                Divider()
                                DatePicker("有效期至*", selection: $expiry, displayedComponents: .date)
                                    .font(.system(size: 15))
                                    .padding(.vertical, 8)
                            }
                            .padding(.horizontal, 16)
                        }

                        if course != nil {
                            Card(padding: 0) {
                                VStack(spacing: 0) {
                                    HStack {
                                        Text("续费（增加课时）").font(.system(size: 15)).foregroundStyle(KB.text)
                                        Spacer()
                                        Toggle("", isOn: $advance).labelsHidden()
                                    }
                                    .padding(.vertical, 8)
                                    if advance {
                                        Divider()
                                        FieldRow(label: "新增课时", text: $advanceLessons, placeholder: "24", keyboard: .numberPad)
                                        Divider()
                                        FieldRow(label: "本次单价", text: $advancePrice, placeholder: "留空沿用原价", keyboard: .decimalPad)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        HStack {
                            Text("总费用：").font(.system(size: 14)).foregroundStyle(KB.dim)
                            Text("¥\(String(format: "%.2f", totalFee))")
                                .font(.system(size: 17, weight: .bold)).foregroundStyle(KB.accent)
                            Spacer()
                        }
                        .padding(.horizontal, 4)

                        KBButton(title: course == nil ? "添加课程" : "保存修改") { commit() }
                        Spacer()
                    }
                    .padding(16)
                }
            }
            .navigationTitle(course == nil ? "新增课程" : "编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .onAppear {
                if let c = course {
                    name = c.name; tag = c.tag
                    total = "\(c.total)"
                    price = String(format: "%g", c.pricePerLesson)
                    expiry = c.expiry
                    purchased = c.boughtAt
                    babyID = c.babyID
                }
            }
        }
    }

    private func commit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let t = Int(total), t > 0 else { return }
        let p = Double(price) ?? 0
        let babyID: UUID
        if let chosen = self.babyID {
            babyID = chosen
        } else if let id = store.currentBabyID {
            babyID = id
        } else {
            let b = Baby(name: "宝贝", birthday: nil)
            store.babies.append(b)
            store.currentBabyID = b.id
            babyID = b.id
        }

        if let c = course, let i = store.courses.firstIndex(where: { $0.id == c.id }) {
            store.courses[i].name = n
            store.courses[i].tag = tag
            store.courses[i].total = t
            store.courses[i].pricePerLesson = p
            store.courses[i].expiry = KBDate.day(expiry)
            store.courses[i].purchasedAt = KBDate.day(purchased)
            if advance, let add = Int(advanceLessons), add > 0 {
                let np = Double(advancePrice) ?? 0
                store.charge(c.id, lessons: add, price: np, note: "续费")
            }
        } else {
            let c = Course(babyID: babyID, name: n, tag: tag, total: t,
                           pricePerLesson: p, expiry: KBDate.day(expiry),
                           purchasedAt: KBDate.day(purchased))
            store.courses.append(c)
            if t > 0 {
                store.ledger.append(LedgerEntry(courseID: c.id, date: KBDate.day(purchased),
                                                delta: t, kind: .charge, note: "初始购买"))
            }
        }
        store.save()
        dismiss()
    }
}

// MARK: - 排课编辑
