import SwiftUI

// MARK: - 课程管理（可编辑）

struct CourseManageView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Course?
    @State private var adding = false
    @State private var showArchived = false

    private var archived: [Course] { store.archivedCourses() }

    var body: some View {
        ZStack {
            KB.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    if store.courses.isEmpty {
                        Text("还没有课程")
                            .font(.system(size: 13)).foregroundStyle(KB.dim)
                            .padding(.vertical, 24)
                    }
                    ForEach(store.courses.filter { !$0.archived }) { c in
                        Button { editing = c } label: { row(c) }
                            .buttonStyle(.plain)
                    }
                    KBButton(title: "新增课程", icon: "plus") { adding = true }

                    if !archived.isEmpty {
                        HStack {
                            Text("已结课（\(archived.count)）")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(KB.dim)
                            Spacer()
                            Button(showArchived ? "收起" : "展开") { showArchived.toggle() }
                                .font(.system(size: 12)).foregroundStyle(KB.accent)
                                .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                        if showArchived {
                            ForEach(archived) { c in
                                Card {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(c.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(KB.dim)
                                            Text("已上 \(store.consumed(c.id))/\(c.total) 节 · 流水保留")
                                                .font(.system(size: 11)).foregroundStyle(KB.dim)
                                        }
                                        Spacer()
                                        Button {
                                            store.setArchived(c.id, false)
                                        } label: {
                                            Text("恢复").font(.system(size: 12)).foregroundStyle(KB.accent)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(16)
            }
        }
        .navigationTitle("课程管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { c in CourseEditorView(course: c) }
        .sheet(isPresented: $adding) { CourseEditorView(course: nil) }
    }

    private func row(_ c: Course) -> some View {
        let used = store.consumed(c.id)
        return Card {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(c.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                        if !c.tag.isEmpty {
                            Text(c.tag)
                                .font(.system(size: 10)).foregroundStyle(KB.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(KB.accentSoft).clipShape(Capsule())
                        }
                    }
                    Text("\(store.baby(c.babyID)?.name ?? "—") · 已上 \(used)/\(c.total) 节 · 剩余 \(c.total - used)")
                        .font(.system(size: 11)).foregroundStyle(KB.dim)
                    Text("购买 \(KBDate.ymd.string(from: c.boughtAt)) · 到期 \(KBDate.ymd.string(from: c.expiry))")
                        .font(.system(size: 11)).foregroundStyle(KB.dim)
                }
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: 13)).foregroundStyle(KB.accent)
            }
        }
    }
}

// MARK: - 宝贝管理（列表 + 新增合并）

struct BabyManageView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Baby?
    @State private var adding = false

    var body: some View {
        ZStack {
            KB.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    if store.babies.isEmpty {
                        Text("还没有宝贝档案")
                            .font(.system(size: 13)).foregroundStyle(KB.dim)
                            .padding(.vertical, 24)
                    }
                    ForEach(store.babies) { b in
                        row(b)
                    }
                    KBButton(title: "添加宝贝", icon: "person.badge.plus") { adding = true }
                    Color.clear.frame(height: 20)
                }
                .padding(16)
            }
        }
        .navigationTitle("宝贝管理")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { b in BabyEditorView(baby: b) }
        .sheet(isPresented: $adding) { BabyEditorView(baby: nil) }
    }

    private func row(_ b: Baby) -> some View {
        let current = !store.allBabies && b.id == store.currentBabyID
        let n = store.courses(for: b.id).count
        return Card {
            HStack(spacing: 12) {
                Button {
                    store.currentBabyID = b.id
                    store.save()
                } label: {
                    Image(systemName: current ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(current ? KB.accent : KB.line)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(b.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                        if current {
                            Text("当前")
                                .font(.system(size: 10)).foregroundStyle(KB.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(KB.accentSoft).clipShape(Capsule())
                        }
                    }
                    Text(b.birthday.map { "生日 \(KBDate.cnFull.string(from: $0)) · \(n) 门课程" }
                         ?? "\(n) 门课程")
                        .font(.system(size: 11)).foregroundStyle(KB.dim)
                }
                Spacer()
                Button { editing = b } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13)).foregroundStyle(KB.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
