import Foundation
import SwiftUI

final class Store: ObservableObject {
    @Published var babies: [Baby] = []
    @Published var courses: [Course] = []
    @Published var templates: [LessonTemplate] = []
    @Published var ledger: [LedgerEntry] = []
    @Published var currentBabyID: UUID?

    private var fileURL: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return d.appendingPathComponent("kebiaobao.json")
    }

    private struct Snapshot: Codable {
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
        let s = Snapshot(babies: babies, courses: courses, templates: templates,
                         ledger: ledger, currentBabyID: currentBabyID)
        guard let data = try? JSONEncoder.kb.encode(s) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 查询

    var currentBaby: Baby? { babies.first { $0.id == currentBabyID } }

    func baby(_ id: UUID?) -> Baby? { babies.first { $0.id == id } }

    func course(_ id: UUID) -> Course? { courses.first { $0.id == id } }

    func courses(for babyID: UUID?) -> [Course] {
        guard let babyID else { return [] }
        return courses.filter { $0.babyID == babyID && !$0.archived }
    }

    func templates(for courseID: UUID) -> [LessonTemplate] {
        templates.filter { $0.courseID == courseID }
    }

    /// 已消耗课时（正数）
    func consumed(_ courseID: UUID) -> Int {
        ledger.filter { $0.courseID == courseID && $0.delta < 0 }
              .reduce(0) { $0 + abs($1.delta) }
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

    func spent(_ courseID: UUID) -> Double {
        guard let c = course(courseID) else { return 0 }
        return Double(consumed(courseID)) * c.pricePerLesson
    }

    func remainingValue(_ courseID: UUID) -> Double {
        guard let c = course(courseID) else { return 0 }
        return Double(remaining(c)) * c.pricePerLesson
    }

    /// 某天的课（展开排课模板）
    func lessons(on date: Date, babyID: UUID?) -> [LessonTemplate] {
        let w = KBDate.cal.component(.weekday, from: date)
        return templates.filter { t in
            t.weekdays.contains(w) &&
            (babyID == nil || course(t.courseID)?.babyID == babyID) &&
            (course(t.courseID)?.archived == false)
        }.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
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

    func checkIn(_ template: LessonTemplate, on date: Date) {
        let e = LedgerEntry(courseID: template.courseID, date: date,
                            delta: -abs(template.deduct), kind: .consume, note: "正常上课")
        ledger.append(e)
        save()
    }

    func takeLeave(_ template: LessonTemplate, on date: Date) {
        let e = LedgerEntry(courseID: template.courseID, date: date,
                            delta: 0, kind: .leave, note: "请假（不扣课时）")
        ledger.append(e)
        save()
    }

    func charge(_ courseID: UUID, lessons: Int, price: Double, note: String) {
        guard let i = courses.firstIndex(where: { $0.id == courseID }) else { return }
        courses[i].total += lessons
        if price > 0 { courses[i].pricePerLesson = price }
        ledger.append(LedgerEntry(courseID: courseID, date: Date(),
                                  delta: lessons, kind: .charge, note: note))
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
                                      kind: .consume, note: memo))
        case .leave:
            ledger.append(LedgerEntry(courseID: courseID, date: date, delta: 0,
                                      kind: .leave, note: memo))
        case .charge:
            guard let i = courses.firstIndex(where: { $0.id == courseID }) else { return }
            courses[i].total += n
            if price > 0 { courses[i].pricePerLesson = price }
            ledger.append(LedgerEntry(courseID: courseID, date: date, delta: n,
                                      kind: .charge, note: memo))
        }
        save()
    }

    private static func manualDefaultNote(_ op: ManualOp) -> String {
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

    func deleteCourse(_ id: UUID) {
        courses.removeAll { $0.id == id }
        templates.removeAll { $0.courseID == id }
        ledger.removeAll { $0.courseID == id }
        save()
    }

    // MARK: - 导入导出

    func exportJSON() -> String {
        let s = Snapshot(babies: babies, courses: courses, templates: templates,
                         ledger: ledger, currentBabyID: currentBabyID)
        guard let data = try? JSONEncoder.kb.encode(s),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    func importJSON(_ text: String) throws {
        guard let data = text.data(using: .utf8) else { throw NSError(domain: "kb", code: 1) }
        let s = try JSONDecoder.kb.decode(Snapshot.self, from: data)
        babies = s.babies
        courses = s.courses
        templates = s.templates
        ledger = s.ledger
        currentBabyID = s.currentBabyID ?? s.babies.first?.id
        save()
    }
}
