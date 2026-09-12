import SwiftUI

private enum AppTheme { static let accent = Color.indigo }

final class IdentitySession: IdentityGate, ObservableObject, @unchecked Sendable {
    @Published var confirmedUserID: String? { didSet { UserDefaults.standard.set(confirmedUserID, forKey: "confirmedUserID") } }
    init() { confirmedUserID = UserDefaults.standard.string(forKey: "confirmedUserID") }
    func confirm() { confirmedUserID = "local-\(UUID().uuidString)" }
}

@MainActor final class AppModel: ObservableObject {
    @Published var records: [Record] = []
    @Published var error: String?
    let identity = IdentitySession()
    let core: QuickNoteCore
    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        core = QuickNoteCore(store: FileRecordStore(url: folder.appendingPathComponent("records.json")), identity: identity)
        reload()
    }
    func reload() { do { records = try core.records() } catch { self.error = error.localizedDescription } }
    func save(_ record: Record) throws { _ = try core.save(record); reload() }
}

@main struct AIQuickNoteApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene { WindowGroup { RootView().environmentObject(model) } }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { ComposerView() }.tabItem { Label("记录", systemImage: "square.and.pencil") }
            NavigationStack { ModulesView() }.tabItem { Label("模块", systemImage: "square.grid.2x2") }
            NavigationStack { SearchView() }.tabItem { Label("搜索", systemImage: "magnifyingglass") }
        }.tint(AppTheme.accent)
    }
}

struct ComposerView: View {
    @AppStorage("lastModule") private var lastModule = Module.memo.rawValue
    @State private var text = ""
    @State private var draft: Record?
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("记下此刻").font(.largeTitle.bold())
            HStack {
                Button(action: {}) { Image(systemName: "mic") }.disabled(true).accessibilityLabel("语音，暂未开放")
                TextField("输入一条记录", text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
                Button { submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(action: {}) { Image(systemName: "plus") }.disabled(true).accessibilityLabel("附件，暂未开放")
            }.padding()
            Spacer()
        }
        .navigationTitle("AI 随手记")
        .navigationDestination(item: $draft) { ReviewView(draft: $0) { text = "" } }
    }
    private func submit() { draft = Record(module: Module(rawValue: lastModule) ?? .memo, rawInput: text) }
}

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastModule") private var lastModule = Module.memo.rawValue
    @State var draft: Record
    @State private var showIdentity = false
    let onSaved: () -> Void
    var body: some View {
        RecordForm(record: $draft, showRawInput: true)
            .navigationTitle("确认记录")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("确认保存") { save() } } }
            .sheet(isPresented: $showIdentity) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 56))
                        Text("首次保存需要确认身份").font(.title2.bold())
                        Text("仅用于确认本地数据归属，不会开启备份、上传或分享。").multilineTextAlignment(.center)
                        Button("确认本机身份并保存") { model.identity.confirm(); showIdentity = false; save() }.buttonStyle(.borderedProminent)
                    }.padding().navigationTitle("身份确认")
                }.presentationDetents([.medium])
            }
    }
    private func save() {
        do { try model.save(draft); lastModule = draft.module.rawValue; onSaved(); dismiss() }
        catch CoreError.identityRequired { showIdentity = true }
        catch { model.error = error.localizedDescription }
    }
}

struct ModulesView: View {
    var body: some View {
        List(Module.allCases) { module in NavigationLink(value: module) { Label(module.title, systemImage: module.icon) } }
            .navigationTitle("模块")
            .navigationDestination(for: Module.self) { ModuleListView(module: $0) }
    }
}

struct ModuleListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var adding = false
    let module: Module
    var body: some View {
        List(model.records.filter { $0.module == module }) { record in NavigationLink(value: record) { RecordRow(record: record) } }
            .navigationTitle(module.title)
            .toolbar { Button { adding = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $adding) { NavigationStack { ModuleComposerView(module: module) } }
            .navigationDestination(for: Record.self) { DetailView(record: $0) }
            .overlay { if model.records.allSatisfy({ $0.module != module }) { ContentUnavailableView("暂无记录", systemImage: module.icon) } }
            .onAppear { model.reload() }
    }
}

