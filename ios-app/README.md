# 出口成章 iOS App（SwiftUI 客户端源码）

这是“出口成章”的 iPhone 客户端源码目录，当前目标已经从单纯 Demo 骨架，推进到**可接后端、可录音、可做完整表达训练闭环**，并且现在已经补上了**可在 Mac 上直接打开接手的 Xcode 工程骨架**。

## 现在已有的 App 能力

1. 首页
2. 录音 / 文本输入页
3. 结果页（原文 / 优化稿 / 标签 / 下一步建议 / 分享 / 复制）
4. 训练页（文本 / 语音复述，支持试听录音）
5. 灵感库页
6. 报告页
7. 设置页（远端地址保存、预设切换、连接测试）

## 当前能力

### 已完成
- SwiftUI 多页面主流程
- 本地 Mock 模式
- 远端 API 模式
- 服务地址本地持久化（UserDefaults）
- 设置页测试连接 / 保存并连接
- 录音能力（`AVAudioRecorder`）
- 录音试听能力（`AVAudioPlayer`）
- 录音直传后端 `/api/transcripts/create`
- 训练页语音复述 → `/api/transcribe` → `/api/train/evaluate`
- 灵感归档
- 每日报告
- 线上正式服地址预留（`Info.plist` 的 `CKCZReleaseBaseURL`）
- 正式 iOS 宿主工程骨架：
  - `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang.xcodeproj`
  - `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/Config/Info.plist`
  - `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/Resources/Assets.xcassets/`

### 还差最后一公里
- 在 macOS + Xcode 上打开工程，跑一次模拟器编译
- 真机编译安装并验证录音权限 / 网络访问
- 选择签名方式（个人免费签名 or Apple Developer）
- 如果要长期分发，再接 TestFlight / 正式上架

> 也就是说：**现在已经不是“只有源码目录”的状态，而是已经接近“下载到 Mac 后就能继续编译”的 iOS 工程。**

---

## 目录

核心源码目录：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang/`

Xcode 工程：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang.xcodeproj`

后端服务目录：
- `/home/gem/workspace/agent/workspace/projects/出口成章/app/`

> 注意：如果你只把 `ios-app` 单独拷到 Mac，那么此处这个 `app/` 后端目录并不会跟着过去；那样你仍然可以编译、跑 Mock、做基础真机安装，但不能直接跑真实转写/训练闭环。

---

## 与后端的默认联调方式

默认服务地址：
- `http://127.0.0.1:4321`

注意：
- **iOS 模拟器**可直接尝试 `127.0.0.1`
- **iPhone 真机**不能用 `127.0.0.1`，要改成电脑局域网 IP，例如 `http://192.168.1.23:4321`

先启动后端：

```bash
cd ../app
npm start
```

然后在 iOS App 的设置页里：
1. 切到“模拟器联调”或手动填地址
2. 点“测试连接”
3. 点“保存并连接”

---

## 如何在 Mac 上接手

1. **只想先编译 / 跑 Mock / 看 UI**：把整个 `ios-app` 目录拉到 Mac 就够了。
2. **想直接跑完整“录音 → 转写 → 优化 → 训练”闭环**：不要只拿 `ios-app`，还要把同级 `app/` 一起带过去；如果你还在原始工程环境，最省事的做法是先进入 `ios-app/` 目录再执行：
   ```bash
   bash scripts/package-mac-handoff.sh
   ```
   它会把 `ios-app + app` 打成一个 Mac 交接包，并附带 `HANDOFF-README.md`。
   到 Mac 后，如果解压出来的是同级 `ios-app/` 与 `app/`，进入 `ios-app/` 目录后还可以直接执行：
   ```bash
   bash scripts/handoff-backend.sh verify
   ```
   可直接从 `ios-app` 目录侧对同级 `app/` 后端做一轮总自检（`npm test + smoke-flow`；除 `transcribe/create/train/archive/report` 写链路外，还会回读 `transcripts/training/ideas` 列表，并顺手校验 `bootstrap` / `reports-daily` 与 iOS 依赖字段），不必先手动切目录。
