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
        XCTAssertEqual(quantityLedger.amount, 16); XCTAssertEqual(quantityLedger.currency, "USD"); XCTAssertEqual(quantityLedger.rawInput, "买了2瓶水16美元")
        guard case .create(let todo) = try await parser.parse("明天早上8点提醒我吃早饭") else { return XCTFail() }; XCTAssertEqual(todo.module, .todo); XCTAssertNotNil(todo.dueAt); XCTAssertTrue(todo.reminderEnabled)
        guard case .create(let memo) = try await parser.parse("车内有早点") else { return XCTFail() }; XCTAssertEqual(memo.module, .memo)
        guard case .create(let idea) = try await parser.parse("以后这个软件可以增加家庭模式") else { return XCTFail() }; XCTAssertEqual(idea.module, .idea)
        guard case .search(let query) = try await parser.parse("找重要的账目和备忘") else { return XCTFail() }; XCTAssertEqual(query.modules, [.ledger, .memo]); XCTAssertTrue(query.importantOnly)
    }

    func testSearchesStructuredFieldsAndTotalsNumbersByCurrency() throws {
        let core = QuickNoteCore(store: MemoryRecordStore(), identity: TestIdentity("owner"))
        _ = try core.save(Record(module: .ledger, rawInput: "买2瓶水16美元", content: "买水", merchant: "商店", amount: 16, currency: "USD"))
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
        for text in ["B12", "房间1806", "2026年", "iPhone 17 Pro Max 256GB", "完成50%"] { guard case .create(let value) = try await parser.parse(text) else { return XCTFail() }; XCTAssertNil(value.amount, text) }
        guard case .create(let quantity) = try await parser.parse("买了2瓶水") else { return XCTFail() }; XCTAssertEqual(quantity.module, .memo); XCTAssertEqual(quantity.rawInput, "买了2瓶水")
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
        XCTAssertEqual(idea.dueAt, todo.dueAt); XCTAssertNil(idea.status); XCTAssertTrue(idea.reminderEnabled)
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
        XCTAssertEqual(memo.module, .memo); XCTAssertEqual(memo.rawInput, "B12车位有3箱水")
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
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any]); object.removeValue(forKey: "amountItems"); object["quantity"] = 3
        let decoded = try JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.amountItems, [AmountItem(value: 50, currency: "USD")])
        let core = QuickNoteCore(store: MemoryRecordStore([Record(ownerID: "owner", module: .ledger, rawInput: "购物", amountItems: [AmountItem(value: 50, currency: "USD")])]), identity: TestIdentity("owner"))
        XCTAssertEqual(try core.search(RecordQuery(minimumAmount: 50, minimumInclusive: true, currency: "USD")).count, 1)
        XCTAssertEqual(try core.search(RecordQuery(minimumAmount: 50, currency: "USD")).count, 0)
    }

    func testUnitPriceIsIgnoredWhenTotalExists() async throws {
        let parser = DeterministicDraftParser()
        for (text, total) in [("买了3盒电池，每盒8美元，一共24美元", 24), ("买了2盒药，每盒10美元，一共20美元", 20)] {
            guard case .create(let record) = try await parser.parse(text) else { return XCTFail() }
            XCTAssertEqual(record.amountItems, [AmountItem(value: Decimal(total), currency: "USD")], text)
        }
    }

    func testNoOpSaveDoesNotWriteOrChangeUpdatedAtAndRecordsSortByDisplayDate() throws {
        let identity = TestIdentity("owner"), store = SpyStore(), core = QuickNoteCore(store: store, identity: identity)
        let sep12 = Date(timeIntervalSince1970: 1_789_171_200), sep13 = Date(timeIntervalSince1970: 1_789_257_600)
        let older = Record(ownerID: "owner", module: .memo, rawInput: "A", createdAt: sep12, updatedAt: sep12)
        let newer = Record(ownerID: "owner", module: .memo, rawInput: "B", createdAt: sep12, updatedAt: sep12, occurredAt: sep13)
        store.records = [older, newer]
        let before = store.saveCount, viewed = try core.save(older)
        XCTAssertEqual(store.saveCount, before); XCTAssertEqual(viewed.updatedAt, sep12); XCTAssertEqual(try core.records().map(\.id), [newer.id, older.id])
        var edited = older; edited.rawInput = "A edited"; edited.content = "A edited"
        let saved = try core.save(edited)
        XCTAssertEqual(saved.createdAt, sep12); XCTAssertGreaterThan(saved.updatedAt, sep12); XCTAssertEqual(store.saveCount, before + 1)
    }

    func testMockIdentityIsStableAndRecordsAreOwnerIsolated() async throws {
        let provider = MockAuthProvider(.google), userA = try await provider.signIn(account: 1), userAAgain = try await provider.signIn(account: 1), userB = try await provider.signIn(account: 2)
        XCTAssertEqual(userA.id, userAAgain.id); XCTAssertNotEqual(userA.id, userB.id)
        let identity = TestIdentity(nil), store = MemoryRecordStore(), core = QuickNoteCore(store: store, identity: identity)
        XCTAssertEqual(try core.records(), [])
        XCTAssertThrowsError(try core.save(Record(module: .ledger, rawInput: "沃尔玛16美元")))
        identity.confirmedUserID = userA.id; _ = try core.save(Record(module: .ledger, rawInput: "沃尔玛16美元", amount: 16, currency: "美元"))
        identity.confirmedUserID = userB.id; XCTAssertEqual(try core.records(), []); _ = try core.save(Record(module: .todo, rawInput: "明天买牛奶"))
        XCTAssertEqual(try core.records().map(\.rawInput), ["明天买牛奶"])
        identity.confirmedUserID = nil; XCTAssertEqual(try core.records(), []); XCTAssertEqual(store.records.count, 2)
        identity.confirmedUserID = userA.id; XCTAssertEqual(try core.records().map(\.rawInput), ["沃尔玛16美元"]); XCTAssertEqual(try core.records().first?.ownerID, userA.id)
    }

    func testCurrencyCanonicalizationLocalizationAndLegacyTotals() async throws {
        let parser = DeterministicDraftParser()
        for (text, code) in [("16美元", "USD"), ("16 USD", "USD"), ("16 dollars", "USD"), ("$16", "USD"), ("3000日元", "JPY"), ("25欧元", "EUR"), ("16美金", "USD"), ("3000 yen", "JPY")] {
            guard case .create(let record) = try await parser.parse(text) else { return XCTFail(text) }
            XCTAssertEqual(record.currency, code, text)
        }
        let legacyUSD = Record(module: .ledger, rawInput: "旧记录", amount: 16, currency: "美元")
        let totals = QuickNoteCore.numericTotals(in: [legacyUSD, Record(module: .ledger, rawInput: "new", amount: 70, currency: "USD")])
        XCTAssertEqual(totals, ["USD": 86]); XCTAssertEqual(CurrencyCanonicalizer.displayName("USD", languageCode: "zh-CN"), "美元"); XCTAssertEqual(CurrencyCanonicalizer.displayName("美元", languageCode: "en-US"), "USD")
        let core = QuickNoteCore(store: MemoryRecordStore([Record(ownerID: "owner", module: .ledger, rawInput: "旧记录", amount: 16, currency: "美元")]), identity: TestIdentity("owner"))
        XCTAssertEqual(try core.search(RecordQuery(currency: "USD")).count, 1)
    }

    func testReminderMappingPersistsWithoutMakingLocalSaveDependOnSystemPermission() throws {
        let core = QuickNoteCore(store: MemoryRecordStore(), identity: TestIdentity("owner")), due = Date(timeIntervalSince1970: 1_800_000_000)
        let local = try core.save(Record(module: .todo, rawInput: "提醒吃饭", dueAt: due, reminderEnabled: true, status: .pending))
        XCTAssertTrue(local.reminderEnabled); XCTAssertFalse(local.reminderLinked); XCTAssertNil(local.reminderExternalID)
        var linked = local; linked.reminderLinked = true; linked.reminderExternalID = "mock-reminder-1"
        let saved = try core.save(linked); XCTAssertTrue(saved.reminderLinked); XCTAssertEqual(saved.reminderExternalID, "mock-reminder-1")
    }

    func testExportZipManifestAndBackupRestoreAreValidatedBeforeReplacement() throws {
        let user = IdentityUser(id: "owner", provider: .apple, providerSubject: "mock-apple-user-001", displayName: "Test User")
        let records = [Record(ownerID: "owner", module: .ledger, rawInput: "Walmart 16 USD", amount: 16, currency: "USD"), Record(ownerID: "owner", module: .todo, rawInput: "Call John", dueAt: Date(), reminderEnabled: true, reminderLinked: true, reminderExternalID: "reminder-1")]
        let exported = try ExportService.makeExport(records: records, users: [user], exportedAt: Date(timeIntervalSince1970: 0)), entries = try ZipArchive.entries(in: exported)
        XCTAssertEqual(Set(entries.keys), ["manifest.json", "records.json", "users.json", "metadata.json", "attachments/"])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; let manifest = try decoder.decode(ExportManifest.self, from: XCTUnwrap(entries["manifest.json"])); XCTAssertEqual(manifest.recordCount, 2); XCTAssertEqual(manifest.userCount, 1); XCTAssertEqual(manifest.attachmentCount, 0)
        let archiveText = String(decoding: exported, as: UTF8.self); XCTAssertFalse(archiveText.localizedCaseInsensitiveContains("oauth")); XCTAssertFalse(archiveText.localizedCaseInsensitiveContains("password")); XCTAssertFalse(archiveText.localizedCaseInsensitiveContains("token"))
        let backup = try BackupService.makeBackup(records: records, users: [user], settings: ["theme": "lake-light"]), payload = try BackupService.validateAndRead(backup)
        XCTAssertEqual(payload.records.map(\.id), records.map(\.id)); XCTAssertEqual(payload.records.map(\.rawInput), records.map(\.rawInput)); XCTAssertEqual(payload.records.last?.reminderExternalID, "reminder-1")
        XCTAssertEqual(payload.users.map(\.id), [user.id]); XCTAssertEqual(payload.users.first?.provider, .apple); XCTAssertEqual(payload.settings["theme"], "lake-light")
        let identity = TestIdentity("owner"), store = MemoryRecordStore([Record(ownerID: "owner", module: .memo, rawInput: "existing")]), core = QuickNoteCore(store: store, identity: identity), before = store.records
        XCTAssertThrowsError(try BackupService.validateAndRead(Data("invalid".utf8))); XCTAssertEqual(store.records, before)
        try core.replaceCurrentOwnerRecords(with: payload.records); XCTAssertEqual(try core.records().count, 2)
    }

    func testMinimalEnglishTodoSearchAndCanonicalCurrencyQueries() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; let now = Date(timeIntervalSince1970: 1_800_000_000), parser = DeterministicDraftParser(calendar: calendar, now: { now })
        for input in ["Tomorrow 8 AM breakfast", "Call John at 3 PM tomorrow", "Buy milk Friday", "Dentist next Monday 10 AM", "Remind me in two hours to turn off the oven"] { guard case .create(let record) = try await parser.parse(input) else { return XCTFail(input) }; XCTAssertEqual(record.module, .todo, input); XCTAssertNotNil(record.dueAt, input) }
        guard case .search(let walmart) = try await parser.parse("Find Walmart ledger records") else { return XCTFail() }; XCTAssertEqual(walmart.modules, [.ledger]); XCTAssertEqual(walmart.keyword, "Walmart")
        guard case .search(let memos) = try await parser.parse("Find important memos") else { return XCTFail() }; XCTAssertEqual(memos.modules, [.memo]); XCTAssertTrue(memos.importantOnly)
        guard case .search(let amount) = try await parser.parse("Find ledger records over 50 USD") else { return XCTFail() }; XCTAssertEqual(amount.minimumAmount, 50); XCTAssertEqual(amount.currency, "USD")
        guard case .search(let ideas) = try await parser.parse("Find ideas about family mode") else { return XCTFail() }; XCTAssertEqual(ideas.modules, [.idea]); XCTAssertEqual(ideas.keyword, "family mode")
        let core = QuickNoteCore(store: MemoryRecordStore([Record(ownerID: "owner", module: .ledger, rawInput: "old Chinese", amount: 16, currency: "美元"), Record(ownerID: "owner", module: .ledger, rawInput: "canonical", amount: 70, currency: "USD"), Record(ownerID: "owner", module: .ledger, rawInput: "euro", amount: 25, currency: "EUR")]), identity: TestIdentity("owner"))
        func result(_ input: String) async throws -> ([UUID], [String: Decimal]) { guard case .search(let query) = try await parser.parse(input) else { throw ArchiveError.invalidArchive }; let records = try core.search(query); return (records.map(\.id), QuickNoteCore.numericTotals(in: records)) }
        let usdChinese = try await result("搜索美元"), usdCode = try await result("Search USD"); XCTAssertEqual(usdChinese.0, usdCode.0); XCTAssertEqual(usdChinese.1, usdCode.1)
        let euroChinese = try await result("搜索欧"), euroCode = try await result("Search EUR"); XCTAssertEqual(euroChinese.0, euroCode.0); XCTAssertEqual(euroChinese.1, euroCode.1)
    }

    func testFeatureFreezeEnglishDatesStructuredSearchPaginationAndReminderState() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 10))!, parser = DeterministicDraftParser(calendar: calendar, now: { now })
        guard case .create(let dentist) = try await parser.parse("Dentist next Monday 10 AM") else { return XCTFail() }; XCTAssertEqual(dentist.module, .todo); let dentistDate = calendar.dateComponents([.year, .month, .day, .hour], from: try XCTUnwrap(dentist.dueAt)); XCTAssertEqual(dentistDate.year, 2026); XCTAssertEqual(dentistDate.month, 9); XCTAssertEqual(dentistDate.day, 21); XCTAssertEqual(dentistDate.hour, 10)
        guard case .create(let pickup) = try await parser.parse("Pick up package at 6 PM") else { return XCTFail() }; XCTAssertEqual(pickup.module, .todo); XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(pickup.dueAt)), 18)
        guard case .search(let today) = try await parser.parse("Show todos today") else { return XCTFail() }; XCTAssertEqual(today.modules, [.todo]); XCTAssertNotNil(today.dateStart); XCTAssertEqual(today.keyword, "")
        guard case .search(let monthly) = try await parser.parse("Find expenses this month over 100 dollars") else { return XCTFail() }; XCTAssertEqual(monthly.modules, [.ledger]); XCTAssertEqual(monthly.minimumAmount, 100); XCTAssertEqual(monthly.currency, "USD"); XCTAssertNotNil(monthly.dateStart); XCTAssertEqual(monthly.keyword, "")
        let values = Array(0..<37); XCTAssertEqual(Pagination.pageCount(itemCount: values.count), 4); XCTAssertEqual(Pagination.page(values, index: 0), Array(0..<10)); XCTAssertEqual(Pagination.page(values, index: 3), Array(30..<37))
        var denied = Record(module: .todo, rawInput: "提醒", reminderEnabled: true, reminderState: .permissionDenied); denied.reminderLinked = false; XCTAssertEqual(denied.reminderState, .permissionDenied); XCTAssertFalse(denied.reminderLinked)
    }

    func testRCClockTimeReminderAndPaginationRegressions() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func due(_ hour: Int, _ input: String) async throws -> Date { let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: hour))!, parser = DeterministicDraftParser(calendar: calendar, now: { now }); guard case .create(let record) = try await parser.parse(input) else { throw ArchiveError.invalidArchive }; return try XCTUnwrap(record.dueAt) }
        let before = try await due(17, "Pick up package at 6 PM"), after = try await due(20, "Pick up package at 6 PM"), today = try await due(20, "Pick up package today at 6 PM"), tomorrow = try await due(20, "Pick up package tomorrow at 6 PM"), monday = try await due(20, "Dentist next Monday 10 AM")
        XCTAssertEqual(calendar.component(.day, from: before), 16)
        XCTAssertEqual(calendar.component(.day, from: after), 17)
        XCTAssertEqual(calendar.component(.day, from: today), 16)
        XCTAssertEqual(calendar.component(.day, from: tomorrow), 17)
        XCTAssertEqual(calendar.component(.hour, from: monday), 10)

        let store = MemoryRecordStore(), core = QuickNoteCore(store: store, identity: TestIdentity("owner")), dueAt = Date(timeIntervalSince1970: 2_000_000_000)
        for module in Module.allCases { let saved = try core.save(Record(module: module, rawInput: "remind", dueAt: dueAt, reminderEnabled: true, reminderState: .requested)); XCTAssertTrue(saved.reminderEnabled, module.rawValue); XCTAssertEqual(saved.reminderState, .requested, module.rawValue); XCTAssertEqual(saved.dueAt, dueAt, module.rawValue) }
        let denied = try core.save(Record(module: .memo, rawInput: "memo", reminderEnabled: true, reminderState: .permissionDenied)); XCTAssertEqual(denied.reminderState, .permissionDenied)
        var missing = Record(module: .todo, rawInput: "todo", reminderEnabled: true, reminderState: .missingExternalReminder); missing.reminderLinked = false; XCTAssertEqual((try core.save(missing)).reminderState, .missingExternalReminder)

        XCTAssertEqual(Pagination.clampedPage(1, itemCount: 25), 1)
        XCTAssertEqual(Pagination.clampedPage(99, itemCount: 25), 2)
        XCTAssertEqual(Pagination.clampedPage(-1, itemCount: 25), 0)
    }

    func testCurrencySearchAliasesMatchCanonicalAndLegacyValues() async throws {
        let parser = DeterministicDraftParser(), records = [Record(ownerID: "owner", module: .ledger, rawInput: "usd", amount: 1, currency: "美元"), Record(ownerID: "owner", module: .ledger, rawInput: "jpy", amount: 2, currency: "日元"), Record(ownerID: "owner", module: .ledger, rawInput: "eur", amount: 3, currency: "欧元"), Record(ownerID: "owner", module: .ledger, rawInput: "cny", amount: 4, currency: "人民币")]
        func ids(_ input: String) async throws -> [UUID] { guard case .search(let query) = try await parser.parse(input) else { throw ArchiveError.invalidArchive }; return QuickNoteCore.search(query, in: records).map(\.id) }
        for aliases in [["美元", "USD", "美金", "dollars"], ["日元", "JPY", "yen"], ["欧元", "EUR", "欧", "euros"], ["人民币", "CNY", "RMB"]] { let expected = try await ids("搜索 \(aliases[0])"); for alias in aliases.dropFirst() { let actual = try await ids("Search \(alias)"); XCTAssertEqual(actual, expected, alias) } }
    }

    func testMixedCurrencyAliasesFilterCanonicalItems() async throws {
        let parser = DeterministicDraftParser()
        guard case .create(let usd) = try await parser.parse("60美元 70usd"), case .create(let english) = try await parser.parse("60 dollars + 70 USD"), case .create(let mixed) = try await parser.parse("Paid $50 and €30") else { return XCTFail() }
        XCTAssertEqual(QuickNoteCore.numericTotals(in: [usd]), ["USD": 130])
        XCTAssertEqual(QuickNoteCore.numericTotals(in: [english]), ["USD": 130])
        XCTAssertEqual(QuickNoteCore.numericTotals(in: [mixed]), ["USD": 50, "EUR": 30])
        for alias in ["美元", "美金", "USD", "usd", "US dollars", "$", "bucks"] {
            let query = RecordQuery(keyword: alias)
            XCTAssertEqual(QuickNoteCore.search(query, in: [usd]).map(\.id), [usd.id], alias)
            XCTAssertEqual(QuickNoteCore.numericTotals(in: [usd], currency: query.effectiveCurrency), ["USD": 130], alias)
        }
        XCTAssertEqual(QuickNoteCore.numericTotals(in: QuickNoteCore.search(RecordQuery(keyword: "USD"), in: [mixed]), currency: "USD"), ["USD": 50])
        XCTAssertEqual(QuickNoteCore.numericTotals(in: QuickNoteCore.search(RecordQuery(keyword: "EUR"), in: [mixed]), currency: "EUR"), ["EUR": 30])
        for aliases in [["欧元", "EUR", "euros"], ["日元", "JPY", "yen"], ["人民币", "CNY", "RMB", "yuan"], ["英镑", "GBP", "pounds"]] { XCTAssertEqual(Set(aliases.compactMap(CurrencyCanonicalizer.recognized)).count, 1) }
    }

    func testEnglishV1Benchmark100Utterances() async throws {
        let parser = DeterministicDraftParser()
        let ledger = [
            "Paid $16 at Walmart", "Spent 30 dollars on lunch", "Coffee cost 5 bucks", "Groceries were USD 42",
            "Bought a book for 12 euros", "Paid €18 for dinner", "Train ticket cost 500 yen", "Spent JPY 1200 on food",
            "Gas was 40 US dollars", "Parking cost 8 dollars", "Paid 24 pounds for shoes", "Spent GBP 30 on a gift",
            "Lunch cost CNY 25", "Bought milk for 10 yuan", "Paid 16 USD with Visa", "Spent 70 dollars at Costco",
            "Bought headphones for $90", "Taxi fare was 22 bucks", "The hotel cost €95", "Paid 12 euros for coffee",
            "Spent 35 pounds on groceries", "Dinner was 60 USD", "Bus pass cost 900 yen", "Paid $7 for breakfast",
            "Spent 45 yuan on a notebook"
        ]
        let todo = [
            "Remind me to call Mom tomorrow", "Remind me to submit the report Friday", "Remind me to buy milk tonight",
            "Remind me to email Alex Monday", "Remind me to pick up the parcel Tuesday", "Remind me to visit the dentist Wednesday",
            "Remind me to water plants Thursday", "Remind me to check the car Saturday", "Remind me to clean the desk Sunday",
            "Remind me to send the invoice tomorrow morning", "Remind me to call the bank tomorrow afternoon",
            "Remind me to pack my bag tomorrow evening", "Remind me to take a break in 2 hours",
            "Remind me to leave in 30 minutes", "Remind me to review notes this weekend", "Remind me to finish the draft today",
            "Remind me to book tickets tomorrow", "Remind me to reply to Sam Friday morning",
            "Remind me to charge my phone tonight", "Remind me to make breakfast tomorrow morning",
            "Remind me to check the calendar Monday", "Remind me to send photos Tuesday afternoon",
            "Remind me to call the doctor Wednesday morning", "Remind me to collect the mail Thursday",
            "Remind me to prepare lunch tomorrow at 8 AM"
        ]
        let memo = [
            "The garage code is blue pine", "Mom likes jasmine tea", "The spare key is in the drawer",
            "Our WiFi name is Lake House", "The car manual is in the glove box", "The bakery on Main Street is quiet",
            "The new chair feels comfortable", "The pantry has rice and beans", "The blue folder holds receipts",
            "The train station has a small cafe", "The garden soil is very dry", "The dog prefers the red blanket",
            "The camera battery is in the cabinet", "The kitchen light flickers sometimes", "The travel bag has a hidden pocket",
            "The guest room window opens inward", "The printer paper is on the top shelf", "The museum entrance is on Oak Street",
            "The neighbor has a friendly cat", "The library card is in my wallet", "The recipe uses fresh basil",
            "The old laptop is in the closet", "The meeting room has a whiteboard", "The balcony gets afternoon sun",
            "The blue mug belongs to Sam"
        ]
        let idea = [
            "Idea: a simpler welcome screen", "Idea: show a calm background", "Idea: use larger buttons",
            "Idea: group related notes", "Idea: reduce setup steps", "Idea: make search easier",
            "Idea: highlight important notes", "Idea: offer a quiet mode", "Idea: use softer colors",
            "Idea: make cards easier to scan", "Idea: add a compact layout", "Idea: show recent activity",
            "Idea: improve empty states", "Idea: let users reorder cards", "Idea: use clearer labels",
            "Idea: show a short hint", "Idea: make editing faster", "Idea: simplify sharing",
            "Idea: support offline drafts", "Idea: remember the last filter", "Idea: offer a reading view",
            "Idea: make text more legible", "Idea: explain permissions clearly", "Idea: reduce visual clutter",
            "Idea: keep the home screen peaceful"
        ]
        XCTAssertEqual(ledger.count + todo.count + memo.count + idea.count, 100)
        for (module, inputs) in [(Module.ledger, ledger), (.todo, todo), (.memo, memo), (.idea, idea)] {
            for input in inputs {
                guard case .create(let record) = try await parser.parse(input) else { return XCTFail(input) }
                XCTAssertEqual(record.module, module, input)
                XCTAssertEqual(record.rawInput, input)
                if module == .ledger { XCTAssertFalse(record.amountItems.isEmpty, input) }
                if module == .todo { XCTAssertNotNil(record.dueAt, input) }
            }
        }
        let segments = parser.parseSegments("Paid $16 at Walmart and remind me to buy milk tomorrow")
        XCTAssertEqual(segments.map(\.module), [.ledger, .todo])
    }

