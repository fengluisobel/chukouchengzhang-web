# 出口成章 iOS App｜Mac 首次编译手册

目标：把 `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/` 拿到 Mac 后，尽快在 Xcode 里跑起第一版。

## 一、先准备什么

### 必需
- 一台 Mac
- Xcode（建议最新版稳定版）
- 一个 Apple ID

### 可选但推荐
- 一台 iPhone（真机验证录音、局域网访问、本地服务）
- Node.js 22+（如果要在 Mac 上同时跑后端）

---

## 二、把哪个目录拿到 Mac

如果你只是想先编译、跑 Mock、看 UI，把这个目录拿过去就够：

- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/`

如果你想在 Mac 上直接跑完整“录音 → 转写 → 优化 → 训练”闭环，还要把同级后端目录一起拿过去：

- `/home/gem/workspace/agent/workspace/projects/出口成章/app/`

最省事的做法是在原环境先进入 `ios-app/` 目录，再执行：

```bash
bash scripts/package-mac-handoff.sh
```

它会把 `ios-app + app` 一起打成一个 Mac 交接包。

如果这轮不是自己现打，而是直接拿现成完整包去 Mac，当前最新完整交接包是：
- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/dist/chukouchengzhang-mac-handoff-20260420-100846.tar.gz`
- 对应校验文件：`/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/dist/chukouchengzhang-mac-handoff-20260420-100846.tar.gz.sha256`

关键工程文件是：

- `/home/gem/workspace/agent/workspace/projects/出口成章/ios-app/ChuKouChengZhang.xcodeproj`

---

## 三、第一次打开工程前，先跑一遍自动首编脚本（推荐）

现在最短路径已经不是手动点一堆命令，而是先进入解压后的 `ios-app/` 目录，再在 Mac 终端执行：

```bash
bash scripts/mac-env-check.sh

bash scripts/mac-first-run.sh \
  --team 你的TEAMID \
  --bundle-id 你的.bundle.id
```

它会自动串起来做：
1. `scripts/mac-env-check.sh` 先查 Xcode / xcrun / python3 / Node / npm 是否齐，并把结果写到 `build/mac-env-check.log`
2. `scripts/check-ios-project.sh` 静态校验
3. 如果同级 `app/` 也带到了 Mac，会先跑一次 `scripts/handoff-backend.sh verify`（`npm test + smoke-flow`；除覆盖 `transcribe / create / train / archive / report` 写链路外，还会回读 `transcripts / training / ideas` 列表与 `bootstrap / reports-daily` 契约，并顺手校验 iOS 依赖字段）；如果你只带了 `ios-app`，它会自动跳过这一步，不会再误报失败
4. 调 `scripts/configure-signing.sh` 写入 Team / Bundle Identifier（以及可选正式服地址）
5. 调 `scripts/xcodebuild-smoke.sh` 做一次模拟器编译烟测，并生成 `.xcresult` 结果包

如果你暂时不想写签名，也可以先跑：

```bash
bash scripts/mac-first-run.sh --skip-signing
```

如果你希望在这条“一把串完”的主路径里，也把 `mac-env-check.sh` 里的 WARN 一并当成阻断项，不必先手动单独跑 `bash scripts/mac-env-check.sh --strict`，可以直接改用：

```bash
bash scripts/mac-first-run.sh --strict-env-check \
  --team 你的TEAMID \
  --bundle-id 你的.bundle.id
```

如果你想手动指定后端检查强度，`--backend-check` 现在只接受这些值：
- `auto`：默认；检测到同级 `app/` 就跑 `verify`，否则自动跳过，适合只带 `ios-app` 先首编 / Mock
- `smoke`：做 `provider/status + bootstrap + health + reports/daily` 轻量烟测，并顺手校验报告页关键字段
- `smoke-flow`：跑 transcribe / create / train / archive / report 全链路烟测
- `test`：只跑同级 `app/` 的 `npm test`
- `verify`：先跑 `npm test`，再跑 `smoke-flow`；除 `transcribe / create / train / archive / report` 写链路外，还会回读 `transcripts / training / ideas` 列表与 `bootstrap / reports-daily` 契约，并顺手校验 iOS 依赖字段
- `skip`：显式跳过后端检查（等价于 `--skip-backend`）

如果把值拼错，脚本现在会在入口直接报错，不会等跑到半程才失败。

---

## 四、第一次打开工程（手动路径）

1. 双击 `ChuKouChengZhang.xcodeproj`
2. 等 Xcode 完成索引
3. 左上角选中 target：`ChuKouChengZhang`
4. 打开 `Signing & Capabilities`
5. 在 `Team` 里选择你的 Apple ID 对应 Team

如果你想少点手改，也可以先在终端一把写进去：

```bash
bash scripts/configure-signing.sh \
  --team 你的TEAMID \
  --bundle-id 你的.bundle.id
```

如果是第一次用个人 Apple ID：
- Xcode → Settings → Accounts
- 登录 Apple ID
- 回到工程再选 Team

---

## 五、先跑模拟器

### 先检查这几个设置
- Bundle Identifier 不要和别的工程冲突
  - 默认现在是：`ai.openclaw.chukouchengzhang`
  - 如果冲突，可改成你自己的，比如：`com.keke.chukouchengzhang`
