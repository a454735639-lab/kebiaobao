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
                                store.deleteBaby(b.id)
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
    @State private var babyIDs: Set<UUID> = []
    @State private var advance = false
    @State private var advanceLessons = ""
    @State private var advancePrice = ""
    @State private var colorHex: UInt32 = KBPalette.colors[0]
    /// 年卡（课时池）编辑模式
    @State private var isPool = false
    /// 这门课从哪张年卡扣课时。nil = 自己管自己的课时
    @State private var poolID: UUID?
    @State private var noPool = true
    /// 删除确认（课程与年卡都能从这里删，池卡原本没有可达入口）
    @State private var confirmDelete = false

    /// 可选的年卡列表（不含自己）
    private var poolOptions: [Course] {
        store.courses.filter { $0.isPool && !$0.archived && $0.id != course?.id }
    }

    /// 颜色选择行：10 个色点 + 说明
    /// 单选行（年卡选择用）
    private func pickRow(title: String, on: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(on ? KB.accent : KB.dim)
            Text(title).font(.system(size: 15)).foregroundStyle(KB.text)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("课程颜色").font(.system(size: 15)).foregroundStyle(KB.text)
                Spacer()
                Text("用于日历、进度图配色")
                    .font(.system(size: 11)).foregroundStyle(KB.dim)
            }
            HStack(spacing: 10) {
                ForEach(KBPalette.colors, id: \.self) { hex in
                    Button {
                        colorHex = hex
                    } label: {
                        Circle()
                            .fill(Color.course(hex))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Circle().stroke(KB.text, lineWidth: colorHex == hex ? 2 : 0)
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .opacity(colorHex == hex ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 10)
    }

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
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("所属宝贝").font(.system(size: 15)).foregroundStyle(KB.text)
                                            Spacer()
                                            Text("可多选 · 共用课时")
                                                .font(.system(size: 11)).foregroundStyle(KB.dim)
                                        }
                                        ForEach(store.babies) { b in
                                            Button {
                                                if babyIDs.contains(b.id) { babyIDs.remove(b.id) }
                                                else { babyIDs.insert(b.id) }
                                            } label: {
                                                HStack(spacing: 10) {
                                                    Image(systemName: babyIDs.contains(b.id)
                                                          ? "checkmark.circle.fill" : "circle")
                                                        .foregroundStyle(babyIDs.contains(b.id) ? KB.accent : KB.dim)
                                                    Text(b.name).font(.system(size: 15)).foregroundStyle(KB.text)
                                                    Spacer()
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    Divider()
                                }
                                FieldRow(label: "总课时*", text: $total, placeholder: "12", keyboard: .numberPad)
                                Divider()
                                FieldRow(label: "单价（元/节）*", text: $price, placeholder: "90", keyboard: .decimalPad)
                                Divider()
                                if course == nil || !isPool {
                                    Toggle("这是一张年卡（课时池）", isOn: $isPool)
                                        .font(.system(size: 15))
                                        .padding(.vertical, 8)
                                    Divider()
                                }
                                DatePicker("购买时间*", selection: $purchased, displayedComponents: .date)
                                    .font(.system(size: 15))
                                    .padding(.vertical, 8)
                                Divider()
                                DatePicker("有效期至*", selection: $expiry, displayedComponents: .date)
                                    .font(.system(size: 15))
                                    .padding(.vertical, 8)
                                Divider()
                                colorRow
                            }
                            .padding(.horizontal, 16)
                        }

                        // 年卡不排课，普通课才需要选池
                        if !isPool && !poolOptions.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("课时从哪扣").font(.system(size: 15)).foregroundStyle(KB.text)
                                        Spacer()
                                        Text("共用一张年卡")
                                            .font(.system(size: 11)).foregroundStyle(KB.dim)
                                    }
                                    Button {
                                        noPool = true; poolID = nil
                                    } label: {
                                        pickRow(title: "自己管自己的课时", on: noPool)
                                    }
                                    .buttonStyle(.plain)
                                    ForEach(poolOptions) { p in
                                        Button {
                                            noPool = false; poolID = p.id
                                        } label: {
                                            pickRow(title: "\(p.name)（剩 \(store.poolRemaining(p.id)) 节）",
                                                    on: !noPool && poolID == p.id)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
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
                        if course != nil {
                            KBButton(title: isPool ? "删除年卡" : "删除课程",
                                     filled: false, tint: KB.danger) { confirmDelete = true }
                        }
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
            .alert(isPool ? "删除年卡？" : "删除课程？", isPresented: $confirmDelete) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let c = course { store.deleteCourse(c.id) }
                    dismiss()
                }
            } message: {
                Text(isPool
                     ? "挂在它下面的课程会改为各自独立计课时，不会跟着被删。年卡自身的课时流水会一并删除，不可恢复。删除前会自动备份，可在「我的 → 备份与恢复」里还原。"
                     : "将同时删除该课程的排课与全部课时流水，不可恢复。删除前会自动备份，可在「我的 → 备份与恢复」里还原。")
            }
            .onAppear {
                if let c = course {
                    name = c.name; tag = c.tag
                    total = "\(c.total)"
                    price = String(format: "%g", c.pricePerLesson)
                    expiry = c.expiry
                    purchased = c.boughtAt
                    babyIDs = Set(c.babyIDs)
                    colorHex = c.color
                    isPool = c.isPool
                    poolID = c.poolID
                    noPool = c.poolID == nil
                }
            }
        }
    }

    private func commit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let t = Int(total), t > 0 else { return }
        let p = Double(price) ?? 0
        // 未勾选任何宝贝时回退当前宝贝；一个都没有就新建
        var picked = Array(babyIDs)
        if picked.isEmpty {
            if let id = store.currentBabyID { picked = [id] }
            else {
                let b = Baby(name: "宝贝", birthday: nil)
                store.babies.append(b)
                store.currentBabyID = b.id
                picked = [b.id]
            }
        }
        // 稳定顺序：按 babies 列表排，避免 Set 顺序抖动导致每次保存都改文件
        let ordered = store.babies.map(\.id).filter { picked.contains($0) }

        if let c = course, let i = store.courses.firstIndex(where: { $0.id == c.id }) {
            store.courses[i].babyIDs = ordered
            store.courses[i].name = n
            store.courses[i].tag = tag
            store.courses[i].total = t
            store.courses[i].pricePerLesson = p
            store.courses[i].expiry = KBDate.day(expiry)
            store.courses[i].purchasedAt = KBDate.day(purchased)
            store.courses[i].colorHex = colorHex
            store.courses[i].isPool = isPool
            // 年卡自己不挂池；普通课按选择挂或不挂
            store.courses[i].poolID = isPool ? nil : (noPool ? nil : poolID)
            if advance, let add = Int(advanceLessons), add > 0 {
                let np = Double(advancePrice) ?? 0
                store.charge(c.id, lessons: add, price: np, note: "续费",
                             babyID: ordered.first)
            }
        } else {
            let c = Course(babyIDs: ordered, name: n, tag: tag, total: t,
                           pricePerLesson: p, expiry: KBDate.day(expiry),
                           purchasedAt: KBDate.day(purchased), colorHex: colorHex,
                           isPool: isPool, poolID: isPool ? nil : (noPool ? nil : poolID))
            store.courses.append(c)
            if t > 0 {
                store.ledger.append(LedgerEntry(courseID: c.id, date: KBDate.day(purchased),
                                                delta: t, kind: .charge, note: "初始购买",
                                                babyID: ordered.first))
            }
        }
        store.save()
        dismiss()
    }
}

// MARK: - 排课编辑
