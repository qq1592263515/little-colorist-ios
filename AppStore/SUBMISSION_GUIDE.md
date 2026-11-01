# 真实上架流程

这份清单以“macOS 主版本先上架，iOS 同源版本随后提交”为目标。项目已经包含双平台 Xcode 工程、离线资源、沙盒、隐私清单、商店文案和截图生成入口。

## 一、当前机器状态

- Apple Team ID：`TX65SX7Y23`
- 钥匙串已有 3rd Party Mac Developer Application 和 Installer 证书
- App Store Connect API 私钥已存在：`AuthKey_7692Q25SWM.p8`
- 已安装 Transporter.app
- 当前没有安装 Xcode，也没有 Mac App Store/iOS 分发描述文件
- 因而可以先做完整工程与本地包，但最终 Archive、自动签名和上传必须在 Xcode 中完成

## 二、准备开发者账号

1. 登录 Apple Developer 和 App Store Connect，确认会员资格有效。
2. 同意最新 Developer Program License Agreement 和 Free Apps Agreement。
3. 进入 Certificates, Identifiers & Profiles。
4. 创建 App ID：
   - `com.jiahuichen.littlecolorist`
   - `com.jiahuichen.littlecolorist.ios`
5. 为两个 App ID 启用 Game Center 并非必需；本版本不需要任何 Capability。
6. 在 App Store Connect 创建 Mac 应用记录，价格选 Free。

## 三、在 Xcode 完成签名

1. 安装 Xcode，然后在 Settings > Accounts 登录与 `TX65SX7Y23` 对应的 Apple 账号。
2. 打开 `LittleColorist.xcodeproj`。
3. macOS Target 的 Signing & Capabilities：
   - Team 选 `JIAHUI CHEN`
   - Bundle ID 确认 `com.jiahuichen.littlecolorist`
   - Distribution 自动管理
   - 保留 App Sandbox 和 User Selected File Read/Write，不勾选 Network
4. iOS Target 使用 `com.jiahuichen.littlecolorist.ios`，同样自动管理签名。
5. 选择 Any Mac，Product > Archive。
6. Organizer 中先 Validate App，再 Distribute App > App Store Connect > Upload。

## 四、在 App Store Connect 填写

Mac 应用信息：

- Name：`小小涂色家 - 儿童离线涂色`（若“小小涂色家”可用，可去掉后缀）
- Subtitle：`24 张动物画，轻松自由填色`
- Primary Category：Games
- Secondary Category：Education
- Age Rating：4+
- Price：Free
- App Privacy：No, we do not collect data
- Support URL：`https://qq1592263515.github.io/little-colorist-support/support.html`
- Privacy Policy URL：`https://qq1592263515.github.io/little-colorist-support/privacy.html`

版本信息：

- Version：`1.0`
- Copyright：`Copyright © 2026 JIAHUI CHEN. All rights reserved.`
- Description、Promotional Text、Keywords 从 `Metadata/zh-Hans.md` 复制
- Review Notes 从 `Metadata/Review-Notes.txt` 复制

## 五、商店素材

App Store Mac 截图要求以 App Store Connect 当前上传页面为准。本项目准备 1440 × 900 和 2880 × 1800 两套，避免缩放失真。

iOS 准备：

- 6.9 英寸 iPhone：1320 × 2868
- 6.5 英寸 iPhone：1242 × 2688
- 13 英寸 iPad：2064 × 2752
- 12.9 英寸 iPad：2048 × 2732

截图文件放在 `AppStore/Screenshots`。必须体现实际游戏界面，不使用装饰性营销卡代替游戏画面。

## 六、审核前检查

- 断开网络仍可进入所有 4 本画册并完成涂色
- 切换“照样闯关”正常
- 退回画册和重启应用后进度仍在
- “保存作品”打开系统保存或分享面板
- 不出现外部网页、登录、广告、内购或虚假按钮
- 小屏窗口没有按钮或文字被裁切
- App 隐私、年龄分级、免费价格与实际上线内容一致

## 七、iOS 版本

iOS Target 已与 Mac 共用游戏资源。完成 Mac 版本后，选择 `LittleColorist-iOS` Scheme 和真机/Any iOS Device 进行 Archive。iOS 需要额外的开发/分发证书和描述文件，可在 Xcode 自动签名中生成。使用同一 App Store Connect 记录体系但新建 iOS App 记录，Bundle ID 使用 `.ios` 结尾的独立标识。

## 八、审核被拒时最常见的两个原因

1. 最低功能要求：如果审核认为只是网页壳，需要强调这是完整离线游戏，并准备后续增加原生家长设置、涂色导出模板等原生功能。本工程已经包含原生保存/分享和沙盒，但 WebView 仍是主要内容呈现层。
2. 元数据不完整：Support URL、Privacy Policy URL、审核联系方式和截图必须是真实可访问内容。示例邮箱必须替换。
