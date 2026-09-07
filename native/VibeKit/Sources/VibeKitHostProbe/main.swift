// VibeKitHostProbe — 主机侧动作单元的可执行 runner。
// 本机是 Command Line Tools 环境，没有 XCTest/Testing，故沿用 VibeKitOracle 的路子：
// 用可执行文件跑断言，任一不符即打印并以非零码退出。
//
// 用法：
//   swift run VibeKitHostProbe          跑全部自动断言
import AppKit
import Foundation
import VibeKitHost

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { print("  ✅ \(name)") }
    else { print("  ❌ \(name)  \(detail)"); failures += 1 }
}

// 人工模式：跑在自动断言之前，用完直接退出。
if CommandLine.arguments.contains("--list") {
    let apps = InstalledApps.scan()
    print("枚举到 \(apps.count) 个 App：")
    for a in apps { print("  \(a.name)  [\(a.bundleID)]  \(a.url.path)") }
    exit(0)
}
if let i = CommandLine.arguments.firstIndex(of: "--activate"), i + 1 < CommandLine.arguments.count {
    let bid = CommandLine.arguments[i + 1]
    do {
        try AppLauncher.activate(bundleID: bid)
        // openApplication 是异步 XPC 调用；probe 是一次性 CLI 进程，
        // 打印完就 exit 的话，进程会在请求真正送达前被杀掉（实测验证过这个坑）。
        // 这里用短切片跑 run loop，边转边轮询目标是否已变前台，
        // 一旦确认就立刻退出，不做无谓的整段等待；总超时约 3 秒防止卡死。
        let deadline = Date().addingTimeInterval(3.0)
        var didActivate = false
        while Date() < deadline {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first,
               running.isActive {
                didActivate = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        if didActivate {
            print("已激活 \(bid)，确认已置于前台")
            exit(0)
        } else {
            print("已请求激活 \(bid)，但超时内未观察到其进入前台")
            exit(1)
        }
    }
    catch { print("激活失败：\(error)"); exit(1) }
}

print("== SentinelPool ==")
check("池 14 个组合", SentinelPool.all.count == 14, "got \(SentinelPool.all.count)")
check("主键无重复", Set(SentinelPool.mainKeys).count == SentinelPool.mainKeys.count)
check("首个是 F9", SentinelPool.all.first?.mainKey == "F9")
check("末个是 0", SentinelPool.all.last?.mainKey == "0")
check("F9 tokens", SentinelCombo(mainKey: "F9").tokens == ["LCtrl", "LOpt", "LCmd", "F9"])
check("F9 display = ⌃⌥⌘F9", SentinelCombo(mainKey: "F9").display == "⌃⌥⌘F9",
      "got \(SentinelCombo(mainKey: "F9").display)")
check("组合长度 4，正好压设备上限", SentinelCombo(mainKey: "F9").tokens.count == 4)

print("== SentinelPool.allocate ==")
check("空池全可注册 → F9",
      SentinelPool.allocate(taken: [], isRegistrable: { _ in true })?.mainKey == "F9")
check("F9 被别的槽占 → F10",
      SentinelPool.allocate(taken: ["F9"], isRegistrable: { _ in true })?.mainKey == "F10")
check("F9 注册不上 → F10",
      SentinelPool.allocate(taken: [], isRegistrable: { $0.mainKey != "F9" })?.mainKey == "F10")
check("占用与注册失败叠加 → F11",
      SentinelPool.allocate(taken: ["F10"], isRegistrable: { $0.mainKey != "F9" })?.mainKey == "F11")
check("F 键全废 → 落到数字 1",
      SentinelPool.allocate(taken: [], isRegistrable: { !$0.mainKey.hasPrefix("F") })?.mainKey == "1")
check("池耗尽（全被占） → nil",
      SentinelPool.allocate(taken: Set(SentinelPool.mainKeys), isRegistrable: { _ in true }) == nil)
check("池耗尽（全注册不上） → nil",
      SentinelPool.allocate(taken: [], isRegistrable: { _ in false }) == nil)
// 只试到第一个成功者为止——否则真机上会留下一串没人用的已注册热键
do {
    var tried: [String] = []
    _ = SentinelPool.allocate(taken: [], isRegistrable: { tried.append($0.mainKey); return $0.mainKey == "F11" })
    check("试到第一个成功者即停", tried == ["F9", "F10", "F11"], "got \(tried)")
}

print("== AppBinding ==")
do {
    let b = AppBinding(bundleID: "com.googlecode.iterm2", displayName: "iTerm",
                       sentinelTokens: ["LCtrl", "LOpt", "LCmd", "F9"])
    let data = (try? JSONEncoder().encode(b)) ?? Data()
    check("Codable 往返", (try? JSONDecoder().decode(AppBinding.self, from: data)) == b)
    check("sentinelMainKey = F9", b.sentinelMainKey == "F9")
    check("sentinelDisplay = ⌃⌥⌘F9", b.sentinelDisplay == "⌃⌥⌘F9")
    let broken = AppBinding(bundleID: "x", displayName: "x", sentinelTokens: [])
    check("空 tokens → sentinelMainKey 为 nil，不崩", broken.sentinelMainKey == nil)
    let modsOnly = AppBinding(bundleID: "x", displayName: "x", sentinelTokens: ["LCtrl", "LOpt", "LCmd"])
    check("只有修饰键 → sentinelMainKey 为 nil", modsOnly.sentinelMainKey == nil)

    // 写设备的字节序只有一份真相：SentinelPool.modifiers 的顺序，Oracle 里逐字节钉死的
    // 也是它（83 01 / 83 04 / 83 08 = LCtrl/LOpt/LCmd）。存档里那份 ButtonState.tokens 镜像
    // 会按 UI 的 MODS 顺序（LCmd,LOpt,LShift,LCtrl）重排，同一个逻辑组合就有了两种字节序列。
    // applyProfile 必须写 sentinelTokens 而不是那份镜像——这条断言把「哪一份是真相」钉住。
    check("哨兵 tokens 就是池的规范顺序", b.sentinelTokens == SentinelCombo(mainKey: "F9").tokens)
    check("规范顺序确实是 LCtrl,LOpt,LCmd", SentinelPool.modifiers == ["LCtrl", "LOpt", "LCmd"])
    let uiMirrorOrder = ["LCmd", "LOpt", "LCtrl", "F9"]   // ButtonState.tokens 会重排成这样
    check("UI 镜像顺序与规范顺序确实不同（所以不能拿它写设备）",
          uiMirrorOrder != b.sentinelTokens)
}

print("== SentinelBookkeeping.slotsLosingBinding ==")
do {
    let order = ["btn1", "btn2", "btn3", "dialP"]
    func bind(_ n: String, _ mk: String) -> AppBinding {
        AppBinding(bundleID: "com.example.\(n)", displayName: n, sentinelTokens: SentinelCombo(mainKey: mk).tokens)
    }
    let a: [String: AppBinding] = ["btn1": bind("iTerm", "F9"), "dialP": bind("Safari", "F10")]
    check("切到什么都没配的配置 → 两个槽都要清",
          SentinelBookkeeping.slotsLosingBinding(previous: a, next: [:], order: order) == ["btn1", "dialP"])
    check("切回同一份 → 一个都不用清",
          SentinelBookkeeping.slotsLosingBinding(previous: a, next: a, order: order).isEmpty)
    check("只丢一个 → 只报那一个",
          SentinelBookkeeping.slotsLosingBinding(previous: a, next: ["btn1": bind("iTerm", "F9")], order: order) == ["dialP"])
    check("新增绑定不算丢",
          SentinelBookkeeping.slotsLosingBinding(previous: [:], next: a, order: order).isEmpty)
    check("换个 App 仍是绑着，不算丢",
          SentinelBookkeeping.slotsLosingBinding(previous: a, next: ["btn1": bind("Xcode", "F9"), "dialP": bind("Safari", "F10")],
                                                 order: order).isEmpty)
    check("结果按 order 排，不随字典迭代顺序变",
          SentinelBookkeeping.slotsLosingBinding(
            previous: ["dialP": bind("A", "F9"), "btn3": bind("B", "F10"), "btn1": bind("C", "F11")],
            next: [:], order: order) == ["btn1", "btn3", "dialP"])
    check("不在 order 里的槽（dialL 之类）不会被带进来",
          SentinelBookkeeping.slotsLosingBinding(previous: ["dialL": bind("A", "F9")], next: [:], order: order).isEmpty)
}

print("== SentinelBookkeeping.drainPlan ==")
do {
    let order = ["btn1", "btn2", "btn3", "dialP"]
    let p1 = SentinelBookkeeping.drainPlan(pending: ["btn1", "dialP"], order: order, isVacant: { _ in true })
    check("全空着 → 全清，且按 order 排", p1.clear == ["btn1", "dialP"])
    check("一次 drain 把整本账结清", p1.settled == ["btn1", "dialP"])

    // 记账之后槽位被别的东西占了（重新绑 App / 配了媒体键 / 新配置写了普通快捷键）：
    // 只销账，不能写空——否则把刚落地的配置抹掉。
    let p2 = SentinelBookkeeping.drainPlan(pending: ["btn1", "btn2"], order: order, isVacant: { $0 != "btn1" })
    check("被占住的槽不清", p2.clear == ["btn2"])
    check("被占住的槽照样销账", p2.settled == ["btn1", "btn2"])

    let p3 = SentinelBookkeeping.drainPlan(pending: [], order: order, isVacant: { _ in true })
    check("空账 → 无事可做", p3.clear.isEmpty && p3.settled.isEmpty)
    let p4 = SentinelBookkeeping.drainPlan(pending: ["dialL"], order: order, isVacant: { _ in true })
    check("不在 order 里的槽不会被清（但仍会被销账，不至于永远挂着）",
          p4.clear.isEmpty && p4.settled == ["dialL"])
}

print("== InstalledApps ==")
do {
    let apps = InstalledApps.scan()
    check("能枚举到 App（>10 个）", apps.count > 10, "got \(apps.count)")
    check("bundleID 无重复", Set(apps.map(\.bundleID)).count == apps.count)
    check("按名称升序", apps.map(\.name) == apps.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    check("没有空名字/ 空 bundleID", apps.allSatisfy { !$0.name.isEmpty && !$0.bundleID.isEmpty })
    // 系统 App 必然在 /System/Applications 下，扫不到说明目录清单漏了
    check("含「访达」(com.apple.finder)", apps.contains { $0.bundleID == "com.apple.finder" },
          "扫描目录清单可能漏了 /System/Library/CoreServices")
    check("含「文本编辑」(com.apple.TextEdit)", apps.contains { $0.bundleID == "com.apple.TextEdit" })
    check("id 就是 bundleID", apps.allSatisfy { $0.id == $0.bundleID })

    // 从路径解析单个 App（「从文件选择…」兜底走这条）
    let te = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    check("app(at:) 解析文本编辑", InstalledApps.app(at: te)?.bundleID == "com.apple.TextEdit")
    check("app(at:) 对非 App 路径返回 nil", InstalledApps.app(at: URL(fileURLWithPath: "/etc/hosts")) == nil)

    // 回归用例：名字中间本身就带 ".app" 子串时，只能砍掉末尾真正的扩展名。
    // 旧实现用 replacingOccurrences(of: ".app", with: "") 会把中间那段也吃掉，
    // 把「Snapshot.app Manager」错改成「Snapshot Manager」——现场造一个这样命名的
    // fixture bundle，跑完就删，不依赖真机上恰好有这种怪名字的 App。
    do {
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeKitHostProbeFixture-\(UUID().uuidString)")
        let appURL = fixtureRoot.appendingPathComponent("Snapshot.app Manager.app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        try? FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>com.example.snapshotmanager.probe</string>
        </dict>
        </plist>
        """
        try? plist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let parsed = InstalledApps.app(at: appURL)
        check("名字中间带 .app 子串时只砍末尾扩展名，不误删中间那段",
              parsed?.name == "Snapshot.app Manager", "got \(String(describing: parsed?.name))")
        try? FileManager.default.removeItem(at: fixtureRoot)
    }
}

print("== AppLauncher ==")
do {
    var threw: AppLauncherError?
    do { try AppLauncher.activate(bundleID: "com.example.绝对不存在的应用") }
    catch { threw = error as? AppLauncherError }
    check("不存在的 bundleID 抛 notFound", threw == .notFound("com.example.绝对不存在的应用"), "got \(String(describing: threw))")
    // 存在的 App 不抛错。这里不真去激活——自动跑的时候不该抢用户焦点，
    // 「按下真能跳过去」由 --activate 与真机验收负责。
    check("已安装 App 能解析出路径", NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") != nil)
}

print("== HotKeyCenter ==")
do {
    // RegisterEventHotKey 要求进程是 UI 进程才拿得到 application event target。
    // .prohibited 表示「不进 Dock、不抢焦点」，足够让 Carbon 事件管理器初始化。
    NSApplication.shared.setActivationPolicy(.prohibited)

    let c = HotKeyCenter.shared
    c.unregisterAll()
    check("起点无注册", c.registeredIDs.isEmpty, "got \(c.registeredIDs)")

    // 用池里靠后的组合做测试，尽量不撞上用户真在用的键
    let a = SentinelCombo(mainKey: "9")
    let b = SentinelCombo(mainKey: "0")
    let okA = c.register(tokens: a.tokens, id: "probeA") {}
    check("注册 \(a.display) 成功", okA)
    check("isRegistered(probeA)", c.isRegistered("probeA"))

    // 同一组合再注册（换个 id）必须失败——这正是「被占用则换池中下一个」的触发条件
    let dup = c.register(tokens: a.tokens, id: "probeDup") {}
    check("同组合重复注册返回 false", !dup)
    check("失败的注册不留痕", !c.isRegistered("probeDup"))

    // 同一 id 换组合 = 先注销旧的再注册新的
    let okRebind = c.register(tokens: b.tokens, id: "probeA") {}
    check("同 id 换组合成功", okRebind)
    check("换绑后旧组合被释放（别的 id 能占上）", c.register(tokens: a.tokens, id: "probeB", handler: {}))

    // 未知 token 不得崩溃，只返回 false
    check("未知 token → false", !c.register(tokens: ["LCtrl", "不存在的键"], id: "probeBad", handler: {}))
    check("空 tokens → false", !c.register(tokens: [], id: "probeEmpty", handler: {}))
    check("只有修饰键 → false", !c.register(tokens: ["LCtrl", "LOpt", "LCmd"], id: "probeModsOnly", handler: {}))

    // 换绑失败不得摧毁同 id 原有的、还在正常工作的注册（回归用例）
    let keepCombo = SentinelCombo(mainKey: "8")
    let otherCombo = SentinelCombo(mainKey: "7")
    check("probeKeep 先注册成功", c.register(tokens: keepCombo.tokens, id: "probeKeep", handler: {}))
    check("probeOther 占住另一个组合", c.register(tokens: otherCombo.tokens, id: "probeOther", handler: {}))

    check("换绑到无效 token 失败", !c.register(tokens: ["LCtrl", "不存在的键"], id: "probeKeep", handler: {}))
    check("换绑失败（无效 token）后 probeKeep 原组合原样保留", c.isRegistered("probeKeep"))

    check("换绑到被别的 id 占用的组合失败", !c.register(tokens: otherCombo.tokens, id: "probeKeep", handler: {}))
    check("换绑失败（组合被占）后 probeKeep 原组合原样保留", c.isRegistered("probeKeep"))

    // 陷阱用例：换绑到自己当前就持有的那个组合——旧 ref 还占着它，
    // RegisterEventHotKey 会报 eventHotKeyExistsErr，必须特判为成功而非失败
    check("换绑到相同组合成功（陷阱用例）", c.register(tokens: keepCombo.tokens, id: "probeKeep", handler: {}))
    check("换绑到相同组合后仍注册着", c.isRegistered("probeKeep"))

    c.unregister("probeKeep"); c.unregister("probeOther")

    c.unregister("probeA"); c.unregister("probeB")
    check("注销后 isRegistered 为假", !c.isRegistered("probeA") && !c.isRegistered("probeB"))
    c.unregister("从未注册过的 id")   // 不得崩溃
    c.unregisterAll()
    check("unregisterAll 清空", c.registeredIDs.isEmpty, "got \(c.registeredIDs)")
}

print(String(repeating: "-", count: 40))
if failures == 0 { print("主机侧单元全部通过 ✅"); exit(0) }
else { print("失败 \(failures) 项 ❌"); exit(1) }
