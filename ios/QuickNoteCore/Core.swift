import Foundation
import Compression

public enum Module: String, Codable, CaseIterable, Identifiable, Sendable {
    case ledger, todo, memo, idea
    public var id: Self { self }
    public var title: String { ["ledger": "账目", "todo": "待办", "memo": "备忘", "idea": "灵感"][rawValue]! }
}

public enum TodoStatus: String, Codable, CaseIterable, Sendable { case pending = "待处理", done = "已完成" }

public enum IdentityProvider: String, Codable, CaseIterable, Sendable { case apple, google, x, facebook }

public struct IdentityUser: Codable, Hashable, Sendable {
    public var id: String
    public var provider: IdentityProvider
    public var providerSubject: String
    public var displayName: String
    public var email: String?
    public var createdAt: Date
    public init(id: String, provider: IdentityProvider, providerSubject: String, displayName: String, email: String? = nil, createdAt: Date = Date()) { self.id = id; self.provider = provider; self.providerSubject = providerSubject; self.displayName = displayName; self.email = email; self.createdAt = createdAt }
}

public protocol AuthProvider: Sendable {
    var providerID: IdentityProvider { get }
    var displayName: String { get }
    func signIn(account: Int) async throws -> IdentityUser
}

public struct MockAuthProvider: AuthProvider {
    public let providerID: IdentityProvider
    public var displayName: String { providerID == .x ? "X" : providerID.rawValue.capitalized }
    public init(_ providerID: IdentityProvider) { self.providerID = providerID }
    public func signIn(account: Int) async throws -> IdentityUser {
        let slot = account == 2 ? 2 : 1
        let ids: [IdentityProvider: [String]] = [
            .apple: ["00000000-0000-4000-8000-000000000101", "00000000-0000-4000-8000-000000000102"],
            .google: ["00000000-0000-4000-8000-000000000201", "00000000-0000-4000-8000-000000000202"],
            .x: ["00000000-0000-4000-8000-000000000301", "00000000-0000-4000-8000-000000000302"],
            .facebook: ["00000000-0000-4000-8000-000000000401", "00000000-0000-4000-8000-000000000402"]
        ]
        return IdentityUser(id: ids[providerID]![slot - 1], provider: providerID, providerSubject: "mock-\(providerID.rawValue)-user-00\(slot)", displayName: "Test User \(slot)", email: "test\(slot)@example.invalid", createdAt: Date(timeIntervalSince1970: 0))
    }
}

public enum CurrencyCanonicalizer {
    public static let aliasPattern = #"US\s*dollars?|US\$|dollars?|bucks?|USD|美元|美金|\$|JPY|日元|円|yen|EUR|欧元|euros?|欧|€|CNY|RMB|人民币|yuan|元|块|¥|￥|GBP|英镑|pounds?|£"#
    public static func recognized(_ value: String) -> String? { guard let regex = try? NSRegularExpression(pattern: #"^(?:\#(aliasPattern))$"#, options: .caseInsensitive), regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil else { return nil }; return canonical(value) }
    public static func canonical(_ value: String?) -> String? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let upper = raw.uppercased()
        if ["USD", "$", "US$", "US DOLLAR", "US DOLLARS", "美元", "美金", "DOLLAR", "DOLLARS", "BUCK", "BUCKS"].contains(upper) { return "USD" }
        if ["JPY", "日元", "円", "YEN"].contains(upper) { return "JPY" }
        if ["EUR", "欧元", "欧", "EURO", "EUROS", "€"].contains(upper) { return "EUR" }
        if ["CNY", "RMB", "人民币", "YUAN", "元", "块", "¥", "￥"].contains(upper) { return "CNY" }
        if ["GBP", "英镑", "POUND", "POUNDS", "£"].contains(upper) { return "GBP" }
        return upper
    }
    public static func displayName(_ value: String?, languageCode: String) -> String? {
        guard let code = canonical(value) else { return nil }
        guard languageCode.lowercased().hasPrefix("zh") else { return code }
        return ["USD": "美元", "JPY": "日元", "EUR": "欧元", "CNY": "人民币", "GBP": "英镑"][code] ?? code
    }
}

public struct AmountItem: Codable, Hashable, Sendable {
    public var value: Decimal
    public var currency: String?
    public init(value: Decimal, currency: String? = nil) { self.value = value; self.currency = CurrencyCanonicalizer.canonical(currency) }
    private enum CodingKeys: String, CodingKey { case value, currency }
    public init(from decoder: Decoder) throws { let box = try decoder.container(keyedBy: CodingKeys.self); value = try box.decode(Decimal.self, forKey: .value); currency = CurrencyCanonicalizer.canonical(try box.decodeIfPresent(String.self, forKey: .currency)) }
}

public enum ReminderState: String, Codable, Sendable { case none, requested, active, permissionDenied, missingExternalReminder }

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
    public var reminderLinked: Bool
    public var reminderExternalID: String?
    public var reminderState: ReminderState
    public var location: String?
    public var status: TodoStatus?

