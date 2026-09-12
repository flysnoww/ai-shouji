import XCTest
#if canImport(QuickNoteCore)
@testable import QuickNoteCore
#elseif canImport(AIQuickNote)
@testable import AIQuickNote
#endif

private final class TestIdentity: IdentityGate, @unchecked Sendable { var confirmedUserID: String?; init(_ id: String?) { confirmedUserID = id } }
private final class SpyStore: RecordStore, @unchecked Sendable {
    var records: [Record] = []; var saveCount = 0
    func load() -> [Record] { records }
    func save(_ records: [Record]) { saveCount += 1; self.records = records }
}

final class CoreTests: XCTestCase {
    func testDraftParserExamplesAndSearch() async throws {
        let parser = DeterministicDraftParser(calendar: Calendar(identifier: .gregorian), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        guard case .create(let ledger) = try await parser.parse("今天沃尔玛购物16美元，用美国银行支付") else { return XCTFail() }
        XCTAssertEqual(ledger.module, .ledger); XCTAssertEqual(ledger.amount, 16); XCTAssertEqual(ledger.currency, "USD"); XCTAssertNotNil(ledger.merchant); XCTAssertNotNil(ledger.category); XCTAssertFalse(ledger.tags.isEmpty)
        guard case .create(let quantityLedger) = try await parser.parse("买了2瓶水16美元") else { return XCTFail() }
        XCTAssertEqual(quantityLedger.quantity, 2); XCTAssertEqual(quantityLedger.amount, 16); XCTAssertEqual(quantityLedger.currency, "USD")
        guard case .create(let todo) = try await parser.parse("明天早上8点提醒我吃早饭") else { return XCTFail() }; XCTAssertEqual(todo.module, .todo); XCTAssertNotNil(todo.dueAt); XCTAssertTrue(todo.reminderEnabled)
        guard case .create(let memo) = try await parser.parse("车内有早点") else { return XCTFail() }; XCTAssertEqual(memo.module, .memo)
        guard case .create(let idea) = try await parser.parse("以后这个软件可以增加家庭模式") else { return XCTFail() }; XCTAssertEqual(idea.module, .idea)
        guard case .search(let query) = try await parser.parse("找重要的账目和备忘") else { return XCTFail() }; XCTAssertEqual(query.modules, [.ledger, .memo]); XCTAssertTrue(query.importantOnly)
    }

    func testSearchesStructuredFieldsAndTotalsNumbersByCurrency() throws {
        let core = QuickNoteCore(store: MemoryRecordStore(), identity: TestIdentity("owner"))
        _ = try core.save(Record(module: .ledger, rawInput: "买2瓶水16美元", content: "买水", merchant: "商店", quantity: 2, amount: 16, currency: "USD"))
        _ = try core.save(Record(module: .memo, rawInput: "库存5000日元"))
        XCTAssertEqual(try core.search(RecordQuery(keyword: "商店")).count, 1)
        let totals = QuickNoteCore.numericTotals(in: try core.records())
        XCTAssertEqual(totals["USD"], 16); XCTAssertNil(totals["JPY"])
    }

    func testPriorityRulesDatesMixedLanguageAndNumericRoles() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_788_883_200), parser = DeterministicDraftParser(calendar: calendar, now: { now })
        for text in ["明天早上8点吃早饭", "下周一提交方案", "后天上午十点看牙医"] { guard case .create(let value) = try await parser.parse(text) else { return XCTFail() }; XCTAssertEqual(value.module, .todo, text); XCTAssertNotNil(value.dueAt, text); XCTAssertEqual(value.content, text) }
        for (text, amount, currency) in [("Target买东西42美元", 42, "USD"), ("买菜120块", 120, "CNY"), ("日元三千买午饭", 3000, "JPY"), ("买书25欧元", 25, "EUR"), ("Starbucks coffee 8 dollars", 8, "USD")] { guard case .create(let value) = try await parser.parse(text) else { return XCTFail() }; XCTAssertEqual(value.module, .ledger, text); XCTAssertEqual(value.amount, Decimal(amount), text); XCTAssertEqual(value.currency, currency, text) }
        for text in ["B12", "房间1806", "2026年", "iPhone 17 Pro Max 256GB", "完成50%"] { guard case .create(let value) = try await parser.parse(text) else { return XCTFail() }; XCTAssertNil(value.amount, text); XCTAssertNil(value.quantity, text) }
        guard case .create(let quantity) = try await parser.parse("买了2瓶水") else { return XCTFail() }; XCTAssertEqual(quantity.quantity, 2)
    }

    func testStructuredSearchRemovesGrammarFromKeyword() async throws {
        let parser = DeterministicDraftParser()
        for (text, modules, keyword) in [("找今天的记录", Set(Module.allCases), ""), ("找昨天的账目", [.ledger], ""), ("找这个月的购物", Set(Module.allCases), ""), ("找灵感里的家庭模式", [.idea], "家庭模式"), ("找账目和备忘里面的沃尔玛", [.ledger, .memo], "沃尔玛")] { guard case .search(let query) = try await parser.parse(text) else { return XCTFail() }; XCTAssertEqual(query.modules, modules, text); XCTAssertEqual(query.keyword, keyword, text) }
    }

    func testParserEmptyInputReturnsManualSafeDraft() async throws {
        guard case .create(let draft) = try await DeterministicDraftParser().parse("   ") else { return XCTFail() }
        XCTAssertEqual(draft.module, .memo); XCTAssertEqual(draft.rawInput, "   ")
    }
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
        let store = SpyStore(), core = QuickNoteCore(store: store, identity: TestIdentity(nil))
        XCTAssertThrowsError(try core.save(Record(module: .idea, rawInput: "秘密"))) { XCTAssertEqual($0 as? CoreError, .identityRequired) }
        XCTAssertEqual(store.saveCount, 0)
    }

    func testModuleNormalizationPreservesRawInput() throws {
        let core = QuickNoteCore(store: MemoryRecordStore(), identity: TestIdentity("user-1"))
        var ledger = try core.save(Record(module: .ledger, rawInput: "原始账目", merchant: "商家", amount: 16, paymentMethod: "现金"))
        ledger.module = .memo
        let memo = try core.save(ledger)
        XCTAssertNil(memo.merchant); XCTAssertNil(memo.amount); XCTAssertNil(memo.paymentMethod)
        XCTAssertEqual(memo.rawInput, "原始账目")

        var todo = try core.save(Record(module: .todo, rawInput: "原始待办", dueAt: Date(), reminderEnabled: true, status: .done))
        todo.module = .idea
        let idea = try core.save(todo)
        XCTAssertNil(idea.dueAt); XCTAssertNil(idea.status); XCTAssertFalse(idea.reminderEnabled)
        XCTAssertEqual(idea.rawInput, "原始待办")
    }

    func testUpdatePreservesCoreOwnedFieldsAndUpserts() throws {
        let identity = TestIdentity("owner"), store = MemoryRecordStore(), core = QuickNoteCore(store: store, identity: identity)
        let original = try core.save(Record(module: .memo, rawInput: "原始"))
        var draft = original
        draft.ownerID = "attacker"; draft.rawInput = "篡改"; draft.createdAt = .distantFuture; draft.content = "更新"
        let updated = try core.save(draft)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.rawInput, original.rawInput)
        XCTAssertEqual(updated.ownerID, "owner")
        XCTAssertEqual(store.records.count, 1)
    }
}
