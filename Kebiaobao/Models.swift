import Foundation

enum RecordKind: String, Codable, CaseIterable, Identifiable {
    case charge, consume, leave, refund
    var id: String { rawValue }
    var label: String {
        switch self {
        case .charge: return "充值"
        case .consume: return "扣课"
        case .leave: return "请假"
        case .refund: return "撤销"
        }
    }
    var sign: String {
        switch self {
        case .charge: return "+"
        case .consume: return "-"
        default: return ""
        }
    }
}

struct Baby: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var birthday: Date?
}

struct Course: Identifiable, Codable, Hashable {
    var id = UUID()
    var babyID: UUID
    var name: String
    var tag: String
    var total: Int
    var pricePerLesson: Double
    var expiry: Date
    var createdAt: Date = Date()
    var archived: Bool = false

    var totalFee: Double { Double(total) * pricePerLesson }
}

/// 排课模板：按星期重复
struct LessonTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var courseID: UUID
    var weekdays: [Int]          // 1=周日 … 7=周六
    var hour: Int
    var minute: Int
    var place: String
    var teacher: String
    var deduct: Int              // 每次划扣课时
    var remindMinutes: Int       // 提前提醒分钟

    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

struct LedgerEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var courseID: UUID
    var date: Date
    var delta: Int               // 正=充值，负=扣课
    var kind: RecordKind
    var note: String
}

extension JSONEncoder {
    static let kb: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let kb: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return d
    }()
}

enum KBDate {
    static let cal = Calendar(identifier: .gregorian)

    static func day(_ d: Date) -> Date { cal.startOfDay(for: d) }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool { cal.isDate(a, inSameDayAs: b) }

    static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let mdhm: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static let cnFull: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f
    }()

    static let weekdayCN = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    static func weekdayName(_ w: Int) -> String {
        (w >= 1 && w <= 7) ? weekdayCN[w] : ""
    }

    /// 生成某月内所有匹配 weekdays 的日期
    static func occurrences(weekdays: [Int], in month: Date) -> [Date] {
        guard !weekdays.isEmpty else { return [] }
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = 1
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        var out: [Date] = []
        for offset in 0..<range.count {
            guard let d = cal.date(byAdding: .day, value: offset, to: first) else { continue }
            if weekdays.contains(cal.component(.weekday, from: d)) { out.append(d) }
        }
        return out
    }
}
