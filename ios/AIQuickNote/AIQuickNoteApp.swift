import SwiftUI
import Speech
import AVFoundation

private let appBackground = Color(uiColor: .systemGroupedBackground)

final class IdentitySession: IdentityGate, ObservableObject, @unchecked Sendable {
    @Published var confirmedUserID: String? { didSet { UserDefaults.standard.set(confirmedUserID, forKey: "confirmedUserID") } }
    init() { confirmedUserID = UserDefaults.standard.string(forKey: "confirmedUserID") }
    func confirm() { confirmedUserID = "local-\(UUID().uuidString)" }
}

@MainActor final class AppModel: ObservableObject {
    @Published var records: [Record] = []; @Published var error: String?
    let identity = IdentitySession(); let core: QuickNoteCore; let parser = DeterministicDraftParser()
    init() { let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]; core = QuickNoteCore(store: FileRecordStore(url: folder.appendingPathComponent("records.json")), identity: identity); reload() }
    func reload() { do { records = try core.records() } catch { self.error = error.localizedDescription } }
    func save(_ value: Record) throws { _ = try core.save(value); reload() }
}

@main struct AIQuickNoteApp: App { @StateObject private var model = AppModel(); var body: some Scene { WindowGroup { RootView().environmentObject(model) } } }

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View { NavigationStack { HomeView() }.tint(.indigo).alert("操作失败", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("确定") {} } message: { Text(model.error ?? "未知错误") } }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel; @StateObject private var speech = SpeechInput()
    @State private var text = ""; @State private var draft: Record?; @State private var query: RecordQuery?; @FocusState private var focused: Bool
    var body: some View {
        ScrollView { LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 16) { ForEach(Module.allCases) { module in NavigationLink(value: module) { ModuleCard(module: module, records: model.records.filter { $0.module == module }) }.simultaneousGesture(TapGesture().onEnded { focused = false }) } }.padding() }
            .background(appBackground.onTapGesture { focused = false }).safeAreaInset(edge: .bottom) { captureBar }.navigationTitle("AI 随手记")
            .navigationDestination(for: Module.self) { ModuleListView(module: $0) }.navigationDestination(item: $draft) { ReviewView(draft: $0) { text = "" } }
            .navigationDestination(isPresented: Binding(get: { query != nil }, set: { if !$0 { query = nil } })) { SearchView(initialQuery: query ?? RecordQuery()) }
            .onAppear { model.reload(); focused = false }.onDisappear { focused = false; speech.stop() }
            .onChange(of: speech.transcript) { text = $0 }.onChange(of: speech.finishedTranscript) { if $0 != nil { submit() } }.onChange(of: speech.error) { if let value = $0 { model.error = value } }
    }
    private var captureBar: some View { HStack(spacing: 12) {
        Button { speech.isRecording ? speech.stop() : speech.start() } label: { Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill").font(.title2).frame(width: 52, height: 52).background(speech.isRecording ? .red : .indigo).foregroundStyle(.white).clipShape(Circle()) }.accessibilityLabel("语音输入")
        TextField("说一句或写一句…", text: $text, axis: .vertical).focused($focused).lineLimit(1...4).padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)).onSubmit { submit() }
        Button { submit() } label: { Image(systemName: text.trimmed.isEmpty ? "plus" : "arrow.up").font(.title2).frame(width: 42, height: 52) }.disabled(text.trimmed.isEmpty).accessibilityLabel("提交")
    }.padding().background(.thinMaterial).shadow(color: .black.opacity(0.08), radius: 12, y: -3) }
    private func submit() { let input = text.trimmed; guard !input.isEmpty else { return }; focused = false; speech.stop(); Task { do { switch try await model.parser.parse(input) { case .create(let value): draft = value; case .search(let value): query = value } } catch { draft = Record(module: .memo, rawInput: input); model.error = "解析不可用，已保留原文供手工填写。" } } }
}

