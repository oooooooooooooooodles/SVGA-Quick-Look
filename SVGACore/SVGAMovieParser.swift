//
//  SVGAMovieParser.swift
//  SVGACore
//
//  SVGA 文件解析入口。兼容三种形态:
//  1. ZIP 包(SVGA 1.x JSON movie.spec / SVGA 2.x protobuf movie.binary + images/)
//  2. zlib 压缩的扁平 protobuf(SVGA 2.0.0 单文件形态)
//  3. 纯 JSON(SVGA 1.0 单文件形态)
//
//  自包含实现:内置极简 ZIP 读取器 + zlib inflate,无第三方依赖。
//

import Foundation
import CoreGraphics
import zlib

// MARK: - 入口

public enum SVGAMovieParser {

    /// 从 .svga 文件原始数据解析出 SVGAMovie。
    public static func parse(data: Data) throws -> SVGAMovie {
        guard data.count >= 4 else { throw SVGAError.notSVGA }

        // 1. ZIP 包
        if data[data.startIndex] == 0x50 && data[data.startIndex + 1] == 0x4B { // "PK"
            return try parseZip(data)
        }

        // 2. 扁平 protobuf:整体 zlib 解压后按 proto 解析
        if data[data.startIndex] == 0x78 { // zlib 头
            if let inflated = zlibInflate(data, windowBits: 15) {
                do {
                    return try SVGAMovieProtoParser.parse(data: inflated)
                } catch {
                    // 解压成功但 proto 解析失败:尝试把解压结果当作 JSON(SVGA 1.0 变体),
                    // 必须用解压后的数据,原始压缩字节无法解析
                    if let json = try? JSONSerialization.jsonObject(with: inflated) as? [String: Any] {
                        return try parseJSON(json)
                    }
                }
            }
        }

        // 3. 纯 JSON
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return try parseJSON(json)
        }