    public init(id: UUID = UUID(), ownerID: String = "", module: Module, rawInput: String, content: String? = nil,
                important: Bool = false, tags: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date(),
                merchant: String? = nil, amount: Decimal? = nil, currency: String? = nil, amountItems: [AmountItem] = [], category: String? = nil,
                paymentMethod: String? = nil, occurredAt: Date? = nil, dueAt: Date? = nil,
                reminderEnabled: Bool = false, reminderLinked: Bool = false, reminderExternalID: String? = nil, reminderState: ReminderState? = nil, location: String? = nil, status: TodoStatus? = nil) {
        self.id = id; self.ownerID = ownerID; self.module = module; self.rawInput = rawInput
        self.content = content ?? rawInput; self.important = important; self.tags = tags
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.merchant = merchant; self.amount = amount
        self.currency = CurrencyCanonicalizer.canonical(currency); self.amountItems = amountItems.isEmpty ? amount.map { [AmountItem(value: $0, currency: currency)] } ?? [] : amountItems.map { AmountItem(value: $0.value, currency: $0.currency) }; self.category = category; self.paymentMethod = paymentMethod
        self.occurredAt = occurredAt; self.dueAt = dueAt; self.reminderEnabled = reminderEnabled; self.reminderLinked = reminderLinked; self.reminderExternalID = reminderExternalID; self.reminderState = reminderState ?? (reminderLinked ? .active : reminderEnabled ? .requested : .none)
        self.location = location; self.status = status
    }

    private enum CodingKeys: String, CodingKey { case id, ownerID, module, rawInput, content, important, tags, createdAt, updatedAt, merchant, amount, currency, amountItems, category, paymentMethod, occurredAt, dueAt, reminderEnabled, reminderLinked, reminderExternalID, reminderState, location, status }
    public init(from decoder: Decoder) throws { let box = try decoder.container(keyedBy: CodingKeys.self); let legacyAmount = try box.decodeIfPresent(Decimal.self, forKey: .amount), legacyCurrency = CurrencyCanonicalizer.canonical(try box.decodeIfPresent(String.self, forKey: .currency)); id = try box.decode(UUID.self, forKey: .id); ownerID = try box.decode(String.self, forKey: .ownerID); module = try box.decode(Module.self, forKey: .module); rawInput = try box.decode(String.self, forKey: .rawInput); content = try box.decode(String.self, forKey: .content); important = try box.decode(Bool.self, forKey: .important); tags = try box.decode([String].self, forKey: .tags); createdAt = try box.decode(Date.self, forKey: .createdAt); updatedAt = try box.decode(Date.self, forKey: .updatedAt); merchant = try box.decodeIfPresent(String.self, forKey: .merchant); amount = legacyAmount; currency = legacyCurrency; amountItems = try box.decodeIfPresent([AmountItem].self, forKey: .amountItems) ?? legacyAmount.map { [AmountItem(value: $0, currency: legacyCurrency)] } ?? []; category = try box.decodeIfPresent(String.self, forKey: .category); paymentMethod = try box.decodeIfPresent(String.self, forKey: .paymentMethod); occurredAt = try box.decodeIfPresent(Date.self, forKey: .occurredAt); dueAt = try box.decodeIfPresent(Date.self, forKey: .dueAt); reminderEnabled = try box.decode(Bool.self, forKey: .reminderEnabled); reminderLinked = try box.decodeIfPresent(Bool.self, forKey: .reminderLinked) ?? false; reminderExternalID = try box.decodeIfPresent(String.self, forKey: .reminderExternalID); reminderState = try box.decodeIfPresent(ReminderState.self, forKey: .reminderState) ?? (reminderLinked ? .active : reminderEnabled ? .requested : .none); location = try box.decodeIfPresent(String.self, forKey: .location); status = try box.decodeIfPresent(TodoStatus.self, forKey: .status) }
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
    public var effectiveCurrency: String? { CurrencyCanonicalizer.canonical(currency) ?? CurrencyCanonicalizer.recognized(keyword.trimmingCharacters(in: .whitespacesAndNewlines)) }
    public init(keyword: String = "", modules: Set<Module> = Set(Module.allCases), importantOnly: Bool = false, tags: [String] = [], dateStart: Date? = nil, dateEnd: Date? = nil, minimumAmount: Decimal? = nil, minimumInclusive: Bool = false, maximumAmount: Decimal? = nil, maximumInclusive: Bool = false, currency: String? = nil, category: String? = nil) {
        self.keyword = keyword; self.modules = modules; self.importantOnly = importantOnly; self.tags = tags; self.dateStart = dateStart; self.dateEnd = dateEnd; self.minimumAmount = minimumAmount; self.minimumInclusive = minimumInclusive; self.maximumAmount = maximumAmount; self.maximumInclusive = maximumInclusive; self.currency = currency; self.category = category
    }
}