struct ModuleCard: View { let module: Module; let records: [Record]; var body: some View { VStack(alignment: .leading, spacing: 12) { Image(systemName: module.icon).font(.title).foregroundStyle(module.color); Text(module.title).font(.title2.bold()).foregroundStyle(.primary); Text(module.subtitle).font(.subheadline).foregroundStyle(.secondary); Spacer(); Text(records.first?.content ?? "\(records.count) 条记录").font(.caption).foregroundStyle(.secondary).lineLimit(2) }.frame(maxWidth: .infinity, minHeight: 150, alignment: .leading).padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24)).shadow(color: .black.opacity(0.07), radius: 12, y: 5) } }

struct ReviewView: View {
    @EnvironmentObject private var model: AppModel; @Environment(\.dismiss) private var dismiss; @State var draft: Record; @State private var identity = false; @State private var searchQuery: RecordQuery?; let onSaved: () -> Void
    var body: some View { RecordForm(record: $draft, showRawInput: true, saveTitle: "确认保存", onSave: save, onSearch: search).navigationTitle("确认记录").navigationBarTitleDisplayMode(.inline).navigationDestination(isPresented: Binding(get: { searchQuery != nil }, set: { if !$0 { searchQuery = nil } })) { SearchView(initialQuery: searchQuery ?? RecordQuery()) }.sheet(isPresented: $identity) { VStack(spacing: 20) { Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 56)); Text("首次保存需要确认身份").font(.title2.bold()); Text("仅确认本地数据归属，不会备份、上传或分享。"); Button("确认本机身份并保存") { model.identity.confirm(); identity = false; save(draft) }.buttonStyle(.borderedProminent) }.padding().presentationDetents([.medium]) } }
    private func save(_ value: Record) { do { try model.save(value); onSaved(); dismiss() } catch CoreError.identityRequired { identity = true } catch { model.error = error.localizedDescription } }
    private func search(_ value: Record) { draft = value; searchQuery = RecordQuery(keyword: value.merchant ?? value.paymentMethod ?? value.content, modules: [value.module], importantOnly: value.important, tags: value.tags) }
}

struct ModuleListView: View {
    @EnvironmentObject private var model: AppModel; @State private var adding = false; let module: Module
    var body: some View { List(model.records.filter { $0.module == module }) { record in NavigationLink(value: record) { RecordRow(record: record) }.listRowBackground(Color.white.opacity(0.82)) }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(appBackground).navigationTitle(module.title).toolbar { Button { adding = true } label: { Image(systemName: "plus") } }.sheet(isPresented: $adding) { NavigationStack { ModuleComposerView(module: module) } }.navigationDestination(for: Record.self) { DetailView(record: $0) }.overlay { if model.records.allSatisfy({ $0.module != module }) { ContentUnavailableView("暂无记录", systemImage: module.icon) } }.onAppear { model.reload() } }
}

struct ModuleComposerView: View {
    @Environment(\.dismiss) private var dismiss; @State private var text = ""; @State private var draft: Record?; @FocusState private var focused: Bool; let module: Module
    var body: some View { VStack { TextField("输入一条\(module.title)记录", text: $text, axis: .vertical).focused($focused).textFieldStyle(.roundedBorder).padding(); Button("继续") { focused = false; draft = Record(module: module, rawInput: text) }.buttonStyle(.borderedProminent).disabled(text.trimmed.isEmpty); Spacer() }.background(appBackground.onTapGesture { focused = false }).navigationTitle("新建\(module.title)").toolbar { Button("取消") { dismiss() } }.navigationDestination(item: $draft) { ReviewView(draft: $0) { dismiss() } } }
}