3. 到 Mac 后，最省事的首编路径已经变成：先进入解压后的 `ios-app/` 目录，再跑环境预检和一键首编：
   ```bash
   bash scripts/mac-env-check.sh

   bash scripts/mac-first-run.sh \
     --team 你的TEAMID \
     --bundle-id 你的.bundle.id
   ```
   它会串起来做：环境预检（Xcode / xcrun / python3 / Node 等）→ 静态校验 → 若检测到同级 `app/` 后端则自动跑 verify（`npm test + smoke-flow`；除覆盖 `transcribe/create/train/archive/report` 写链路外，还会回读 `transcripts/training/ideas` 列表，并顺手校验 `bootstrap` / `reports-daily` 与 iOS 依赖字段），若没有则自动跳过后端检查 → 写入签名 → `xcodebuild` 模拟器烟测，并落地 `.xcresult` 结果包。
   如果你想手动指定后端检查强度，`--backend-check` 当前支持：`auto`（默认；有同级 `app/` 就跑 verify，否则自动跳过）、`smoke`（轻量探活；会检查 `provider/status`、`bootstrap`、`health`、`reports/daily`，并顺手校验报告页关键字段）、`smoke-flow`（完整 transcribe/create/train/archive/report 烟测）、`test`（只跑 `npm test`）、`verify`（`npm test + smoke-flow`；除 `transcribe/create/train/archive/report` 写链路外，还会回读 `transcripts/training/ideas` 列表，并顺手校验 `bootstrap` / `reports-daily` 与 iOS 依赖字段）、`skip`（显式跳过，等价于 `--skip-backend`）。
4. 如果你更想拆开执行，也可以先一键写入 Team / Bundle Identifier：
   ```bash
   bash scripts/configure-signing.sh \
     --team 你的TEAMID \
     --bundle-id 你的.bundle.id
   ```
5. 再单独跑一次命令行编译烟测：
   ```bash
   bash scripts/xcodebuild-smoke.sh
   ```
   默认会优先自动挑一台当前可用的 iPhone Simulator；如果当前没挑到可用设备，才回退到 `generic/platform=iOS Simulator`，并把实际来源打印到 `destinationSource` 里。
   它现在会同时产出：
   - `build/xcodebuild-smoke.log`
   - `build/xcodebuild-smoke.xcresult`
6. 然后回到 Xcode 里跑 iPhone Simulator
7. 如果要真机联调本地后端，先算出电脑局域网 IP：
   ```bash
   bash scripts/resolve-local-ip.sh
   ```
8. 最后连真机跑一轮录音 → 转写 → 优化 → 训练 → 归档

更细的最短操作路径见：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/Mac-首编手册.md`

下载前预检 / 打包 / 首编脚本：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/check-ios-project.sh`
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/mac-env-check.sh`（Mac 上先查 Xcode / xcrun / python3 / Node / npm 是否齐，并把结果写到 `build/mac-env-check.log`）
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/mac-first-run.sh`（Mac 上一条命令串起环境预检、静态校验、若同级 `app/` 存在则自动跑后端 verify=`npm test + smoke-flow`（除 `transcribe/create/train/archive/report` 写链路外，还会回读 `transcripts/training/ideas` 与 `bootstrap/reports-daily`，并顺手校验 iOS 依赖字段）、签名写入、xcodebuild 烟测；只带 `ios-app` 时会自动跳过后端检查）
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/package-ios-app.sh`（只打 iOS 工程）
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/package-mac-handoff.sh`（把 `ios-app + app` 一起打成 Mac 交接包）
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/handoff-backend.sh`（从 `ios-app` 目录侧统一启动 / 停止 / 烟测同级 `app/` 后端）
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/smoke-backend.sh`
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/resolve-local-ip.sh`
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/configure-signing.sh`
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/scripts/xcodebuild-smoke.sh`（会同时产出 `build/xcodebuild-smoke.log` 与 `build/xcodebuild-smoke.xcresult`，更利于回传首编失败证据）

Mac 环境与安装清单：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/Mac-环境安装清单.md`

