# AIQuickNote Apple 发布身份卡

更新：2026-10-31。项目事实来源：`docs/testflight-release.md`、`configs/aiquicknote-release.json` 和签名身份更新记录；中央 Team/API 凭据索引见 [Fireseed Apple 发布身份与凭据索引](../../.workflow/apple-publishing-identity.md)。全局身份只在中央索引维护。

## App 标识与 TestFlight

| 字段 | 已核实值 |
|---|---|
| App 名称 | AIQuickNote |
| ASC App ID | **待核实**；现有可复核记录未找到数字 ID，不得从 Bundle ID 推导。 |
| Production Bundle ID | `org.tmiai.aiquicknote` |
| Apple Team ID | 见中央索引 |
| 最近有回执的上传 | `0.1 (12)`，2026-10-20；Delivery UUID `e4320ec2-db71-4690-9ee8-fae5d865f65d` |
| 已留存处理状态 | `RECEIVED` / `PROCESSING`；这是历史响应，不代表当前 ASC 状态。 |
| 内部测试组 | 名称曾记录为 `测试`；Build 12 分组未确认，组 UUID 待核实。 |

## 签名配置

| Target | Profile | UUID | 状态 |
|---|---|---|---|
| iOS | `AIQuickNote App Store Distribution` | `d223d0d6-e73e-461f-8eaa-21de08a8bc81` | 2026-10-31 更新并同步到本机；下一次 Archive/IPA 需重新验证。 |

Build 12 的历史发布报告只确认复用了当时匹配的 Profile；不能用当前 Profile UUID 反推历史 IPA 配置。发行证书指纹和有效期见中央索引。

## 认证、查询与上传

- Build 12 通过既有 Xcode 账号上传路径收到 Apple 回执；该证据不证明本地 ASC REST 查询能力可用。
- 本轮未确认 AIQuickNote 专属 ASC REST 查询脚本可用，也未确认当前 App Store Connect App ID。下次发布先查看本项目最新配置与历史凭据，再选择可用查询通道。
- 禁止把 API 私钥、密码、Token、Cookie 或证书私钥写入本页或 Git。

## 版本与复核入口

- 最近发布记录：`docs/releases/2026-10-20-ephemeral-account-choice-build-12.md`；当前编号下限：`configs/aiquicknote-release.json`（需发布前实时查询 ASC）。
- 当前签名资料：`docs/releases/2026-10-31-distribution-signing-update.md`。
- 读取 [TestFlight Runbook](testflight-release.md) 与中央索引后，再进行任何发布预检。
