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
                        todayLessonsCard
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
                Button {
                    store.allBabies = true; store.save()
                } label: {
                    Label("全部宝贝", systemImage: store.allBabies ? "checkmark" : "square.grid.2x2")
                }
                Divider()
                ForEach(store.babies) { b in
                    Button {
                        store.allBabies = false
                        store.currentBabyID = b.id; store.save()
                    } label: {
                        Label(b.name, systemImage: (!store.allBabies && b.id == store.currentBabyID) ? "checkmark" : "person")
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
                        if store.allBabies {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 16)).foregroundStyle(KB.accent)
                        } else {
                            Text(String(store.currentBaby?.name.prefix(1) ?? "宝"))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(KB.accent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.allBabies ? "全部宝贝" : (store.currentBaby?.name ?? "宝贝"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(KB.text)
                        if store.allBabies {
                            Text("\(store.babies.count) 个宝贝 · \(store.courses(for: nil).count) 门课程")
                                .font(.system(size: 11)).foregroundStyle(KB.dim)
                        } else if let bd = store.currentBaby?.birthday {
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
        let list = store.courses(for: store.scope)
        let remain = list.reduce(0) { $0 + store.remaining($1) }
        // 进行中 = 还有剩余课时的课程（原来与「总课程」都是 list.count，恒等）
        let active = list.filter { store.remaining($0) > 0 }.count
        return Card {
            HStack(spacing: 0) {
                StatTile(value: "\(list.count)", label: "总课程")
                Divider().frame(height: 34)
                StatTile(value: "\(active)", label: "进行中")
                Divider().frame(height: 34)
                StatTile(value: "\(remain)", label: "剩余课时",
                         tint: remain <= 3 ? KB.danger : KB.accent)
            }
        }
    }

    // MARK: - 近 3 天课程

    private var upcomingCard: some View {
        let days = store.upcomingDays(days: 3, babyID: store.scope)
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
        let tomorrow = KBDate.cal.date(byAdding: .day, value: 1, to: today)
        let label: String = KBDate.isSameDay(date, today) ? "今天"
            : (tomorrow.map { KBDate.isSameDay(date, $0) } == true ? "明天" : "后天")
        let items = store.lessons(on: date, babyID: store.scope)
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
        let col = Color.course(c?.color ?? KBPalette.colors[0])
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(col).frame(width: 9, height: 9)
                Text(c?.name ?? "课程")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                Text(s.timeText)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(col)
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
        let list = store.courses(for: store.scope)
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

    // MARK: - 今日课程

    private var todayLessonsCard: some View {
        let today = KBDate.day(Date())
        let items = store.lessons(on: today, babyID: store.scope)
        let lunar = Lunar.date(today)
        let term = Lunar.term(today)
        let badge = Holiday.badge(today)
        let skipped = store.isSkipped(today)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: skipped ? "calendar.badge.exclamationmark" : "sun.max")
                        .font(.system(size: 13)).foregroundStyle(KB.accent)
                    Text("今日课程")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                    Spacer()
                    if let badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: Holiday.isHoliday(today) ? 0xE06A6A : 0xC9A24D))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: Holiday.isHoliday(today) ? 0xE06A6A : 0xC9A24D).opacity(0.14))
                            .clipShape(Capsule())
                    }
                    if let term {
                        Text(term)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x5F8FD0))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: 0x5F8FD0).opacity(0.14))
                            .clipShape(Capsule())
                    }
                    if let lunar {
                        Text("\(lunar.monthName)月\(lunar.dayName)")
                            .font(.system(size: 11)).foregroundStyle(KB.dim)
                    }
                }
                if items.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: store.isSkipped(today) ? "calendar.badge.exclamationmark" : "sun.max")
                            .font(.system(size: 13)).foregroundStyle(KB.accent)
                        Text(store.isSkipped(today) ? "法定节假日，不排课" : "今天没有课")
                            .font(.system(size: 13)).foregroundStyle(KB.dim)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
                } else {
                    ForEach(items) { t in
                        todayRow(t, date: today)
                    }
                }
            }
        }
    }

    /// 共用年卡：这一节是哪个宝宝上的（单宝贝课程返回 nil，不显示徽章）
    private func ownerName(_ t: LessonTemplate, _ c: Course) -> String? {
        guard let id = t.babyID ?? c.babyIDs.first else { return nil }
        return store.baby(id)?.name
    }

    private func todayRow(_ t: LessonTemplate, date: Date) -> some View {
        let c = store.course(t.courseID)
        let s = t.slot(for: KBDate.cal.component(.weekday, from: date))
        let col = Color.course(c?.color ?? KBPalette.colors[0])
        let left = c.map { store.remaining($0) } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(s.timeText)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(col)
                Text(c?.name ?? "课程")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                if let c, c.babyIDs.count > 1, let n = ownerName(t, c) {
                    Text(n)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(KB.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(KB.accentSoft)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("剩余 \(left) 节")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(left <= 3 ? KB.warn : KB.dim)
            }
            HStack(spacing: 10) {
                if !s.teacher.isEmpty {
                    Label(s.teacher, systemImage: "person")
                        .font(.system(size: 12)).foregroundStyle(KB.dim)
                }
                if !s.place.isEmpty {
                    Label(s.place, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 12)).foregroundStyle(KB.dim)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                KBButton(title: "请假", filled: false, tint: KB.dim) {
                    sheet = .manual(t, date, .leave)
                }
                KBButton(title: "打卡", icon: "checkmark.circle.fill", tint: col) {
                    sheet = .checkIn(t, date)
                }
            }
        }
        .padding(12)
        .background(Color.courseSoft(c?.color ?? KBPalette.colors[0]).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func courseRow(_ c: Course) -> some View {
        let used = store.consumed(c.id)
        let left = c.total - used
        let col = Color.course(c.color)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(col).frame(width: 9, height: 9)
                Text(c.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(KB.text)
                if !c.tag.isEmpty {
                    Text(c.tag)
                        .font(.system(size: 11))
                        .foregroundStyle(col)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.courseSoft(c.color)).clipShape(Capsule())
                }
                Spacer()
                Text("¥\(Int(c.pricePerLesson))/节")
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
            }
            KBProgress(value: used, total: c.total,
                       color: left <= 3 ? KB.warn : col)
            HStack {
                Text("已上 \(used) / \(c.total) 节")
                    .font(.system(size: 12)).foregroundStyle(KB.dim)
                Spacer()
                Text(left <= 0 ? "已完成" : "剩余 \(left) 节")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(left <= 0 ? col : (left <= 3 ? KB.warn : KB.text))
            }
        }
        .padding(12)
        .background(KB.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