#if canImport(UIKit) && !canImport(QuickNoteCore)
    @MainActor func testShareRendererProducesPNGAndPrivacyOptionsChangeOutput() throws {
        let record = Record(module: .ledger, rawInput: "Walmart 16 USD", tags: ["shopping"], merchant: "Walmart", amount: 16, currency: "USD")
        let full = try XCTUnwrap(ShareCardRenderer.png(records: [record], options: SharePrivacyOptions())), privateImage = try XCTUnwrap(ShareCardRenderer.png(records: [record], options: SharePrivacyOptions(showAmount: false, showDateTime: false, showTags: false, showMerchantOrLocation: false)))
        XCTAssertEqual(Array(full.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10]); XCTAssertNotEqual(full, privateImage)
        XCTAssertNil(ShareCardRenderer.png(records: [], options: .init())); XCTAssertFalse(SharePresentation.text(for: record, showAmount: false).contains("16"))
    }

    @MainActor func testSkinValidationFallbackPersistenceAndLanguagePersistence() throws {
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
        func archive(schema: Int = 1, assetPath: String = "assets/background.png", includeAsset: Bool = true) throws -> Data { let skin = SkinDefinition(schemaVersion: schema, id: "test-skin", name: "Test", author: nil, colors: ["primary": "#112233"], assets: ["pageBackgroundImage": assetPath], effects: .init(globalEffectEnabled: false, globalEffectType: "none")), json = try JSONEncoder().encode(skin); var entries = [("skin.json", json)]; if includeAsset { entries.append((assetPath, png)) }; return ZipArchive.make(entries) }
        XCTAssertThrowsError(try SkinManager.validate(Data("bad".utf8))); XCTAssertThrowsError(try SkinManager.validate(archive(schema: 2))); XCTAssertThrowsError(try SkinManager.validate(archive(includeAsset: false))); XCTAssertThrowsError(try SkinManager.validate(archive(assetPath: "../escape.png")))
        let suite = "skin-test-\(UUID())", defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite); defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let manager = SkinManager(defaults: defaults, folder: folder); try manager.importSkin(archive()); XCTAssertEqual(manager.current.id, "test-skin")
        let relaunched = SkinManager(defaults: defaults, folder: folder); XCTAssertEqual(relaunched.current.id, "test-skin"); relaunched.delete("test-skin"); XCTAssertEqual(relaunched.current.id, SkinDefinition.default.id)
        XCTAssertEqual(DisplayLanguage.saved(in: defaults), .system)
        defaults.set(DisplayLanguage.english.rawValue, forKey: "language.display"); XCTAssertEqual(DisplayLanguage.saved(in: defaults), .english)
        defaults.set(DisplayLanguage.simplifiedChinese.rawValue, forKey: "language.display"); XCTAssertEqual(DisplayLanguage.saved(in: defaults), .simplifiedChinese)
        defaults.set(SpeechInputLanguage.simplifiedChinese.rawValue, forKey: "language.speech"); XCTAssertEqual(defaults.string(forKey: "language.speech"), "simplifiedChinese"); XCTAssertEqual(DisplayLanguage.resolved("english").localeIdentifier, "en"); XCTAssertEqual(DisplayLanguage.resolved("simplifiedChinese").localeIdentifier, "zh-Hans"); XCTAssertEqual(DisplayLanguage.resolved("unknown"), .system)
        let date = Date(timeIntervalSince1970: 1_800_000_000), englishDate = AppLocalization.homeDate(date, locale: Locale(identifier: "en")), chineseDate = AppLocalization.homeDate(date, locale: Locale(identifier: "zh-Hans"))
        XCTAssertFalse(englishDate.contains("月")); XCTAssertFalse(englishDate.contains("星期")); XCTAssertTrue(chineseDate.contains("月")); XCTAssertEqual(AppLocalization.recordCount(1, locale: Locale(identifier: "en")), "1 record"); XCTAssertEqual(AppLocalization.recordCount(2, locale: Locale(identifier: "en")), "2 records"); XCTAssertEqual(AppLocalization.recordCount(1, locale: Locale(identifier: "zh-Hans")), "1 条记录"); XCTAssertEqual(AppLocalization.recordCount(2, locale: Locale(identifier: "zh-Hans")), "2 条记录")
        let catalogURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("AIQuickNote/Localizable.xcstrings"), catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any], strings = try XCTUnwrap(catalog?["strings"] as? [String: Any])
        for key in ["用户名", "身份", "退出登录", "导出、备份与恢复"] { let entry = try XCTUnwrap(strings[key] as? [String: Any]), localizations = try XCTUnwrap(entry["localizations"] as? [String: Any]); XCTAssertNotNil(localizations["en"], key) }
    }
#endif
}
