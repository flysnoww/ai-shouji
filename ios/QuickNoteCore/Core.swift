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
    public var quantity: Decimal?
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
                merchant: String? = nil, quantity: Decimal? = nil, amount: Decimal? = nil, currency: String? = nil, category: String? = nil,
                paymentMethod: String? = nil, occurredAt: Date? = nil, dueAt: Date? = nil,
                reminderEnabled: Bool = false, location: String? = nil, status: TodoStatus? = nil) {
        self.id = id; self.ownerID = ownerID; self.module = module; self.rawInput = rawInput
        self.content = content ?? rawInput; self.important = important; self.tags = tags
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.merchant = merchant; self.quantity = quantity; self.amount = amount
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
    public var dateStart: Date?
    public var dateEnd: Date?
    public var minimumAmount: Decimal?
    public var currency: String?
    public var category: String?
    public init(keyword: String = "", modules: Set<Module> = Set(Module.allCases), importantOnly: Bool = false, tags: [String] = [], dateStart: Date? = nil, dateEnd: Date? = nil, minimumAmount: Decimal? = nil, currency: String? = nil, category: String? = nil) {
        self.keyword = keyword; self.modules = modules; self.importantOnly = importantOnly; self.tags = tags; self.dateStart = dateStart; self.dateEnd = dateEnd; self.minimumAmount = minimumAmount; self.currency = currency; self.category = category
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
        let range = dateRange(in: text), category = category(in: text), minimum = capturedNumber(in: text, pattern: #"(?:超过|大于)\s*(\d+(?:\.\d+)?)"#)
        var keyword = text.replacingOccurrences(of: #"(?:今天|昨天|明天|后天|本月|这个月|下个月|本周|下周[一二三四五六日天]?|星期[一二三四五六日天]|周[一二三四五六日天]|\d+\s*(?:小时|分钟)后)"#, with: "", options: .regularExpression)
        keyword = keyword.replacingOccurrences(of: #"(?:金额)?(?:超过|大于)\s*\d+(?:\.\d+)?\s*(?:美元|USD|日元|JPY|欧元|EUR|人民币|CNY|元)?"#, with: "", options: [.regularExpression, .caseInsensitive])
        ["搜索", "查询", "找", "所有", "全部", "重要的", "重要", "记录", "里面", "里的", "里", "和", "的", "金额"].forEach { keyword = keyword.replacingOccurrences(of: $0, with: "") }
        Module.allCases.forEach { keyword = keyword.replacingOccurrences(of: $0.title, with: "") }
        if let category { keyword = keyword.replacingOccurrences(of: category, with: "") }
        return RecordQuery(keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines), modules: named.isEmpty ? Set(Module.allCases) : named, importantOnly: text.contains("重要"), dateStart: range?.0, dateEnd: range?.1, minimumAmount: minimum, currency: currency(in: text), category: category)
    }

    private func draft(_ text: String) -> Record {
        let parsedQuantity = quantity(in: text)
        if hasMoney(in: text) {
            return Record(module: .ledger, rawInput: text, tags: tags(text, module: .ledger), merchant: merchant(in: text), quantity: parsedQuantity, amount: amount(in: text), currency: currency(in: text), category: category(in: text), paymentMethod: payment(in: text), occurredAt: date(in: text) ?? now())
        }
        if text.contains("提醒") || text.contains("待办") || (hasFutureTime(in: text) && hasAction(in: text)) || text.contains("别忘了") {
            return Record(module: .todo, rawInput: text, tags: tags(text, module: .todo), quantity: parsedQuantity, dueAt: date(in: text), reminderEnabled: text.contains("提醒"), status: .pending)
        }
        if text.contains("以后") || text.contains("想法") || text.contains("灵感") || text.contains("可以增加") {
            return Record(module: .idea, rawInput: text, tags: tags(text, module: .idea), quantity: parsedQuantity)
        }
        return Record(module: .memo, rawInput: text, tags: tags(text, module: .memo), quantity: parsedQuantity)
    }

    private func amount(in text: String) -> Decimal? {
        if let total = capturedNumber(in: text, pattern: #"(?:一共|总共|合计)\s*(\d+(?:\.\d+)?)\s*(?:美元|dollars?|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)"#) { return total }
        if let value = capturedNumber(in: text, pattern: #"(?:\$|USD\s*)(\d+(?:\.\d+)?)|(?:花了|支付|付款)?\s*(\d+(?:\.\d+)?)\s*(?:美元|dollars?|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)"#) { return value }
        if let value = capture(in: text, pattern: #"([零〇一二两三四五六七八九十百千万]+)\s*(?:美元|日元|欧元|人民币|元|块)"#) { return Decimal(chineseNumber(value)) }
        if let value = capture(in: text, pattern: #"(?:美元|日元|欧元|人民币)\s*([零〇一二两三四五六七八九十百千万]+)"#) { return Decimal(chineseNumber(value)) }
        return nil
    }

    private func quantity(in text: String) -> Decimal? {
        guard let range = text.range(of: #"\d+(?:\.\d+)?(?=\s*(?:瓶|个|件|盒|包|杯|份|本|张|台|箱))"#, options: .regularExpression) else { return nil }
        return Decimal(string: String(text[range]), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func currency(in text: String) -> String? {
        if text.contains("美元") || text.localizedCaseInsensitiveContains("USD") { return "USD" }
        if text.contains("日元") || text.localizedCaseInsensitiveContains("JPY") { return "JPY" }
        if text.contains("欧元") || text.localizedCaseInsensitiveContains("EUR") { return "EUR" }
        if text.contains("人民币") || text.localizedCaseInsensitiveContains("CNY") || text.contains("元") || text.contains("块") { return "CNY" }
        if text.contains("美元") || text.localizedCaseInsensitiveContains("dollar") || text.contains("$") { return "USD" }
        return nil
    }

    private func merchant(in text: String) -> String? { ["沃尔玛", "Walmart", "Costco", "Target", "Amazon", "亚马逊", "Starbucks"].first(where: { text.localizedCaseInsensitiveContains($0) }) }
    private func payment(in text: String) -> String? { ["美国银行", "Bank of America", "Visa", "现金", "支付宝", "微信", "信用卡"].first(where: { text.localizedCaseInsensitiveContains($0) }) }

    private func date(in text: String) -> Date? {
        if let hours = capturedInt(in: text, pattern: #"(\d+)\s*小时后"#) { return calendar.date(byAdding: .hour, value: hours, to: now()) }
        if let minutes = capturedInt(in: text, pattern: #"(\d+)\s*分钟后"#) { return calendar.date(byAdding: .minute, value: minutes, to: now()) }
        var value = dateRange(in: text)?.0
        if value == nil, let weekday = weekday(in: text) { let current = calendar.component(.weekday, from: now()); var delta = (weekday - current + 7) % 7; if text.contains("下周") { delta += 7 }; value = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now())) }
        if value == nil, let yearText = capture(in: text, pattern: #"([零〇一二两三四五六七八九]{4})年([零〇一二两三四五六七八九十]+)月([零〇一二两三四五六七八九十]+)[日号]"#, group: 0) { let parts = yearText.split(whereSeparator: { "年月日号".contains($0) }).map { chineseNumber(String($0)) }; if parts.count == 3 { value = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) } }
        guard var value else { return nil }
        if let expression = capture(in: text, pattern: #"((?:早上|上午|中午|下午|晚上|今晚)?\s*(?:\d{1,2}|[一二两三四五六七八九十]+)(?:点|:)\s*(?:半|\d{1,2})?)"#) { let digits = expression.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }; var hourText = expression; ["早上", "上午", "中午", "下午", "晚上", "今晚"].forEach { hourText = hourText.replacingOccurrences(of: $0, with: "") }; hourText = String(hourText.prefix { $0 != "点" && $0 != ":" }).trimmingCharacters(in: .whitespaces); let chineseHour = digits.first ?? chineseNumber(hourText); var hour = chineseHour; if (expression.contains("下午") || expression.contains("晚上") || expression.contains("今晚")) && hour < 12 { hour += 12 }; let minute = expression.contains("半") ? 30 : digits.dropFirst().first ?? 0; value = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: value) ?? value }
        return value
    }

    private func tags(_ text: String, module: Module) -> [String] {
        var values: [String] = []
        let candidates = ["购物", "家庭", "汽车", "工作", "旅行", "健康", "生活", "电子", "餐饮"]
        values += candidates.filter { text.localizedCaseInsensitiveContains($0) }
        if text.contains("买") { values.append("购物") }; if text.contains("车") { values.append("汽车") }; if ["午饭", "咖啡", "早餐", "早饭", "Starbucks"].contains(where: { text.localizedCaseInsensitiveContains($0) }) { values.append("餐饮") }
        if module == .idea { values.append("产品想法") }
        return Array(values.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(3))
    }

    private func hasMoney(in text: String) -> Bool { amount(in: text) != nil || ["美元", "dollar", "USD", "日元", "JPY", "欧元", "EUR", "人民币", "CNY", "$", "花了", "支付", "付款", "一共"].contains { text.localizedCaseInsensitiveContains($0) } }
    private func hasFutureTime(in text: String) -> Bool { text.range(of: #"今天晚些时候|今晚|明天|后天|星期[一二三四五六日天]|周[一二三四五六日天]|下周|\d+\s*(?:小时|分钟)后|上午|下午|晚上|早上"#, options: .regularExpression) != nil }
    private func hasAction(in text: String) -> Bool { ["去", "买", "吃", "提交", "打电话", "充电", "看", "预约", "做", "拿", "送", "检查", "打扫", "提醒", "完成"].contains(where: text.contains) }
    private func category(in text: String) -> String? { [("停车", "停车"), ("加油", "加油"), ("午饭", "餐饮"), ("咖啡", "餐饮"), ("Starbucks", "餐饮"), ("买菜", "食品"), ("牛奶", "食品"), ("显示器", "电子产品"), ("充电器", "电子产品"), ("iPhone", "电子产品"), ("买书", "书籍"), ("医疗", "医疗"), ("看牙", "医疗"), ("购物", "购物"), ("买", "购物")].first(where: { text.localizedCaseInsensitiveContains($0.0) })?.1 }
    private func dateRange(in text: String) -> (Date, Date)? { let start: Date?; if let target = weekday(in: text) { let current = calendar.component(.weekday, from: now()); var delta = (target - current + 7) % 7; if text.contains("下周") { delta += 7 }; start = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now())) } else if text.contains("昨天") { start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now())) } else if text.contains("后天") { start = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now())) } else if text.contains("明天") { start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now())) } else if text.contains("今天") || text.contains("今晚") { start = calendar.startOfDay(for: now()) } else if text.contains("本月") || text.contains("这个月") { start = calendar.date(from: calendar.dateComponents([.year, .month], from: now())) } else if text.contains("下个月") { start = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: now()))!) } else { start = nil }; guard let start else { return nil }; let component: Calendar.Component = (text.contains("月") && !text.contains("明天")) ? .month : .day; return (start, calendar.date(byAdding: component, value: 1, to: start)!) }
    private func weekday(in text: String) -> Int? { let names = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1]; return names.first(where: { text.range(of: "(?:星期|周|下周)\($0.key)", options: .regularExpression) != nil })?.value }
    private func capture(in text: String, pattern: String, group: Int = 1) -> String? { guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }; return String(text[range]) }
    private func capturedNumber(in text: String, pattern: String) -> Decimal? { guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }; for index in 1..<match.numberOfRanges { if let range = Range(match.range(at: index), in: text), let value = Decimal(string: String(text[range]), locale: Locale(identifier: "en_US_POSIX")) { return value } }; return nil }
    private func capturedInt(in text: String, pattern: String) -> Int? { capture(in: text, pattern: pattern).flatMap(Int.init) }
    private func chineseNumber(_ text: String) -> Int { let digits: [Character: Int] = ["零":0,"〇":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]; if !text.contains(where: { "十百千万".contains($0) }) { return text.reduce(0) { $0 * 10 + (digits[$1] ?? 0) } }; var total = 0, section = 0, number = 0; for char in text { if let digit = digits[char] { number = digit } else { let unit = char == "十" ? 10 : char == "百" ? 100 : char == "千" ? 1000 : 10000; if unit == 10000 { section = (section + number) * unit; total += section; section = 0 } else { section += max(number, 1) * unit }; number = 0 } }; return total + section + number }
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
            let fields = [record.merchant, record.currency, record.category, record.paymentMethod, record.location, record.amount.map(String.init(describing:)), record.quantity.map(String.init(describing:))].compactMap { $0 }
            let haystack = ([record.content, record.rawInput] + record.tags + fields).joined(separator: " ")
            return query.modules.contains(record.module)
                && (!query.importantOnly || record.important)
                && (query.keyword.isEmpty || haystack.localizedCaseInsensitiveContains(query.keyword))
                && query.tags.allSatisfy { record.tags.contains($0) }
                && (query.category == nil || record.category == query.category || record.tags.contains(query.category!))
                && (query.currency == nil || record.currency == query.currency)
                && (query.minimumAmount == nil || (record.amount.map { $0 > query.minimumAmount! } ?? false))
                && (query.dateStart == nil || ((record.occurredAt ?? record.dueAt ?? record.createdAt) >= query.dateStart!))
                && (query.dateEnd == nil || ((record.occurredAt ?? record.dueAt ?? record.createdAt) < query.dateEnd!))
        }
    }

    public static func numericTotals(in records: [Record]) -> [String: Decimal] {
        records.reduce(into: [:]) { totals, record in
            if let amount = record.amount { totals[record.currency ?? "未标币种", default: 0] += amount; return }
            if let quantity = record.quantity { totals["数量", default: 0] += quantity }
        }
    }
}
