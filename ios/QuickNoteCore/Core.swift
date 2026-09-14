import Foundation

public enum Module: String, Codable, CaseIterable, Identifiable, Sendable {
    case ledger, todo, memo, idea
    public var id: Self { self }
    public var title: String { ["ledger": "账目", "todo": "待办", "memo": "备忘", "idea": "灵感"][rawValue]! }
}

public enum TodoStatus: String, Codable, CaseIterable, Sendable { case pending = "待处理", done = "已完成" }

public struct AmountItem: Codable, Hashable, Sendable {
    public var value: Decimal
    public var currency: String?
    public init(value: Decimal, currency: String? = nil) { self.value = value; self.currency = currency }
}

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
    public var amountItems: [AmountItem]
    public var category: String?
    public var paymentMethod: String?
    public var occurredAt: Date?
    public var dueAt: Date?
    public var reminderEnabled: Bool
    public var location: String?
    public var status: TodoStatus?

    public init(id: UUID = UUID(), ownerID: String = "", module: Module, rawInput: String, content: String? = nil,
                important: Bool = false, tags: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date(),
                merchant: String? = nil, amount: Decimal? = nil, currency: String? = nil, amountItems: [AmountItem] = [], category: String? = nil,
                paymentMethod: String? = nil, occurredAt: Date? = nil, dueAt: Date? = nil,
                reminderEnabled: Bool = false, location: String? = nil, status: TodoStatus? = nil) {
        self.id = id; self.ownerID = ownerID; self.module = module; self.rawInput = rawInput
        self.content = content ?? rawInput; self.important = important; self.tags = tags
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.merchant = merchant; self.amount = amount
        self.currency = currency; self.amountItems = amountItems.isEmpty ? amount.map { [AmountItem(value: $0, currency: currency)] } ?? [] : amountItems; self.category = category; self.paymentMethod = paymentMethod
        self.occurredAt = occurredAt; self.dueAt = dueAt; self.reminderEnabled = reminderEnabled
        self.location = location; self.status = status
    }

    private enum CodingKeys: String, CodingKey { case id, ownerID, module, rawInput, content, important, tags, createdAt, updatedAt, merchant, amount, currency, amountItems, category, paymentMethod, occurredAt, dueAt, reminderEnabled, location, status }
    public init(from decoder: Decoder) throws { let box = try decoder.container(keyedBy: CodingKeys.self); let legacyAmount = try box.decodeIfPresent(Decimal.self, forKey: .amount), legacyCurrency = try box.decodeIfPresent(String.self, forKey: .currency); id = try box.decode(UUID.self, forKey: .id); ownerID = try box.decode(String.self, forKey: .ownerID); module = try box.decode(Module.self, forKey: .module); rawInput = try box.decode(String.self, forKey: .rawInput); content = try box.decode(String.self, forKey: .content); important = try box.decode(Bool.self, forKey: .important); tags = try box.decode([String].self, forKey: .tags); createdAt = try box.decode(Date.self, forKey: .createdAt); updatedAt = try box.decode(Date.self, forKey: .updatedAt); merchant = try box.decodeIfPresent(String.self, forKey: .merchant); amount = legacyAmount; currency = legacyCurrency; amountItems = try box.decodeIfPresent([AmountItem].self, forKey: .amountItems) ?? legacyAmount.map { [AmountItem(value: $0, currency: legacyCurrency)] } ?? []; category = try box.decodeIfPresent(String.self, forKey: .category); paymentMethod = try box.decodeIfPresent(String.self, forKey: .paymentMethod); occurredAt = try box.decodeIfPresent(Date.self, forKey: .occurredAt); dueAt = try box.decodeIfPresent(Date.self, forKey: .dueAt); reminderEnabled = try box.decode(Bool.self, forKey: .reminderEnabled); location = try box.decodeIfPresent(String.self, forKey: .location); status = try box.decodeIfPresent(TodoStatus.self, forKey: .status) }
}

