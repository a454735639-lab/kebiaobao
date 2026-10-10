import Foundation
import UserNotifications

/// 排课提醒：把排课模板的「提前提醒」落成本地通知（按星期重复）
enum KBReminder {
    private static let prefix = "kb.lesson."

    /// 请求权限（首次会弹系统框）；授权结果回来后回调
    static func requestAuth(then done: (() -> Void)? = nil) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                DispatchQueue.main.async { done?() }
            }
    }

    /// 按当前排课重建全部提醒。无权限时静默失败。
    static func sync(templates: [LessonTemplate], courses: [Course]) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let active = Set(courses.filter { !$0.archived }.map(\.id))

            center.getPendingNotificationRequests { pending in
                let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
                center.removePendingNotificationRequests(withIdentifiers: stale)

                var reqs: [UNNotificationRequest] = []
                for t in templates where active.contains(t.courseID) && t.remindMinutes > 0 {
                    let name = courses.first { $0.id == t.courseID }?.name ?? "课程"
                    for slot in t.orderedSlots {
                        // 提醒时间 = 上课时间 - 提前分钟；跨零点则回退到前一天
                        var mins = slot.hour * 60 + slot.minute - t.remindMinutes
                        var weekday = slot.weekday
                        while mins < 0 { mins += 1440; weekday -= 1 }
                        if weekday < 1 { weekday += 7 }

                        var dc = DateComponents()
                        dc.weekday = weekday
                        dc.hour = mins / 60
                        dc.minute = mins % 60
                        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: true)

                        let content = UNMutableNotificationContent()
                        content.title = "\(name) 上课提醒"
                        content.body = "\(t.remindMinutes) 分钟后在\(slot.place.isEmpty ? "上课地点" : slot.place)上课"
                            + (slot.teacher.isEmpty ? "" : " · \(slot.teacher)")
                        content.sound = .default

                        reqs.append(UNNotificationRequest(
                            identifier: "\(prefix)\(t.id.uuidString)-\(slot.weekday)",
                            content: content, trigger: trigger))
                    }
                }
                for r in reqs { center.add(r, withCompletionHandler: nil) }
            }
        }
    }

    /// 清空全部排课提醒
    static func clearAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}
