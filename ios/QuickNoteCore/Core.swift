import Foundation

public enum Module: String, Codable, CaseIterable, Identifiable, Sendable {
    case ledger, todo, memo, idea
    public var id: Self { self }
    public var title: String { ["ledger": "账目", "todo": "待办", "memo": "备忘", "idea": "灵感"][rawValue]! }
}

public enum TodoStatus: String, Codable, CaseIterable, Sendable { case pending = "待处理", done = "已完成" }

public struct Record: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var ownerID: String
    public var module: Module
    public var rawInput: String
    public var content: String
    public var important: Bool
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date
    public var merchant: String?
    public var amount: Decimal?
    public var currency: String?
    public var category: String?
    public var paymentMethod: String?
    public var occurredAt: Date?
    public var dueAt: Date?
    public var reminderEnabled: Bool
    public var location: String?
    public var status: TodoStatus?

    public init(id: UUID = UUID(), ownerID: String = "", module: Module, rawInput: String, content: String? = nil,
                important: Bool = false, tags: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date(),
                merchant: String? = nil, amount: Decimal? = nil, currency: String? = nil, category: String? = nil,
                paymentMethod: String? = nil, occurredAt: Date? = nil, dueAt: Date? = nil,
                reminderEnabled: Bool = false, location: String? = nil, status: TodoStatus? = nil) {
        self.id = id; self.ownerID = ownerID; self.module = module; self.rawInput = rawInput
        self.content = content ?? rawInput; self.important = important; self.tags = tags
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.merchant = merchant; self.amount = amount
        self.currency = currency; self.category = category; self.paymentMethod = paymentMethod
        self.occurredAt = occurredAt; self.dueAt = dueAt; self.reminderEnabled = reminderEnabled
        self.location = location; self.status = status
    }
}

public struct RecordQuery: Sendable, Equatable {
    public var keyword = ""
    public var modules = Set(Module.allCases)
    public var importantOnly = false
    public var tags: [String] = []
    public init(keyword: String = "", modules: Set<Module> = Set(Module.allCases), importantOnly: Bool = false, tags: [String] = []) {
        self.keyword = keyword; self.modules = modules; self.importantOnly = importantOnly; self.tags = tags
    }
}

public protocol IdentityGate: Sendable { var confirmedUserID: String? { get } }
public enum ParsedInput: Sendable, Equatable {
    case create(Record)
    case search(RecordQuery)
}

public protocol DraftParser: Sendable { func parse(_ input: String) async throws -> ParsedInput }

