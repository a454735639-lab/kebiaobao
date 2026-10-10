import Foundation

/// 中国法定节假日 / 调休数据（**纯本地**）。
///
/// 数据源：`Resources/holidays.json`，构建时由 `tools/update_holidays.py`
/// 从 timor.tech 整理好打进 bundle。App 运行期**不发起任何网络请求**。
///
/// 每年国务院发布次年安排后，重新跑一次 `tools/update_holidays.py` 再发版即可。
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

    /// 数据覆盖的年份范围（保留：日历年份选择器可用）
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
