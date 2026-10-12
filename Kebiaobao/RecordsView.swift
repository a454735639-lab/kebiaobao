import SwiftUI

/// 记录页：课时记录 / 缴费记录 / 打卡记录 三个 tab
struct RecordsView: View {
    @EnvironmentObject var store: Store

    enum Tab: String, CaseIterable {
        case lesson = "课时记录"
        case payment = "缴费记录"
        case checkIn = "打卡记录"
    }

    @State private var tab: Tab = .lesson
    @State private var filter: UUID?
    @State private var query = ""

    private var scoped: [LedgerEntry] {
        let list = store.ledger.filter { e in
            guard let s = store.scope else { return true }
            // 共用年卡的记录按归属人算；老记录没归属就退回课程成员判定
            if let who = e.babyID { return who == s }
            return store.course(e.courseID)?.babyIDs.contains(s) ?? false
        }
        return list.sorted { $0.date > $1.date }
    }

    private func matches(_ e: LedgerEntry) -> Bool {
        if let f = filter, e.courseID != f { return false }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return e.note.localizedCaseInsensitiveContains(q)
            || (e.summary ?? "").localizedCaseInsensitiveContains(q)
            || (store.course(e.courseID)?.name.localizedCaseInsensitiveContains(q) ?? false)
    }

    private var items: [LedgerEntry] {
        switch tab {
        case .lesson:
            return scoped.filter { $0.kind == .consume || $0.kind == .leave }.filter(matches)
        case .payment:
            return scoped.filter { $0.kind == .charge || $0.kind == .refund }.filter(matches)
        case .checkIn:
            return scoped.filter(matches)
        }
    }

    private var courses: [Course] { store.courses(for: store.scope) }

    var body: some View {
        ZStack {
            KB.bg.ignoresSafeArea()
            VStack(spacing: 10) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("全部", active: filter == nil) { filter = nil }
                        ForEach(courses) { c in
                            chip(c.name, active: filter == c.id,
                                 color: Color.course(c.color)) { filter = c.id }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13)).foregroundStyle(KB.dim)
                    TextField("搜备注／小结／课程", text: $query)
                        .font(.system(size: 14)).textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
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

                HStack {
                    Text("共 \(items.count) 条")
                        .font(.system(size: 12)).foregroundStyle(KB.dim)
                    Spacer()
                    if tab == .checkIn {
                        let days = Set(items.map { KBDate.ymd.string(from: $0.date) }).count
                        Text("\(days) 天").font(.system(size: 12)).foregroundStyle(KB.dim)
                    }
                }
                .padding(.horizontal, 20)

                if items.isEmpty {
                    Spacer()
                    EmptyHint(icon: "tray", title: "暂无记录", message: "打卡或缴费后会出现在这里")
                    Spacer()
                } else {
                    ScrollView {
                        if tab == .checkIn {
                            groupedList
                        } else {
                            VStack(spacing: 8) {
                                ForEach(items) { e in
                                    LedgerRow(entry: e)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        Color.clear.frame(height: 30)
                    }
                }
            }
        }
        .navigationTitle("记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 打卡记录按天分组
    private var groupedList: some View {
        let groups = Dictionary(grouping: items) { KBDate.ymd.string(from: $0.date) }
        let keys = groups.keys.sorted(by: >)
        return VStack(spacing: 12) {
            ForEach(keys, id: \.self) { k in
                let dayItems = groups[k] ?? []
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            IconBadge(icon: "calendar", size: 22)
                            Text(dayLabel(k))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(KB.text)
                            Spacer()
                            Text("\(dayItems.count) 条")
                                .font(.system(size: 12)).foregroundStyle(KB.dim)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(KB.bg)
                        Divider()
                        ForEach(dayItems) { e in
                            LedgerRow(entry: e)
                                .padding(.horizontal, 12)
                            if e.id != dayItems.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func dayLabel(_ ymd: String) -> String {
        guard let d = KBDate.ymd.date(from: ymd) else { return ymd }
        let w = KBDate.cal.component(.weekday, from: d)
        return "\(ymd) \(KBDate.weekdayName(w))"
    }

    private func chip(_ t: String, active: Bool, color: Color = KB.accent,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? KB.onAccent : KB.text)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(active ? color : KB.card)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : KB.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