public struct DeterministicDraftParser: DraftParser {
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = Date.init) {
        self.calendar = calendar; self.now = now
    }

    public func parse(_ input: String) async throws -> ParsedInput {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .create(Record(module: .memo, rawInput: input)) }
        if text.hasPrefix("找") || text.hasPrefix("搜索") || text.hasPrefix("查询") { return .search(query(text)) }
        return .create(draft(text))
    }

    private func query(_ text: String) -> RecordQuery {
        let named = Set(Module.allCases.filter { text.contains($0.title) })
        var keyword = text
        ["搜索", "查询", "找", "所有", "全部", "重要的", "重要", "记录", "和", "的"].forEach { keyword = keyword.replacingOccurrences(of: $0, with: "") }
        Module.allCases.forEach { keyword = keyword.replacingOccurrences(of: $0.title, with: "") }
        return RecordQuery(keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines), modules: named.isEmpty ? Set(Module.allCases) : named, importantOnly: text.contains("重要"))
    }

    private func draft(_ text: String) -> Record {
        if text.contains("提醒") || text.contains("待办") || text.contains("明天") && text.contains("点") {
            return Record(module: .todo, rawInput: text, content: todoContent(text), tags: tags(text, module: .todo), dueAt: date(in: text), reminderEnabled: text.contains("提醒"), status: .pending)
        }
        if text.contains("以后") || text.contains("想法") || text.contains("灵感") || text.contains("可以增加") {
            return Record(module: .idea, rawInput: text, tags: tags(text, module: .idea))
        }
        if amount(in: text) != nil || ["美元", "支付", "购物", "付款", "花了"].contains(where: text.contains) {
            return Record(module: .ledger, rawInput: text, tags: tags(text, module: .ledger), merchant: merchant(in: text), amount: amount(in: text), currency: text.contains("美元") || text.localizedCaseInsensitiveContains("USD") ? "USD" : nil, category: text.contains("购物") ? "购物" : nil, paymentMethod: payment(in: text), occurredAt: date(in: text) ?? now())
        }
        return Record(module: .memo, rawInput: text, tags: tags(text, module: .memo))
    }

    private func amount(in text: String) -> Decimal? {
        guard let range = text.range(of: #"\d+(?:\.\d+)?(?=\s*(?:美元|USD|元))"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Decimal(string: String(text[range]), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func merchant(in text: String) -> String? { ["沃尔玛", "Walmart", "Costco", "Target", "亚马逊"].first(where: { text.localizedCaseInsensitiveContains($0) }) }
    private func payment(in text: String) -> String? { ["美国银行", "Bank of America", "现金", "支付宝", "微信", "信用卡"].first(where: { text.localizedCaseInsensitiveContains($0) }) }

    private func date(in text: String) -> Date? {
        let offset = text.contains("后天") ? 2 : text.contains("明天") ? 1 : text.contains("今天") ? 0 : nil
        guard let offset else { return nil }
        var value = calendar.date(byAdding: .day, value: offset, to: now())!
        if let range = text.range(of: #"(?:早上|上午|下午|晚上)?\s*(\d{1,2})(?:点|:)\s*(\d{1,2})?"#, options: .regularExpression) {
            let parts = text[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let hour = parts.first { value = calendar.date(bySettingHour: hour + ((text[range].contains("下午") || text[range].contains("晚上")) && hour < 12 ? 12 : 0), minute: parts.dropFirst().first ?? 0, second: 0, of: value)! }
        }
        return value
    }

    private func todoContent(_ text: String) -> String {
        var value = text
        ["提醒我", "提醒", "明天", "后天", "今天", "早上8点", "上午8点"].forEach { value = value.replacingOccurrences(of: $0, with: "") }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tags(_ text: String, module: Module) -> [String] {
        var values: [String] = []
        let candidates = ["沃尔玛", "购物", "美国银行", "汽车", "早点", "早餐", "吃饭", "家庭模式"]
        values += candidates.filter { text.localizedCaseInsensitiveContains($0) }
        if module == .todo && (text.contains("早饭") || text.contains("早餐")) { values += ["早餐", "吃饭"] }
        if module == .memo && text.contains("车") { values.append("汽车") }
        if module == .idea { values.append("产品想法") }
        return Array(values.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(5))
    }
}
// Backup remains a separate, future system capability; saving never triggers backup, upload, or sharing.

public protocol RecordStore: Sendable {
    func load() throws -> [Record]
    func save(_ records: [Record]) throws
}

public enum CoreError: Error, Equatable { case identityRequired, emptyContent, recordNotFound }

public final class FileRecordStore: RecordStore, @unchecked Sendable {
    private let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [Record] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Record].self, from: Data(contentsOf: url))
    }
    public func save(_ records: [Record]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
}

public final class MemoryRecordStore: RecordStore, @unchecked Sendable {
    public var records: [Record]
    public init(_ records: [Record] = []) { self.records = records }
    public func load() -> [Record] { records }
    public func save(_ records: [Record]) { self.records = records }
}

public final class QuickNoteCore: @unchecked Sendable {
    private let store: RecordStore
    private let identity: IdentityGate
    public init(store: RecordStore, identity: IdentityGate) { self.store = store; self.identity = identity }

    @discardableResult public func save(_ draft: Record) throws -> Record {
        guard let ownerID = identity.confirmedUserID else { throw CoreError.identityRequired }
        guard !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CoreError.emptyContent }
        var records = try store.load(), value = draft
        value.ownerID = ownerID; value.updatedAt = Date()
        if let index = records.firstIndex(where: { $0.id == value.id && $0.ownerID == ownerID }) {
            value.createdAt = records[index].createdAt; value.rawInput = records[index].rawInput
            value = normalizeForModule(value); records[index] = value
        } else { value = normalizeForModule(value); records.append(value) }
        try store.save(records)
        return value
    }

    private func normalizeForModule(_ record: Record) -> Record {
        var value = record
        switch value.module {
        case .ledger:
            value.dueAt = nil; value.reminderEnabled = false; value.status = nil
        case .todo:
            value.merchant = nil; value.amount = nil; value.currency = nil; value.category = nil
            value.paymentMethod = nil; value.occurredAt = nil; value.status = value.status ?? .pending
        case .memo:
            value.merchant = nil; value.amount = nil; value.currency = nil; value.category = nil
            value.paymentMethod = nil; value.occurredAt = nil; value.dueAt = nil; value.location = nil; value.status = nil
        case .idea:
            value.merchant = nil; value.amount = nil; value.currency = nil; value.category = nil
            value.paymentMethod = nil; value.occurredAt = nil; value.dueAt = nil
            value.reminderEnabled = false; value.location = nil; value.status = nil
        }
        return value
    }

    public func records(module: Module? = nil) throws -> [Record] {
        guard let ownerID = identity.confirmedUserID else { return [] }
        return try store.load().filter { $0.ownerID == ownerID && (module == nil || $0.module == module) }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func search(_ query: RecordQuery) throws -> [Record] {
        try records().filter { record in
            let haystack = ([record.content, record.rawInput] + record.tags).joined(separator: " ")
            return query.modules.contains(record.module)
                && (!query.importantOnly || record.important)
                && (query.keyword.isEmpty || haystack.localizedCaseInsensitiveContains(query.keyword))
                && query.tags.allSatisfy { record.tags.contains($0) }
        }
    }
}