- Deployment Target 当前是 iOS 16.0

### 先做一次命令行烟测（推荐）
如果你还没跑过环境预检，先执行：

```bash
bash scripts/mac-env-check.sh
```

然后在 Mac 终端执行：

```bash
bash scripts/xcodebuild-smoke.sh
```

默认会先做工程预检，再优先自动挑一台当前可用的 iPhone Simulator；如果当前没挑到可用设备，才回退到 `generic/platform=iOS Simulator`，并把实际来源打印到 `destinationSource`。随后再走一次 `xcodebuild` 的 Debug 模拟器编译，并产出：

- `build/xcodebuild-smoke.log`
- `build/xcodebuild-smoke.xcresult`

如果这里失败，优先把这两个产物连同 `build/mac-env-check.log` 一起拿去排障，定位会比口述报错快得多。

### 跑法
1. 设备选 `iPhone 16` 或任一 iPhone Simulator
2. 点运行（⌘R）

### 模拟器阶段预期
- App 能启动
- 首页 / 设置 / 录音页 / 训练页 / 报告页能进
- Mock 模式应可直接使用
- 远端模式如果后端没开，会提示连接失败，但 App 不应崩

---

## 六、如果要联调后端

后端目录：

- `/home/gem/workspace/agent/workspace/projects/出口成章/app/`

如果你拿的是最新 Mac 交接包，最省事的启动方式已经变成：

```bash
bash scripts/handoff-backend.sh verify
```

它会从 `ios-app` 目录侧自动定位同级 `app/`，先跑 `npm test`，再跑一轮隔离的 `smoke-flow`，把 iOS 依赖的关键接口字段也顺手验掉。若你只想先拉起服务再轻量探活，也可以：

```bash
bash scripts/handoff-backend.sh start
bash scripts/handoff-backend.sh smoke
```

如果你更想直接进后端目录，也可以：

```bash
cd ../app
bash scripts/start.sh
```

默认地址：

- `http://127.0.0.1:4321`

> 顺手补的一个真实交接坑：`app/scripts/start.sh` / `status.sh` / `stop.sh` 现在已经改成相对路径解析，不再写死 Linux 工作区绝对路径；所以把交接包放到任意 Mac 目录后，上面的命令仍然能直接跑。

### 模拟器联调
设置页里填：

- `http://127.0.0.1:4321`

### 真机联调
不能用 `127.0.0.1`，要填 Mac 的局域网 IP。现在可以先在 Mac 上直接算：

```bash
bash scripts/resolve-local-ip.sh
```

它会输出候选地址，比如：

- `http://192.168.1.23:4321`

然后在 App 设置页里：
1. 开启远端 API
2. 填局域网地址
3. 点“测试连接”
4. 点“保存并连接”

---

## 七、真机安装

### 没有 Apple Developer 付费账号也能做
可以用个人 Apple ID（Personal Team）先装到你自己的 iPhone。

### 真机步骤
1. iPhone 用数据线连 Mac
2. iPhone 上信任这台电脑
3. Xcode 设备列表里选你的 iPhone
4. target 的 Signing 里选 Team
5. 点运行（⌘R）

### 第一次可能遇到
- iPhone 上需要允许开发者模式
- iPhone 上需要信任开发证书
- Xcode 可能要求唯一 Bundle Identifier

---

## 八、首次真机验证要测什么

按这个顺序测：

1. App 能打开
2. 设置页能打开
3. Mock 模式能生成结果
4. 麦克风权限弹窗正常
5. 录音开始 / 停止正常
6. 试听录音正常
7. 若后端已开：
   - 测试连接成功
   - 录音上传成功
   - 返回优化稿成功
   - 训练评分成功
   - 归档到灵感库成功

---

## 九、现在最可能的剩余问题

### 1. 签名问题
表现：Xcode 报 signing / provisioning profile 错

处理：
- 选 Team
- 换唯一 Bundle Identifier
- 清理构建后重试（Shift+⌘+K）

### 2. 真机访问不到本地后端
表现：设置页测试连接失败

处理：
- 确认 Mac 上 `npm start` 正在运行
- 确认 iPhone 和 Mac 在同一局域网
- 用 Mac 的局域网 IP，不要用 `127.0.0.1`
- 确认系统防火墙没有拦截 Node 端口 4321

### 3. 麦克风权限问题
表现：录音按钮点了没反应或权限被拒

处理：
- iPhone 设置 → App → 麦克风
- 或删除 App 后重装重新触发权限弹窗

---

## 十、什么叫“已经可用”

对这个项目来说，当前“可用”的标准不是上架，而是：

- 能在 iPhone 上正常安装
- 能录音
- 能生成转写 / 优化稿
- 能做训练评分
- 能完成一次完整闭环

做到这一步，就已经是“自己能用的 iOS App”。

---

## 十一、当前一句实话

现在这份工程，已经很接近：

**拿到 Mac → 打开 Xcode → 处理签名 → 跑起来**

真正还没在当前环境做完的，只剩 Xcode / iPhone 这一步，因为这里不是 macOS，没法替你真的点下编译按钮。
