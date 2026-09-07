// VibeKitAudio.swift — macOS 音频：读/切系统默认输入设备 + 麦克风电平表。
// 判断"当前录音用的是 VibeKey 还是 MacBook 麦"，并为里程碑 4「语音切麦」铺路——该里程碑最终以组合方案达成（设备侧快捷键触发第三方听写 App +
/// 「插着时锁定为 AU05」承担切麦），未实现 ActionExecutor，见 design §里程碑 4 的 2026-09-05 修订。
import Foundation
import CoreAudio
import AVFoundation

public struct AudioInput: Identifiable, Sendable, Equatable {
    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    /// 传输类型短标签（"USB"/"内置"/"蓝牙"/"虚拟"/"其他"），查询失败给兜底文案，不影响设备本身可用。
    public let transport: String
    /// 标称采样率文案（如 "48 kHz"），查询失败给 "—"。
    public let sampleRateText: String
}

public enum VibeKitAudio {

    private static func addr(_ sel: AudioObjectPropertySelector,
                            _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// 当前系统默认输入设备 ID。
    public static func defaultInputID() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = addr(kAudioHardwarePropertyDefaultInputDevice)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return st == noErr ? id : nil
    }

    /// 设备名。
    public static func name(of dev: AudioDeviceID) -> String {
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var a = addr(kAudioObjectPropertyName)
        let st = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(dev, &a, 0, nil, &size, $0)
        }
        return st == noErr ? (name as String) : "未知设备"
    }

    /// 设备 UID（用于持久标识 VibeKey 麦）。
    public static func uid(of dev: AudioDeviceID) -> String {
        var uid: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        var a = addr(kAudioDevicePropertyDeviceUID)
        let st = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(dev, &a, 0, nil, &size, $0)
        }
        return st == noErr ? (uid as String) : ""
    }

    /// 读取输入设备的系统音量(增益) 0..1；主元素或声道 1 任一可读即可。查不到返回 nil。
    public static func inputVolume(_ dev: AudioDeviceID) -> Float? {
        for el: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioObjectPropertyScopeInput, mElement: el)
            if AudioObjectHasProperty(dev, &a) {
                var v = Float32(0); var size = UInt32(MemoryLayout<Float32>.size)
                if AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr { return v }
            }
        }
        return nil
    }
    /// 设置输入设备系统音量(增益) 0..1；主元素+两个声道都试，任一成功即 true。
    @discardableResult
    public static func setInputVolume(_ dev: AudioDeviceID, _ value: Float) -> Bool {
        var ok = false
        var v = Float32(max(0, min(1, value)))
        for el: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioObjectPropertyScopeInput, mElement: el)
            var settable = DarwinBoolean(false)
            if AudioObjectHasProperty(dev, &a),
               AudioObjectIsPropertySettable(dev, &a, &settable) == noErr, settable.boolValue,
               AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr {
                ok = true
            }
        }
        return ok
    }

    /// 该设备是否有输入声道。
    private static func hasInput(_ dev: AudioDeviceID) -> Bool {
        var a = addr(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr, size > 0 else { return false }
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, ptr) == noErr else { return false }
        let list = ptr.assumingMemoryBound(to: AudioBufferList.self)
        let bufs = UnsafeMutableAudioBufferListPointer(list)
        return bufs.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    /// 设备传输类型。
    private static func transportType(_ dev: AudioDeviceID) -> UInt32 {
        var t: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        var a = addr(kAudioDevicePropertyTransportType)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &t) == noErr ? t : 0
    }
    /// 是否进程内私有聚合设备（AVAudioEngine 等生成的 CADefaultDeviceAggregate-*，只对该进程可见，应从列表隐藏）。
    private static func isPrivateAggregate(_ dev: AudioDeviceID) -> Bool {
        guard transportType(dev) == kAudioDeviceTransportTypeAggregate else { return false }
        var a = addr(kAudioAggregateDevicePropertyComposition)
        var comp: CFDictionary?
        var size = UInt32(MemoryLayout<CFDictionary?>.size)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &comp) == noErr,
              let dict = comp as? [String: Any] else { return false }
        return (dict[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
    }

    /// 传输类型短标签，供菜单栏面板设备行副标题用。查询失败（transportType 返回 0）走 default 兜底，
    /// 不会导致调用方崩溃或把设备从列表里漏掉。
    private static func transportLabel(_ raw: UInt32) -> String {
        switch raw {
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeBuiltIn: return "内置"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "蓝牙"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return "虚拟"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeFireWire: return "FireWire"
        case kAudioDeviceTransportTypePCI: return "PCI"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        default: return "其他"
        }
    }

    /// 标称采样率（Hz）；查询失败返回 0。
    private static func nominalSampleRate(_ dev: AudioDeviceID) -> Double {
        var rate = Float64(0); var size = UInt32(MemoryLayout<Float64>.size)
        var a = addr(kAudioDevicePropertyNominalSampleRate)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &rate) == noErr ? Double(rate) : 0
    }
    /// "48 kHz" 形式的采样率文案；查不到给 "—" 兜底。
    private static func sampleRateText(_ dev: AudioDeviceID) -> String {
        let hz = nominalSampleRate(dev)
        return hz > 0 ? String(format: "%g kHz", hz / 1000) : "—"
    }

    /// 所有输入设备（过滤掉私有聚合设备）。
    public static func inputDevices() -> [AudioInput] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { hasInput($0) && !isPrivateAggregate($0) }
            .map { AudioInput(id: $0, name: name(of: $0), uid: uid(of: $0),
                               transport: transportLabel(transportType($0)),
                               sampleRateText: sampleRateText($0)) }
    }

    /// 当前默认输入设备（名字）。
    public static func currentInputName() -> String {
        guard let id = defaultInputID() else { return "（未知）" }
        return name(of: id)
    }

    /// 设为系统默认输入设备。macOS 输入只有唯一默认属性（"系统默认"只对输出存在）。
    @discardableResult
    public static func setDefaultInput(_ dev: AudioDeviceID) -> Bool {
        var d = dev
        var a = addr(kAudioHardwarePropertyDefaultInputDevice)
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, size, &d) == noErr
    }
}

