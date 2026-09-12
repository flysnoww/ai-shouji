import XCTest
#if canImport(QuickNoteCore)
@testable import QuickNoteCore
#elseif canImport(AIQuickNote)
@testable import AIQuickNote
#endif

private final class TestIdentity: IdentityGate, @unchecked Sendable { var confirmedUserID: String?; init(_ id: String?) { confirmedUserID = id } }

final class CoreTests: XCTestCase {
    func testCreateSearchUpdateAndTraceability() throws {
        let identity = TestIdentity("user-1"), store = MemoryRecordStore(), core = QuickNoteCore(store: store, identity: identity)
        let ledger = try core.save(Record(module: .ledger, rawInput: "沃尔玛购物16美元", important: true, tags: ["购物"], amount: 16))
        _ = try core.save(Record(module: .memo, rawInput: "needle memo"))
        XCTAssertEqual(ledger.rawInput, "沃尔玛购物16美元")
        XCTAssertEqual(ledger.module, .ledger); XCTAssertTrue(ledger.important)
        XCTAssertEqual(try core.search(RecordQuery(keyword: "沃尔玛")).map(\.id), [ledger.id])
        XCTAssertEqual(try core.search(RecordQuery(modules: [.ledger], importantOnly: true)).count, 1)
        XCTAssertEqual(try core.search(RecordQuery(keyword: "needle", modules: [.ledger, .memo])).count, 1)
        var changed = ledger; changed.content = "更新后的账目"
        let updated = try core.save(changed)
        XCTAssertEqual(updated.rawInput, ledger.rawInput); XCTAssertEqual(try core.records().count, 2)
    }

    func testIdentityGateBlocksAnonymousSave() {
        let core = QuickNoteCore(store: MemoryRecordStore(), identity: TestIdentity(nil))
        XCTAssertThrowsError(try core.save(Record(module: .idea, rawInput: "秘密"))) { XCTAssertEqual($0 as? CoreError, .identityRequired) }
    }
}
