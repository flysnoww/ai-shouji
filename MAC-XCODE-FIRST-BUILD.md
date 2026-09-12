# AI随手记：Mac / Xcode 首次编译指南

当前状态：`IMPLEMENTATION_CANDIDATE`

## 1. 把项目复制到 Mac

1. 把整个 `1ai suishou` 文件夹复制到 Mac，不要只复制 `ios` 子文件夹。
2. 建议放到“访达 → 个人收藏 → 文稿”中，例如：`文稿/1ai suishou`。
3. 保留原有目录结构，不要移动 `ios` 内的 Swift 文件。

## 2. 打开正确的 Xcode 工程

1. 打开项目文件夹中的 `ios` 文件夹。
2. 双击 `AIQuickNote.xcodeproj`。
3. 本项目没有 `.xcworkspace`，首次运行不要双击 `Package.swift`。

`Package.swift` 只负责独立编译和测试 Core。Xcode App target 与 Swift Package 共用同一个 `ios/QuickNoteCore/Core.swift`，没有第二套业务代码。

## 3. 处理 Xcode 第一次出现的提示

1. 如果 macOS 询问是否信任从其他电脑复制来的项目，点击“打开”或“信任并打开”。
2. 如果 Xcode 要求同意许可协议，按提示同意。
3. 如果出现“Update to recommended settings”，第一次先选“Later（稍后）”。先确认原工程能编译，再决定是否更新。
4. 如果 Xcode 正在建立索引，等待顶部进度结束；这通常只发生在第一次打开时。

## 4. 选择开发团队 Team

模拟器通常不需要开发团队，真实 iPhone 需要。

1. 在 Xcode 左侧点击最上方蓝色项目图标 `AIQuickNote`。
2. 中间区域的 `TARGETS` 下点击 `AIQuickNote`。
3. 点击顶部的 `Signing & Capabilities`。
4. 保持 `Automatically manage signing` 已勾选。
5. 打开 `Team` 下拉菜单，选择自己的 Apple ID 团队。
6. 如果没有团队，打开 Xcode 菜单 `Xcode → Settings… → Accounts`，点击左下角 `+`，登录 Apple ID，然后返回本页选择团队。

## 5. Bundle Identifier 冲突时修改

默认占位值是 `com.example.AIQuickNote`，真机签名时通常需要改成唯一值。

1. 仍在 `AIQuickNote` target 的 `Signing & Capabilities` 页面。
2. 找到 `Bundle Identifier`。
3. 改成只属于你的反向域名形式，例如 `com.你的英文名.AIQuickNote`。
4. 只使用英文字母、数字、点和连字符，不要使用空格或中文。
5. 如果测试 target 同样提示冲突，在 `TARGETS → AIQuickNoteTests → Signing & Capabilities` 中把它改成相似的唯一值，例如在末尾加 `.tests`。

## 6. 选择 iPhone Simulator

1. 查看 Xcode 窗口顶部、运行三角按钮右边的设备名称。
2. 点击设备名称打开列表。
3. 在 `iOS Simulators` 下选择任意安装了 iOS 17 或更高版本的 iPhone，例如 `iPhone 16`。
4. 如果没有模拟器，打开 `Xcode → Settings… → Components`，下载一个 iOS 17 或更高版本的 Simulator Runtime。

## 7. 编译 Build

1. 确认顶部 Scheme 显示 `AIQuickNote`，设备显示刚选择的 iPhone Simulator。
2. 点击菜单 `Product → Build`，或按 `Command + B`。
3. 成功时顶部会显示 `Build Succeeded`。
4. 失败时点击左侧红色错误图标，保存第一条完整错误信息；不要先批量修改工程设置。

## 8. 运行 Run

1. 点击 Xcode 左上角的三角形运行按钮，或按 `Command + R`。
2. Xcode 会启动 iPhone Simulator 并安装 AI随手记。
3. 等待 App 首页出现“记下此刻”和文字输入框。

## 9. 运行单元测试

1. 保持 Scheme 为 `AIQuickNote`，设备为 iPhone Simulator。
2. 点击菜单 `Product → Test`，或按 `Command + U`。
3. 左侧 Test Navigator 中应能看到 `AIQuickNoteTests` 和 `CoreTests`。
4. 两个测试通过时会显示绿色对勾。
5. 也可以在项目根目录打开“终端”，运行 `swift test`；它测试同一份 Core，但不启动 iOS App。

当前 Swift/Xcode 测试状态：`NOT RUN — requires macOS / Xcode`。

## 10. 连接真实 iPhone

1. 用数据线连接 iPhone 和 Mac，并解锁 iPhone。
2. iPhone 弹出“要信任此电脑吗？”时点击“信任”，输入锁屏密码。
3. 在 Xcode 顶部设备列表中选择这台 iPhone。
4. 确认已经按第 4 步选择 Team，并按第 5 步设置唯一 Bundle Identifier。
5. 点击运行按钮。
6. 如果 iPhone 要求开启开发者模式，打开 `设置 → 隐私与安全性 → 开发者模式`，按提示重启并确认。
7. 免费 Apple ID 签名可能只有短期有效期；过期后重新从 Xcode 运行即可。

## 11. 真机签名失败的常见处理

1. 确认 Mac 和 iPhone 已联网，Apple ID 已登录 Xcode。
2. 确认 `Automatically manage signing` 已勾选并选择了 Team。
3. 把 Bundle Identifier 改成更独特的值。
4. 确认 iPhone 已解锁、已信任 Mac，并启用了开发者模式。
5. 点击 `Product → Clean Build Folder`，然后再次 `Product → Build`。
6. 如果错误仍在，只处理 Xcode 显示的第一条签名错误；不要删除项目文件或重建工程。

## 12. 第一次运行后的人工验证

按项目根目录的 `V0-FIRST-RUN-CHECKLIST.md` 从上到下检查。重点完成一条真实闭环：输入文字 → 一次确认 → 切换模块并编辑 → 首次身份确认 → 保存 → 模块列表与搜索可见 → 进入详情修改 → 重启后数据仍存在。

本轮范围冻结：不验证语音、AI、Siri、App Intents、MCP、OCR、相机、图片、系统提醒执行、Calendar、云端备份、真实账号服务器、Dashboard、复杂统计或最终视觉设计。
