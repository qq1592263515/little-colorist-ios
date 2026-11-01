# GitHub iOS 云构建

公开仓库使用标准 macOS 26 runner，GitHub Actions 不产生构建费用。

- Workflow: `.github/workflows/ios-app-store.yml`
- Runner: `macos-26`
- Xcode project: `LittleColorist.xcodeproj`
- Target/scheme: `LittleColorist-iOS`
- Bundle ID: `com.jiahuichen.littlecolorist`（与 macOS 使用同一 Universal App ID）
- Version/build: `1.0 (1)`
- Export method: App Store Connect

## GitHub Secrets

签名材料只存于公开仓库的加密 Secrets，不提交到 Git：

- `IOS_DISTRIBUTION_P12_BASE64`
- `IOS_DISTRIBUTION_P12_PASSWORD`
- `IOS_PROVISIONING_PROFILE_GZIP_BASE64`
- `ASC_API_KEY_ID`
- `ASC_API_ISSUER_ID`
- `ASC_API_PRIVATE_KEY_BASE64`

## 手动运行

在 GitHub 仓库的 Actions 页面选择
`Build and upload iOS App Store`，运行工作流。默认会在构建成功后自动把
IPA 上传到 App Store Connect。