public enum Pagination {
    public static func page<T>(_ values: [T], index: Int, size: Int = 10) -> [T] { guard size > 0 else { return [] }; let start = max(0, min(index, max(0, (values.count - 1) / size))) * size; return Array(values.dropFirst(start).prefix(size)) }
    public static func pageCount(itemCount: Int, size: Int = 10) -> Int { max(1, Int(ceil(Double(itemCount) / Double(max(1, size))))) }
    public static func clampedPage(_ index: Int, itemCount: Int, size: Int = 10) -> Int { min(max(0, index), pageCount(itemCount: itemCount, size: size) - 1) }
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
        if text.hasPrefix("找") || text.hasPrefix("搜索") || text.hasPrefix("查询") || ["search", "find", "show"].contains(where: { text.lowercased().hasPrefix($0) }) { return .search(query(text)) }
        return .create(draft(text))
    }

    public func parseSegments(_ input: String) -> [Record] {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let split = #"\s+(?:and\s+)?(?=remind\s+me\b|note\s+that\b)"#
        guard let regex = try? NSRegularExpression(pattern: split, options: .caseInsensitive) else { return [draft(text)] }
        let range = NSRange(text.startIndex..., in: text), cuts = regex.matches(in: text, range: range).compactMap { Range($0.range, in: text) }
        guard !cuts.isEmpty else { return [draft(text)] }
        var parts: [String] = [], start = text.startIndex
        for cut in cuts { parts.append(String(text[start..<cut.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)); start = cut.upperBound }
        parts.append(String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        return parts.filter { !$0.isEmpty }.map(draft)
    }

    private func query(_ text: String) -> RecordQuery {
        let text = text.replacingOccurrences(of: "代办", with: "待办")
        var named = Set(Module.allCases.filter { text.contains($0.title) })
        let lower = text.lowercased(), aliases: [(Module, [String])] = [(.ledger, ["ledger", "expense", "expenses"]), (.todo, ["todo", "todos", "task", "tasks"]), (.memo, ["memo", "memos", "note", "notes"]), (.idea, ["idea", "ideas"])]
        aliases.filter { pair in pair.1.contains { lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil } }.forEach { named.insert($0.0) }
        let range = dateRange(in: text), category = category(in: text)
        let strictMinimum = capturedNumber(in: text, pattern: #"(?:超过|大于|over|above|more\s+than)\s*(\d+(?:\.\d+)?)"#)
        let inclusiveMinimum = capturedNumber(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:美元|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)?\s*以上"#)
        let strictMaximum = capturedNumber(in: text, pattern: #"(?:少于|小于|under|below|less\s+than)\s*(\d+(?:\.\d+)?)"#)
        let inclusiveMaximum = capturedNumber(in: text, pattern: #"(\d+(?:\.\d+)?)\s*(?:美元|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)?\s*以下"#)
        var keyword = text.replacingOccurrences(of: #"(?:今天|昨天|明天|后天|本月|这个月|下个月|本周|下周[一二三四五六日天]?|星期[一二三四五六日天]|周[一二三四五六日天]|[\d零〇一二两三四五六七八九十百千万]+\s*(?:小时|分钟)后)"#, with: "", options: .regularExpression)
        keyword = keyword.replacingOccurrences(of: #"(?:金额)?(?:(?:超过|大于|少于|小于)\s*\d+(?:\.\d+)?|\d+(?:\.\d+)?\s*(?:美元|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)?\s*(?:以上|以下))\s*(?:美元|USD|日元|JPY|欧元|EUR|人民币|CNY|元|块)?"#, with: "", options: [.regularExpression, .caseInsensitive])
        ["搜索", "查询", "找", "所有", "全部", "重要的", "重要", "记录", "里面", "里的", "里", "和", "的", "金额"].forEach { keyword = keyword.replacingOccurrences(of: $0, with: "") }
        Module.allCases.forEach { keyword = keyword.replacingOccurrences(of: $0.title, with: "") }
        keyword = keyword.replacingOccurrences(of: #"\b(?:search|find|show|all|important|records?|about|ledger|expenses?|todos?|tasks?|memos?|notes?|ideas?|today|yesterday|this\s+week|this\s+month)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
        keyword = keyword.replacingOccurrences(of: #"\b(?:over|above|more\s+than|under|below|less\s+than)\s*\d+(?:\.\d+)?\s*(?:USD|dollars?|\$|JPY|yen|EUR|euros?|CNY|RMB)?"#, with: "", options: [.regularExpression, .caseInsensitive])
        keyword = keyword.replacingOccurrences(of: CurrencyCanonicalizer.aliasPattern, with: "", options: [.regularExpression, .caseInsensitive])
        if let category { keyword = keyword.replacingOccurrences(of: category, with: "") }
        return RecordQuery(keyword: keyword.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "), modules: named.isEmpty ? Set(Module.allCases) : named, importantOnly: text.contains("重要") || lower.contains("important"), dateStart: range?.0, dateEnd: range?.1, minimumAmount: strictMinimum ?? inclusiveMinimum, minimumInclusive: inclusiveMinimum != nil, maximumAmount: strictMaximum ?? inclusiveMaximum, maximumInclusive: inclusiveMaximum != nil, currency: currency(in: text), category: category)
    }

    private func draft(_ text: String) -> Record {
        if hasMoney(in: text) {
            let items = amountItems(in: text), single = items.count == 1 ? items.first : nil
            return Record(module: .ledger, rawInput: text, tags: tags(text, module: .ledger), merchant: merchant(in: text), amount: single?.value, currency: single?.currency, amountItems: items, category: category(in: text), paymentMethod: payment(in: text), occurredAt: date(in: text))
        }
        if text.contains("提醒") || text.contains("待办") || text.localizedCaseInsensitiveContains("remind me") || (hasFutureTime(in: text) && (hasAction(in: text) || ["breakfast", "dentist", "appointment"].contains(where: { text.localizedCaseInsensitiveContains($0) }))) || text.contains("别忘了") {
            return Record(module: .todo, rawInput: text, tags: tags(text, module: .todo), dueAt: date(in: text), reminderEnabled: text.contains("提醒") || text.localizedCaseInsensitiveContains("remind me"), status: .pending)
        }
        if ["方案", "想法", "改进", "可以", "以后", "也许", "灵感"].contains(where: text.contains) || ["idea", "maybe", "I have an idea"].contains(where: { text.localizedCaseInsensitiveContains($0) }) || (text.contains("如果") && text.contains("就")) {
            return Record(module: .idea, rawInput: text, tags: tags(text, module: .idea))
        }
        return Record(module: .memo, rawInput: text, tags: tags(text, module: .memo))
    }

    private func amountItems(in text: String) -> [AmountItem] {
        let text = normalizedEnglishNumbers(text)
        let alias = CurrencyCanonicalizer.aliasPattern, number = #"\d+(?:\.\d+)?"#, whole = NSRange(text.startIndex..., in: text)
        let totalPattern = #"(?:一共|总共|合计|共|总价|total)\s*[:：]?\s*(\#(number))\s*(\#(alias))"#
        if let regex = try? NSRegularExpression(pattern: totalPattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: whole), let valueRange = Range(match.range(at: 1), in: text), let unitRange = Range(match.range(at: 2), in: text), let value = Decimal(string: String(text[valueRange]), locale: Locale(identifier: "en_US_POSIX")) { return [AmountItem(value: value, currency: normalizedCurrency(String(text[unitRange])))] }
        var matches: [(NSRange, AmountItem)] = []
        for (pattern, valueGroup, unitGroup) in [(#"(\#(alias))\s*(\#(number))"#, 2, 1), (#"(\#(number))\s*(\#(alias))"#, 1, 2)] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: text, range: whole) {
                guard let fullRange = Range(match.range, in: text), let valueRange = Range(match.range(at: valueGroup), in: text), let unitRange = Range(match.range(at: unitGroup), in: text), let value = Decimal(string: String(text[valueRange]), locale: Locale(identifier: "en_US_POSIX")) else { continue }
                let prefix = String(text[..<fullRange.lowerBound].suffix(12))
                if prefix.range(of: #"(?:每盒|每个|每件|每瓶|每台|每本|每份|每箱|单价|each|per)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
                matches.append((match.range, AmountItem(value: value, currency: normalizedCurrency(String(text[unitRange])))))
            }
        }
        var used: [NSRange] = []
        let items = matches.sorted { $0.0.location < $1.0.location }.compactMap { range, item -> AmountItem? in
            guard !used.contains(where: { NSIntersectionRange($0, range).length > 0 }) else { return nil }
            used.append(range); return item
        }
        if !items.isEmpty { return items }
        if let value = capture(in: text, pattern: #"([零〇一二两三四五六七八九十百千万]+)\s*(美元|日元|欧元|人民币|元|块)"#), let unit = capture(in: text, pattern: #"[零〇一二两三四五六七八九十百千万]+\s*(美元|日元|欧元|人民币|元|块)"#) { return [AmountItem(value: Decimal(chineseNumber(value)), currency: normalizedCurrency(unit))] }
        if let unit = capture(in: text, pattern: #"(美元|日元|欧元|人民币)\s*[零〇一二两三四五六七八九十百千万]+"#), let value = capture(in: text, pattern: #"(?:美元|日元|欧元|人民币)\s*([零〇一二两三四五六七八九十百千万]+)"#) { return [AmountItem(value: Decimal(chineseNumber(value)), currency: normalizedCurrency(unit))] }
        return []
    }

    private func currency(in text: String) -> String? { guard let regex = try? NSRegularExpression(pattern: CurrencyCanonicalizer.aliasPattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range, in: text) else { return nil }; return CurrencyCanonicalizer.canonical(String(text[range])) }
    private func normalizedCurrency(_ value: String) -> String { CurrencyCanonicalizer.canonical(value) ?? value.uppercased() }

    private func merchant(in text: String) -> String? { ["沃尔玛", "Walmart", "Costco", "Target", "Amazon", "亚马逊", "Starbucks"].first(where: { text.localizedCaseInsensitiveContains($0) }) }
    private func payment(in text: String) -> String? { ["美国银行", "Bank of America", "Visa", "现金", "支付宝", "微信", "信用卡"].first(where: { text.localizedCaseInsensitiveContains($0) }) }

    private func date(in text: String) -> Date? {
        let text = normalizedEnglishNumbers(text)
        if let hours = capturedCount(in: text, pattern: #"([\d零〇一二两三四五六七八九十百千万]+)\s*小时后"#) { return calendar.date(byAdding: .hour, value: hours, to: now()) }
        if let minutes = capturedCount(in: text, pattern: #"([\d零〇一二两三四五六七八九十百千万]+)\s*分钟后"#) { return calendar.date(byAdding: .minute, value: minutes, to: now()) }
        if let count = capture(in: text, pattern: #"\bin\s+(\d+|one|two)\s+(hours?|minutes?)\b"#), let unit = capture(in: text, pattern: #"\bin\s+(?:\d+|one|two)\s+(hours?|minutes?)\b"#) { let value = Int(count) ?? (count.lowercased() == "two" ? 2 : 1); return calendar.date(byAdding: unit.lowercased().hasPrefix("hour") ? .hour : .minute, value: value, to: now()) }
        var value = dateRange(in: text)?.0
        if value == nil, let weekday = weekday(in: text) { let current = calendar.component(.weekday, from: now()); var delta = (weekday - current + 7) % 7; if text.contains("下周") { delta += 7 } else if text.localizedCaseInsensitiveContains("next "), delta == 0 { delta = 7 }; value = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now())) }
        if value == nil, let yearText = capture(in: text, pattern: #"([零〇一二两三四五六七八九]{4})年([零〇一二两三四五六七八九十]+)月([零〇一二两三四五六七八九十]+)[日号]"#, group: 0) { let parts = yearText.split(whereSeparator: { "年月日号".contains($0) }).map { chineseNumber(String($0)) }; if parts.count == 3 { value = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) } }
        let hasExplicitDate = dateRange(in: text) != nil || weekday(in: text) != nil
        if value == nil, text.range(of: #"(?:早上|上午|中午|下午|晚上)?\s*(?:\d{1,2}|[一二两三四五六七八九十]+)(?:点|:)|(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:AM|PM)|\b(?:morning|afternoon|evening|noon|midnight)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { value = calendar.startOfDay(for: now()) }
        guard var value else { return nil }
        if let hourText = capture(in: text, pattern: #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(AM|PM)"#), let hour = Int(hourText) { let minute = Int(capture(in: text, pattern: #"(?:at\s+)?\d{1,2}:(\d{2})\s*(?:AM|PM)"#) ?? "0") ?? 0, marker = capture(in: text, pattern: #"(?:at\s+)?\d{1,2}(?::\d{2})?\s*(AM|PM)"#)?.uppercased(); let adjusted = marker == "PM" && hour < 12 ? hour + 12 : marker == "AM" && hour == 12 ? 0 : hour; value = calendar.date(bySettingHour: adjusted, minute: minute, second: 0, of: value) ?? value }
        else if let hour = [("midnight", 0), ("noon", 12), ("morning", 9), ("afternoon", 15), ("evening", 18), ("tonight", 20)].first(where: { text.localizedCaseInsensitiveContains($0.0) })?.1 { value = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: value) ?? value }
        if let expression = capture(in: text, pattern: #"((?:早上|上午|中午|下午|晚上|今晚)?\s*(?:\d{1,2}|[一二两三四五六七八九十]+)(?:点|:)\s*(?:半|\d{1,2})?)"#) { let digits = expression.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }; var hourText = expression; ["早上", "上午", "中午", "下午", "晚上", "今晚"].forEach { hourText = hourText.replacingOccurrences(of: $0, with: "") }; hourText = String(hourText.prefix { $0 != "点" && $0 != ":" }).trimmingCharacters(in: .whitespaces); let chineseHour = digits.first ?? chineseNumber(hourText); var hour = chineseHour; if (expression.contains("下午") || expression.contains("晚上") || expression.contains("今晚")) && hour < 12 { hour += 12 }; let minute = expression.contains("半") ? 30 : digits.dropFirst().first ?? 0; value = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: value) ?? value }
        if !hasExplicitDate, value <= now() { return calendar.date(byAdding: .day, value: 1, to: value) }
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

    private func hasMoney(in text: String) -> Bool { !amountItems(in: text).isEmpty || ["美元", "dollar", "buck", "USD", "日元", "yen", "JPY", "欧元", "euro", "EUR", "人民币", "yuan", "RMB", "CNY", "pound", "GBP", "$", "€", "£", "花了", "支付", "付款", "一共"].contains { text.localizedCaseInsensitiveContains($0) } }
    private func hasFutureTime(in text: String) -> Bool { text.range(of: #"今天晚些时候|今晚|明天|后天|每周[一二三四五六日天]|星期[一二三四五六日天]|周[一二三四五六日天]|下周|[\d零〇一二两三四五六七八九十百千万]+\s*(?:小时|分钟)后|(?:早上|上午|中午|下午|晚上)?\s*(?:\d{1,2}|[一二两三四五六七八九十]+)(?:点|:)|\b(?:today|tomorrow|tonight|weekend|morning|afternoon|evening|noon|midnight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|in\s+(?:\d+|one|two)\s+(?:hours?|minutes?)|at\s+\d{1,2}(?::\d{2})?\s*(?:AM|PM)?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
    private func hasAction(in text: String) -> Bool { ["去", "买", "吃", "提交", "打电话", "充电", "看", "开会", "预约", "做", "拿", "送", "检查", "打扫", "提醒", "完成", "remind me", "call", "buy", "go", "send", "submit", "finish", "pick up", "appointment", "dentist"].contains { text.localizedCaseInsensitiveContains($0) } }
    private func category(in text: String) -> String? { [("停车", "停车"), ("加油", "加油"), ("午饭", "餐饮"), ("咖啡", "餐饮"), ("Starbucks", "餐饮"), ("买菜", "食品"), ("牛奶", "食品"), ("显示器", "电子产品"), ("充电器", "电子产品"), ("iPhone", "电子产品"), ("买书", "书籍"), ("医疗", "医疗"), ("看牙", "医疗"), ("购物", "购物"), ("买", "购物")].first(where: { text.localizedCaseInsensitiveContains($0.0) })?.1 }
    private func dateRange(in text: String) -> (Date, Date)? {
        let lower = text.lowercased(), weekday = weekday(in: text), start: Date?
        if let target = weekday { let current = calendar.component(.weekday, from: now()); var delta = (target - current + 7) % 7; if text.contains("下周") { delta += 7 } else if lower.contains("next "), delta == 0 { delta = 7 }; start = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now())) }
        else if text.contains("下周") { start = calendar.dateInterval(of: .weekOfYear, for: now()).flatMap { calendar.date(byAdding: .weekOfYear, value: 1, to: $0.start) } }
        else if lower.contains("weekend") { let weekday = calendar.component(.weekday, from: now()); start = calendar.date(byAdding: .day, value: (7 - weekday + 7) % 7, to: calendar.startOfDay(for: now())) }
        else if text.contains("本周") || lower.contains("this week") { start = calendar.dateInterval(of: .weekOfYear, for: now())?.start }
        else if text.contains("昨天") || lower.contains("yesterday") { start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now())) }
        else if text.contains("后天") { start = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now())) }
        else if text.contains("明天") || lower.contains("tomorrow") { start = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now())) }
        else if text.contains("今天") || text.contains("今晚") || lower.contains("today") || lower.contains("tonight") { start = calendar.startOfDay(for: now()) }
        else if text.contains("本月") || text.contains("这个月") || lower.contains("this month") { start = calendar.date(from: calendar.dateComponents([.year, .month], from: now())) }
        else if text.contains("下个月") { start = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: now()))!) }
        else { start = nil }
        guard let start else { return nil }; let component: Calendar.Component = weekday != nil || lower.contains("weekend") ? .day : (text.contains("周") || lower.contains("week")) ? .weekOfYear : (text.contains("月") || lower.contains("month")) && !text.contains("明天") ? .month : .day; guard let end = calendar.date(byAdding: component, value: 1, to: start) else { return nil }; return (start, end)
    }
    private func weekday(in text: String) -> Int? { let english = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]; if let value = english.first(where: { text.localizedCaseInsensitiveContains($0.key) })?.value { return value }; let names = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1]; return names.first(where: { text.range(of: "(?:星期|周|下周)\($0.key)", options: .regularExpression) != nil })?.value }
    private func capture(in text: String, pattern: String, group: Int = 1) -> String? { guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }; return String(text[range]) }
    private func capturedNumber(in text: String, pattern: String) -> Decimal? { guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }; for index in 1..<match.numberOfRanges { if let range = Range(match.range(at: index), in: text), let value = Decimal(string: String(text[range]), locale: Locale(identifier: "en_US_POSIX")) { return value } }; return nil }
    private func capturedCount(in text: String, pattern: String) -> Int? { capture(in: text, pattern: pattern).map { Int($0) ?? chineseNumber($0) } }
    private func chineseNumber(_ text: String) -> Int { let digits: [Character: Int] = ["零":0,"〇":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]; if !text.contains(where: { "十百千万".contains($0) }) { return text.reduce(0) { $0 * 10 + (digits[$1] ?? 0) } }; var total = 0, section = 0, number = 0; for char in text { if let digit = digits[char] { number = digit } else { let unit = char == "十" ? 10 : char == "百" ? 100 : char == "千" ? 1000 : 10000; if unit == 10000 { section = (section + number) * unit; total += section; section = 0 } else { section += max(number, 1) * unit }; number = 0 } }; return total + section + number }
    private func normalizedEnglishNumbers(_ text: String) -> String {
        let units = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19]
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        guard let regex = try? NSRegularExpression(pattern: #"\b(twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[- ](one|two|three|four|five|six|seven|eight|nine))?\b|\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen)\b"#, options: .caseInsensitive) else { return text }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            func word(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { String(text[$0]).lowercased() } }
            let value = (word(1).flatMap { tens[$0] } ?? 0) + (word(2).flatMap { units[$0] } ?? 0) + (word(3).flatMap { units[$0] } ?? 0)
            result.replaceSubrange(range, with: String(value))
        }
        return result
    }
}
// Backup remains user-triggered and separate from identity; saving never triggers backup, upload, or sharing.

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
            value.currency = CurrencyCanonicalizer.canonical(value.currency)
            value.amountItems = value.amountItems.map { AmountItem(value: $0.value, currency: $0.currency) }
            if value.amountItems.isEmpty, let amount = value.amount { value.amountItems = [AmountItem(value: amount, currency: value.currency)] }
            if value.amountItems.count == 1 { value.amount = value.amountItems[0].value; value.currency = value.amountItems[0].currency }
            if value.amountItems.count > 1 { value.amount = nil; value.currency = nil }
            if !value.reminderEnabled { value.dueAt = nil }; value.status = nil
        case .todo:
            value.merchant = nil; value.amount = nil; value.currency = nil; value.amountItems = []; value.category = nil
            value.paymentMethod = nil; value.occurredAt = nil; value.status = value.status ?? .pending
            if !value.reminderEnabled { value.reminderLinked = false; value.reminderExternalID = nil; value.reminderState = .none }
        case .memo:
            value.merchant = nil; value.amount = nil; value.currency = nil; value.amountItems = []; value.category = nil
            value.paymentMethod = nil; value.occurredAt = nil; if !value.reminderEnabled { value.dueAt = nil }; value.location = nil; value.status = nil
        case .idea:
            value.merchant = nil; value.amount = nil; value.currency = nil; value.amountItems = []; value.category = nil
            value.paymentMethod = nil; value.occurredAt = nil; if !value.reminderEnabled { value.dueAt = nil }; value.location = nil; value.status = nil
        }
        if !value.reminderEnabled { value.reminderLinked = false; value.reminderExternalID = nil; value.reminderState = .none }
        return value
    }

    public func records(module: Module? = nil) throws -> [Record] {
        guard let ownerID = identity.confirmedUserID else { return [] }
        return try store.load().filter { $0.ownerID == ownerID && (module == nil || $0.module == module) }.sorted { ($0.occurredAt ?? $0.createdAt) > ($1.occurredAt ?? $1.createdAt) }
    }

    public func search(_ query: RecordQuery) throws -> [Record] { Self.search(query, in: try records()) }

    public static func search(_ query: RecordQuery, in records: [Record]) -> [Record] {
        let queryCurrency = query.effectiveCurrency
        return records.filter { record in
            let amountFields = record.amountItems.flatMap { [String(describing: $0.value), $0.currency].compactMap { $0 } }
            let fields = [record.merchant, record.currency, record.category, record.paymentMethod, record.location, record.amount.map(String.init(describing:))].compactMap { $0 } + amountFields
            let haystack = ([record.content, record.rawInput] + record.tags + fields).joined(separator: " ")
            let comparableAmounts = record.amountItems.filter { queryCurrency == nil || CurrencyCanonicalizer.canonical($0.currency) == queryCurrency }.map(\.value)
            return query.modules.contains(record.module)
                && (!query.importantOnly || record.important)
                && (query.keyword.isEmpty || CurrencyCanonicalizer.recognized(query.keyword.trimmingCharacters(in: .whitespacesAndNewlines)) != nil || haystack.localizedCaseInsensitiveContains(query.keyword))
                && query.tags.allSatisfy { record.tags.contains($0) }
                && (query.category == nil || record.category == query.category || record.tags.contains(query.category!))
                && (queryCurrency == nil || !comparableAmounts.isEmpty)
                && (query.minimumAmount == nil || comparableAmounts.contains { query.minimumInclusive ? $0 >= query.minimumAmount! : $0 > query.minimumAmount! })
                && (query.maximumAmount == nil || comparableAmounts.contains { query.maximumInclusive ? $0 <= query.maximumAmount! : $0 < query.maximumAmount! })
                && (query.dateStart == nil || ((record.occurredAt ?? record.dueAt ?? record.createdAt) >= query.dateStart!))
                && (query.dateEnd == nil || ((record.occurredAt ?? record.dueAt ?? record.createdAt) < query.dateEnd!))
        }
    }

    public static func numericTotals(in records: [Record], currency: String? = nil) -> [String: Decimal] {
        let selected = CurrencyCanonicalizer.canonical(currency)
        return records.filter { $0.module == .ledger }.reduce(into: [:]) { totals, record in
            for item in record.amountItems { let code = CurrencyCanonicalizer.canonical(item.currency) ?? "未标币种"; if selected == nil || selected == code { totals[code, default: 0] += item.value } }
        }
    }

    public func replaceCurrentOwnerRecords(with restored: [Record]) throws {
        guard let ownerID = identity.confirmedUserID else { throw CoreError.identityRequired }
        var all = try store.load().filter { $0.ownerID != ownerID }
        all += restored.map { var value = $0; value.ownerID = ownerID; return normalizeForModule(value) }
        try store.save(all)
    }
}

