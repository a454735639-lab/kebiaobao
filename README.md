# 课时宝 Kebiaobao

iOS 课时打卡 / 排课管理 App。原生 SwiftUI，本地存储，无需账号。
本仓库通过 GitHub Actions 构建 **未签名 IPA**，自行签名安装。

## 功能

| 模块 | 说明 |
|---|---|
| 首页 | 宝贝切换、在读课程 / 本月课时、近 3 天课程、一键扣课时 / 请假 |
| 课表 | 月历视图，有课日期打点；点日期看当天排课 |
| 我的 | 宝贝档案、课程管理、课时流水、数据分析 |
| 课程 | 名称 / 标签 / 总课时 / 单价 / 有效期；进度条；续费 |
| 排课 | 按星期多选 + 时间 + 地点 + 老师 + 每次划扣课时 + 提前提醒 |
| 流水 | 每笔充值 / 扣课记录，可撤销 |
| 分析 | 累计支出、已上课时、按科目消耗、剩余价值 |
| 备份 | 数据文件在「文件」App 可见，支持导出 / 导入 JSON |

## 构建

推送到 `main` 或手动触发 `Build unsigned IPA` workflow。
产物：Artifacts → `Kebiaobao-unsigned-ipa` → `Kebiaobao-unsigned.ipa`

本地构建（需 macOS + Xcode 15+）：

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Kebiaobao.xcodeproj -scheme Kebiaobao \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/Kebiaobao.app Payload/
zip -qry Kebiaobao-unsigned.ipa Payload
```

## 自签安装

未签名 IPA 需要本机签名后安装：

- **Sideloadly**（Win/macOS）：拖入 IPA，填 Apple ID，Start。免费账号 7 天有效、最多 3 个 App。
- **AltStore / SideStore**（iPhone 上装）：自签 + 自动续签。
- **TrollStore**：iOS 14.0–16.6.1 / 17.0 特定版本免签直装。
- **企业证书 / 个人开发者证书**：用 iOS App Signer 重签后安装。

免费 Apple ID 签名需要开启「设置 → 隐私与安全性 → 开发者模式」。

## 已知限制

- 未签名 IPA 不含任何 provisioning profile，必须自行签名才能安装。
- 使用**免费** Apple ID 签名时，iCloud / Push 等能力不可用，本 App 仅用本地通知，不受影响。
- 数据存本地沙盒，换机请先导出 JSON。
