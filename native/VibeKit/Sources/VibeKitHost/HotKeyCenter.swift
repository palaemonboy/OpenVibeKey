// HotKeyCenter.swift — Carbon 全局热键的最小封装。
//
// 为什么是 Carbon 而不是输入监控（设计文档 §3.1）：
//   · RegisterEventHotKey 不需要任何 TCC 权限
//   · 更关键——命中时系统会「消费掉」这一下按键，前台 App 不会同时收到。
//     NSEvent/IOHIDManager 的监控类 API 拿到的是事件副本，事件照常下发，
//     用它就意味着「按一下切到 iTerm2，同时正在编辑的文档也收到一次按键」。
//   · 代价是认不出按键来自哪台设备。靠哨兵组合足够罕见来规避。
//
// 线程约定：只在主线程调用。Carbon 事件回调本身就在主 run loop 上派发，
// 内部不加锁；跨线程调用会撕裂 handlers 字典。
import AppKit
import Carbon.HIToolbox
import Foundation

public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    private struct Entry {
        let ref: EventHotKeyRef
        let carbonID: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
        let handler: () -> Void
    }

    private var entries: [String: Entry] = [:]
    private var nextCarbonID: UInt32 = 1
    private var handlerInstalled = false

    private init() {}

    public var registeredIDs: [String] { Array(entries.keys) }
    public func isRegistered(_ id: String) -> Bool { entries[id] != nil }

    /// 注册一个全局热键。
    /// - Returns: 是否注册成功。
    ///
    /// 同一个 id 换绑组合时，**先确认新组合能注册上，再释放旧的**——
    /// 换绑失败（新组合无效或被占用）不得摧毁这个 id 原本还在正常工作的热键，
    /// 调用方（哨兵池换槽逻辑）依赖"换绑失败 = 原键盘快捷键原样保留"。
    /// 新组合和旧组合相同则只换 handler，不碰 Carbon——否则旧 ref 还占着这个组合，
    /// `RegisterEventHotKey` 会返回 `eventHotKeyExistsErr`，把一次合法的同组合重注册误判成失败。
    /// 全新 id 的组合被**本进程别的 id** 占用时返回 false，且不留下任何痕迹。
    ///
    /// 注意它**检测不到别的进程**：RegisterEventHotKey 只在同一进程内重复注册时才返回
    /// eventHotKeyExistsErr，跨进程注册同一个组合两边都会成功。2026-09-05 实测——两个
    /// 独立进程用相同键码/修饰键/GetApplicationEventTarget() 先后注册 ⌃⌥⌘F9，都返回
    /// noErr。所以「别的软件抢了这个组合」这件事，这里返回 true，上层无从知晓。
    @discardableResult
    public func register(tokens: [String], id: String, handler: @escaping () -> Void) -> Bool {
        guard let spec = Self.carbonSpec(tokens) else { return false }   // 无效 tokens：不碰已有条目

        if let existing = entries[id], existing.keyCode == spec.keyCode, existing.modifiers == spec.modifiers {
            // 同 id 同组合重注册：只是换个 handler，Carbon 那边的注册原样保留。
            entries[id] = Entry(ref: existing.ref, carbonID: existing.carbonID,
                                 keyCode: existing.keyCode, modifiers: existing.modifiers, handler: handler)
            return true
        }

        installHandlerIfNeeded()
        let carbonID = nextCarbonID
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: Self.signature, id: carbonID)
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &ref)
        // eventHotKeyExistsErr(-9878) 是「组合已被占用」的正常结果，不是异常。
        // 新注册没成功之前绝不碰旧条目——保证换绑失败时旧热键继续有效。
        guard status == noErr, let ref else { return false }

        nextCarbonID &+= 1
        if let old = entries[id] {
            UnregisterEventHotKey(old.ref)   // 新的已经注册成功，才轮到释放旧的
        }
        entries[id] = Entry(ref: ref, carbonID: carbonID, keyCode: spec.keyCode, modifiers: spec.modifiers, handler: handler)
        return true
    }

    public func unregister(_ id: String) {
        guard let e = entries.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(e.ref)
    }

    public func unregisterAll() {
        // 先把 key 拷成数组再遍历：unregister 会改 entries。
        // 值语义 + COW 让直接遍历 entries.keys 目前也不会崩，但那是「恰好没事」，
        // 读起来是一处边遍历边改集合的错误，不留给后人去赌。
        for id in Array(entries.keys) { unregister(id) }
    }

    // MARK: 内部

    /// 四字符签名 "VBKY"，用于区分本 App 注册的热键。
    private static let signature: OSType = {
        var v: OSType = 0
        for b in Array("VBKY".utf8) { v = (v << 8) | OSType(b) }
        return v
    }()

    /// token → Carbon 虚拟键码与修饰位。
    /// 注意这是**另一套编码**：VibeKitKeymap 给的是设备用的 HID usage，
    /// Carbon 要的是 macOS 虚拟键码（kVK_*），两者不能混用。
    /// 只需覆盖哨兵池用得到的键（SentinelPool.modifiers + SentinelPool.mainKeys）。
    private static let keyCodes: [String: UInt32] = [
        "F9": UInt32(kVK_F9), "F10": UInt32(kVK_F10), "F11": UInt32(kVK_F11), "F12": UInt32(kVK_F12),
        "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9),
        "0": UInt32(kVK_ANSI_0),
    ]
    private static let modifierBits: [String: UInt32] = [
        "LCtrl": UInt32(controlKey), "LOpt": UInt32(optionKey),
        "LCmd": UInt32(cmdKey), "LShift": UInt32(shiftKey),
    ]

    private static func carbonSpec(_ tokens: [String]) -> (keyCode: UInt32, modifiers: UInt32)? {
        var mods: UInt32 = 0
        var main: UInt32?
        for t in tokens {
            if let m = modifierBits[t] { mods |= m; continue }
            guard main == nil, let k = keyCodes[t] else { return nil }   // 两个主键或未知键都拒绝
            main = k
        }
        guard let main else { return nil }   // 只有修饰键，注册不了
        return (main, mods)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            let st = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID), nil,
                                       MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            guard st == noErr else { return st }
            HotKeyCenter.shared.fire(hkID.id)
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Carbon 回调派发在主 run loop 上，直接查表调用即可。
    private func fire(_ carbonID: UInt32) {
        entries.values.first { $0.carbonID == carbonID }?.handler()
    }
}