public struct ExportManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var appVersion: String
    public var exportedAt: Date
    public var recordCount: Int
    public var userCount: Int
    public var attachmentCount: Int
}

public struct ExportMetadata: Codable, Equatable, Sendable {
    public var locale: String
    public var timezone: String
    public var currencyCanonicalizationVersion: Int
    public var modules: [String]
}

public struct BackupPayload: Equatable, Sendable {
    public var records: [Record]
    public var users: [IdentityUser]
    public var settings: [String: String]
}

public enum ArchiveError: Error, Equatable { case invalidArchive, unsupportedSchema }

public enum ZipArchive {
    public static func make(_ entries: [(String, Data)]) -> Data {
        var archive = Data(), central = Data()
        for (name, body) in entries {
            let filename = Data(name.utf8), crc = crc32(body), offset = UInt32(archive.count), size = UInt32(body.count)
            archive.appendLE(UInt32(0x04034b50)); archive.appendLE(UInt16(20)); archive.appendLE(UInt16(0)); archive.appendLE(UInt16(0)); archive.appendLE(UInt16(0)); archive.appendLE(UInt16(0)); archive.appendLE(crc); archive.appendLE(size); archive.appendLE(size); archive.appendLE(UInt16(filename.count)); archive.appendLE(UInt16(0)); archive.append(filename); archive.append(body)
            central.appendLE(UInt32(0x02014b50)); central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(crc); central.appendLE(size); central.appendLE(size); central.appendLE(UInt16(filename.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0)); central.appendLE(offset); central.append(filename)
        }
        let centralOffset = UInt32(archive.count); archive.append(central); archive.appendLE(UInt32(0x06054b50)); archive.appendLE(UInt16(0)); archive.appendLE(UInt16(0)); archive.appendLE(UInt16(entries.count)); archive.appendLE(UInt16(entries.count)); archive.appendLE(UInt32(central.count)); archive.appendLE(centralOffset); archive.appendLE(UInt16(0)); return archive
    }

