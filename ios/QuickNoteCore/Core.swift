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

public struct RecordQuery: Sendable {
    public var keyword = ""
    public var modules = Set(Module.allCases)
    public var importantOnly = false
    public var tags: [String] = []
    public init(keyword: String = "", modules: Set<Module> = Set(Module.allCases), importantOnly: Bool = false, tags: [String] = []) {
        self.keyword = keyword; self.modules = modules; self.importantOnly = importantOnly; self.tags = tags
    }
}

public protocol IdentityGate: Sendable { var confirmedUserID: String? { get } }
public protocol QueryParsing: Sendable { func parse(_ text: String) -> RecordQuery }
public struct DeterministicQueryParser: QueryParsing { public init() {} ; public func parse(_ text: String) -> RecordQuery { RecordQuery(keyword: text) } }
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
            value.createdAt = records[index].createdAt; value.rawInput = records[index].rawInput; records[index] = value
        } else { records.append(value) }
        try store.save(records)
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