public struct RecordQuery: Sendable, Equatable {
    public var keyword = ""
    public var modules = Set(Module.allCases)
    public var importantOnly = false
    public var tags: [String] = []
    public var dateStart: Date?
    public var dateEnd: Date?
    public var minimumAmount: Decimal?
    public var minimumInclusive = false
    public var maximumAmount: Decimal?
    public var maximumInclusive = false
    public var currency: String?
    public var category: String?
    public init(keyword: String = "", modules: Set<Module> = Set(Module.allCases), importantOnly: Bool = false, tags: [String] = [], dateStart: Date? = nil, dateEnd: Date? = nil, minimumAmount: Decimal? = nil, minimumInclusive: Bool = false, maximumAmount: Decimal? = nil, maximumInclusive: Bool = false, currency: String? = nil, category: String? = nil) {
        self.keyword = keyword; self.modules = modules; self.importantOnly = importantOnly; self.tags = tags; self.dateStart = dateStart; self.dateEnd = dateEnd; self.minimumAmount = minimumAmount; self.minimumInclusive = minimumInclusive; self.maximumAmount = maximumAmount; self.maximumInclusive = maximumInclusive; self.currency = currency; self.category = category
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
        let text = text.replacingOccurrences(of: "代办", with: "待办")
        let named = Set(Module.allCases.filter { text.contains($0.title) })
        let range = dateRange(in: text), category = category(in: text)
        let strictMinimum = capturedNumber(in: text, pattern: #"(?:超过|大于)\s*(\d+(?:\.\d+)?)"#)
        let inclusiveMinimum = capturedNumber(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:美元|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)?\s*以上"#)
        let strictMaximum = capturedNumber(in: text, pattern: #"(?:少于|小于)\s*(\d+(?:\.\d+)?)"#)
        let inclusiveMaximum = capturedNumber(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:美元|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)?\s*以下"#)
        var keyword = text.replacingOccurrences(of: #"(?:今天|昨天|明天|后天|本月|这个月|下个月|本周|下周[一二三四五六日天]?|星期[一二三四五六日天]|周[一二三四五六日天]|[\d零〇一二两三四五六七八九十百千万]+\s*(?:小时|分钟)后)"#, with: "", options: .regularExpression)
        keyword = keyword.replacingOccurrences(of: #"(?:金额)?(?:(?:超过|大于|少于|小于)\s*\d+(?:\.\d+)?|\d+(?:\.\d+)?\s*(?:美元|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)?\s*(?:以上|以下))\s*(?:美元|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)?"#, with: "", options: [.regularExpression, .caseInsensitive])
        ["搜索", "查询", "找", "所有", "全部", "重要的", "重要", "记录", "里面", "里的", "里", "和", "的", "金额"].forEach { keyword = keyword.replacingOccurrences(of: $0, with: "") }
        Module.allCases.forEach { keyword = keyword.replacingOccurrences(of: $0.title, with: "") }
        if let category { keyword = keyword.replacingOccurrences(of: category, with: "") }
        return RecordQuery(keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines), modules: named.isEmpty ? Set(Module.allCases) : named, importantOnly: text.contains("重要"), dateStart: range?.0, dateEnd: range?.1, minimumAmount: strictMinimum ?? inclusiveMinimum, minimumInclusive: inclusiveMinimum != nil, maximumAmount: strictMaximum ?? inclusiveMaximum, maximumInclusive: inclusiveMaximum != nil, currency: currency(in: text), category: category)
    }

    private func draft(_ text: String) -> Record {
        if hasMoney(in: text) {
            let items = amountItems(in: text), single = items.count == 1 ? items.first : nil
            return Record(module: .ledger, rawInput: text, tags: tags(text, module: .ledger), merchant: merchant(in: text), amount: single?.value, currency: single?.currency, amountItems: items, category: category(in: text), paymentMethod: payment(in: text), occurredAt: date(in: text))
        }
        if text.contains("提醒") || text.contains("待办") || (hasFutureTime(in: text) && hasAction(in: text)) || text.contains("别忘了") {
            return Record(module: .todo, rawInput: text, tags: tags(text, module: .todo), dueAt: date(in: text), reminderEnabled: text.contains("提醒"), status: .pending)
        }
        if ["方案", "想法", "改进", "可以", "以后", "也许", "灵感"].contains(where: text.contains) || (text.contains("如果") && text.contains("就")) {
            return Record(module: .idea, rawInput: text, tags: tags(text, module: .idea))
        }
        return Record(module: .memo, rawInput: text, tags: tags(text, module: .memo))
    }

    private func amountItems(in text: String) -> [AmountItem] {
        if let regex = try? NSRegularExpression(pattern: #"(?:一共|总共|合计|共|总价|total)\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(美元|dollars?|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)"#, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let valueRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text), let value = Decimal(string: String(text[valueRange]), locale: Locale(identifier: "en_US_POSIX")) { return [AmountItem(value: value, currency: normalizedCurrency(String(text[unitRange])))] }
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(美元|dollars?|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)"#, options: .caseInsensitive) else { return [] }
        let items: [AmountItem] = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let fullRange = Range(match.range, in: text), let valueRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text), let value = Decimal(string: String(text[valueRange]), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            let prefix = String(text[..<fullRange.lowerBound].suffix(8))
            guard prefix.range(of: #"(?:每盒|每个|每件|每瓶|每台|每本|每份|每箱|单价|each|per)\s*$"#, options: [.regularExpression, .caseInsensitive]) == nil else { return nil }
            return AmountItem(value: value, currency: normalizedCurrency(String(text[unitRange])))
        }
        if !items.isEmpty { return items }
        if let value = capture(in: text, pattern: #"([零〇一二两三四五六七八九十百千万]+)\s*(美元|日元|欧元|人民币|元|块)"#), let unit = capture(in: text, pattern: #"[零〇一二两三四五六七八九十百千万]+\s*(美元|日元|欧元|人民币|元|块)"#) { return [AmountItem(value: Decimal(chineseNumber(value)), currency: normalizedCurrency(unit))] }
        if let unit = capture(in: text, pattern: #"(美元|日元|欧元|人民币)\s*[零〇一二两三四五六七八九十百千万]+"#), let value = capture(in: text, pattern: #"(?:美元|日元|欧元|人民币)\s*([零〇一二两三四五六七八九十百千万]+)"#) { return [AmountItem(value: Decimal(chineseNumber(value)), currency: normalizedCurrency(unit))] }
        return []
    }

    private func currency(in text: String) -> String? {
        if text.contains("美元") || text.localizedCaseInsensitiveContains("USD") || text.localizedCaseInsensitiveContains("dollar") || text.contains("$") { return "USD" }
        if text.contains("日元") || text.localizedCaseInsensitiveContains("JPY") { return "JPY" }
        if text.contains("欧元") || text.localizedCaseInsensitiveContains("EUR") { return "EUR" }
        if text.contains("人民币") || text.localizedCaseInsensitiveContains("CNY") || text.contains("元") || text.contains("块") { return "CNY" }
        return nil
    }
    private func normalizedCurrency(_ value: String) -> String { if value.localizedCaseInsensitiveContains("USD") || value.localizedCaseInsensitiveContains("dollar") || value == "美元" { return "USD" }; if value.localizedCaseInsensitiveContains("JPY") || value == "日元" { return "JPY" }; if value.localizedCaseInsensitiveContains("EUR") || value == "欧元" { return "EUR" }; return "CNY" }

    private func merchant(in text: String) -> String? { ["沃尔玛", "Walmart", "Costco", "Target", "Amazon", "亚马逊", "Starbucks"].first(where: { text.localizedCaseInsensitiveContains($0) }) }
    private func payment(in text: String) -> String? { ["美国银行", "Bank of America", "Visa", "现金", "支付宝", "微信", "信用卡"].first(where: { text.localizedCaseInsensitiveContains($0) }) }

    private func date(in text: String) -> Date? {
        if let hours = capturedCount(in: text, pattern: #"([\d零〇一二两三四五六七八九十百千万]+)\s*小时后"#) { return calendar.date(byAdding: .hour, value: hours, to: now()) }
        if let minutes = capturedCount(in: text, pattern: #"([\d零〇一二两三四五六七八九十百千万]+)\s*分钟后"#) { return calendar.date(byAdding: .minute, value: minutes, to: now()) }
        var value = dateRange(in: text)?.0
        if value == nil, let weekday = weekday(in: text) { let current = calendar.component(.weekday, from: now()); var delta = (weekday - current + 7) % 7; if text.contains("下周") { delta += 7 }; value = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now())) }
        if value == nil, let yearText = capture(in: text, pattern: #"([零〇一二两三四五六七八九]{4})年([零〇一二两三四五六七八九十]+)月([零〇一二两三四五六七八九十]+)[日号]"#, group: 0) { let parts = yearText.split(whereSeparator: { "年月日号".contains($0) }).map { chineseNumber(String($0)) }; if parts.count == 3 { value = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) } }
        if value == nil, text.range(of: #"(?:早上|上午|中午|下午|晚上)?\s*(?:\d{1,2}|[一二两三四五六七八九十]+)(?:点|:)"#, options: .regularExpression) != nil { value = calendar.startOfDay(for: now()) }
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
        if module == .todo, let repeatHint = capture(in: text, pattern: #"(每周[一二三四五六日天])"#) { values.append(repeatHint) }
        return Array(values.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(3))
    }

    private func hasMoney(in text: String) -> Bool { !amountItems(in: text).isEmpty || ["美元", "dollar", "USD", "日元", "JPY", "欧元", "EUR", "人民币", "CNY", "$", "花了", "支付", "付款", "一共"].contains { text.localizedCaseInsensitiveContains($0) } }
    private func hasFutureTime(in text: String) -> Bool { text.range(of: #"今天晚些时候|今晚|明天|后天|每周[一二三四五六日天]|星期[一二三四五六日天]|周[一二三四五六日天]|下周|[\d零〇一二两三四五六七八九十百千万]+\s*(?:小时|分钟)后|(?:早上|上午|中午|下午|晚上)?\s*(?:\d{1,2}|[一二两三四五六七八九十]+)(?:点|:)"#, options: .regularExpression) != nil }
    private func hasAction(in text: String) -> Bool { ["去", "买", "吃", "提交", "打电话", "充电", "看", "开会", "预约", "做", "拿", "送", "检查", "打扫", "提醒", "完成"].contains(where: text.contains) }
    private func category(in text: String) -> String? { [("停车", "停车"), ("加油", "加油"), ("午饭", "餐饮"), ("咖啡", "餐饮"), ("Starbucks", "餐饮"), ("买菜", "食品"), ("牛奶", "食品"), ("显示器", "电子产品"), ("充电器", "电子产品"), ("iPhone", "电子产品"), ("买书", "书籍"), ("医疗", "医疗"), ("看牙", "医疗"), ("购物", "购物"), ("买", "购物")].first(where: { text.localizedCaseInsensitiveContains($0.0) })?.1 }
    private func dateRange(in text: String) -> (Date, Date)? { let weekday = weekday(in: text); let start: Date?; if let target = weekday { let current = calendar.component(.weekday, from: now()); var delta = (target - current + 7) % 7; if text.contains("下周") { delta += 7 }; start = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now())) } else if text.contains("下周") { start = calendar.date(byAdding: .weekOfYear, value: 1, to: calendar.dateInterval(of: .weekOfYear, for: now())!.start) } else if text.contains("本周") { start = calendar.dateInterval(of: .weekOfYear, for: now())?.start } else if text.contains("昨天") { start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now())) } else if text.contains("后天") { start = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now())) } else if text.contains("明天") { start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now())) } else if text.contains("今天") || text.contains("今晚") { start = calendar.startOfDay(for: now()) } else if text.contains("本月") || text.contains("这个月") { start = calendar.date(from: calendar.dateComponents([.year, .month], from: now())) } else if text.contains("下个月") { start = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: now()))!) } else { start = nil }; guard let start else { return nil }; let component: Calendar.Component = weekday != nil ? .day : text.contains("周") ? .weekOfYear : (text.contains("月") && !text.contains("明天")) ? .month : .day; return (start, calendar.date(byAdding: component, value: 1, to: start)!) }
    private func weekday(in text: String) -> Int? { let names = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1]; return names.first(where: { text.range(of: "(?:星期|周|下周)\($0.key)", options: .regularExpression) != nil })?.value }
    private func capture(in text: String, pattern: String, group: Int = 1) -> String? { guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }; return String(text[range]) }
    private func capturedNumber(in text: String, pattern: String) -> Decimal? { guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }; for index in 1..<match.numberOfRanges { if let range = Range(match.range(at: index), in: text), let value = Decimal(string: String(text[range]), locale: Locale(identifier: "en_US_POSIX")) { return value } }; return nil }
    private func capturedCount(in text: String, pattern: String) -> Int? { capture(in: text, pattern: pattern).map { Int($0) ?? chineseNumber($0) } }
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
        value.ownerID = ownerID
        if let index = records.firstIndex(where: { $0.id == value.id && $0.ownerID == ownerID }) {
            value.createdAt = records[index].createdAt
            value = normalizeForModule(value); value.updatedAt = records[index].updatedAt
            guard value != records[index] else { return records[index] }
            value.updatedAt = Date(); records[index] = value
        } else { value = normalizeForModule(value); value.updatedAt = value.createdAt; records.append(value) }
        try store.save(records)
        return value
    }

    private func normalizeForModule(_ record: Record) -> Record {
        var value = record
        switch value.module {
        case .ledger:
            if value.amountItems.isEmpty, let amount = value.amount { value.amountItems = [AmountItem(value: amount, currency: value.currency)] }
            if value.amountItems.count == 1 { value.amount = value.amountItems[0].value; value.currency = value.amountItems[0].currency }
            if value.amountItems.count > 1 { value.amount = nil; value.currency = nil }
            value.dueAt = nil; value.reminderEnabled = false; value.status = nil
        case .todo:
            value.merchant = nil; value.amount = nil; value.currency = nil; value.amountItems = []; value.category = nil
            value.paymentMethod = nil; value.occurredAt = nil; value.status = value.status ?? .pending
        case .memo:
            value.merchant = nil; value.amount = nil; value.currency = nil; value.amountItems = []; value.category = nil
            value.paymentMethod = nil; value.occurredAt = nil; value.dueAt = nil; value.location = nil; value.status = nil
        case .idea:
            value.merchant = nil; value.amount = nil; value.currency = nil; value.amountItems = []; value.category = nil
            value.paymentMethod = nil; value.occurredAt = nil; value.dueAt = nil
            value.reminderEnabled = false; value.location = nil; value.status = nil
        }
        return value
    }

    public func records(module: Module? = nil) throws -> [Record] {
        guard let ownerID = identity.confirmedUserID else { return [] }
        return try store.load().filter { $0.ownerID == ownerID && (module == nil || $0.module == module) }.sorted { ($0.occurredAt ?? $0.createdAt) > ($1.occurredAt ?? $1.createdAt) }
    }

    public func search(_ query: RecordQuery) throws -> [Record] {
        try records().filter { record in
            let amountFields = record.amountItems.flatMap { [String(describing: $0.value), $0.currency].compactMap { $0 } }
            let fields = [record.merchant, record.currency, record.category, record.paymentMethod, record.location, record.amount.map(String.init(describing:))].compactMap { $0 } + amountFields
            let haystack = ([record.content, record.rawInput] + record.tags + fields).joined(separator: " ")
            let comparableAmounts = record.amountItems.filter { query.currency == nil || $0.currency == query.currency }.map(\.value)
            return query.modules.contains(record.module)
                && (!query.importantOnly || record.important)
                && (query.keyword.isEmpty || haystack.localizedCaseInsensitiveContains(query.keyword))
                && query.tags.allSatisfy { record.tags.contains($0) }
                && (query.category == nil || record.category == query.category || record.tags.contains(query.category!))
                && (query.currency == nil || !comparableAmounts.isEmpty)
                && (query.minimumAmount == nil || comparableAmounts.contains { query.minimumInclusive ? $0 >= query.minimumAmount! : $0 > query.minimumAmount! })
                && (query.maximumAmount == nil || comparableAmounts.contains { query.maximumInclusive ? $0 <= query.maximumAmount! : $0 < query.maximumAmount! })
                && (query.dateStart == nil || ((record.occurredAt ?? record.dueAt ?? record.createdAt) >= query.dateStart!))
                && (query.dateEnd == nil || ((record.occurredAt ?? record.dueAt ?? record.createdAt) < query.dateEnd!))
        }
    }

    public static func numericTotals(in records: [Record]) -> [String: Decimal] {
        records.filter { $0.module == .ledger }.reduce(into: [:]) { totals, record in
            for item in record.amountItems { totals[item.currency ?? "未标币种", default: 0] += item.value }
        }
    }
}