    public static func entries(in archive: Data, requiredEntry: String? = "manifest.json") throws -> [String: Data] {
        var result: [String: Data] = [:], offset = 0
        while offset + 4 <= archive.count, archive.uint32(at: offset) == 0x04034b50 {
            guard offset + 30 <= archive.count else { throw ArchiveError.invalidArchive }
            let method = archive.uint16(at: offset + 8), crc = archive.uint32(at: offset + 14), compressedSize = Int(archive.uint32(at: offset + 18)), uncompressedSize = Int(archive.uint32(at: offset + 22)), nameLength = Int(archive.uint16(at: offset + 26)), extraLength = Int(archive.uint16(at: offset + 28)), nameStart = offset + 30, dataStart = nameStart + nameLength + extraLength, end = dataStart + compressedSize
            guard end <= archive.count, let name = String(data: archive[nameStart..<(nameStart + nameLength)], encoding: .utf8) else { throw ArchiveError.invalidArchive }
            let compressed = Data(archive[dataStart..<end]), body: Data; if method == 0 { body = compressed } else if method == 8 { body = try inflate(compressed, expectedSize: uncompressedSize) } else { throw ArchiveError.invalidArchive }; guard body.count == uncompressedSize, crc32(body) == crc else { throw ArchiveError.invalidArchive }
            result[name] = body; offset = end
        }
        if let requiredEntry, result[requiredEntry] == nil { throw ArchiveError.invalidArchive }
        return result
    }