        throw SVGAError.notSVGA
    }

    // MARK: - ZIP 包解析

    private static func parseZip(_ data: Data) throws -> SVGAMovie {
        let archive = try ZIPArchive.open(data)

        if let binary = archive.extract("movie.binary") {
            var movie = try SVGAMovieProtoParser.parse(data: binary)
            // images map 的 value 可能是文件名,需要从 zip 里取真正的图片数据
            var resolved: [String: Data] = [:]
            for (key, value) in movie.images {
                if let imageData = resolveImageEntry(value, in: archive) {
                    resolved[key] = imageData
                } else {
                    resolved[key] = value
                }
            }
            movie.images = resolved
            return movie
        }

        if let spec = archive.extract("movie.spec") {
            guard let json = try JSONSerialization.jsonObject(with: spec) as? [String: Any] else {
                throw SVGAError.jsonCorrupted("movie.spec is not a JSON object")
            }
            var movie = try parseJSON(json)
            // JSON 模式 images:key → 文件名,从 zip 读取图片数据
            var resolved: [String: Data] = [:]
            for (key, value) in movie.images {
                if let fileName = String(data: value, encoding: .utf8),
                   let imageData = archive.extractFirst(matching: { name in
                       candidateImageNames(for: fileName).contains(name)
                   }) {
                    resolved[key] = imageData
                }
            }
            movie.images = resolved
            return movie
        }

        throw SVGAError.notSVGA
    }

    /// proto images map 的 value:若本身是 PNG/JPEG/MP3 数据直接返回,否则视为文件名。
    private static func resolveImageEntry(_ value: Data, in archive: ZIPArchive) -> Data? {
        if isImageData(value) { return value }
        if let fileName = String(data: value, encoding: .utf8) {
            return archive.extractFirst { candidateImageNames(for: fileName).contains($0) }
        }
        return nil
    }

    /// 依据官方实现(先尝试 "文件名.png" 再尝试原文)生成候选 zip 路径。
    private static func candidateImageNames(for fileName: String) -> [String] {
        var names: [String] = []
        if !fileName.hasSuffix(".png") { names.append("images/\(fileName).png"); names.append("\(fileName).png") }
        names.append("images/\(fileName)")
        names.append(fileName)
        return names
    }

    static func isImageData(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let b = data[data.startIndex]
        // PNG: 89 50 4E 47 ; JPEG: FF D8
        if b == 0x89 { return true }
        if b == 0xFF && data[data.startIndex + 1] == 0xD8 { return true }
        // MP3: ID3 或 FF FB / FF F3
        if b == 0x49 { return String(data: data.prefix(3), encoding: .utf8) == "ID3" }
        if b == 0xFF && (data[data.startIndex + 1] & 0xE0) == 0xE0 { return true }
        return false
    }

    // MARK: - JSON 解析(SVGA 1.x)

    static func parseJSON(_ json: [String: Any]) throws -> SVGAMovie {
        var movie = SVGAMovie()
        movie.version = json["ver"] as? String ?? "1.0"

        if let movieObj = json["movie"] as? [String: Any] {
            if let viewBox = movieObj["viewBox"] as? [String: Any] {
                movie.videoSize.width = CGFloat((viewBox["width"] as? NSNumber)?.floatValue ?? 100)
                movie.videoSize.height = CGFloat((viewBox["height"] as? NSNumber)?.floatValue ?? 100)
            }
            movie.fps = (movieObj["fps"] as? NSNumber)?.intValue ?? 20
            movie.frames = (movieObj["frames"] as? NSNumber)?.intValue ?? 0
        }

        if let images = json["images"] as? [String: Any] {
            for (key, value) in images {
                if let s = value as? String, let data = s.data(using: .utf8) {
                    movie.images[key] = data
                }
            }
        }

        if let sprites = json["sprites"] as? [[String: Any]] {
            for spriteJSON in sprites {
                movie.sprites.append(parseSpriteJSON(spriteJSON))
            }
        }

        if let audios = json["audios"] as? [[String: Any]] {
            for audioJSON in audios {
                movie.audios.append(SVGAAudio(
                    audioKey: audioJSON["audioKey"] as? String ?? "",
                    startFrame: (audioJSON["startFrame"] as? NSNumber)?.intValue ?? 0,
                    endFrame: (audioJSON["endFrame"] as? NSNumber)?.intValue ?? 0,
                    startTime: (audioJSON["startTime"] as? NSNumber)?.intValue ?? 0,
                    totalTime: (audioJSON["totalTime"] as? NSNumber)?.intValue ?? 0
                ))
            }
        }
        return movie
    }

    private static func parseSpriteJSON(_ json: [String: Any]) -> SVGASprite {
        var sprite = SVGASprite(imageKey: json["imageKey"] as? String ?? "")
        if let matte = json["matteKey"] as? String, !matte.isEmpty {
            sprite.matteKey = matte
        }
        if let frames = json["frames"] as? [[String: Any]] {
            for frameJSON in frames {
                sprite.frames.append(parseFrameJSON(frameJSON))
            }
        }
        return sprite
    }

    private static func parseFrameJSON(_ json: [String: Any]) -> SVGAFrame {
        var frame = SVGAFrame()
        frame.alpha = CGFloat((json["alpha"] as? NSNumber)?.floatValue ?? 0)

        if let layout = json["layout"] as? [String: Any] {
            frame.layout = CGRect(
                x: CGFloat((layout["x"] as? NSNumber)?.floatValue ?? 0),
                y: CGFloat((layout["y"] as? NSNumber)?.floatValue ?? 0),
                width: CGFloat((layout["width"] as? NSNumber)?.floatValue ?? 0),
                height: CGFloat((layout["height"] as? NSNumber)?.floatValue ?? 0)
            )
        }
        if let t = json["transform"] as? [String: Any] {
            frame.transform = CGAffineTransform(
                a: CGFloat((t["a"] as? NSNumber)?.floatValue ?? 1),
                b: CGFloat((t["b"] as? NSNumber)?.floatValue ?? 0),
                c: CGFloat((t["c"] as? NSNumber)?.floatValue ?? 0),
                d: CGFloat((t["d"] as? NSNumber)?.floatValue ?? 1),
                tx: CGFloat((t["tx"] as? NSNumber)?.floatValue ?? 0),
                ty: CGFloat((t["ty"] as? NSNumber)?.floatValue ?? 0)
            )
        }
        frame.clipPath = json["clipPath"] as? String
        if let shapes = json["shapes"] as? [[String: Any]] {
            for shapeJSON in shapes {
                frame.shapes.append(parseShapeJSON(shapeJSON))
            }
        }
        return frame
    }

    private static func parseShapeJSON(_ json: [String: Any]) -> SVGAShape {
        let typeName = json["type"] as? String ?? "shape"
        let type: SVGAShapeType
        switch typeName {
        case "rect": type = .rect
        case "ellipse": type = .ellipse
        case "keep": type = .keep
        default: type = .shape
        }

        var shape = SVGAShape(type: type)
        if let args = json["args"] as? [String: Any] {
            switch type {
            case .shape:
                shape.pathD = args["d"] as? String
            case .rect:
                shape.rect = SVGAArgRect(
                    x: CGFloat((args["x"] as? NSNumber)?.floatValue ?? 0),
                    y: CGFloat((args["y"] as? NSNumber)?.floatValue ?? 0),
                    width: CGFloat((args["width"] as? NSNumber)?.floatValue ?? 0),
                    height: CGFloat((args["height"] as? NSNumber)?.floatValue ?? 0),
                    cornerRadius: CGFloat((args["cornerRadius"] as? NSNumber)?.floatValue ?? 0)
                )
            case .ellipse:
                shape.ellipse = SVGAArgEllipse(
                    x: CGFloat((args["x"] as? NSNumber)?.floatValue ?? 0),
                    y: CGFloat((args["y"] as? NSNumber)?.floatValue ?? 0),
                    radiusX: CGFloat((args["radiusX"] as? NSNumber)?.floatValue ?? 0),
                    radiusY: CGFloat((args["radiusY"] as? NSNumber)?.floatValue ?? 0)
                )
            case .keep:
                break
            }
        }
        if let styles = json["styles"] as? [String: Any] {
            shape.styles = parseStyleJSON(styles)
        }
        if let t = json["transform"] as? [String: Any] {
            shape.transform = CGAffineTransform(
                a: CGFloat((t["a"] as? NSNumber)?.floatValue ?? 1),
                b: CGFloat((t["b"] as? NSNumber)?.floatValue ?? 0),
                c: CGFloat((t["c"] as? NSNumber)?.floatValue ?? 0),
                d: CGFloat((t["d"] as? NSNumber)?.floatValue ?? 1),
                tx: CGFloat((t["tx"] as? NSNumber)?.floatValue ?? 0),
                ty: CGFloat((t["ty"] as? NSNumber)?.floatValue ?? 0)
            )
        }
        return shape
    }

    private static func parseStyleJSON(_ json: [String: Any]) -> SVGAShapeStyle {
        var style = SVGAShapeStyle()
        if let fill = json["fill"] as? [NSNumber], fill.count == 4 {
            style.fill = (CGFloat(fill[0].floatValue), CGFloat(fill[1].floatValue), CGFloat(fill[2].floatValue), CGFloat(fill[3].floatValue))
        }
        if let stroke = json["stroke"] as? [NSNumber], stroke.count == 4 {
            style.stroke = (CGFloat(stroke[0].floatValue), CGFloat(stroke[1].floatValue), CGFloat(stroke[2].floatValue), CGFloat(stroke[3].floatValue))
        }
        style.strokeWidth = CGFloat((json["strokeWidth"] as? NSNumber)?.floatValue ?? 0)
        switch json["lineCap"] as? String {
        case "round": style.lineCap = .round
        case "square": style.lineCap = .square
        default: style.lineCap = .butt
        }
        switch json["lineJoin"] as? String {
        case "round": style.lineJoin = .round
        case "bevel": style.lineJoin = .bevel
        default: style.lineJoin = .miter
        }
        style.miterLimit = CGFloat((json["miterLimit"] as? NSNumber)?.floatValue ?? 4)
        if let dash = json["lineDash"] as? [NSNumber], dash.count == 3 {
            style.lineDashI = CGFloat(dash[0].floatValue)
            style.lineDashII = CGFloat(dash[1].floatValue)
            style.lineDashIII = CGFloat(dash[2].floatValue)
        }
        return style
    }
}