struct ModuleComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var draft: Record?
    let module: Module
    var body: some View {
        VStack {
            TextField("输入一条\(module.title)记录", text: $text, axis: .vertical).textFieldStyle(.roundedBorder).padding()
            Button("继续") { draft = Record(module: module, rawInput: text) }.buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .navigationTitle("新建\(module.title)")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .navigationDestination(item: $draft) { ReviewView(draft: $0) { dismiss() } }
    }
}

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyword = ""
    @State private var modules = Set(Module.allCases)
    @State private var importantOnly = false
    @State private var tags = ""
    private var results: [Record] { (try? model.core.search(RecordQuery(keyword: keyword, modules: modules, importantOnly: importantOnly, tags: tags.csv))) ?? [] }
    var body: some View {
        List {
            Section("查询条件") {
                ScrollView(.horizontal) { HStack { ForEach(Module.allCases) { module in Toggle(module.title, isOn: moduleBinding(module)).toggleStyle(.button) } } }
                Toggle("只看重要记录", isOn: $importantOnly)
                TextField("标签，用逗号分隔", text: $tags)
            }
            Section("结果 \(results.count)") { ForEach(results) { record in NavigationLink(value: record) { RecordRow(record: record) } } }
        }
        .navigationTitle("统一搜索").searchable(text: $keyword, prompt: "关键词")
        .navigationDestination(for: Record.self) { DetailView(record: $0) }
        .onAppear { model.reload() }
    }
    private func moduleBinding(_ module: Module) -> Binding<Bool> { Binding(get: { modules.contains(module) }, set: { enabled in if enabled { modules.insert(module) } else { modules.remove(module) } }) }
}

struct DetailView: View {
    @EnvironmentObject private var model: AppModel
    @State var record: Record
    var body: some View {
        RecordForm(record: $record, showRawInput: true)
            .navigationTitle("记录详情")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("保存") { try? model.save(record) } }
                ToolbarItem(placement: .bottomBar) { Button("分享") {}.disabled(true) }
                ToolbarItem(placement: .bottomBar) { Button("删除", role: .destructive) {}.disabled(true) }
            }
    }
}

struct RecordForm: View {
    @Binding var record: Record
    let showRawInput: Bool
    var body: some View {
        Form {
            Section("模块") { Picker("模块", selection: $record.module) { ForEach(Module.allCases) { Text($0.title).tag($0) } } }
            if showRawInput { Section("原始输入") { Text(record.rawInput).foregroundStyle(.secondary).textSelection(.enabled) } }
            Section("内容") {
                TextField("内容", text: $record.content, axis: .vertical)
                TextField("标签，用逗号分隔", text: Binding(get: { record.tags.joined(separator: ", ") }, set: { record.tags = $0.csv }))
                Toggle("重要", isOn: $record.important)
            }
            moduleFields
        }
    }
    @ViewBuilder private var moduleFields: some View {
        switch record.module {
        case .ledger:
            Section("账目字段") {
                optionalText("商家或对象", $record.merchant); decimalText("金额", $record.amount); optionalText("币种", $record.currency)
                optionalText("分类", $record.category); optionalText("支付方式", $record.paymentMethod); optionalText("地点", $record.location)
                DatePicker("发生时间", selection: optionalDate($record.occurredAt))
            }
        case .todo:
            Section("待办字段") {
                DatePicker("日期时间", selection: optionalDate($record.dueAt)); Toggle("提醒", isOn: $record.reminderEnabled)
                optionalText("地点", $record.location)
                Picker("状态", selection: Binding(get: { record.status ?? .pending }, set: { record.status = $0 })) { ForEach(TodoStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }
        case .memo: Section("备忘字段") { Toggle("提醒", isOn: $record.reminderEnabled) }
        case .idea: EmptyView()
        }
    }
    private func optionalText(_ title: String, _ value: Binding<String?>) -> some View { TextField(title, text: Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })) }
    private func decimalText(_ title: String, _ value: Binding<Decimal?>) -> some View { TextField(title, text: Binding(get: { value.wrappedValue.map { String(describing: $0) } ?? "" }, set: { value.wrappedValue = Decimal(string: $0) })).keyboardType(.decimalPad) }
    private func optionalDate(_ value: Binding<Date?>) -> Binding<Date> { Binding(get: { value.wrappedValue ?? Date() }, set: { value.wrappedValue = $0 }) }
}

struct RecordRow: View {
    let record: Record
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(record.content).lineLimit(2); Spacer(); if record.important { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).accessibilityLabel("重要") } }
            Text(record.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private extension String { var csv: [String] { split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } } }
private extension Module {
    var icon: String { switch self { case .ledger: "dollarsign.circle"; case .todo: "checkmark.circle"; case .memo: "note.text"; case .idea: "lightbulb" } }
}
