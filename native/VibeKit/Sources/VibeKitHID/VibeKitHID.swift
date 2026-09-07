// VibeKitHID.swift — IOKit IOHIDManager 打开 VibeKey 的 0x55 厂商接口，收发报文。
// 用 dispatch queue 驱动（IOHIDDeviceSetDispatchQueue + Activate），不占用主 run loop，
// 同时适配 CLI 与 SwiftUI GUI。收发流程等价网页 WebHID。
import Foundation
import IOKit
import IOKit.hid
import VibeKitCore

public enum VibeKitHIDError: Error {
    case notFound
    case openFailed(IOReturn)
    case sendFailed(IOReturn)
}

public final class VibeKitHID: @unchecked Sendable {
    public static let vendorID = 0xfff1
    public static let productID = 0x00dd
    public static let usagePage = 0xfffc
    public static let reportID: CFIndex = 0x55
    private static let bufSize = 64

    private var device: IOHIDDevice?
    private let queue = DispatchQueue(label: "com.vibekit.hid")
    private let inputBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
    private let lock = NSLock()
    private var received: [[UInt8]] = []   // 解密后明文(含4字节头)，lock 保护
    private var rawFrames: [(UInt32, [UInt8])] = []  // (reportID, 原始字节) 诊断用

    public init() {}
    deinit { inputBuf.deallocate() }
    public var isOpen: Bool { device != nil }

    /// 接收器（dongle）此刻还插在机器上吗——**只查 IOKit 注册表，不打开任何设备**。
    ///
    /// 为什么需要它：拔掉接收器后，我们手里那个 `IOHIDDevice` 引用不会变成 nil，
    /// `isOpen` 照样为真，只是每条命令都必败。而「命令失败」这一个现象同时对应
    /// 两种完全不同的处境——设备待机（接收器还在，转一下旋钮就回来）和接收器被拔了
    /// （必须重建整个 HID 会话）。光看命令结果分不开，必须直接问 IOKit。
    ///
    /// 刻意用 `IOServiceGetMatchingServices` 而不是再造一个 IOHIDManager：
    /// `IOHIDManagerOpen` 会把匹配到的设备一并打开，可能干扰本对象已经持有的会话。
    /// 这条路只读注册表属性，对现有会话零影响。
    public static func devicePresent() -> Bool {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOHIDDevice"), &iter) == KERN_SUCCESS,
              iter != 0 else { return false }
        defer { IOObjectRelease(iter) }
        var svc = IOIteratorNext(iter)
        while svc != 0 {
            defer { IOObjectRelease(svc); svc = IOIteratorNext(iter) }
            func prop(_ k: String) -> Int? {
                (IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber)?.intValue
            }
            if prop("VendorID") == vendorID, prop("ProductID") == productID { return true }
        }
        return false
    }

    public func open() throws {
        // 重连前先拆掉旧会话：拔插后会走到这里，而旧的 device 引用与输入回调还挂着，
        // 不拆就是一次泄漏，且旧回调可能往 received 里塞过期帧。
        close()
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: Self.vendorID,
            kIOHIDProductIDKey as String: Self.productID,
            kIOHIDPrimaryUsagePageKey as String: Self.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        var devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>
        if devices == nil || devices!.isEmpty {
            _ = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>
        }
        guard let dev = devices?.first else { throw VibeKitHIDError.notFound }
        let devOpen = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        guard devOpen == kIOReturnSuccess else { throw VibeKitHIDError.openFailed(devOpen) }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuf, Self.bufSize, { context, _, _, _, reportID, report, length in
            guard let context, length > 0 else { return }
            let me = Unmanaged<VibeKitHID>.fromOpaque(context).takeUnretainedValue()
            let cipher = Array(UnsafeBufferPointer(start: report, count: length))
            // 输入 buffer 首字节是 reportID(0x55)，剥掉再 TEA 解密。
            let body = (cipher.first == 0x55 && cipher.count > 1) ? Array(cipher.dropFirst()) : cipher
            let plain = VibeKitFrame.decodeVendorFrame(body)
            me.lock.lock()
            me.received.append(plain)
            me.rawFrames.append((reportID, cipher))
            me.lock.unlock()
        }, ctx)
        IOHIDDeviceSetDispatchQueue(dev, queue)
        IOHIDDeviceActivate(dev)
        self.device = dev
    }

    public func close() {
        if let dev = device { IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone)) }
        device = nil
    }

    /// 发送一帧密文。buffer 前置 reportID(0x55)——与输入侧对称，否则设备不响应。
    public func send(_ frame: [UInt8]) throws {
        guard let dev = device else { throw VibeKitHIDError.notFound }
        let buf: [UInt8] = [UInt8(Self.reportID)] + frame
        let ret = buf.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, Self.reportID, $0.baseAddress!, buf.count)
        }
        guard ret == kIOReturnSuccess else { throw VibeKitHIDError.sendFailed(ret) }
    }

    private func drain() -> [[UInt8]] { lock.lock(); defer { lock.unlock() }; return received }
    private func clearReceived() { lock.lock(); received.removeAll(); lock.unlock() }

    /// 发一条读命令，轮询等待匹配响应（b0 高位=1 且 b1/b2 一致）；返回剥 4 字节头的 data，超时 nil。
    /// 输入回调在专用队列上填充 received；这里从调用线程轮询，主线程/GUI 不被阻塞在 run loop。
    public func request(b0: UInt8 = 0x01, b1: UInt8, b2: UInt8, dir: UInt8 = 0x01,
                        payload: [UInt8] = [], timeout: TimeInterval = 0.8) -> [UInt8]? {
        clearReceived()
        try? send(VibeKitFrame.sentFrame(b0: b0, b1: b1, b2: b2, b3: dir, payload: payload))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for p in drain() where p.count >= 3 && (p[0] & 0x80) != 0 && p[1] == b1 && p[2] == b2 {
                return Array(p.dropFirst(4))
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return nil
    }

    /// 被动监听：只听不发，window 秒内把每个新到的解密帧回调出来（用于观察按键上报 st_key_msg）。
    public func listen(window: TimeInterval, onFrame: ([UInt8]) -> Void) {
        clearReceived()
        var seen = 0
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            let cur = drain()
            if cur.count > seen { for p in cur[seen...] { onFrame(p) }; seen = cur.count }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// 被动监听原始帧：回调 (reportID, 原始字节)。诊断按键上报格式用。
    public func listenRaw(window: TimeInterval, onFrame: (UInt32, [UInt8]) -> Void) {
        lock.lock(); rawFrames.removeAll(); lock.unlock()
        var seen = 0
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            lock.lock(); let cur = rawFrames; lock.unlock()
            if cur.count > seen { for f in cur[seen...] { onFrame(f.0, f.1) }; seen = cur.count }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// 多帧收集（SN/UUID 分片）。
    public func collect(b0: UInt8 = 0x01, b1: UInt8, b2: UInt8, dir: UInt8 = 0x01,
                        payload: [UInt8] = [], window: TimeInterval = 0.6) -> [[UInt8]] {
        clearReceived()
        try? send(VibeKitFrame.sentFrame(b0: b0, b1: b1, b2: b2, b3: dir, payload: payload))
        Thread.sleep(forTimeInterval: window)
        return drain().filter { $0.count >= 3 && ($0[0] & 0x80) != 0 && $0[1] == b1 && $0[2] == b2 }
            .map { Array($0.dropFirst(4)) }
    }
}
