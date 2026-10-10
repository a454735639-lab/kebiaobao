import Foundation
import SwiftUI

final class Store: ObservableObject {
    @Published var babies: [Baby] = []
    @Published var courses: [Course] = []
    @Published var templates: [LessonTemplate] = []
    @Published var ledger: [LedgerEntry] = []
    @Published var currentBabyID: UUID?
    /// true = 显示全部宝贝的数据（currentBabyID 被忽略）
    @Published var allBabies = false

    private var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var fileURL: URL { dir.appendingPathComponent("kebiaobao.json") }

    /// 最近一次覆盖式导入前的自动快照
    private var backupURL: URL { dir.appendingPathComponent("kebiaobao.backup.json") }

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

    init() { load() }

    // MARK: - 持久化

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder.kb.decode(Snapshot.self, from: data) else { return }
        babies = s.babies
        courses = s.courses
        templates = s.templates
        ledger = s.ledger
        currentBabyID = s.currentBabyID ?? s.babies.first?.id
    }

    func save() {
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
        if allBabies && babies.count <= 1 { allBabies = false }
        save()
    }

    // MARK: - 查询

    var currentBaby: Baby? { babies.first { $0.id == currentBabyID } }

    func baby(_ id: UUID?) -> Baby? { babies.first { $0.id == id } }

    func course(_ id: UUID) -> Course? { courses.first { $0.id == id } }

    func courses(for babyID: UUID?) -> [Course] {
        courses.filter { (babyID == nil || $0.babyID == babyID) && !$0.archived }
    }

    /// 当前筛选范围：开启「全部宝贝」时为 nil（= 全部）
    var scope: UUID? { allBabies ? nil : currentBabyID }

    func templates(for courseID: UUID) -> [LessonTemplate] {
        templates.filter { $0.courseID == courseID }
    }

    /// 已消耗课时（正数）
    func consumed(_ courseID: UUID) -> Int {
        ledger.filter { $0.courseID == courseID && $0.delta < 0 }
              .reduce(0) { $0 + abs($1.delta) }
    }

    /// 已花费金额：优先用记账当时的单价，旧数据回退课程当前单价
    func spent(_ courseID: UUID) -> Double {
        let c = course(courseID)
        return ledger.filter { $0.courseID == courseID && $0.delta < 0 }
            .reduce(0) { $0 + Double(abs($1.delta)) * ($1.unitPrice ?? c?.pricePerLesson ?? 0) }
    }

    func remaining(_ course: Course) -> Int { course.total - consumed(course.id) }

    func entries(_ courseID: UUID) -> [LedgerEntry] {
        ledger.filter { $0.courseID == courseID }.sorted { $0.date > $1.date }
    }

    /// 本月已上课时（按扣课记录数）
    func monthConsumed(_ babyID: UUID?) -> Int {
        let cal = KBDate.cal
        let now = Date()
        return ledger.filter { e in
            e.delta < 0 && e.kind == .consume &&
            cal.isDate(e.date, equalTo: now, toGranularity: .month) &&
            (babyID == nil || course(e.courseID)?.babyID == babyID)
        }.reduce(0) { $0 + abs($1.delta) }
    }

    func remainingValue(_ courseID: UUID) -> Double {
        guard let c = course(courseID) else { return 0 }
        return Double(remaining(c)) * c.pricePerLesson
    }

    /// 某天的课（展开排课模板），按当天的实际时间排序
    func lessons(on date: Date, babyID: UUID?) -> [LessonTemplate] {
        let w = KBDate.cal.component(.weekday, from: date)
        return templates.filter { t in
            t.weekdays.contains(w) &&
            (babyID == nil || course(t.courseID)?.babyID == babyID) &&
            (course(t.courseID)?.archived == false)
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
    enum CheckInResult { case ok, duplicate }

    /// 打卡。同一天同一排课已有扣课记录时返回 .duplicate，不重复记账。
    @discardableResult
    func checkIn(_ template: LessonTemplate, on date: Date) -> CheckInResult {
        let day = KBDate.day(date)
        let dup = ledger.contains {
            $0.courseID == template.courseID && $0.kind == .consume &&
            KBDate.isSameDay($0.date, day)
        }
        if dup { return .duplicate }
        ledger.append(LedgerEntry(courseID: template.courseID, date: date,
                                  delta: -abs(template.deduct), kind: .consume,
                                  note: "正常上课",
                                  unitPrice: course(template.courseID)?.pricePerLesson))
        save()
        return .ok
    }

    func takeLeave(_ template: LessonTemplate, on date: Date) {
        let e = LedgerEntry(courseID: template.courseID, date: date,
                            delta: 0, kind: .leave, note: "请假（不扣课时）")
        ledger.append(e)
        save()
    }

    func charge(_ courseID: UUID, lessons: Int, price: Double, note: String) {
        guard let i = courses.firstIndex(where: { $0.id == courseID }) else { return }
        let unit = price > 0 ? price : courses[i].pricePerLesson
        courses[i].total += lessons
        if price > 0 { courses[i].pricePerLesson = price }
        ledger.append(LedgerEntry(courseID: courseID, date: Date(),
                                  delta: lessons, kind: .charge, note: note,
                                  unitPrice: unit))
        save()
    }

    /// 手动记账：扣课时 / 请假 / 加课时。独立于排课，可自选日期与课时数。
    enum ManualOp: Hashable { case consume, leave, charge }

    func recordManual(_ op: ManualOp, courseID: UUID, lessons: Int, date: Date,
                      note: String, price: Double) {
        let n = max(1, lessons)
        let memo = note.isEmpty ? Self.manualDefaultNote(op) : note
        switch op {
        case .consume:
            ledger.append(LedgerEntry(courseID: courseID, date: date, delta: -n,
                                      kind: .consume, note: memo,
                                      unitPrice: course(courseID)?.pricePerLesson))
        case .leave:
            ledger.append(LedgerEntry(courseID: courseID, date: date, delta: 0,
                                      kind: .leave, note: memo))
        case .charge:
            guard let i = courses.firstIndex(where: { $0.id == courseID }) else { return }
            let unit = price > 0 ? price : courses[i].pricePerLesson
            courses[i].total += n
            if price > 0 { courses[i].pricePerLesson = price }
            ledger.append(LedgerEntry(courseID: courseID, date: date, delta: n,
                                      kind: .charge, note: memo, unitPrice: unit))
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
        courses.removeAll { $0.id == id }
        templates.removeAll { $0.courseID == id }
        ledger.removeAll { $0.courseID == id }
        save()
    }

    // MARK: - Excel 导出 / 导入

    /// 单课程导出：只含该课程及其排课、流水、所属宝贝
    func exportXLSX(courseID: UUID? = nil) -> Data {
        let cs: [Course]
        if let courseID { cs = courses.filter { $0.id == courseID } } else { cs = courses }
        let ids = Set(cs.map(\.id))
        let bs = babies.filter { b in courseID == nil || cs.contains { $0.babyID == b.id } }

        var babyRows: [[String]] = [["ID", "姓名", "生日"]]
        for b in bs {
            babyRows.append([b.id.uuidString, b.name,
                             b.birthday.map { KBDate.ymd.string(from: $0) } ?? ""])
        }

        var courseRows: [[String]] = [["ID", "宝贝ID", "宝贝", "课程", "标签",
                                       "总课时", "已用", "剩余", "单价", "总价", "购买时间", "到期日"]]
        for c in cs {
            let used = consumed(c.id)
            courseRows.append([c.id.uuidString, c.babyID.uuidString,
                               baby(c.babyID)?.name ?? "", c.name, c.tag,
                               "\(c.total)", "\(used)", "\(c.total - used)",
                               String(format: "%g", c.pricePerLesson),
                               String(format: "%.2f", c.totalFee),
                               KBDate.ymd.string(from: c.boughtAt),
                               KBDate.ymd.string(from: c.expiry)])
        }

        var slotRows: [[String]] = [["排课ID", "课程ID", "课程", "星期", "时间",
                                     "老师", "地点", "每次划扣", "提前提醒(分)"]]
        for t in templates where ids.contains(t.courseID) {
            for s in t.orderedSlots {
                slotRows.append([t.id.uuidString, t.courseID.uuidString,
                                 course(t.courseID)?.name ?? "",
                                 s.dayName, s.timeText, s.teacher, s.place,
                                 "\(t.deduct)", "\(t.remindMinutes)"])
            }
        }

        var entryRows: [[String]] = [["流水ID", "课程ID", "课程", "日期", "类型",
                                      "课时", "单价", "备注", "课后小结"]]
        for e in ledger.filter({ ids.contains($0.courseID) }).sorted(by: { $0.date < $1.date }) {
            entryRows.append([e.id.uuidString, e.courseID.uuidString,
                              course(e.courseID)?.name ?? "",
                              KBDate.mdhm.string(from: e.date), e.kind.label,
                              "\(e.delta)",
                              String(format: "%g", e.unitPrice ?? course(e.courseID)?.pricePerLesson ?? 0),
                              e.note, e.summary ?? ""])
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
        var summary: String {
            "宝贝 \(babyCount) · 课程 \(courseCount) · 排课 \(templateCount) · 流水 \(ledgerCount)"
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
            // 宝贝ID 必须能在宝贝表里找到，否则课程会挂到不可见的孤儿宝贝上
            guard let bid = UUID(uuidString: r["宝贝ID"] ?? ""), babyIDs.contains(bid) else {
                throw NSError(domain: "kb", code: 5, userInfo: [NSLocalizedDescriptionKey:
                    "课程「\(name)」的宝贝ID 在「宝贝」表里找不到，导入会丢数据。请检查导出文件是否完整。"])
            }
            let c = Course(id: UUID(uuidString: r["ID"] ?? "") ?? UUID(),
                           babyID: bid, name: name,
                           tag: r["标签"] ?? "",
                           total: Int(r["总课时"] ?? "") ?? 0,
                           pricePerLesson: Double(r["单价"] ?? "") ?? 0,
                           expiry: KBDate.ymd.date(from: r["到期日"] ?? "") ?? Date(),
                           purchasedAt: KBDate.ymd.date(from: r["购买时间"] ?? ""))
            newCourses.append(c)
        }
        let courseIDs = Set(newCourses.map(\.id))

        // 排课：按排课ID 聚合，同一模板的多个星期合成一条
        var newTemplates: [LessonTemplate] = []
        let slotRows = table(sheets, "排课", requiring: ["排课ID", "星期"]).filter {
            courseIDs.contains(UUID(uuidString: $0["课程ID"] ?? "") ?? UUID())
        }
        var grouped: [UUID: [String: String]] = [:]
        var order: [UUID] = []
        for r in slotRows {
            guard let tid = UUID(uuidString: r["排课ID"] ?? "") else { continue }
            if grouped[tid] == nil { grouped[tid] = r; order.append(tid) }
        }
        for tid in order {
            guard let r = grouped[tid] else { continue }
            let days = slotRows.filter { $0["排课ID"] == r["排课ID"] }
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
                slots: slots))
        }

        let kinds: [String: RecordKind] = Dictionary(uniqueKeysWithValues:
            RecordKind.allCases.map { ($0.label, $0) })
        var newLedger: [LedgerEntry] = []
        for r in table(sheets, "流水", requiring: ["流水ID", "课程ID"]) {
            guard let cid = UUID(uuidString: r["课程ID"] ?? ""), courseIDs.contains(cid) else { continue }
            let date = KBDate.mdhm.date(from: r["日期"] ?? "")
                ?? KBDate.ymd.date(from: r["日期"] ?? "") ?? Date()
            let sum = (r["课后小结"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            newLedger.append(LedgerEntry(
                id: UUID(uuidString: r["流水ID"] ?? "") ?? UUID(),
                courseID: cid, date: date,
                delta: Int(r["课时"] ?? "") ?? 0,
                kind: kinds[r["类型"] ?? ""] ?? .consume,
                note: r["备注"] ?? "",
                summary: sum.isEmpty ? nil : sum,
                unitPrice: Double(r["单价"] ?? "")))
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
            templateCount: newTemplates.count, ledgerCount: newLedger.count)
    }

    /// 应用一份已解析的导入结果（用户确认后调用）
    func commitImport(_ p: ImportPreview) {
        backupNow()
        apply(p.snapshot)
    }
}
