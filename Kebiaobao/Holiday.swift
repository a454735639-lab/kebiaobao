import Foundation

/// 中国法定节假日 / 调休数据（内置，来源：国务院办公厅通知，经 timor.tech API 整理）
///
/// 覆盖年份见 `Resources/holidays.json`。数据是静态的 —— 每年国务院发新通知后需更新。
/// 更新方式：`python3 tools/update_holidays.py`
enum Holiday {
    struct Day: Codable {
        var holiday: Bool   // true=放假，false=补班
        var name: String    // 「春节」「春节后补班」
        var target: String  // 补班对应的节日
    }

    /// key = "yyyy-MM-dd"
    private static let table: [String: Day] = {
        guard let url = Bundle.main.url(forResource: "holidays", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let d = try? JSONDecoder().decode([String: Day].self, from: data)
        else { return [:] }
        return d
    }()

    /// 数据覆盖的年份范围（用于提示「该年数据未收录」）
    static var coveredYears: [Int] {
        Set(table.keys.compactMap { Int($0.prefix(4)) }).sorted()
    }

    private static let key: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func info(_ date: Date) -> Day? { table[key.string(from: date)] }

    /// 是否法定放假日
    static func isHoliday(_ date: Date) -> Bool { info(date)?.holiday == true }
    /// 是否调休补班日（周末上班）
    static func isMakeup(_ date: Date) -> Bool { info(date)?.holiday == false }

    /// 短标签，显示在日期下面：休 / 班 / 节名
    static func badge(_ date: Date) -> String? {
        guard let i = info(date) else { return nil }
        if i.holiday {
            // 「国庆节」→「国庆」；单字节日保留
            let n = i.name.replacingOccurrences(of: "节", with: "")
            return n.isEmpty ? "休" : (n.count <= 2 ? n : String(n.prefix(2)))
        }
        return "班"
    }

    /// 完整描述：「春节 放假」「春节后补班」
    static func label(_ date: Date) -> String? {
        guard let i = info(date) else { return nil }
        return i.holiday ? "\(i.name) 放假" : i.name
    }
}
