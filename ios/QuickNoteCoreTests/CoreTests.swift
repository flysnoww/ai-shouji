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
        guard case .create(let quantity) = try await parser.parse("买了2瓶水") else { return XCTFail() }; XCTAssertEqual(quantity.module, .memo); XCTAssertNil(quantity.quantity)
        for text in ["下午三点开会", "九点半检查邮件"] { guard case .create(let value) = try await parser.parse(text) else { return XCTFail() }; XCTAssertNotNil(value.dueAt ?? value.occurredAt, text) }
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
        XCTAssertEqual(updated.rawInput, "篡改")
        XCTAssertEqual(updated.ownerID, "owner")
        XCTAssertEqual(store.records.count, 1)
    }

    func testLedgerOnlyQuantityMultipleAmountsAndTotals() async throws {
        let parser = DeterministicDraftParser()
        guard case .create(let two) = try await parser.parse("70美元和3000日元") else { return XCTFail() }
        XCTAssertEqual(two.amountItems, [AmountItem(value: 70, currency: "USD"), AmountItem(value: 3000, currency: "JPY")]); XCTAssertNil(two.amount)
        guard case .create(let three) = try await parser.parse("16美元3000日元25欧元") else { return XCTFail() }
        XCTAssertEqual(three.amountItems.count, 3)
        guard case .create(let memo) = try await parser.parse("B12车位有3箱水") else { return XCTFail() }
        XCTAssertEqual(memo.module, .memo); XCTAssertNil(memo.quantity)
        let totals = QuickNoteCore.numericTotals(in: [two, three, Record(module: .memo, rawInput: "库存5000日元", amount: 5000, currency: "JPY")])
        XCTAssertEqual(totals["USD"], 86); XCTAssertEqual(totals["JPY"], 6000); XCTAssertEqual(totals["EUR"], 25)
    }

    func testAmountComparatorsNormalizationRelativeTimeAndRepeatHint() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000), parser = DeterministicDraftParser(calendar: calendar, now: { now })
        guard case .search(let minimum) = try await parser.parse("找50美元以上的购物") else { return XCTFail() }
        XCTAssertEqual(minimum.minimumAmount, 50); XCTAssertTrue(minimum.minimumInclusive); XCTAssertEqual(minimum.currency, "USD"); XCTAssertEqual(minimum.category, "购物"); XCTAssertFalse(minimum.keyword.contains("50"))
        guard case .search(let maximum) = try await parser.parse("找少于50美元的代办") else { return XCTFail() }
        XCTAssertEqual(maximum.maximumAmount, 50); XCTAssertFalse(maximum.maximumInclusive); XCTAssertEqual(maximum.modules, [.todo])
        guard case .create(let relative) = try await parser.parse("两小时后提醒我关烤箱") else { return XCTFail() }
        XCTAssertEqual(relative.module, .todo); XCTAssertEqual(relative.dueAt, calendar.date(byAdding: .hour, value: 2, to: now))
        guard case .create(let repeating) = try await parser.parse("每周六打扫车库") else { return XCTFail() }
        XCTAssertEqual(repeating.module, .todo); XCTAssertTrue(repeating.tags.contains("每周六")); XCTAssertNotNil(repeating.dueAt)
    }

    func testLegacyAmountDecodesAsOneAmountItemAndInclusiveSearchUsesItems() throws {
        let old = Record(module: .ledger, rawInput: "旧账", amount: 50, currency: "USD")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any]); object.removeValue(forKey: "amountItems")
        let decoded = try JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.amountItems, [AmountItem(value: 50, currency: "USD")])
        let core = QuickNoteCore(store: MemoryRecordStore([Record(ownerID: "owner", module: .ledger, rawInput: "购物", amountItems: [AmountItem(value: 50, currency: "USD")])]), identity: TestIdentity("owner"))
        XCTAssertEqual(try core.search(RecordQuery(minimumAmount: 50, minimumInclusive: true, currency: "USD")).count, 1)
        XCTAssertEqual(try core.search(RecordQuery(minimumAmount: 50, currency: "USD")).count, 0)
    }
}
