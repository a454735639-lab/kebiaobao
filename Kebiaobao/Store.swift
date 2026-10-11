import Foundation
import SwiftUI

final class Store: ObservableObject {
    @Published var babies: [Baby] = []
    @Published var courses: [Course] = [] {
        didSet { statsDirty = true; indexDirty = true }
    }
    @Published var templates: [LessonTemplate] = []
    @Published var ledger: [LedgerEntry] = [] {
        didSet { statsDirty = true }
    }

    // MARK: - 课程索引
    //
    // course(id) 原来是 courses.first { … } 线性扫描，而全项目有 39 处调用，
    // 且多处在 ForEach 的每一行里（月历 42 格、记录页每行）。这里建一份字典索引。

    private var indexDirty = true
    private var courseIndex: [UUID: Course] = [:]

    // MARK: - 统计缓存
    //
    // consumed/spent 原本每次调用都全表扫一遍 ledger，而它们又被放进 ForEach 的每一行里，
    // 于是渲染成本是 O(课程数 × 流水数)。这里缓存一份按课程聚合的结果，ledger/courses 变化时才重算。

    private var statsDirty = true
    private var statCache: [UUID: (used: Int, spent: Double)] = [:]
    /// 按月聚合的消课数：key = 年*100+月，value = 归属宝贝ID → 课时（共用年卡按归属人分账）
    private var monthStatCache: [Int: [UUID: Int]] = [:]

    private func stats() -> [UUID: (used: Int, spent: Double)] {
        if statsDirty {
            var m: [UUID: (used: Int, spent: Double)] = [:]
            var byMonth: [Int: [UUID: Int]] = [:]
            let cal = KBDate.cal
            let price = Dictionary(courses.map { ($0.id, $0.pricePerLesson) }, uniquingKeysWith: { a, _ in a })
            let firstBaby = Dictionary(courses.compactMap { c in
                c.babyIDs.first.map { (c.id, $0) }
            }, uniquingKeysWith: { a, _ in a })
            for e in ledger where e.delta < 0 {
                let n = abs(e.delta)
                let p = e.unitPrice ?? price[e.courseID] ?? 0
                var cur = m[e.courseID] ?? (0, 0)
                cur.used += n
                cur.spent += Double(n) * p
                m[e.courseID] = cur
                // 同一趟遍历顺手按月分桶，供「本月」口径复用
                let comps = cal.dateComponents([.year, .month], from: e.date)
                if let y = comps.year, let mo = comps.month,
                   let owner = e.babyID ?? firstBaby[e.courseID] {
                    byMonth[y * 100 + mo, default: [:]][owner, default: 0] += n
                }
            }
            statCache = m
            monthStatCache = byMonth
            statsDirty = false
        }
        return statCache
    }

    /// 一次性取某课程的已消耗/已花费，避免两趟全表扫
    func usedAndSpent(_ courseID: UUID) -> (used: Int, spent: Double) {
        stats()[courseID] ?? (0, 0)
    }
    @Published var currentBabyID: UUID?
    /// 首页是否默认显示全部宝贝。存 UserDefaults（不进 Snapshot，避免旧数据解码失败）
    @Published var allBabies: Bool =
        UserDefaults.standard.object(forKey: "kb.allBabies") as? Bool ?? true {
        didSet { UserDefaults.standard.set(allBabies, forKey: "kb.allBabies") }
    }

    /// 法定节假日不排课（默认开）。存 UserDefaults，不进 Snapshot，避免旧数据解码失败。
    @Published var skipHolidays: Bool =
        UserDefaults.standard.object(forKey: "kb.skipHolidays") as? Bool ?? true {
        didSet { UserDefaults.standard.set(skipHolidays, forKey: "kb.skipHolidays") }
    }

    private var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL { dir.appendingPathComponent("kebiaobao.json") }

    /// 最近一次覆盖式导入前的自动快照
    private var backupURL: URL { dir.appendingPathComponent("kebiaobao.backup.json") }
    /// 解析失败时的现场留存（供人工/后续恢复）
    private var badURL: URL { dir.appendingPathComponent("kebiaobao.bad.json") }

