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

    /// 数据覆盖的年份（保留：日历年份选择器可用）。缓存，避免每次日期渲染都遍历全表。
    static let coveredYears: [Int] =
        Set(table.keys.compactMap { Int($0.prefix(4)) }).sorted()

    private static let key: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func info(_ date: Date) -> Day? { table[key.string(from: date)] }

    /// 数据未覆盖的年份用的保守回退：只算**节日当天**，不含国务院的调休安排。
    /// 依据是固定公历日 + 农历节日（农历初一等），因此不会凭空多放假、也不会漏掉当天。
    /// 数据补齐后（tools/update_holidays.py）此分支自动失效。
    private static func fallbackInfo(_ date: Date) -> Day? {
        let c = KBDate.cal.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        guard !coveredYears.contains(y) else { return nil }

        // 固定公历节日
        switch (m, d) {
        case (1, 1):  return Day(holiday: true, name: "元旦", target: "")
        case (5, 1):  return Day(holiday: true, name: "劳动节", target: "")
        case (10, 1), (10, 2), (10, 3):
            return Day(holiday: true, name: "国庆节", target: "")
        default: break
        }
        // 农历节日（当天）
        if let l = Lunar.date(date) {
            if l.month == 1 && !l.leap && (1...3).contains(l.day) {
                return Day(holiday: true, name: "春节", target: "")
            }
            if l.month == 5 && !l.leap && l.day == 5 {
                return Day(holiday: true, name: "端午节", target: "")
            }
            if l.month == 8 && !l.leap && l.day == 15 {
                return Day(holiday: true, name: "中秋节", target: "")
            }
        }
        // 清明（节气当天）
        if Lunar.term(date) == "清明" {
            return Day(holiday: true, name: "清明节", target: "")
        }
        return nil
    }

    private static func resolved(_ date: Date) -> Day? {
        table[key.string(from: date)] ?? fallbackInfo(date)
    }

    /// 是否法定放假日
    static func isHoliday(_ date: Date) -> Bool { resolved(date)?.holiday == true }

    /// 短标签，显示在日期下面：休 / 班 / 节名
    static func badge(_ date: Date) -> String? {
        guard let i = resolved(date) else { return nil }
        if i.holiday {
            // 「国庆节」→「国庆」；单字节日保留
            let n = i.name.replacingOccurrences(of: "节", with: "")
            return n.isEmpty ? "休" : (n.count <= 2 ? n : String(n.prefix(2)))
        }
        return "班"
    }

    /// 完整描述：「春节 放假」「春节后补班」
    static func label(_ date: Date) -> String? {
        guard let i = resolved(date) else { return nil }
        return i.holiday ? "\(i.name) 放假" : i.name
    }
}
