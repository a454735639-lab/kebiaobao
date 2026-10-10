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
              let s = try? JSONDecoder.kb.decode(Snapshot.self, from: data) else {
            seed()
            return
        }
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

    private func seed() {
        let b = Baby(name: "宝贝", birthday: nil)
        babies = [b]
        currentBabyID = b.id
        save()
    }

    func resetToSample() {
        let b = Baby(name: "乐橙", birthday: KBDate.cal.date(from: DateComponents(year: 2019, month: 5, day: 20)))
        let c1 = Course(babyID: b.id, name: "Kim", tag: "音乐", total: 144,
                        pricePerLesson: 90,
                        expiry: KBDate.cal.date(byAdding: .year, value: 1, to: Date())!)
        let c2 = Course(babyID: b.id, name: "艾里", tag: "运动", total: 48,
                        pricePerLesson: 120,
                        expiry: KBDate.cal.date(byAdding: .month, value: 8, to: Date())!)
        babies = [b]
        courses = [c1, c2]
        templates = [
            LessonTemplate(courseID: c1.id, weekdays: [2, 4], hour: 16, minute: 40,
                           place: "少年宫3楼", teacher: "王老师", deduct: 1, remindMinutes: 30),
            LessonTemplate(courseID: c2.id, weekdays: [6], hour: 11, minute: 0,
                           place: "游泳馆", teacher: "李教练", deduct: 1, remindMinutes: 60)
        ]
        ledger = [
            LedgerEntry(courseID: c1.id, date: Date(), delta: -1, kind: .consume, note: "正常上课"),
            LedgerEntry(courseID: c1.id, date: Date(), delta: -1, kind: .consume, note: "正常上课")
        ]
        currentBabyID = b.id
        save()
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