    var hasBackup: Bool { FileManager.default.fileExists(atPath: backupURL.path) }

    var backupDate: Date? {
        (try? backupURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
    }

    struct Snapshot: Codable {
        var babies: [Baby]
        var courses: [Course]
        var templates: [LessonTemplate]
        var ledger: [LedgerEntry]
        var currentBabyID: UUID?
    }

    /// 上次启动时本地数据无法解析。为 true 时禁止写盘，避免把坏文件覆盖掉。
    @Published var loadFailed = false

    init() { load() }

    // MARK: - 持久化

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let s = try JSONDecoder.kb.decode(Snapshot.self, from: data)
            babies = s.babies
            courses = s.courses
            templates = s.templates
            ledger = s.ledger
            currentBabyID = s.currentBabyID ?? s.babies.first?.id
            loadFailed = false
        } catch {
            // 解析失败：另存现场供人工恢复，并停止写盘（否则下一次改动就会覆盖掉原始数据）
            loadFailed = true
            try? FileManager.default.removeItem(at: badURL)
            try? FileManager.default.copyItem(at: fileURL, to: badURL)
        }
    }

    func save() {
        // ponytail: 解析失败时宁可这次改动不落盘，也不覆盖用户唯一的数据文件
        guard !loadFailed else { return }
        write(snapshot(), to: fileURL)
    }

    private func snapshot() -> Snapshot {
        Snapshot(babies: babies, courses: courses, templates: templates,
                 ledger: ledger, currentBabyID: currentBabyID)
    }

    private func write(_ s: Snapshot, to url: URL) {
        guard let data = try? JSONEncoder.kb.encode(s) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 覆盖前快照：把当前数据另存一份，供「恢复上次导入」使用
    func backupNow() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: fileURL, to: backupURL)
    }

    /// 恢复上一次导入前的数据
    func restoreBackup() throws {
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            throw NSError(domain: "kb", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "没有可恢复的备份"])
        }
        let data = try Data(contentsOf: backupURL)
        let s = try JSONDecoder.kb.decode(Snapshot.self, from: data)
        apply(s)
    }

    private func apply(_ s: Snapshot) {
        babies = s.babies
        courses = s.courses
        templates = s.templates
        ledger = s.ledger
        currentBabyID = s.currentBabyID ?? s.babies.first?.id
        // 恢复/导入的数据是可信的，解除「解析失败停写盘」锁，否则恢复结果落不了盘
        loadFailed = false
        save()
    }

    // MARK: - 查询

    var currentBaby: Baby? { babies.first { $0.id == currentBabyID } }

    func baby(_ id: UUID?) -> Baby? { babies.first { $0.id == id } }

    /// 多个宝贝的名字拼串，用于共用年卡的列表显示
    func babyNames(_ ids: [UUID]) -> String {
        let s = ids.compactMap { baby($0)?.name }.joined(separator: "、")
        return s.isEmpty ? "—" : s
    }

    /// 按 id 取课程。走字典索引，不再是线性扫描
    func course(_ id: UUID) -> Course? {
        if indexDirty {
            courseIndex = Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            indexDirty = false
        }
        return courseIndex[id]
    }

    func courses(for babyID: UUID?) -> [Course] {
        courses.filter { (babyID == nil || $0.babyIDs.contains(babyID!)) && !$0.archived && !$0.isPool }
    }

    /// 课时池（年卡）：本身不排课，供多门课多宝宝共用课时
    func pools(for babyID: UUID?) -> [Course] {
        courses.filter { (babyID == nil || $0.babyIDs.contains(babyID!)) && !$0.archived && $0.isPool }
    }

    /// 这门课从哪个池扣课时：有 poolID 就指向年卡，否则自己就是一个池
    func pool(of courseID: UUID) -> Course? {
        guard let c = course(courseID) else { return nil }
        if let pid = c.poolID { return course(pid) ?? c }
        return c
    }

    /// 池子内所有课程的已消耗合计（含池卡自身）
    func poolConsumed(_ poolID: UUID) -> Int {
        courses.filter { $0.id == poolID || $0.poolID == poolID }
            .reduce(0) { $0 + consumed($1.id) }
    }

    /// 当前筛选范围：开启「全部宝贝」时为 nil（= 全部）
    var scope: UUID? { allBabies ? nil : currentBabyID }

    func templates(for courseID: UUID) -> [LessonTemplate] {
        templates.filter { $0.courseID == courseID }
    }

    /// 已消耗课时（正数）
    func consumed(_ courseID: UUID) -> Int { stats()[courseID]?.used ?? 0 }

    /// 已花费金额：优先用记账当时的单价，旧数据回退课程当前单价
    func spent(_ courseID: UUID) -> Double { stats()[courseID]?.spent ?? 0 }

    func remaining(_ course: Course) -> Int {
        // 挂在年卡上的课，剩余看池子总余额（多个宝宝/多门课共用一个池）
        if let pid = course.poolID, let p = self.course(pid) {
            return p.total - poolConsumed(pid)
        }
        return course.total - consumed(course.id)
    }

    /// 池子总余额
    func poolRemaining(_ poolID: UUID) -> Int {
        guard let p = course(poolID) else { return 0 }
        return p.total - poolConsumed(poolID)
    }

    /// 指定月份内的已消耗课时（month 为 nil 则统计全部）
    func consumed(_ courseID: UUID, in month: Date?) -> Int {
        guard let month else { return stats()[courseID]?.used ?? 0 }
        let comps = KBDate.cal.dateComponents([.year, .month], from: month)
        guard let y = comps.year, let mo = comps.month else { return 0 }
        _ = stats()  // 确保按月桶已建好
        return monthStatCache[y * 100 + mo]?[courseID] ?? 0
    }

    func entries(_ courseID: UUID) -> [LedgerEntry] {
        ledger.filter { $0.courseID == courseID }.sorted { $0.date > $1.date }
    }

    /// 本月已上课时。传 babyID 则只算归属该宝宝的（共用年卡按归属人分账）
    func monthConsumed(_ babyID: UUID?) -> Int {
        _ = stats()  // 确保按月桶已建好
        let comps = KBDate.cal.dateComponents([.year, .month], from: Date())
        guard let y = comps.year, let mo = comps.month else { return 0 }
        guard let bucket = monthStatCache[y * 100 + mo] else { return 0 }
        if let babyID { return bucket[babyID] ?? 0 }
        return bucket.values.reduce(0, +)
    }

    /// 剩余课时合计（按池去重：多门课共用一张年卡只算一次）
    func totalRemaining(babyID: UUID?) -> Int {
        var seen = Set<UUID>()
        var sum = 0
        for c in courses(for: babyID) {
            guard seen.insert(c.poolID ?? c.id).inserted else { continue }
            sum += remaining(c)
        }
        return sum
    }

    func remainingValue(_ courseID: UUID) -> Double {
        guard let c = course(courseID) else { return 0 }
        // 挂年卡的课按池子的单价折算剩余价值
        let price = pool(of: courseID)?.pricePerLesson ?? c.pricePerLesson
        return Double(remaining(c)) * price
    }

    /// 该日期是否因法定节假日而不排课
    func isSkipped(_ date: Date) -> Bool { skipHolidays && Holiday.isHoliday(date) }

    /// 某天的课（展开排课模板），按当天的实际时间排序。
    /// 法定节假日（且未关闭该规则）返回空 —— 调休补班日照常上课。
    /// 购买日之前不排课（旧数据 boughtAt 回退到 createdAt）。
    func lessons(on date: Date, babyID: UUID?) -> [LessonTemplate] {
        if isSkipped(date) { return [] }
        let w = KBDate.cal.component(.weekday, from: date)
        let d = KBDate.day(date)
        // course(_:) 走字典索引，不再是 O(课程数) 扫描
        return templates.filter { t in
            guard t.weekdays.contains(w), let c = course(t.courseID), !c.archived else { return false }
            guard d >= KBDate.day(c.boughtAt) else { return false }
            guard let s = babyID else { return true }
            // 排课指定了归属就用它；否则按课程成员判定（共用年卡两个宝宝都看得到）
            if let owner = t.babyID { return owner == s }
            return c.babyIDs.contains(s)
        }.sorted {
            let a = $0.slot(for: w), b = $1.slot(for: w)
            return (a.hour, a.minute) < (b.hour, b.minute)
        }
    }

    /// 未来 N 天内有课的日期集合
    func upcomingDays(days: Int, babyID: UUID?) -> [Date] {
        let today = KBDate.day(Date())
        return (0..<days).compactMap { off -> Date? in
            guard let d = KBDate.cal.date(byAdding: .day, value: off, to: today) else { return nil }
            return lessons(on: d, babyID: babyID).isEmpty ? nil : d
        }
    }

    // MARK: - 变更

    /// 打卡结果
    enum CheckInResult { case ok, duplicate, expired }

    /// 课程是否已过期（按天比较，当天仍可上课）
    func isExpired(_ courseID: UUID) -> Bool {
        // 挂年卡的课按池子的有效期判（一张卡一个到期日）
        guard let c = pool(of: courseID) ?? course(courseID) else { return false }
        return KBDate.day(Date()) > KBDate.day(c.expiry)
    }

    /// 这条排课的归属宝宝：模板指定优先，否则取课程的第一个宝贝
    func owner(of template: LessonTemplate) -> UUID? {
        template.babyID ?? course(template.courseID)?.babyIDs.first
    }

    /// 打卡。同一天同一排课（同一宝宝）已有扣课记录时返回 .duplicate，不重复记账。
    @discardableResult
    func checkIn(_ template: LessonTemplate, on date: Date) -> CheckInResult {
        if isExpired(template.courseID) { return .expired }
        let day = KBDate.day(date)
        let who = owner(of: template)
        let dup = ledger.contains {
            $0.courseID == template.courseID && $0.kind == .consume &&
            $0.babyID == who &&
            KBDate.isSameDay($0.date, day)
        }
        if dup { return .duplicate }
        ledger.append(LedgerEntry(courseID: template.courseID, date: date,
                                  delta: -abs(template.deduct), kind: .consume,
                                  note: "正常上课",
                                  unitPrice: pool(of: template.courseID)?.pricePerLesson
                                             ?? course(template.courseID)?.pricePerLesson,
                                  babyID: who))
        save()
        return .ok
    }

    /// 加课时。挂在年卡上的课，课时加到池子上（一张卡共享）
    func charge(_ courseID: UUID, lessons: Int, price: Double, note: String,
                babyID: UUID? = nil) {
        let target = course(courseID)?.poolID ?? courseID
        guard let i = courses.firstIndex(where: { $0.id == target }) else { return }
        let unit = price > 0 ? price : courses[i].pricePerLesson
        courses[i].total += lessons
        if price > 0 { courses[i].pricePerLesson = price }
        ledger.append(LedgerEntry(courseID: target, date: Date(),
                                  delta: lessons, kind: .charge, note: note,
                                  unitPrice: unit, babyID: babyID))
        save()
    }

    /// 手动记账：扣课时 / 请假 / 加课时。独立于排课，可自选日期与课时数。
    enum ManualOp: Hashable { case consume, leave, charge }

    func recordManual(_ op: ManualOp, courseID: UUID, lessons: Int, date: Date,
                      note: String, price: Double, babyID: UUID? = nil) {
        let n = max(1, lessons)
        let memo = note.isEmpty ? Self.manualDefaultNote(op) : note
        let who = babyID ?? course(courseID)?.babyIDs.first
        switch op {
        case .consume:
            ledger.append(LedgerEntry(courseID: courseID, date: date, delta: -n,
                                      kind: .consume, note: memo,
                                      unitPrice: course(courseID)?.pricePerLesson,
                                      babyID: who))
        case .leave:
            ledger.append(LedgerEntry(courseID: courseID, date: date, delta: 0,
                                      kind: .leave, note: memo, babyID: who))
        case .charge:
            // 课时加到池子上（挂年卡的课共享一张卡）
            let target = course(courseID)?.poolID ?? courseID
            guard let i = courses.firstIndex(where: { $0.id == target }) else { return }
            let unit = price > 0 ? price : courses[i].pricePerLesson
            courses[i].total += n
            if price > 0 { courses[i].pricePerLesson = price }
            ledger.append(LedgerEntry(courseID: target, date: date, delta: n,
                                      kind: .charge, note: memo, unitPrice: unit,
                                      babyID: who))
        }
        save()
    }

    /// 补填最后一条流水的备注与课后小结（打卡弹窗用）
    func updateLastEntry(note: String?, summary: String?) {
        guard let i = ledger.indices.last else { return }
        if let note, !note.isEmpty, note != "正常上课" { ledger[i].note = note }
        if let summary {
            let s = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            ledger[i].summary = s.isEmpty ? nil : s
        }
        save()
    }

    /// 结课归档：保留流水与排课，仅从首页／课表隐藏
    func setArchived(_ courseID: UUID, _ archived: Bool) {
        guard let i = courses.firstIndex(where: { $0.id == courseID }) else { return }
        courses[i].archived = archived
        save()
    }

    /// 已归档课程（不进 scope 过滤）
    func archivedCourses() -> [Course] { courses.filter(\.archived) }

    func deleteTemplate(_ id: UUID) {
        templates.removeAll { $0.id == id }
        save()
    }

    static func manualDefaultNote(_ op: ManualOp) -> String {
        switch op {
        case .consume: return "手动扣课时"
        case .leave:   return "请假（不扣课时）"
        case .charge:  return "补录课时"
        }
    }

    /// 撤销一条流水（反向记账）
    func undo(_ entry: LedgerEntry) {
        guard let i = ledger.firstIndex(where: { $0.id == entry.id }) else { return }
        if entry.kind == .charge, let ci = courses.firstIndex(where: { $0.id == entry.courseID }) {
            courses[ci].total -= entry.delta
            // 撤销充值同时还原被改掉的单价，否则单价永久留在新值
            if let prev = entry.prevPrice { courses[ci].pricePerLesson = prev }
        }
        ledger.remove(at: i)
        save()
    }

    /// 修改某条流水的备注
    func updateNote(_ entry: LedgerEntry, note: String) {
        guard let i = ledger.firstIndex(where: { $0.id == entry.id }) else { return }
        ledger[i].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    /// 修改某条流水的课后小结
    func updateSummary(_ entry: LedgerEntry, summary: String) {
        guard let i = ledger.firstIndex(where: { $0.id == entry.id }) else { return }
        let s = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        ledger[i].summary = s.isEmpty ? nil : s
        save()
    }

    func deleteCourse(_ id: UUID) {
        backupNow()
        // 删的是年卡：挂在它下面的课改为自成一池，不跟着消失
        for i in courses.indices where courses[i].poolID == id {
            courses[i].poolID = nil
            // 池子剩余课时是共用的，无法拆分 → 至少把本课已上的部分补齐，
            // 免得 total 小于已上数、剩余显示成负数
            courses[i].total = max(courses[i].total, consumed(courses[i].id))
        }
        courses.removeAll { $0.id == id }
        templates.removeAll { $0.courseID == id }
        ledger.removeAll { $0.courseID == id }
        save()
    }

    /// 删除宝贝，连同其课程、排课、流水（原来只删宝贝和课程，留下孤儿排课与流水）
    func deleteBaby(_ id: UUID) {
        backupNow()
        babies.removeAll { $0.id == id }
        // 共用年卡不能被一个宝宝带走：只摘除该宝贝；独享课程才整条删
        for i in courses.indices {
            courses[i].babyIDs.removeAll { $0 == id }
        }
        let dropped = Set(courses.filter { $0.babyIDs.isEmpty }.map(\.id))
        courses.removeAll { $0.babyIDs.isEmpty }
        // 池卡被删时，挂在它下面的课改为自成一池
        for i in courses.indices where courses[i].poolID.map({ dropped.contains($0) }) == true {
            courses[i].poolID = nil
        }
        let alive = Set(courses.map(\.id))
        templates.removeAll { !alive.contains($0.courseID) }
        ledger.removeAll { !alive.contains($0.courseID) }
        // 归属该宝贝的流水改挂到课程剩余的第一个宝贝
        for i in ledger.indices where ledger[i].babyID == id {
            ledger[i].babyID = course(ledger[i].courseID)?.babyIDs.first
        }
        if currentBabyID == id { currentBabyID = babies.first?.id }
        save()
    }

    // MARK: - Excel 导出 / 导入

    /// 单课程导出：只含该课程及其排课、流水、所属宝贝
    func exportXLSX(courseID: UUID? = nil) -> Data {
        let cs: [Course]
        if let courseID {
            cs = courses.filter { $0.id == courseID || $0.id == course(courseID)?.poolID }
        } else { cs = courses }
        let ids = Set(cs.map(\.id))
        let bs = babies.filter { b in courseID == nil || cs.contains { $0.babyIDs.contains(b.id) } }

        var babyRows: [[String]] = [["ID", "姓名", "生日"]]
        for b in bs {
            babyRows.append([b.id.uuidString, b.name,
                             b.birthday.map { KBDate.ymd.string(from: $0) } ?? ""])
        }

        var courseRows: [[String]] = [["ID", "宝贝ID", "宝贝", "课程", "标签",
                                       "总课时", "已用", "剩余", "单价", "总价", "购买时间", "到期日",
                                       "年卡", "年卡ID"]]
        for c in cs {
            let used = c.isPool ? poolConsumed(c.id) : consumed(c.id)
            courseRows.append([c.id.uuidString,
                               c.babyIDs.map(\.uuidString).joined(separator: ","),
                               c.babyIDs.compactMap { baby($0)?.name }.joined(separator: "、"),
                               c.name, c.tag,
                               "\(c.total)", "\(used)", "\(c.total - used)",
                               String(format: "%g", c.pricePerLesson),
                               String(format: "%.2f", c.totalFee),
                               KBDate.ymd.string(from: c.boughtAt),
                               KBDate.ymd.string(from: c.expiry),
                               c.isPool ? "是" : "",
                               c.poolID?.uuidString ?? ""])
        }

        var slotRows: [[String]] = [["排课ID", "课程ID", "课程", "星期", "时间",
                                     "老师", "地点", "每次划扣", "提前提醒(分)", "归属宝贝ID"]]
        for t in templates where ids.contains(t.courseID) {
            for s in t.orderedSlots {
                slotRows.append([t.id.uuidString, t.courseID.uuidString,
                                 course(t.courseID)?.name ?? "",
                                 s.dayName, s.timeText, s.teacher, s.place,
                                 "\(t.deduct)", "\(t.remindMinutes)",
                                 t.babyID?.uuidString ?? ""])
            }
        }

        var entryRows: [[String]] = [["流水ID", "课程ID", "课程", "日期", "类型",
                                      "课时", "单价", "备注", "课后小结", "归属宝贝ID"]]
        for e in ledger.filter({ ids.contains($0.courseID) }).sorted(by: { $0.date < $1.date }) {
            entryRows.append([e.id.uuidString, e.courseID.uuidString,
                              course(e.courseID)?.name ?? "",
                              KBDate.mdhm.string(from: e.date), e.kind.label,
                              "\(e.delta)",
                              String(format: "%g", e.unitPrice ?? course(e.courseID)?.pricePerLesson ?? 0),
                              e.note, e.summary ?? "", e.babyID?.uuidString ?? ""])
        }

        let name = cs.count == 1 ? cs[0].name : "全部课程"
        return XLSX.build([
            XLSX.Sheet(name: "宝贝", rows: babyRows),
            XLSX.Sheet(name: Self.safeSheet(name), rows: courseRows),
            XLSX.Sheet(name: "排课", rows: slotRows),
            XLSX.Sheet(name: "流水", rows: entryRows),
        ])
    }

    /// Excel 表名限制：≤31 字符，且不含 []:*?/\
    static func safeSheet(_ s: String) -> String {
        let bad: [Character: String] = ["[": "（", "]": "）", ":": "：",
                                        "*": "＊", "?": "？", "/": "／", "\\": "＼"]
        var t = String(s.map { bad[$0] ?? String($0) }.joined()
                        .prefix(31))
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "课程" : t
    }

    /// 按表头名识别列；找不到同名表时退回「含指定表头」的第一张表
    private func table(_ sheets: [XLSX.Sheet], _ name: String,
                       requiring headers: [String] = []) -> [[String: String]] {
        let s = sheets.first { $0.name == name }
            ?? sheets.first { sh in
                guard !headers.isEmpty, let h = sh.rows.first else { return false }
                return headers.allSatisfy { h.contains($0) }
            }
        guard let s, let head = s.rows.first else { return [] }
        return s.rows.dropFirst().compactMap { r in
            guard r.contains(where: { !$0.isEmpty }) else { return nil }
            var d: [String: String] = [:]
            for (i, h) in head.enumerated() where !h.isEmpty {
                d[h] = i < r.count ? r[i] : ""
            }
            return d
        }
    }

    /// 导入预览：解析后统计条数，供用户确认后再落库
    struct ImportPreview: Identifiable {
        let id = UUID()
        let snapshot: Snapshot
        let babyCount: Int
        let courseCount: Int
        let templateCount: Int
        let ledgerCount: Int
        /// 被跳过的行（日期无法识别等），让用户在确认前看到
        var skipped: [String] = []
        var summary: String {
            let base = "宝贝 \(babyCount) · 课程 \(courseCount) · 排课 \(templateCount) · 流水 \(ledgerCount)"
            return skipped.isEmpty ? base : base + "\n跳过 \(skipped.count) 行：\n" + skipped.prefix(5).joined(separator: "\n")
        }
    }

    /// 只解析不落库；覆盖式导入：按表头名识别列，ID 列用于还原关联
    func parseXLSX(_ data: Data) throws -> ImportPreview {
        let sheets = XLSX.parse(data)
        guard !sheets.isEmpty else {
            throw NSError(domain: "kb", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "无法识别 Excel 文件"])
        }

        var newBabies: [Baby] = []
        for r in table(sheets, "宝贝") {
            let name = (r["姓名"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            var b = Baby(id: UUID(uuidString: r["ID"] ?? "") ?? UUID(), name: name, birthday: nil)
            if let d = r["生日"], !d.isEmpty { b.birthday = KBDate.ymd.date(from: d) }
            newBabies.append(b)
        }
        let babyIDs = Set(newBabies.map(\.id))

        // 课程表可能是「课程」「全部课程」或课程名，按表头识别
        var newCourses: [Course] = []
        for r in table(sheets, "课程", requiring: ["课程", "总课时"]) {
            let name = (r["课程"] ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            // 宝贝ID 可多个（逗号分隔，年卡共用课时）。至少要有一个能在宝贝表里找到
            let bids = (r["宝贝ID"] ?? "").split(separator: ",")
                .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
                .filter { babyIDs.contains($0) }
            guard !bids.isEmpty else {
                throw NSError(domain: "kb", code: 5, userInfo: [NSLocalizedDescriptionKey:
                    "课程「\(name)」的宝贝ID 在「宝贝」表里找不到，导入会丢数据。请检查导出文件是否完整。"])
            }
            // 到期日解析不出来时不能静默变成「今天」——那会让课程立刻显示为已过期
            guard let exp = KBDate.ymd.date(from: r["到期日"] ?? "") else {
                throw NSError(domain: "kb", code: 6, userInfo: [NSLocalizedDescriptionKey:
                    "课程「\(name)」的到期日「\(r["到期日"] ?? "")」无法识别（应为 2026-01-31 这样的格式）。"])
            }
            let c = Course(id: UUID(uuidString: r["ID"] ?? "") ?? UUID(),
                           babyIDs: bids, name: name,
                           tag: r["标签"] ?? "",
                           total: Int(r["总课时"] ?? "") ?? 0,
                           pricePerLesson: Double(r["单价"] ?? "") ?? 0,
                           expiry: exp,
                           purchasedAt: KBDate.ymd.date(from: r["购买时间"] ?? ""),
                           isPool: (r["年卡"] ?? "") == "是",
                           poolID: UUID(uuidString: r["年卡ID"] ?? ""))
            newCourses.append(c)
        }
        let courseIDs = Set(newCourses.map(\.id))

        // 排课：按排课ID 聚合，同一模板的多个星期合成一条
        var newTemplates: [LessonTemplate] = []
        let slotRows = table(sheets, "排课", requiring: ["排课ID", "星期"]).filter {
            courseIDs.contains(UUID(uuidString: $0["课程ID"] ?? "") ?? UUID())
        }
        // 先按排课ID 分组：原来对每个模板都重扫一遍全表，是 O(模板 × 行数)
        var byTemplate: [UUID: [[String: String]]] = [:]
        var order: [UUID] = []
        for r in slotRows {
            guard let tid = UUID(uuidString: r["排课ID"] ?? "") else { continue }
            if byTemplate[tid] == nil { order.append(tid) }
            byTemplate[tid, default: []].append(r)
        }
        for tid in order {
            guard let days = byTemplate[tid], let r = days.first else { continue }
            let weeks = days.compactMap { d -> Int? in
                guard let n = KBDate.weekdayCN.firstIndex(of: d["星期"] ?? "") else { return nil }
                return n == 0 ? nil : n
            }
            guard !weeks.isEmpty, let cid = UUID(uuidString: r["课程ID"] ?? "") else { continue }
            let slots = days.compactMap { d -> DaySlot? in
                guard let n = KBDate.weekdayCN.firstIndex(of: d["星期"] ?? ""), n != 0 else { return nil }
                let hm = (d["时间"] ?? "").split(separator: ":")
                return DaySlot(weekday: n,
                               hour: hm.count == 2 ? (Int(hm[0]) ?? 0) : 0,
                               minute: hm.count == 2 ? (Int(hm[1]) ?? 0) : 0,
                               teacher: d["老师"] ?? "", place: d["地点"] ?? "")
            }
            let first = slots.first
            newTemplates.append(LessonTemplate(
                id: tid, courseID: cid, weekdays: weeks.sorted(),
                hour: first?.hour ?? 0, minute: first?.minute ?? 0,
                place: first?.place ?? "", teacher: first?.teacher ?? "",
                deduct: Int(r["每次划扣"] ?? "") ?? 1,
                remindMinutes: Int(r["提前提醒(分)"] ?? "") ?? 0,
                slots: slots,
                babyID: UUID(uuidString: r["归属宝贝ID"] ?? "")))
        }

        let kinds: [String: RecordKind] = Dictionary(uniqueKeysWithValues:
            RecordKind.allCases.map { ($0.label, $0) })
        var newLedger: [LedgerEntry] = []
        var badRows: [String] = []
        for r in table(sheets, "流水", requiring: ["流水ID", "课程ID"]) {
            guard let cid = UUID(uuidString: r["课程ID"] ?? ""), courseIDs.contains(cid) else { continue }
            // 日期解析失败就跳过该行并记录，而不是静默记成「今天」
            guard let date = KBDate.mdhm.date(from: r["日期"] ?? "")
                    ?? KBDate.ymd.date(from: r["日期"] ?? "") else {
                badRows.append("流水日期「\(r["日期"] ?? "")」无法识别")
                continue
            }
            let sum = (r["课后小结"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            newLedger.append(LedgerEntry(
                id: UUID(uuidString: r["流水ID"] ?? "") ?? UUID(),
                courseID: cid, date: date,
                delta: Int(r["课时"] ?? "") ?? 0,
                kind: kinds[r["类型"] ?? ""] ?? .consume,
                note: r["备注"] ?? "",
                summary: sum.isEmpty ? nil : sum,
                unitPrice: Double(r["单价"] ?? ""),
                babyID: UUID(uuidString: r["归属宝贝ID"] ?? "")))
        }

        guard !newCourses.isEmpty || !newBabies.isEmpty else {
            throw NSError(domain: "kb", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "表格里没有可导入的数据"])
        }

        return ImportPreview(
            snapshot: Snapshot(babies: newBabies, courses: newCourses,
                               templates: newTemplates, ledger: newLedger,
                               currentBabyID: newBabies.first?.id),
            babyCount: newBabies.count, courseCount: newCourses.count,
            templateCount: newTemplates.count, ledgerCount: newLedger.count,
            skipped: badRows)
    }

    /// 应用一份已解析的导入结果（用户确认后调用）
    func commitImport(_ p: ImportPreview) {
        backupNow()
        apply(p.snapshot)
    }
}
