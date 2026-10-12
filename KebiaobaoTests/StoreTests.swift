import XCTest
@testable import Kebiaobao

/// 回归测试：覆盖「打卡记录只显示打卡」与「同日不可重复扣课」两条规则
final class StoreTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kb-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        Store.overrideDir = tmp
    }

    override func tearDownWithError() throws {
        Store.overrideDir = nil
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - 夹具

    private func makeStore() -> Store { Store() }

    @discardableResult
    private func addBaby(_ s: Store, _ name: String = "小明") -> UUID {
        let b = Baby(name: name, birthday: nil)
        s.babies = [b]
        s.currentBabyID = b.id
        return b.id
    }

    @discardableResult
    private func addCourse(_ s: Store, baby: UUID, total: Int = 10,
                           expiry: Date = Date().addingTimeInterval(86400 * 30)) -> UUID {
        let c = Course(babyIDs: [baby], name: "钢琴", tag: "常规",
                       total: total, pricePerLesson: 200, expiry: expiry)
        s.courses = [c]
        return c.id
    }

    // MARK: - 同日重复扣课

    func testManualConsumeTwiceSameDayRejected() {
        let s = makeStore()
        let b = addBaby(s)
        let c = addCourse(s, baby: b)
        let today = Date()

        let first = s.recordManual(.consume, courseID: c, lessons: 1, date: today,
                                   note: "", price: 0, babyID: b)
        XCTAssertEqual(first, .ok)
        XCTAssertEqual(s.ledger.count, 1)

        let second = s.recordManual(.consume, courseID: c, lessons: 1, date: today,
                                    note: "", price: 0, babyID: b)
        XCTAssertEqual(second, .duplicate, "同一天同课程同宝宝不能重复扣课")
        XCTAssertEqual(s.ledger.count, 1, "被拒的打卡不应写入流水")
    }

    func testManualConsumeDifferentDayAccepted() {
        let s = makeStore()
        let b = addBaby(s)
        let c = addCourse(s, baby: b)
        let today = Date()
        let tomorrow = today.addingTimeInterval(86400)

        XCTAssertEqual(s.recordManual(.consume, courseID: c, lessons: 1, date: today,
                                      note: "", price: 0, babyID: b), .ok)
        XCTAssertEqual(s.recordManual(.consume, courseID: c, lessons: 1, date: tomorrow,
                                      note: "", price: 0, babyID: b), .ok)
        XCTAssertEqual(s.ledger.count, 2)
    }

    /// 请假与加课时不受「同日一次」限制
    func testLeaveAndChargeNotDeduplicated() {
        let s = makeStore()
        let b = addBaby(s)
        let c = addCourse(s, baby: b)
        let today = Date()

        XCTAssertEqual(s.recordManual(.leave, courseID: c, lessons: 1, date: today,
                                      note: "", price: 0, babyID: b), .ok)
        XCTAssertEqual(s.recordManual(.leave, courseID: c, lessons: 1, date: today,
                                      note: "", price: 0, babyID: b), .ok)
        XCTAssertEqual(s.recordManual(.charge, courseID: c, lessons: 5, date: today,
                                      note: "", price: 200, babyID: b), .ok)
        XCTAssertEqual(s.ledger.count, 3)
    }

    func testManualConsumeExpiredCourseRejected() {
        let s = makeStore()
        let b = addBaby(s)
        let c = addCourse(s, baby: b, expiry: Date().addingTimeInterval(-86400 * 2))

        let r = s.recordManual(.consume, courseID: c, lessons: 1, date: Date(),
                               note: "", price: 0, babyID: b)
        XCTAssertEqual(r, .expired)
        XCTAssertTrue(s.ledger.isEmpty)
    }

    // MARK: - 排课打卡同一套规则

    func testCheckInTwiceSameDayRejected() {
        let s = makeStore()
        let b = addBaby(s)
        let c = addCourse(s, baby: b)
        let t = LessonTemplate(courseID: c, weekdays: [2], hour: 18, minute: 0,
                               place: "", teacher: "", deduct: 1, remindMinutes: 0,
                               babyID: b)
        s.templates = [t]

        XCTAssertEqual(s.checkIn(t, on: Date()), .ok)
        XCTAssertEqual(s.checkIn(t, on: Date()), .duplicate)
        XCTAssertEqual(s.ledger.count, 1)
    }

    // MARK: - 记录页分类

    func testCheckInTabShowsOnlyCheckIns() {
        XCTAssertEqual(RecordsView.Tab.checkIn.kinds, [.consume])
    }

    func testTabKindMapping() {
        XCTAssertEqual(RecordsView.Tab.lesson.kinds, [.consume, .leave])
        XCTAssertEqual(RecordsView.Tab.payment.kinds, [.charge, .refund])
        XCTAssertNil(RecordsView.Tab.all.kinds, "全部记录不过滤")
    }

    /// 每个 tab 都必须能收到自己该收的类型（防止以后改错集合）
    func testEveryKindBelongsToSomeTab() {
        let tabs: [RecordsView.Tab] = [.lesson, .payment, .checkIn]
        for kind in RecordKind.allCases {
            let covered = tabs.contains { $0.kinds?.contains(kind) ?? false }
            XCTAssertTrue(covered, "\(kind) 没有出现在任何分类 tab 里")
        }
    }
}
