import Foundation
import EventKit
import UIKit

/// 系统日历单向同步：把排课写成系统日历事件（`课时宝` 日历）。
///
/// 只写不读。每次同步先清空本 App 建的日历再重建，保证与 App 内排课一致。
/// 事件标识存在 `EventKit` 的 `eventIdentifier` 上，无需本地持久化。
enum CalendarSync {

    static let calendarTitle = "课时宝"

    /// 同步结果
    enum Outcome {
        case ok(Int)          // 写入事件数
        case denied
        case failed(String)
    }

    // MARK: - 授权

    static var status: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// 已授权（iOS 17 起为 .fullAccess / .writeOnly）
    static var isAuthorized: Bool {
        if #available(iOS 17.0, *) {
            return status == .fullAccess || status == .writeOnly
        }
        return status == .authorized
    }

    static func requestAccess(completion: @escaping (Bool) -> Void) {
        let store = EKEventStore()
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents { ok, _ in
                DispatchQueue.main.async { completion(ok) }
            }
        } else {
            store.requestAccess(to: .event) { ok, _ in
                DispatchQueue.main.async { completion(ok) }
            }
        }
    }

    // MARK: - 同步

    /// 把未来 `days` 天的排课写入系统日历。已存在的同名日历会被清空重建。
    static func sync(templates: [LessonTemplate],
                     courses: [Course],
                     remaining: [UUID: Int],
                     babyNames: [UUID: String] = [:],
                     days: Int = 30,
                     skipHolidays: Bool = true,
                     completion: @escaping (Outcome) -> Void) {
        guard isAuthorized else {
            completion(.denied)
            return
        }
        let store = EKEventStore()
        // 只在主线程改日历，避免并发写冲突
        DispatchQueue.main.async {
            do {
                let cal = try targetCalendar(store)

                // 清空旧事件
                let start = Date().addingTimeInterval(-60 * 60 * 24 * 365)
                let end = Date().addingTimeInterval(60 * 60 * 24 * 365 * 2)
                let pred = store.predicateForEvents(withStart: start, end: end, calendars: [cal])
                for e in store.events(matching: pred) {
                    try? store.remove(e, span: .thisEvent, commit: false)
                }

                var count = 0
                let today = KBDate.day(Date())
                let courseByID = Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

                for offset in 0..<days {
                    guard let day = KBDate.cal.date(byAdding: .day, value: offset, to: today) else { continue }
                    // 法定节假日不写日历（调休补班日照写）
                    if skipHolidays && Holiday.isHoliday(day) { continue }
                    let wd = KBDate.cal.component(.weekday, from: day)
                    for t in templates where t.weekdays.contains(wd) {
                        guard let c = courseByID[t.courseID], !c.archived else { continue }
                        // 购买日之前不写日历（和课表口径一致）
                        guard day >= KBDate.day(c.boughtAt) else { continue }
                        let s = t.slot(for: wd)
                        guard let begin = KBDate.cal.date(bySettingHour: s.hour, minute: s.minute,
                                                          second: 0, of: day) else { continue }
                        let ev = EKEvent(eventStore: store)
                        ev.calendar = cal
                        // 共用年卡：日历标题带上归属宝宝，免得家长分不清哪节是哪个娃
                        let who = t.babyID ?? c.babyIDs.first
                        if let n = who.flatMap({ babyNames[$0] }), c.babyIDs.count > 1 {
                            ev.title = "\(c.name) · \(n)"
                        } else {
                            ev.title = "\(c.name) · \(s.teacher.isEmpty ? "上课" : s.teacher)"
                        }
                        ev.location = s.place
                        ev.startDate = begin
                        ev.endDate = begin.addingTimeInterval(60 * 60)   // 默认 1 小时
                        ev.notes = "课时宝排课 · 打卡 \(t.deduct) 课时 · 剩余 \(remaining[c.id] ?? 0) 课时"
                        if t.remindMinutes > 0 {
                            ev.addAlarm(EKAlarm(relativeOffset: -Double(t.remindMinutes) * 60))
                        }
                        try store.save(ev, span: .thisEvent, commit: false)
                        count += 1
                    }
                }
                try store.commit()
                completion(.ok(count))
            } catch {
                completion(.failed(error.localizedDescription))
            }
        }
    }

    /// 清空 App 建的全部事件（用于关闭同步）
    static func clear(completion: @escaping (Outcome) -> Void) {
        guard isAuthorized else { completion(.denied); return }
        let store = EKEventStore()
        DispatchQueue.main.async {
            guard let cal = store.calendars(for: .event).first(where: { $0.title == calendarTitle }) else {
                completion(.ok(0)); return
            }
            let pred = store.predicateForEvents(
                withStart: Date().addingTimeInterval(-60 * 60 * 24 * 365),
                end: Date().addingTimeInterval(60 * 60 * 24 * 365 * 2),
                calendars: [cal])
            let events = store.events(matching: pred)
            for e in events { try? store.remove(e, span: .thisEvent, commit: false) }
            try? store.commit()
            completion(.ok(events.count))
        }
    }

    /// 取（或建）「课时宝」日历
    private static func targetCalendar(_ store: EKEventStore) throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarTitle }) {
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = calendarTitle
        // 选一个可写源（本地源优先，其次 iCloud）
        if let local = store.sources.first(where: { $0.sourceType == .local }) {
            cal.source = local
        } else if let sub = store.defaultCalendarForNewEvents?.source {
            cal.source = sub
        } else if let any = store.sources.first {
            cal.source = any
        } else {
            throw NSError(domain: "CalendarSync", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "没有可用的日历账户"])
        }
        cal.cgColor = UIColor(hex: 0x53B4A4).cgColor
        try store.saveCalendar(cal, commit: true)
        return cal
    }
}