// MARK: - 极简 ZIP 读取器

struct ZIPEntry {
    let name: String
    let method: UInt16
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
}

struct ZIPArchive {
    let data: Data
    let entries: [String: ZIPEntry]

    static func open(_ data: Data) throws -> ZIPArchive {
        let d = [UInt8](data)
        // 定位 EOCD(从文件尾向前找 0x06054b50)
        var eocd = -1
        var i = d.count - 22
        while i >= 0 {
            if d[i] == 0x50 && d[i+1] == 0x4B && d[i+2] == 0x05 && d[i+3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw SVGAError.zipCorrupted("EOCD not found") }

        func u16(_ offset: Int) -> UInt16 {
            UInt16(d[offset]) | (UInt16(d[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(d[offset]) | (UInt32(d[offset + 1]) << 8) | (UInt32(d[offset + 2]) << 16) | (UInt32(d[offset + 3]) << 24)
        }

        let totalEntries = Int(u16(eocd + 10))
        let cdOffset = Int(u32(eocd + 16))

        var entries: [String: ZIPEntry] = [:]
        var p = cdOffset
        for _ in 0..<totalEntries {
            guard p + 46 <= d.count, d[p] == 0x50, d[p+1] == 0x4B, d[p+2] == 0x01, d[p+3] == 0x02 else {
                throw SVGAError.zipCorrupted("central directory entry signature mismatch")
            }
            let method = u16(p + 10)
            let compressedSize = u32(p + 20)
            let uncompressedSize = u32(p + 24)
            let nameLen = Int(u16(p + 28))
            let extraLen = Int(u16(p + 30))
            let commentLen = Int(u16(p + 32))
            let localOffset = u32(p + 42)
            // 边界校验:条目名/扩展/注释总长不能越过文件末尾,防止 subdata 越界崩溃
            let headerTotal = 46 + nameLen + extraLen + commentLen
            guard p <= d.count, headerTotal <= d.count - p else {
                throw SVGAError.zipCorrupted("central directory entry overrun")
            }
            let nameData = data.subdata(in: data.startIndex + p + 46 ..< data.startIndex + p + 46 + nameLen)
            let name = String(data: nameData, encoding: .utf8) ?? ""
            if !name.isEmpty {
                entries[name] = ZIPEntry(name: name, method: method, compressedSize: compressedSize, uncompressedSize: uncompressedSize, localHeaderOffset: localOffset)
            }
            p += headerTotal
        }
        return ZIPArchive(data: data, entries: entries)
    }

    func extractFirst(matching: (String) -> Bool) -> Data? {
        for (name, _) in entries {
            if matching(name) { return extract(name) }
        }
        return nil
    }

    func extract(_ name: String) -> Data? {
        guard let entry = entries[name] else { return nil }
        let d = [UInt8](data)
        let p = Int(entry.localHeaderOffset)
        guard p + 30 <= d.count, d[p] == 0x50, d[p+1] == 0x4B, d[p+2] == 0x03, d[p+3] == 0x04 else {
            return nil
        }
        func u16(_ offset: Int) -> UInt16 { UInt16(d[offset]) | (UInt16(d[offset + 1]) << 8) }
        let nameLen = Int(u16(p + 26))
        let extraLen = Int(u16(p + 28))
        let dataStart = p + 30 + nameLen + extraLen
        guard dataStart + Int(entry.compressedSize) <= d.count else { return nil }
        let raw = data.subdata(in: data.startIndex + dataStart ..< data.startIndex + dataStart + Int(entry.compressedSize))

        switch entry.method {
        case 0: // stored
            return raw
        case 8: // deflate
            return zlibInflate(raw, windowBits: -15)
        default:
            return nil
        }
    }
}

// MARK: - zlib inflate

/// 使用系统 zlib 解压(windowBits: 15 = zlib 头, -15 = 裸 deflate)。
/// 有输出上限(防解压炸弹),超过即失败。
func zlibInflate(_ source: Data, windowBits: Int32) -> Data? {
    guard !source.isEmpty else { return nil }
    var stream = z_stream()
    let chunk = 1 << 14
    let maxOutput = 512 * 1024 * 1024 // 512MB 输出上限
    var out = Data(capacity: min(max(source.count * 4, chunk), maxOutput))
    var buffer = [UInt8](repeating: 0, count: chunk)

    let success = source.withUnsafeBytes { (inRaw: UnsafeRawBufferPointer) -> Bool in
        guard let inBase = inRaw.baseAddress else { return false }
        stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inBase.assumingMemoryBound(to: Bytef.self))
        stream.avail_in = uInt(source.count)
        guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return false
        }
        var status: Int32 = Z_OK
        var lastAvailIn = uInt.max
        var stalls = 0
        while status == Z_OK {
            let produced = buffer.withUnsafeMutableBytes { (outRaw: UnsafeMutableRawBufferPointer) -> Int in
                stream.next_out = outRaw.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(chunk)
                status = inflate(&stream, Z_NO_FLUSH)
                if status == Z_STREAM_END || status == Z_OK {
                    return chunk - Int(stream.avail_out)
                }
                return 0
            }
            // 输出上限:防止解压炸弹耗尽内存
            if out.count + produced > maxOutput {
                status = Z_MEM_ERROR
                break
            }
            if produced > 0 { out.append(buffer, count: produced) }
            // 防死循环:输入无进展且无输出则视为损坏流
            if produced == 0 && stream.avail_in == lastAvailIn {
                stalls += 1
                if stalls >= 3 { status = Z_STREAM_ERROR; break }
            } else {
                stalls = 0
            }
            lastAvailIn = stream.avail_in
        }
        inflateEnd(&stream)
        return status == Z_STREAM_END
    }
    return success ? out : nil
}