Mac 排障手册：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/Mac-编译失败排障.md`

当前已生成可搬运归档（当前环境已产出 tar.gz + sha256；若运行环境有 `zip` 命令，打包脚本也会顺带产出 zip）：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/dist/`

---

## 没买 Apple Developer 套餐，会不会有影响？

### 不影响的部分
- 在 Xcode 里打开工程
- 跑 iOS 模拟器
- 用个人 Apple ID 做本地真机调试（Personal Team）
- 本地开发、自测、录音、联调后端

### 会受影响的部分
- **不能上 TestFlight**
- **不能上 App Store**
- 免费签名在真机上的可用期更短，分发能力很弱
- 某些高级能力 / 正式分发流程会受限

一句话：

**如果目标是“先做出自己能用的 iPhone App”，没买开发者套餐也能继续推进。**  
**如果目标是“稳定装到多台设备、给别人用、发 TestFlight”，那就需要 Apple Developer 付费账号。**

---

## 录音与语音闭环

当前 iOS 源码已支持两条主线：

### 主线 A：文本输入
- 输入表达内容
- 走 `/api/transcripts/create`
- 得到原文 / 优化稿 / 问题分析
- 进入训练与归档

### 主线 B：真语音输入
- App 内录音
- 可先试听录音
- 直接上传音频到 `/api/transcripts/create`
- 服务端先转写，再生成优化稿
- 训练页可再次录音复述
- App 再调用 `/api/transcribe` + `/api/train/evaluate`

这已经不是“改几个常量看看 UI”的阶段，而是**完整数据流已经按真 App 方式接起来**。

---

## 宿主 iOS 工程已补的配置

### 1. 麦克风权限
`Info.plist` 已包含：

```xml
<key>NSMicrophoneUsageDescription</key>
<string>我们需要麦克风来录制你的表达，并生成转写与训练结果。</string>
```

### 2. 局域网联调权限
开发期如果 iPhone 直连 Mac 的局域网地址，`Info.plist` 已预留：

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>开发调试时需要访问同一局域网中的本地服务。</string>
```

### 3. 本地 HTTP 联调 ATS
开发期已放开：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### 4. 可选：正式服地址
`Info.plist` 已预留：

```xml
<key>CKCZReleaseBaseURL</key>
<string></string>
```

后续填上正式 HTTPS 地址后，设置页就能直接切换。

---

## 现在离“下载下来后在 Mac 上继续做”还有多远？

如果只说**在 Mac 上接手继续做**：已经很近了，核心差距只剩：

1. Xcode 打开工程
2. 选 Team / Bundle Identifier
3. 跑模拟器
4. 真机验证一轮

如果这 4 步顺利，基本就从“源码可用”进入“App 可装可用”。

---

## 建议的最后交付路径

### 阶段 1：源码闭环
- [x] 设置页
- [x] 远端持久化
- [x] 录音上传
- [x] 训练语音复述
- [x] 录音试听
- [x] 结果分享 / 复制
- [x] 灵感归档
- [x] 报告
- [x] 宿主 Xcode 工程骨架

### 阶段 2：可安装包
- [ ] 在 Mac 上打开工程并完成首次编译
- [ ] 真机跑通一轮完整录音
- [ ] 修弱网 / 权限 / 空态问题
- [ ] 用个人签名先装到自己的手机

### 阶段 3：给别人使用
- [ ] 切 HTTPS 正式后端
- [ ] 稳定化日志 / 崩溃 / 限流
- [ ] Apple Developer / TestFlight
- [ ] 隐私政策与上架材料

---

## 结论

当前这份 iOS 目录，已经从“SwiftUI 骨架 Demo”推进到：

**一份带 Xcode 宿主工程、可录音、可联后端、可做真实训练闭环的 iPhone 客户端工程。**

下一步不是再空想 UI，而是：
**拿到 Mac，打开 Xcode，跑模拟器，真机装起来。**
