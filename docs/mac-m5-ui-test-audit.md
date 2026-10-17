# M5 — UI 测试根因审计与修复（2026-10-17）

## 范围与环境

基线为 main / afff942c0133020e5b92d2634a0882c179a37e96。已阅读 M1–M4 报告，复查原始日志、断言、源码、截图、层级快照与合成点击事件。Xcode 27.1（27A9275）；Fireseed-Smoke-iPhone 是 iPhone Duo / iOS 27.1，UDID 为 211F7DB8-3E5F-42C8-81E9-868AD18C2383。

证据保存在 `/tmp/aiquicknote-m5/`，原 M1–M4 证据在 `/tmp/aiquicknote-migration/`。录像提取的部分帧为黑屏，未据此推断页面状态；本次添加失败时 PNG 截图及完整 UI 层级附件，使用实际可读截图完成审计。

## 独立复现与根因

先不改测试或产品源码，分别执行两个测试，每次只选一个 `-only-testing`，均 exit 65：

- `before-ledger.xcresult` / `before-ledger.log`：首页 Ledger 点击后找不到 record 按钮。
- `before-module.xcresult` / `before-module.log`：找不到 module.add。

随后仅增加失败附件，再次执行两项，均失败，`before-screenshots.xcresult` 保留截图、层级和点击事件。`before-attachments/manifest.json` 映射附件至具体用例。

### 首页 Ledger 后找不到记录

真实原因是测试默认点击未命中圆角卡片的有效区域。卡片是 GeometryReader 内带圆角、3D 效果和拖动手势的 NavigationLink。XCTest 对整个卡片调用 `.tap()`，此环境自动选择 `(16.4, 397.93)`；卡片 AX frame 约为 `(15.4,165.7,172.2,233.2)`。该点距包围矩形左下角各约 1 pt，处于半径 30 的可见圆角之外。合成事件记录对两项失败都给出同一坐标。失败截图仍在首页，Ledger 明确显示 22 records，数据存在。

对照：保持产品源码原样，仅改用卡片归一化中心点击，Ledger 记录列表、详情弹出、浮动位置、滚动、关闭及返回列表断言均成功。原有显式卡片边缘坐标测试也已通过。因此不是记录加载/所有权/测试数据隔离故障，也不是 identifier 改名或等待不足。证据证明了当前运行时的自动点击点问题；不宣称已定位到某个 Apple 内部实现缺陷。

中心点击后，原首页测试继续暴露独立的系统控件层级兼容问题：`app.navigationBars.buttons.element(boundBy: 0)` 找不到返回按钮。`center-attachments` 中截图与 failure-hierarchy 表明：NavigationBar 存在，但 iPhone Duo 将系统 `BackButton` 放在右侧独立 Toolbar（frame 约 399,179,38,38），不在 NavigationBar 后代中。

### 模块首次保存找不到 module.add

同一个首页自动点击未命中问题。失败层级仍有 home.module.* / home.search，没有进入 ModuleListView；module.add 定义及 identifier 完整存在于源码，原断言失败只是前序导航没发生的结果。

仅改为卡片中心点击，原有模块首存、取消登录、保留草稿、再次登录及出现记录的全部断言通过（`center-check.xcresult`）。不需要修改 Identity、保存逻辑或添加延时。

## 最终最小修改

- `ios/AIQuickNoteUITests/NavigationRegressionTests.swift`：两处卡片 `.tap()` 改为可见卡片中心坐标点击；返回时优先查全 app 内系统 BackButton，并保留旧 NavigationBar 查询兼容原环境；返回后增加首页卡片存在断言。失败时保留 PNG 与层级附件。
- 没有删除、跳过或放宽任何原断言，没有新增 sleep，没有修改测试数据或登录流程。
- 审计中曾试验只给产品卡片增加圆角 contentShape，但两项仍失败（`shape-check.xcresult`），该试验已完整撤回。最终业务源码无差异。

## 依赖锁文件

应随下次经用户确认的提交纳入 `ios/AIQuickNote.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`，保留当前文件，不删除、不加入忽略规则。

这是 app 工程共享的 SPM 锁文件，只含公开仓库、版本和 commit revision，不含私有路径或凭据。工程把直接依赖 LogtoSDK 固定为 2.0.0-beta.1，但其 Package.swift 对 JOSESwift（from 3.0.0）和 KeychainAccess（from 4.2.2）使用版本范围；锁文件还能固定传递依赖，使 Mac 与 CI 更易复现。本次解析/构建使用 LogtoSDK 2.0.0-beta.1、JOSESwift 3.0.0、KeychainAccess 4.2.2。未升级依赖、未改工程 requirement。

M5 完成时未提交；本次用户已授权将测试修复、本报告及此锁文件作为独立 M5 提交，核对远端后推送 main。

## 并发与工具链警告

仅记录，不做 Swift 6 迁移：IdentityGate conformance 跨 MainActor 边界（Swift 6 模式会成为错误）、Date.init 转换为 @Sendable、既有 SwiftUI onChange/本地化插值弃用与测试未使用返回值。当前 SWIFT_VERSION=5.0。Xcode 另有 invalidDigitCount、AppIntents metadata skipped 等诊断；未修改系统 runtime 或 SDK。完整警告保存在 debug.log / release.log。

## 回归结果

最终完整 Scheme 回归通过，xcodebuild exit 0：

| 检查 | 修复前 | 最终结果 | 证据 |
| --- | --- | --- | --- |
| 首页四模块 / 浮动详情 UI | 独立复现 FAIL | PASS | full-regression.xcresult |
| 模块首次保存 / 登录取消 UI | 独立复现 FAIL | PASS | full-regression.xcresult |
| 全部 UI Tests | M1–M4 为 3/5 | PASS，5/5 | full-regression.log |
| 全部 App XCTest | M1–M4 为 51/51 | PASS，51/51 | full-regression.log |
| Debug Simulator Build | M1–M4 PASS | PASS，exit 0 | debug.log |
| Release Simulator Build | M1–M4 PASS | PASS，exit 0 | release.log |

两次独立基线均失败；增加证据附件后仍失败；仅中心点击对照使模块首存通过，并暴露右侧 Toolbar 返回按钮位置；最终加入兼容定位后全量通过。最终结果包总计 56 通过、0 失败、0 跳过，正式摘要见 full-regression-summary.json。成功截图已导出至 after-attachments/。

测试命令保留 ONLY_ACTIVE_ARCH=YES、CODE_SIGNING_ALLOWED=NO、串行测试；`-collect-test-diagnostics never` 仅关闭之前阻塞的额外 simctl diagnose 收集，不关闭断言或失败附件。

## 行为与 M6 门禁

产品行为、视觉、导航逻辑、Bundle ID、Identity、签名配置、GitHub Secrets、TestFlight 均未修改。测试明确点击现有卡片内部，并识别当前系统返回控件。M6 是后续签名准备与真机验收阶段；M1–M4 查出的账号、证书/私钥与 profile 缺失不在本阶段修复范围。

M5 结论：PASS，可以进入 M6 真机签名准备阶段；并不代表已经具备真机运行条件。M6 需确认 Team Z36ZADH7T7 的账号/App ID 权限、开发证书及私钥、匹配 profile 与可用真机。M5 未进行签名配置；后续提交与推送遵循用户明确授权。
