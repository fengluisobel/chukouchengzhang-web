# 出口成章 iOS App｜Mac 编译失败排障

这份文档只做一件事：

**如果你把工程拿到 Mac，Xcode 没有一把过，这里告诉你先查哪几个点。**

## 0. 先说结论

如果你发现“Xcode 能开，但远端闭环根本跑不起来”，先别急着怪 iOS 工程——有一种很常见的交接坑是：**你只拿了 `ios-app`，却没把同级 `app/` 后端一起带到 Mac**。这一点现在已经补了两层保护：

- 如果还在原始工程环境，先进入 `ios-app/` 目录再执行：`bash scripts/package-mac-handoff.sh`
- `bash scripts/mac-env-check.sh`
- `bash scripts/mac-first-run.sh --team 你的TEAMID --bundle-id 你的.bundle.id`

前者会把 `ios-app + app` 一起打包；`mac-env-check.sh` 会先把 Xcode / xcrun / python3 / Node 这些首编依赖查一遍并落日志；`mac-first-run.sh` 会在 Mac 上把“环境预检 → 静态校验 → 若检测到同级 `app/` 则跑后端 verify（`npm test + smoke-flow`；除 `transcribe / create / train / archive / report` 写链路外，还会回读 `transcripts / training / ideas` 列表与 `bootstrap / reports-daily` 契约，并顺手校验 iOS 依赖字段），否则自动跳过 → 签名写入 → xcodebuild 烟测”串起来，避免刚接手就漏步骤，也避免只带 `ios-app` 时被误拦住。

另外，这轮还顺手修掉了另一个真实交接坑：`app/scripts/start.sh` / `status.sh` / `stop.sh` / `smoke-http-provider.sh` 之前写死了当前 Linux 工作区绝对路径，打到别的 Mac 目录会直接失效；现在都已改成相对路径解析，可随包搬走。

当前这份工程最可能卡住的不是业务逻辑，而是这几类：

1. 签名 / Team / Bundle Identifier
2. Xcode 首次索引或缓存脏了
3. 真机访问本地服务失败
4. 麦克风权限没开
5. Apple ID / Personal Team 限制

---

## 1. 报 Signing / Provisioning Profile 错

### 常见现象
- Signing for target requires a development team
- No profiles for xxx were found
- Failed to register bundle identifier

### 先做这三步
1. 打开 `Signing & Capabilities`
2. `Team` 选择你的 Apple ID 对应 Team
3. 确认 `Bundle Identifier` 是唯一的

如果你不想在 Xcode 里来回点，也可以直接跑自动首编脚本，或者单独用签名脚本：

```bash
bash scripts/mac-first-run.sh \
  --team 你的TEAMID \
  --bundle-id 你的.bundle.id
```

或者只改签名：

```bash
bash scripts/configure-signing.sh \
  --team 你的TEAMID \
  --bundle-id 你的.bundle.id
```

如果默认这个：
- `ai.openclaw.chukouchengzhang`

冲突了，就改成你自己的，例如：
- `com.keke.chukouchengzhang`
- `com.yourname.ckcz`

### 还不行就做
- `Product` → `Clean Build Folder`
- 关闭 Xcode，重新打开工程
- 再跑一次

---

## 2. 工程打开了，但编译不过

### 先排缓存
先看这 3 个产物：
- `build/mac-env-check.log`
- `build/xcodebuild-smoke.log`
- `build/xcodebuild-smoke.xcresult`

然后执行：
- `Product` → `Clean Build Folder`
- 或终端先按顺序跑一遍：
  ```bash
  bash scripts/mac-env-check.sh
  bash scripts/xcodebuild-smoke.sh
  ```
- 再删 DerivedData

DerivedData 通常在：
- `~/Library/Developer/Xcode/DerivedData/`

删掉对应目录后重开 Xcode。

### 再确认
- Xcode 版本别太老
- iOS Deployment Target 当前是 16.0
- Scheme 选的是 `ChuKouChengZhang`

