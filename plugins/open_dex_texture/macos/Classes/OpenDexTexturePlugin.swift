import Cocoa
import CoreVideo
import Darwin
import FlutterMacOS

private final class FrameTexture: NSObject, FlutterTexture {
    let width: Int
    let height: Int
    var id: Int64 = -1
    private let path: String
    private let registrar: FlutterTextureRegistry
    private let lock = NSLock()
    private let worker = DispatchGroup()
    private var stopped = false
    private var pixelBuffer: CVPixelBuffer?
    private var frames: Int64 = 0
    private var presented: Int64 = 0
    private var dropped: Int64 = 0
    private var last: Int64 = 0
    private var center: Int64 = 0
    private var probe: Int64 = 0
    private var pending = false

    init(width: Int, height: Int, path: String, registrar: FlutterTextureRegistry) {
        self.width = width
        self.height = height
        self.path = path
        self.registrar = registrar
    }
    func start() {
        worker.enter()
        DispatchQueue.global(qos: .userInteractive).async { [self] in
            readFrames()
            worker.leave()
        }
    }
    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        worker.wait()
    }
    private func isStopped() -> Bool {
        lock.lock(); defer { lock.unlock() }; return stopped
    }
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock(); defer { lock.unlock() }
        if pending { presented += 1; pending = false }
        guard let buffer = pixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
    func stats() -> [String: Int64] {
        lock.lock(); defer { lock.unlock() }
        return ["frames": frames, "presentedFrames": presented,
                "droppedFrames": dropped, "lastFrameMonotonicUs": last,
                "centerLuma": center, "probeLuma": probe]
    }
    private func readFrames() {
        var descriptor: Int32 = -1
        var offset = 0
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        defer { if descriptor >= 0 { Darwin.close(descriptor) } }
        while !isStopped() {
            if descriptor < 0 {
                descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
                if descriptor < 0 { usleep(5000); continue }
            }
            var item = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP | POLLERR), revents: 0)
            let result = Darwin.poll(&item, 1, 50)
            if result < 0 {
                if errno == EINTR { continue }
                Darwin.close(descriptor); descriptor = -1; offset = 0; continue
            }
            if result == 0 { continue }
            if item.revents & Int16(POLLIN) != 0 {
                let remaining = rgba.count - offset
                let count = rgba.withUnsafeMutableBytes { raw in
                    Darwin.read(descriptor, raw.baseAddress!.advanced(by: offset), remaining)
                }
                if count > 0 {
                    offset += count
                    if offset == rgba.count { present(rgba); offset = 0 }
                    continue
                }
            }
            if item.revents & Int16(POLLHUP | POLLERR) != 0 {
                Darwin.close(descriptor); descriptor = -1; offset = 0; usleep(5000)
            }
        }
    }
    private func present(_ rgba: [UInt8]) {
        var output: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attributes, &output) == kCVReturnSuccess,
              let buffer = output else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, []); return
        }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let source = (y * width + x) * 4
                let target = y * stride + x * 4
                pixels[target] = rgba[source + 2]
                pixels[target + 1] = rgba[source + 1]
                pixels[target + 2] = rgba[source]
                pixels[target + 3] = rgba[source + 3]
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        func luma(_ x: Int, _ y: Int) -> Int64 {
            let i = (y * width + x) * 4
            return Int64((77 * Int(rgba[i]) + 150 * Int(rgba[i+1]) + 29 * Int(rgba[i+2])) >> 8)
        }
        lock.lock()
        if pending { dropped += 1 }
        pixelBuffer = buffer
        pending = true
        frames += 1
        last = Int64(DispatchTime.now().uptimeNanoseconds / 1000)
        center = luma(width / 2, height / 2)
        probe = luma(min(12, width - 1), min(12, height - 1))
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isStopped() else { return }
            self.registrar.textureFrameAvailable(self.id)
        }
    }
}

public final class OpenDexTexturePlugin: NSObject, FlutterPlugin {
    private let registrar: FlutterTextureRegistry
    private var textures: [Int64: FrameTexture] = [:]
    init(registrar: FlutterTextureRegistry) { self.registrar = registrar }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "open_dex_texture", binaryMessenger: registrar.messenger)
        let instance = OpenDexTexturePlugin(registrar: registrar.textures)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    deinit { for texture in textures.values { texture.stop() } }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "invalid-arguments", message: "Expected an argument map.", details: nil)); return
        }
        if call.method == "create" {
            guard let path = args["fifoPath"] as? String,
                  let width = args["width"] as? Int, let height = args["height"] as? Int,
                  (1...4096).contains(width), (1...4096).contains(height) else {
                result(FlutterError(code: "invalid-arguments", message: "Expected a frame pipe and valid dimensions.", details: nil)); return
            }
            var info = stat()
            guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFIFO else {
                result(FlutterError(code: "invalid-frame-source", message: "The frame source must be a FIFO.", details: nil)); return
            }
            let texture = FrameTexture(width: width, height: height, path: path, registrar: registrar)
            texture.id = registrar.register(texture)
            guard texture.id != 0 else {
                result(FlutterError(code: "texture-registration-failed", message: "Could not register video texture.", details: nil)); return
            }
            textures[texture.id] = texture
            texture.start()
            result(texture.id)
            return
        }
        guard let number = args["textureId"] as? NSNumber else {
            result(FlutterError(code: "invalid-arguments", message: "Expected textureId.", details: nil)); return
        }
        let id = number.int64Value
        if call.method == "close" {
            if let texture = textures.removeValue(forKey: id) {
                texture.stop(); registrar.unregisterTexture(id)
            }
            result(nil); return
        }
        guard let texture = textures[id] else {
            result(FlutterError(code: "texture-not-found", message: "That video texture has closed.", details: nil)); return
        }
        if call.method == "stats" { result(texture.stats()) }
        else if call.method == "frameCount" { result(texture.stats()["frames"]) }
        else { result(FlutterMethodNotImplemented) }
    }
}