    private static func crc32(_ data: Data) -> UInt32 { data.reduce(UInt32.max) { value, byte in var crc = value ^ UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xEDB88320 : 0) }; return crc } ^ UInt32.max }
    private static func inflate(_ data: Data, expectedSize: Int) throws -> Data { guard expectedSize >= 0, expectedSize <= 50_000_000 else { throw ArchiveError.invalidArchive }; var output = Data(count: expectedSize); let decoded = output.withUnsafeMutableBytes { destination in data.withUnsafeBytes { source in compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, expectedSize, source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB) } }; guard decoded == expectedSize else { throw ArchiveError.invalidArchive }; return output }
}

public enum ExportService {
    public static func makeExport(records: [Record], users: [IdentityUser], appVersion: String = "0.1", locale: String = Locale.current.identifier, timezone: String = TimeZone.current.identifier, exportedAt: Date = Date()) throws -> Data {
        try archive(records: records, users: users, settings: nil, appVersion: appVersion, locale: locale, timezone: timezone, exportedAt: exportedAt)
    }
    static func archive(records: [Record], users: [IdentityUser], settings: [String: String]?, appVersion: String, locale: String, timezone: String, exportedAt: Date) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = ExportManifest(schemaVersion: 1, appVersion: appVersion, exportedAt: exportedAt, recordCount: records.count, userCount: users.count, attachmentCount: 0)
        let metadata = ExportMetadata(locale: locale, timezone: timezone, currencyCanonicalizationVersion: 1, modules: Module.allCases.map(\.rawValue))
        var entries = [("manifest.json", try encoder.encode(manifest)), ("records.json", try encoder.encode(records)), ("users.json", try encoder.encode(users)), ("metadata.json", try encoder.encode(metadata)), ("attachments/", Data())]
        if let settings { entries.append(("settings.json", try encoder.encode(settings))) }
        return ZipArchive.make(entries)
    }
}