struct SearchView: View {
    @EnvironmentObject private var model: AppModel; @State private var keyword: String; @State private var modules: Set<Module>; @State private var important: Bool; @State private var results: [Record] = []; @FocusState private var focused: Bool
    init(initialQuery: RecordQuery) { _keyword = State(initialValue: initialQuery.keyword); _modules = State(initialValue: initialQuery.modules); _important = State(initialValue: initialQuery.importantOnly) }
    var body: some View { List { if !totalKeys.isEmpty { Section("自动总额") { ScrollView(.horizontal) { HStack { ForEach(totalKeys, id: \.self) { key in VStack(alignment: .leading) { Text(key).font(.caption).foregroundStyle(.secondary); Text(String(describing: totalMap[key] ?? 0)).font(.title3.bold()).foregroundStyle(.indigo) }.padding(.horizontal, 14).padding(.vertical, 10).background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 14)) } } } } }; Section("查询条件") { TextField("关键词", text: $keyword).focused($focused).onSubmit { focused = false; search() }; ScrollView(.horizontal) { HStack { ForEach(Module.allCases) { module in Toggle(module.title, isOn: binding(module)).toggleStyle(.button) } } }; Toggle("重要", isOn: $important) }; Section("结果 \(results.count)") { ForEach(results) { record in NavigationLink(value: record) { RecordRow(record: record) }.simultaneousGesture(TapGesture().onEnded { focused = false }).listRowBackground(Color.white.opacity(0.82)) } } }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(appBackground.onTapGesture { focused = false }).navigationTitle("搜索").navigationDestination(for: Record.self) { DetailView(record: $0) }.onAppear { focused = false; search() }.onChange(of: keyword) { search() }.onChange(of: modules) { search() }.onChange(of: important) { search() } }
    private var totalMap: [String: Decimal] { QuickNoteCore.numericTotals(in: results) }
    private var totalKeys: [String] { totalMap.keys.sorted() }
    private func binding(_ module: Module) -> Binding<Bool> { Binding(get: { modules.contains(module) }, set: { enabled in if enabled { modules.insert(module) } else { modules.remove(module) } }) }
    private func search() { do { results = try model.core.search(RecordQuery(keyword: keyword, modules: modules, importantOnly: important)) } catch { model.error = error.localizedDescription } }
}

struct DetailView: View { @EnvironmentObject private var model: AppModel; @State var record: Record; var body: some View { RecordForm(record: $record, showRawInput: true) { value in do { try model.save(value); record = value } catch { model.error = error.localizedDescription } }.navigationTitle("记录详情") } }

struct RecordForm: View {
    @EnvironmentObject private var model: AppModel; @Binding var record: Record; let showRawInput: Bool; let saveTitle: String; let onSave: (Record) -> Void; let onSearch: ((Record) -> Void)?
    @State private var tags: String; @State private var quantity: String; @State private var amount: String; @FocusState private var focused: Bool
    init(record: Binding<Record>, showRawInput: Bool, saveTitle: String = "保存", onSave: @escaping (Record) -> Void, onSearch: ((Record) -> Void)? = nil) { _record = record; self.showRawInput = showRawInput; self.saveTitle = saveTitle; self.onSave = onSave; self.onSearch = onSearch; _tags = State(initialValue: record.wrappedValue.tags.joined(separator: ", ")); _quantity = State(initialValue: record.wrappedValue.quantity.map(String.init(describing:)) ?? ""); _amount = State(initialValue: record.wrappedValue.amount.map(String.init(describing:)) ?? "") }
    var body: some View { Form { Section { Picker("模块", selection: $record.module) { ForEach(Module.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }; if showRawInput { Section("原始输入") { Text(record.rawInput).foregroundStyle(.secondary) } }; Section("内容") { TextField("内容", text: $record.content, axis: .vertical).focused($focused); TextField("标签，用逗号分隔", text: $tags).focused($focused); Toggle("重要", isOn: $record.important) }; fields }.contentMargins(.top, 18, for: .scrollContent).listStyle(.insetGrouped).scrollContentBackground(.hidden).background(appBackground.onTapGesture { focused = false }).toolbar { ToolbarItemGroup(placement: .topBarTrailing) { if let onSearch { Button("搜索") { if let value = prepared() { onSearch(value) } } }; Button(saveTitle) { if let value = prepared() { onSave(value) } } } }.onDisappear { focused = false } }
    @ViewBuilder private var fields: some View { switch record.module { case .ledger: Section("账目字段") { optional("商家", $record.merchant); TextField("数量", text: $quantity).keyboardType(.decimalPad).focused($focused); TextField("金额", text: $amount).keyboardType(.decimalPad).focused($focused); optional("币种", $record.currency); optional("类别", $record.category); optional("支付方式", $record.paymentMethod); optional("地点", $record.location); date("日期时间", $record.occurredAt) }; case .todo: Section("待办字段") { date("日期时间", $record.dueAt); Toggle("提醒", isOn: $record.reminderEnabled); optional("地点", $record.location); Picker("状态", selection: Binding(get: { record.status ?? .pending }, set: { record.status = $0 })) { ForEach(TodoStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } } }; case .memo: Section("备忘字段") { Toggle("提醒", isOn: $record.reminderEnabled) }; case .idea: EmptyView() } }
    private func optional(_ title: String, _ value: Binding<String?>) -> some View { TextField(title, text: Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })).focused($focused) }
    private func date(_ title: String, _ value: Binding<Date?>) -> some View { VStack { Toggle("设置\(title)", isOn: Binding(get: { value.wrappedValue != nil }, set: { value.wrappedValue = $0 ? Date() : nil })); if value.wrappedValue != nil { DatePicker(title, selection: Binding(get: { value.wrappedValue! }, set: { value.wrappedValue = $0 })) } } }
    private func prepared() -> Record? { focused = false; var value = record; value.tags = tags.csv; if value.module == .ledger { guard (amount.isEmpty || Decimal(string: amount) != nil) && (quantity.isEmpty || Decimal(string: quantity) != nil) else { model.error = "数量或金额格式无效"; return nil }; value.quantity = quantity.isEmpty ? nil : Decimal(string: quantity); value.amount = amount.isEmpty ? nil : Decimal(string: amount) }; record = value; return value }
}

