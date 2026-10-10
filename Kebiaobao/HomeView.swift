import SwiftUI

struct HomeView: View {

    @EnvironmentObject var store: Store
    @State private var sheet: HomeSheet?

    enum HomeSheet: Identifiable, Hashable {
        case addCourse, checkIn(LessonTemplate, Date), ledger
        case manual(LessonTemplate, Date, Store.ManualOp)
        var id: String {
            switch self {
            case .addCourse: return "add"
            case .checkIn(let t, let d): return "ci-\(t.id)-\(d.timeIntervalSince1970)"
            case .manual(let t, let d, let op): return "mn-\(t.id)-\(d.timeIntervalSince1970)-\(op)"
            case .ledger: return "ledger"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                KB.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        header
                        statCard
                        upcomingCard
                        todayCard
                        Color.clear.frame(height: 80)
                    }
                    .padding(.horizontal, 16)
                }
                .safeAreaInset(edge: .top) { Color.clear.frame(height: 0) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $sheet) { s in
                switch s {
                case .addCourse: CourseEditorView(course: nil)
                case .checkIn(let t, let d): CheckInSheet(template: t, date: d)
                case .manual(let t, let d, let op):
                    if s == .manual(t, d, op) {
                        ManualEntryEditorView(
                            preset: (t.courseID, op, t.deduct, d),
                            onDone: { sheet = nil }
                        )
                    } else {
                        EmptyView()
                    }
                case .ledger: LedgerListView(courseID: nil)
                }
            }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(store.babies) { b in
                    Button {
                        store.currentBabyID = b.id; store.save()
                    } label: {
                        Label(b.name, systemImage: b.id == store.currentBabyID ? "checkmark" : "person")
                    }
                }
                Divider()
                NavigationLink { BabyManageView() } label: {
                    Label("宝贝管理", systemImage: "person.2")
                }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(KB.accentSoft).frame(width: 38, height: 38)
                        Text(String(store.currentBaby?.name.prefix(1) ?? "宝"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(KB.accent)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.currentBaby?.name ?? "宝贝")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(KB.text)
                        if let bd = store.currentBaby?.birthday {
                            Text("生日 \(KBDate.cnFull.string(from: bd))")
                                .font(.system(size: 11)).foregroundStyle(KB.dim)
                        }
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(KB.dim)
                }
            }
            Spacer()
            Button { sheet = .ledger } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 18))
                    .foregroundStyle(KB.text)
                    .padding(8)
                    .background(KB.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(KB.line, lineWidth: 1))
            }
        }
        .padding(.top, 6)
    }

    // MARK: - 统计

    private var statCard: some View {
        let babyID = store.currentBabyID
        let list = store.courses(for: babyID)
        let remain = list.reduce(0) { $0 + store.remaining($1) }
        return Card {
            HStack(spacing: 0) {
                StatTile(value: "\(list.count)", label: "总课程")
                Divider().frame(height: 34)
                StatTile(value: "\(list.count)", label: "进行中")
                Divider().frame(height: 34)
                StatTile(value: "\(remain)", label: "剩余课时",
                         tint: remain <= 3 ? KB.danger : KB.accent)
            }
        }
    }

    // MARK: - 近 3 天课程

    private var upcomingCard: some View {
        let days = store.upcomingDays(days: 3, babyID: store.currentBabyID)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13)).foregroundStyle(KB.accent)
                    Text("近 3 天课程")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                    Spacer()
                    Text(KBDate.mdhm.string(from: Date()).prefix(10))
                        .font(.system(size: 12)).foregroundStyle(KB.dim)
                }
                if days.isEmpty {
                    Text("近 3 天暂无排课")
                        .font(.system(size: 13)).foregroundStyle(KB.dim)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 14)
                } else {
                    ForEach(days, id: \.self) { d in
                        dayBlock(d)
                    }
                }
            }
        }
    }

    private func dayBlock(_ date: Date) -> some View {
        let today = KBDate.day(Date())
        let label: String = KBDate.isSameDay(date, today) ? "今天"
            : (KBDate.isSameDay(date, KBDate.cal.date(byAdding: .day, value: 1, to: today)!) ? "明天" : "后天")
        let items = store.lessons(on: date, babyID: store.currentBabyID)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KB.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(KB.accentSoft)
                    .clipShape(Capsule())
                Text("\(date, format: .dateTime.month().day()) \(KBDate.weekdayName(KBDate.cal.component(.weekday, from: date)))")
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
                if let hl = Holiday.label(date) {
                    Text(hl)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Holiday.isHoliday(date) ? KB.danger : KB.warn)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background((Holiday.isHoliday(date) ? KB.danger : KB.warn).opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            ForEach(items) { t in
                lessonRow(t, date: date)
            }
        }
    }

    private func lessonRow(_ t: LessonTemplate, date: Date) -> some View {
        let c = store.course(t.courseID)
        let s = t.slot(for: KBDate.cal.component(.weekday, from: date))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(c?.name ?? "课程")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                Text(s.timeText)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(KB.accent)
                Spacer()
                Text("剩余 \(c.map { store.remaining($0) } ?? 0) 节")
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
            }
            HStack(spacing: 10) {
                Label(s.teacher.isEmpty ? "—" : s.teacher, systemImage: "person")
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
                Label(s.place.isEmpty ? "—" : s.place, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
            }
            HStack(spacing: 10) {
                KBButton(title: "请假", filled: false, tint: KB.dim) {
                    sheet = .manual(t, date, .leave)
                }
                KBButton(title: "扣课时", icon: "checkmark.circle.fill") {
                    sheet = .manual(t, date, .consume)
                }
            }
        }
        .padding(12)
        .background(KB.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 今日 / 在读课程

    private var todayCard: some View {
        let list = store.courses(for: store.currentBabyID)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "book.closed")
                        .font(.system(size: 13)).foregroundStyle(KB.accent)
                    Text("在读课程")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                    Spacer()
                    Button { sheet = .addCourse } label: {
                        Label("新增", systemImage: "plus")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                if list.isEmpty {
                    VStack(spacing: 10) {
                        Text("还没有课程")
                            .font(.system(size: 13)).foregroundStyle(KB.dim)
                        KBButton(title: "添加课程", icon: "plus") { sheet = .addCourse }
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(list) { c in
                        NavigationLink { CourseDetailView(course: c) } label: {
                            courseRow(c)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func courseRow(_ c: Course) -> some View {
        let used = store.consumed(c.id)
        let left = c.total - used
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(c.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                if !c.tag.isEmpty {
                    Text(c.tag)
                        .font(.system(size: 11))
                        .foregroundStyle(KB.accent)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(KB.accentSoft).clipShape(Capsule())
                }
                Spacer()
                Text("¥\(Int(c.pricePerLesson))/节")
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
            }
            KBProgress(value: used, total: c.total,
                       color: left <= 3 ? KB.warn : KB.accent)
            HStack {
                Text("已上 \(used) / \(c.total) 节")
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
                Spacer()
                Text(left <= 0 ? "已完成" : "剩余 \(left) 节")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(left <= 0 ? KB.accent : (left <= 3 ? KB.warn : KB.text))
            }
        }
        .padding(12)
        .background(KB.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