public enum BackupService {
    public static func makeBackup(records: [Record], users: [IdentityUser], settings: [String: String], appVersion: String = "0.1") throws -> Data { try ExportService.archive(records: records, users: users, settings: settings, appVersion: appVersion, locale: Locale.current.identifier, timezone: TimeZone.current.identifier, exportedAt: Date()) }
    public static func validateAndRead(_ archive: Data) throws -> BackupPayload {
        let entries = try ZipArchive.entries(in: archive); let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let manifestData = entries["manifest.json"], let recordsData = entries["records.json"], let usersData = entries["users.json"], let settingsData = entries["settings.json"] else { throw ArchiveError.invalidArchive }
        let manifest = try decoder.decode(ExportManifest.self, from: manifestData); guard manifest.schemaVersion == 1 else { throw ArchiveError.unsupportedSchema }
        let records = try decoder.decode([Record].self, from: recordsData), users = try decoder.decode([IdentityUser].self, from: usersData), settings = try decoder.decode([String: String].self, from: settingsData)
        guard manifest.recordCount == records.count, manifest.userCount == users.count else { throw ArchiveError.invalidArchive }
        return BackupPayload(records: records, users: users, settings: settings)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) } }
    func uint16(at offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func uint32(at offset: Int) -> UInt32 { UInt32(self[offset]) | UInt32(self[offset + 1]) << 8 | UInt32(self[offset + 2]) << 16 | UInt32(self[offset + 3]) << 24 }
}