struct RecordRow: View { let record: Record; var body: some View { VStack(alignment: .leading) { Text(record.content).lineLimit(2); Text(record.updatedAt, style: .date).font(.caption).foregroundStyle(.secondary) } } }

@MainActor final class SpeechInput: ObservableObject {
    @Published var transcript = ""; @Published var finishedTranscript: String?; @Published var isRecording = false; @Published var error: String?
    private let engine = AVAudioEngine(); private var task: SFSpeechRecognitionTask?; private var request: SFSpeechAudioBufferRecognitionRequest?
    func start() { SFSpeechRecognizer.requestAuthorization { [weak self] status in Task { @MainActor in guard status == .authorized else { self?.error = "请允许语音识别权限。"; return }; AVAudioApplication.requestRecordPermission { allowed in Task { @MainActor in guard allowed else { self?.error = "请允许麦克风权限。"; return }; self?.begin() } } } } }
    private func begin() { stop(); transcript = ""; finishedTranscript = nil; guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else { error = "系统语音识别不可用。"; return }; let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true; self.request = request; let node = engine.inputNode; node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buffer, _ in request.append(buffer) }; task = recognizer.recognitionTask(with: request) { [weak self] result, failure in Task { @MainActor in if let result { self?.transcript = result.bestTranscription.formattedString }; if failure != nil || result?.isFinal == true { self?.finishedTranscript = self?.transcript; self?.stop() } } }; do { try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement); try AVAudioSession.sharedInstance().setActive(true); engine.prepare(); try engine.start(); isRecording = true } catch { stop(); self.error = "无法启动麦克风：\(error.localizedDescription)" } }
    func stop() { if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }; request?.endAudio(); task?.cancel(); request = nil; task = nil; isRecording = false }
}

private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }; var csv: [String] { split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty } } }
private extension Module { var icon: String { switch self { case .ledger: "dollarsign.circle.fill"; case .todo: "checkmark.circle.fill"; case .memo: "note.text"; case .idea: "lightbulb.fill" } }; var subtitle: String { switch self { case .ledger: "记录每一笔收支"; case .todo: "别错过要做的事"; case .memo: "保存重要信息"; case .idea: "抓住一闪而过的想法" } }; var color: Color { switch self { case .ledger: .green; case .todo: .blue; case .memo: .orange; case .idea: .purple } } }
