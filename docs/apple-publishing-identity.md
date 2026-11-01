# AIQuickNote Apple 发布身份卡

更新：2026-10-31。项目事实来源：`docs/testflight-release.md`、`configs/aiquicknote-release.json` 和签名身份更新记录；中央 Team/API 凭据索引见 [Fireseed Apple 发布身份与凭据索引](../../.workflow/apple-publishing-identity.md)。全局身份只在中央索引维护。

## App 标识与 TestFlight

| 字段 | 已核实值 |
|---|---|
| App 名称 | AIQuickNote |
| ASC App ID | `6816749718`；2026-10-31 通过 ASC 官方只读 API 按精确 Bundle ID 匹配验证。 |
| Production Bundle ID | `org.tmiai.aiquicknote` |
| Apple Team ID | 见中央索引 |
| 最近上传 | `0.1 (12)`，2026-10-20；Build Upload UUID `e4320ec2-db71-4690-9ee8-fae5d865f65d`；实时查询为 Upload `COMPLETE`、Build `VALID`。 |
| 内部测试组 | `测试`；UUID `1ef078a2-0ffc-4d2f-8c52-f6e898680ad3`；Build 12 关联且 `IN_BETA_TESTING`（2026-10-31 实时查询）。 |

## 签名配置

| Target | Profile | UUID | 状态 |
|---|---|---|---|
| iOS | `AIQuickNote App Store Distribution` | `d223d0d6-e73e-461f-8eaa-21de08a8bc81` | 2026-10-31 更新并同步到本机；下一次 Archive/IPA 需重新验证。 |

Build 12 的历史发布报告只确认复用了当时匹配的 Profile；不能用当前 Profile UUID 反推历史 IPA 配置。发行证书指纹和有效期见中央索引。

## 认证、查询与上传

- Build 12 通过既有 Xcode 账号上传路径收到 Apple 回执；该证据不证明本地 ASC REST 查询能力可用。
- AIQuickNote 没有项目专属 ASC 全分页查询脚本；中央只读 API 本轮已确认 App ID 与 Build 状态。后续发布使用中央索引记录的认证配置和已修复的共享查询工具，避免把 Xcode 上传能力与 REST 查询能力混为一谈。
- 禁止把 API 私钥、密码、Token、Cookie 或证书私钥写入本页或 Git。

## ASC 实时只读复核

2026-10-31 按 Bundle ID `org.tmiai.aiquicknote` 查询 Apple 官方 ASC API，精确匹配 App ID `6816749718`。Build 12 当前为 `VALID`，已关联内部组 `测试` 并可供内部测试。该结果更新此前仅有上传回执的历史状态；本轮没有创建或修改 ASC 资源。全局 Issuer、Key ID 和 Key 可用性见中央索引。

## 版本与复核入口

- 最近发布记录：`docs/releases/2026-10-20-ephemeral-account-choice-build-12.md`；当前编号下限：`configs/aiquicknote-release.json`（需发布前实时查询 ASC）。
- 当前签名资料：`docs/releases/2026-10-31-distribution-signing-update.md`。
- 读取 [TestFlight Runbook](testflight-release.md) 与中央索引后，再进行任何发布预检。