---

## 3. 模拟器能开，但远端 API 连不上

### 先确认后端是否启动
优先用最新交接包里的统一入口：

```bash
bash scripts/handoff-backend.sh verify
```

它会先做 `npm test`，再跑隔离的 `smoke-flow`（除覆盖 `transcribe / create / train / archive / report` 写链路外，还会回读 `transcripts / training / ideas` 列表与 `bootstrap / reports-daily` 契约，并顺手校验 iOS 客户端依赖字段），比只看 health 更容易提前发现接口契约漂移。

如果你只想先拉起服务再轻量探活，也可以：

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

### 模拟器正确地址
- `http://127.0.0.1:4321`

### 真机错误写法
- `http://127.0.0.1:4321`  ❌

### 真机正确写法
- `http://你的Mac局域网IP:4321`  ✅

现在可以先在 Mac 上直接算：

```bash
bash scripts/resolve-local-ip.sh
```

例如：
- `http://192.168.1.23:4321`

---

## 4. 真机测试连接失败

### 先查这 5 件事
1. Mac 上后端是否真的在跑
2. iPhone 和 Mac 是否同一 Wi‑Fi
3. 填的是不是 Mac 局域网 IP，而不是 127.0.0.1
4. macOS 防火墙有没有拦 Node
5. iPhone 是否允许局域网访问

### 你可以在 Mac 上先测
浏览器打开：
- `http://127.0.0.1:4321/api/bootstrap`

如果浏览器都打不开，先别怪 iPhone，先把后端修通。

---

## 5. 麦克风不能录音

### 常见现象
- 点录音没反应
- 权限弹窗没出来
- 一录就报错

### 先查
- iPhone 设置 → 目标 App → 麦克风是否开启
- 或删掉 App 重装，让权限弹窗重新出现

### 工程里已配
`Info.plist` 已经有：
- `NSMicrophoneUsageDescription`
- `NSLocalNetworkUsageDescription`
- 开发期 ATS 放开配置

所以如果录不了，优先查系统权限，不是先怀疑业务代码。

---

## 6. 真机能开 App，但上传录音失败

这类问题通常不是 UI，而是网络链路。

### 优先定位顺序
1. 先在设置页点“测试连接”
2. 测试连接失败 → 先修网络，不要先修录音
3. 测试连接成功但上传失败 → 再看后端日志

### 后端要看的接口
- `/api/provider/status`
- `/api/bootstrap`
- `/api/transcripts/create`
- `/api/transcribe`
- `/api/train/evaluate`

---

## 7. 个人 Apple ID 能不能装真机

能，但有边界。

### 可以
- 模拟器运行
- 自己手机本地安装调试
- 验证录音 / 网络 / 基本流程

### 不行或不稳定
- TestFlight
- App Store
- 稳定长期分发给多人

所以：
**先做出自己能用的版本，Personal Team 足够。**

---

## 8. 我建议的排障顺序

别乱试，按这个顺序：

1. 工程能不能打开
2. Team / Bundle Identifier 先配好
3. 模拟器能不能启动
4. Mock 模式能不能跑通
5. 后端能不能本机访问 `/api/bootstrap`
6. 模拟器远端模式能不能连通
7. 真机能不能安装
8. 真机能不能录音
9. 真机能不能上传和拿到结果

---

## 9. 如果只想尽快看到“它能用”

最快路径不是一上来就折腾真机，而是：

1. 先跑模拟器
2. 先跑 Mock 模式
3. 再接本地后端
4. 最后再上真机

这样出问题时定位最清楚。

---

## 10. 一句大实话

当前这份工程距离“真正可用”差的已经不是大重构，
而是 **Xcode 首编 + 签名 + 真机网络验证** 这最后一跳。

也正因为只剩这一跳，所以现在最该做的是：
**把 Mac 侧的失败路径提前想清楚，不要到时候边试边慌。**
