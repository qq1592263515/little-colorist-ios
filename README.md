# 小小涂色家 - App Store 工程

这是现有单文件离线游戏的 macOS 和 iOS 原生应用工程。游戏内容、进度和作品都不需要联网；应用不包含账号、广告、统计 SDK 或内购。

## 工程组成

- `LittleColorist.xcodeproj`：XcodeGen 生成的 macOS/iOS 双平台工程
- `LittleColorist/Resources/index.html`：原游戏离线资源，仅将站内链接改为离线 `#` 路由
- `LittleColorist/App`：SwiftUI 原生容器、沙盒、系统保存/分享桥
- `AppStore/Metadata`：中文商店文案、审核备注和隐私答案
- `AppStore/Screenshots`：Mac 和 iPhone/iPad 商店截图
- `scripts`：本地构建、Mac App Store `.pkg` 签名与静态校验脚本

## 本机构建

```sh
chmod +x scripts/*.sh
scripts/build_local_macos.sh
open "build/local/小小涂色家.app"
```

本地预览包使用临时签名，便于在没有描述文件时运行。正式 Mac App Store
安装包必须使用 Apple 分发证书和 `MAC_APP_PROVISIONING_PROFILE` 签名。

## App Store Connect

已确认的公开商店页面：

- Support URL: `https://qq1592263515.github.io/little-colorist-support/support.html`
- Privacy Policy URL: `https://qq1592263515.github.io/little-colorist-support/privacy.html`

`scripts/appstore_env.sh` 中的 Key ID 和 Issuer ID 来自当前开发者账号。私钥
只读取本机 `~/.appstoreconnect/private_keys`，不会写进工程。

## 正式上架

1. 在 Xcode 中登录 Apple Developer 账号。
2. 打开 `LittleColorist.xcodeproj`，确认 Team 为 `TX65SX7Y23`。
3. 为 Mac App Store 和 iOS App Store 自动生成分发描述文件。
4. Product > Archive，先验证 macOS 包，再上传 App Store Connect。
5. 在 App Store Connect 创建应用记录，填写 `AppStore/Metadata/zh-Hans.md` 的内容。
6. 上传截图和图标，设置价格为中国区及其他地区免费。
7. 填 App 隐私为“未收集数据”，提交审核。

具体操作与当前机器缺口见 `AppStore/SUBMISSION_GUIDE.md`。
