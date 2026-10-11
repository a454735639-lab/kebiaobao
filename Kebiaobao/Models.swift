import Foundation

enum RecordKind: String, Codable, CaseIterable, Identifiable {
    case charge, consume, leave, refund
    var id: String { rawValue }
    var label: String {
        switch self {
        case .charge: return "充值"
        case .consume: return "打卡"
        case .leave: return "请假"
        case .refund: return "撤销"
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
    /// 所属宝贝。年卡等「多个宝宝共用课时」场景可挂多个
    var babyIDs: [UUID]
    var name: String
    var tag: String
    var total: Int
    var pricePerLesson: Double
    var expiry: Date
    var createdAt: Date = Date()
    /// 购买时间（旧数据回退到 createdAt）
    var purchasedAt: Date? = nil
    var archived: Bool = false
    /// 课程专属色（hex，如 0x86C57C）。nil 时按 id 稳定分配调色板色
    var colorHex: UInt32? = nil
    /// 年卡（课时池）：本身不排课，只放总课时/单价/有效期，供多门课多宝宝共用
    var isPool: Bool = false
    /// 这门课的课时从哪张年卡扣。nil = 自己就是一个池（普通课，老数据）
    var poolID: UUID? = nil

    var totalFee: Double { Double(total) * pricePerLesson }
    var boughtAt: Date { purchasedAt ?? createdAt }

    /// 稳定取色：显式 colorHex 优先，否则按 id 哈希落调色板
    var color: UInt32 {
        colorHex ?? KBPalette.forID(id)
    }

    init(id: UUID = UUID(), babyIDs: [UUID], name: String, tag: String, total: Int,
         pricePerLesson: Double, expiry: Date, createdAt: Date = Date(),
         purchasedAt: Date? = nil, archived: Bool = false, colorHex: UInt32? = nil,
         isPool: Bool = false, poolID: UUID? = nil) {
        self.id = id; self.babyIDs = babyIDs; self.name = name; self.tag = tag
        self.total = total; self.pricePerLesson = pricePerLesson; self.expiry = expiry
        self.createdAt = createdAt; self.purchasedAt = purchasedAt
        self.archived = archived; self.colorHex = colorHex
        self.isPool = isPool; self.poolID = poolID
    }

    /// 手写解码：合成的 init(from:) 会忽略属性默认值，旧快照缺键就会整包解码失败
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        // 旧数据是单个 babyID；新数据是数组。两种都要能读
        if let arr = try c.decodeIfPresent([UUID].self, forKey: .babyIDs) {
            babyIDs = arr
        } else if let one = try c.decodeIfPresent(UUID.self, forKey: .babyID) {
            babyIDs = [one]
        } else {
            babyIDs = []
        }
        name = try c.decode(String.self, forKey: .name)
        tag = try c.decodeIfPresent(String.self, forKey: .tag) ?? ""
        total = try c.decode(Int.self, forKey: .total)
        pricePerLesson = try c.decode(Double.self, forKey: .pricePerLesson)
        expiry = try c.decode(Date.self, forKey: .expiry)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        purchasedAt = try c.decodeIfPresent(Date.self, forKey: .purchasedAt)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        colorHex = try c.decodeIfPresent(UInt32.self, forKey: .colorHex)
        isPool = try c.decodeIfPresent(Bool.self, forKey: .isPool) ?? false
        poolID = try c.decodeIfPresent(UUID.self, forKey: .poolID)
    }

    /// 显式 CodingKeys：保留旧的单值 `babyID` 只用于读旧快照
    private enum CodingKeys: String, CodingKey {
        case id, babyIDs, babyID, name, tag, total, pricePerLesson, expiry
        case createdAt, purchasedAt, archived, colorHex, isPool, poolID
    }

    /// 只写新字段，不再输出单值 babyID
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(babyIDs, forKey: .babyIDs)
        try c.encode(name, forKey: .name)
        try c.encode(tag, forKey: .tag)
        try c.encode(total, forKey: .total)
        try c.encode(pricePerLesson, forKey: .pricePerLesson)
        try c.encode(expiry, forKey: .expiry)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(purchasedAt, forKey: .purchasedAt)
        try c.encode(archived, forKey: .archived)
        try c.encodeIfPresent(colorHex, forKey: .colorHex)
        try c.encode(isPool, forKey: .isPool)
        try c.encodeIfPresent(poolID, forKey: .poolID)
    }
}

/// 每科一色：柔和低饱和调色板（浅色底上可读，深色模式下也够亮）
enum KBPalette {
    static let colors: [UInt32] = [
        0x86C57C,  // 草绿
        0x8A5FAB,  // 紫
        0xE08A5F,  // 橙
        0x5F8FD0,  // 蓝
        0xD06A8A,  // 玫红
        0x5FB8B0,  // 青
        0xC9A24D,  // 金
        0x9A7BC8,  // 淡紫
        0x6FA86F,  // 墨绿
        0xC97B6A,  // 砖红
    ]

