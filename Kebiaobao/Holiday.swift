import Foundation

/// 中国法定节假日 / 调休数据。
///
/// 两级数据源：
/// 1. **内置** `Resources/holidays.json`（构建时由 `tools/update_holidays.py` 打包，离线可用）
/// 2. **联网缓存** `Documents/holidays-cache.json`（App 启动后台从 timor.tech 拉当年及后两年，
///    覆盖内置。抓不到就静默沿用内置，不影响使用）
///
/// 数据源 timor.tech 整理自国务院办公厅每年的节假日安排通知，公开 HTTPS 接口，无需 key。
enum Holiday {
    struct Day: Codable {
        var holiday: Bool   // true=放假，false=补班
        var name: String    // 「春节」「春节后补班」
        var target: String  // 补班对应的节日
    }

    // MARK: - 数据

    /// key = "yyyy-MM-dd"
    private static let bundled: [String: Day] = {
        guard let url = Bundle.main.url(forResource: "holidays", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let d = try? JSONDecoder().decode([String: Day].self, from: data)
        else { return [:] }
        return d
    }()

    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("holidays-cache.json")
    }()

    /// 联网更新的数据，优先于内置。只在主线程写（见 refreshRemote）。
    private static var cache: [String: Day] = {
        guard let data = try? Data(contentsOf: cacheURL),
              let d = try? JSONDecoder().decode([String: Day].self, from: data)
        else { return [:] }
        return d
    }()

    static func info(_ date: Date) -> Day? {
        let k = key.string(from: date)
        return cache[k] ?? bundled[k]
    }

    /// 数据覆盖的年份范围（用于提示「该年数据未收录」）
    static var coveredYears: [Int] {
        Set((cache.isEmpty ? bundled : cache).keys.compactMap { Int($0.prefix(4)) }).sorted()
    }

    private static let key: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

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

    // MARK: - 联网更新

    private static let stampKey = "kb.holiday.lastSync"

    static var lastSync: Date? {
        UserDefaults.standard.object(forKey: stampKey) as? Date
    }

    /// 距上次同步超过 7 天才重新拉取（节假日通知一年才发一两次）
    static func needsRefresh() -> Bool {
        guard let d = lastSync else { return true }
        return Date().timeIntervalSince(d) > 7 * 86400
    }

    /// 抓取当年及后两年，合并写入缓存。返回是否拿到新数据。
    /// 网络失败静默返回 false，不抛错、不弹窗。
    @discardableResult
    static func refreshRemote() async -> Bool {
        let y = Calendar(identifier: .gregorian).component(.year, from: Date())
        let fresh = await fetch(years: [y, y + 1, y + 2])
        guard !fresh.isEmpty else { return false }
        await MainActor.run {
            cache.merge(fresh) { _, new in new }
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: cacheURL, options: .atomic)
            }
            UserDefaults.standard.set(Date(), forKey: stampKey)
        }
        return true
    }

    /// 强制重抓（用户手动点「更新」），忽略 7 天节流
    @discardableResult
    static func forceRefresh() async -> Bool {
        UserDefaults.standard.removeObject(forKey: stampKey)
        return await refreshRemote()
    }

    private static func fetch(years: [Int]) async -> [String: Day] {
        var out: [String: Day] = [:]
        for year in years {
            guard let url = URL(string: "https://timor.tech/api/holiday/year/\(year)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            req.setValue("Kebiaobao/1.2 (iOS)", forHTTPHeaderField: "User-Agent")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = obj["holiday"] as? [String: [String: Any]]
            else { continue }
            for v in list.values {
                guard let date = v["date"] as? String else { continue }
                out[date] = Day(holiday: (v["holiday"] as? Bool) ?? false,
                                name: (v["name"] as? String) ?? "",
                                target: (v["target"] as? String) ?? "")
            }
        }
        return out
    }
}

extension Notification.Name {
    /// 节假日数据联网更新完成，UI 收到后重绘
    static let kbHolidaysUpdated = Notification.Name("kb.holidays.updated")
}