/// 输入强制器：开启后监听默认输入变化与设备增减，自动把系统默认输入锁定为目标设备（如 AU05）。
/// 解决"保证录音默认走 VibeKey 麦"——被切走或设备插入时自动切回。
///
/// 匹配优先级：uid 精确匹配 > 名字子串包含匹配（回落，兼容老数据只有型号 token 如 "AU05" 的情况）。
/// 子串匹配存在"同名设备互相误锁"的风险（如 AirPods / AirPods Pro），uid 精确匹配没有这个问题，
/// 所以任何时候只要能拿到 uid 都优先用 uid；uid 为空或匹配不到时才退回名字子串匹配。
public final class InputEnforcer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.vibekit.audio.enforcer")
    private var targetUID: String?
    private var targetNameContains: String?
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    /// 当走名字回落路径命中、解析出真实 uid 时回调一次（uid 有变化才回调），
    /// 供上层把 uid 回写持久化，下次启动就能走精确匹配。可能在任意队列上触发，回调内部自己切线程。
    public var onResolvedUID: ((String) -> Void)?
    public init() {}

    private func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// 开始强制。uid 为空字符串表示没有已知 uid（老数据），此时纯走 nameContains 回落匹配。
    public func start(uid: String, nameContains: String) {
        stop()
        targetUID = uid.isEmpty ? nil : uid
        targetNameContains = nameContains
        for sel in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var a = addr(sel)
            // 防抖切回：唤醒/插拔时设备分批回来，延迟一下再切，且设备回来会再触发一次。
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleApply() }
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, block)
            listeners.append((a, block))
        }
        apply()
    }

    private var pending: DispatchWorkItem?
    private func scheduleApply(delay: TimeInterval = 0.25) {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.apply() }
        pending = w
        queue.asyncAfter(deadline: .now() + delay, execute: w)
    }

    public func stop() {
        pending?.cancel(); pending = nil
        for (var a, b) in listeners {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, b)
        }
        listeners = []; targetUID = nil; targetNameContains = nil
    }

    public var isEnforcing: Bool { targetUID != nil || targetNameContains != nil }

    private func apply() {
        let devices = VibeKitAudio.inputDevices()
        var target: AudioInput?
        if let uid = targetUID, !uid.isEmpty {
            target = devices.first(where: { $0.uid == uid })
        }
        if target == nil, let key = targetNameContains, !key.isEmpty,
           let byName = devices.first(where: { $0.name.localizedCaseInsensitiveContains(key) }) {
            target = byName
            // 名字回落路径命中：把解析出的真实 uid 记下并回调，下次直接走 uid 精确匹配。
            if targetUID != byName.uid {
                targetUID = byName.uid
                onResolvedUID?(byName.uid)
            }
        }
        guard let target else { return }
        if VibeKitAudio.defaultInputID() != target.id { _ = VibeKitAudio.setDefaultInput(target.id) }
    }
}

/// 麦克风电平表：AVAudioEngine 抓输入，输出 0…1 电平。需麦克风权限。
public final class MicMeter: ObservableObject {
    @Published public var level: Float = 0      // 0…1
    @Published public var running = false
    @Published public var permissionDenied = false
    @Published public var needsBundle = false   // swift run 无 Info.plist 麦克风用途，无法请求权限
    private let engine = AVAudioEngine()

    public init() {}

    public func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        // 无 NSMicrophoneUsageDescription 时请求权限会崩溃；仅在已授权、或有用途说明可安全请求时才继续。
        let hasUsage = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil
        if status == .authorized { beginTap(); return }
        guard hasUsage else { needsBundle = true; return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                if !granted { self.permissionDenied = true; return }
                self.beginTap()
            }
        }
    }

    private func beginTap() {
        let input = engine.inputNode
        let fmt = input.inputFormat(forBus: 0)
        guard fmt.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            guard let ch = buf.floatChannelData?[0] else { return }
            let n = Int(buf.frameLength)
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let rms = n > 0 ? sqrt(sum / Float(n)) : 0
            let level = min(1, rms * 6)  // 经验缩放
            DispatchQueue.main.async { self?.level = level }
        }
        do { try engine.start(); running = true } catch { running = false }
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false; level = 0
    }
}