    /// 同 id 永远同色（UUID 前 8 字节哈希，跨启动稳定）
    static func forID(_ id: UUID) -> UInt32 {
        let b = id.uuid
        let n = (UInt32(b.0) << 24) | (UInt32(b.1) << 16) | (UInt32(b.2) << 8) | UInt32(b.3)
        return colors[Int(n % UInt32(colors.count))]
    }
}

/// 排课模板：按星期重复
struct LessonTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var courseID: UUID
    var weekdays: [Int]          // 1=周日 … 7=周六
    var hour: Int                // 兼容旧数据；新数据取 slots
    var minute: Int
    var place: String
    var teacher: String
    var deduct: Int              // 每次打卡扣课时
    var remindMinutes: Int       // 提前提醒分钟
    /// 每个星期几单独的时间／老师／地点。空则回退到上面的 hour/minute/teacher/place
    var slots: [DaySlot] = []
    /// 共用课时（年卡）时，这一节课是哪个宝宝上的。nil = 用课程的默认归属
    var babyID: UUID? = nil

    var timeText: String { String(format: "%02d:%02d", hour, minute) }

    /// 取某天的具体安排；没有专属 slot 时用模板默认值
    func slot(for weekday: Int) -> DaySlot {
        slots.first { $0.weekday == weekday }
            ?? DaySlot(weekday: weekday, hour: hour, minute: minute,
                       teacher: teacher, place: place)
    }

    /// 按星期排序的全部安排
    var orderedSlots: [DaySlot] { weekdays.sorted().map { slot(for: $0) } }

    /// 手写解码：`slots` / `remindMinutes` 等后加字段在旧快照里不存在，
    /// 合成的 init(from:) 会当必填直接抛错，整包数据就废了。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        courseID = try c.decode(UUID.self, forKey: .courseID)
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 0
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0
        place = try c.decodeIfPresent(String.self, forKey: .place) ?? ""
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher) ?? ""
        deduct = try c.decodeIfPresent(Int.self, forKey: .deduct) ?? 1
        remindMinutes = try c.decodeIfPresent(Int.self, forKey: .remindMinutes) ?? 30
        slots = try c.decodeIfPresent([DaySlot].self, forKey: .slots) ?? []
        babyID = try c.decodeIfPresent(UUID.self, forKey: .babyID)
    }

    init(id: UUID = UUID(), courseID: UUID, weekdays: [Int], hour: Int, minute: Int,
         place: String, teacher: String, deduct: Int, remindMinutes: Int,
         slots: [DaySlot] = [], babyID: UUID? = nil) {
        self.id = id; self.courseID = courseID; self.weekdays = weekdays
        self.hour = hour; self.minute = minute; self.place = place; self.teacher = teacher
        self.deduct = deduct; self.remindMinutes = remindMinutes; self.slots = slots
        self.babyID = babyID
    }
}

/// 某个星期几的上课安排
struct DaySlot: Identifiable, Codable, Hashable {
    var id = UUID()
    var weekday: Int             // 1=周日 … 7=周六
    var hour: Int
    var minute: Int
    var teacher: String
    var place: String

    var timeText: String { String(format: "%02d:%02d", hour, minute) }
    var dayName: String { KBDate.weekdayName(weekday) }
}

struct LedgerEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var courseID: UUID
    var date: Date
    var delta: Int               // 正=充值，负=打卡
    var kind: RecordKind
    var note: String
    /// 课后小结（可选，旧数据解码为 nil）
    var summary: String? = nil
    /// 记账当时的单价（旧数据为 nil，回退到课程当前单价）
    var unitPrice: Double? = nil
    /// 充值前的课程单价：撤销这条充值时要还原，否则单价被永久改掉
    var prevPrice: Double? = nil
    /// 共用课时（年卡）时，这条记录属于哪个宝宝
    var babyID: UUID? = nil

    init(id: UUID = UUID(), courseID: UUID, date: Date, delta: Int,
         kind: RecordKind, note: String, summary: String? = nil, unitPrice: Double? = nil,
         prevPrice: Double? = nil, babyID: UUID? = nil) {
        self.id = id; self.courseID = courseID; self.date = date; self.delta = delta
        self.kind = kind; self.note = note; self.summary = summary; self.unitPrice = unitPrice
        self.prevPrice = prevPrice; self.babyID = babyID
    }

    /// 手写解码：`summary` / `unitPrice` 在旧快照里不存在
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        courseID = try c.decode(UUID.self, forKey: .courseID)
        date = try c.decode(Date.self, forKey: .date)
        delta = try c.decode(Int.self, forKey: .delta)
        kind = try c.decode(RecordKind.self, forKey: .kind)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        unitPrice = try c.decodeIfPresent(Double.self, forKey: .unitPrice)
        prevPrice = try c.decodeIfPresent(Double.self, forKey: .prevPrice)
        babyID = try c.decodeIfPresent(UUID.self, forKey: .babyID)
    }
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
}
