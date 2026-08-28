//
//  SVGAProto.swift
//  SVGACore
//
//  手写 protobuf wire-format 解码器,用于解析 movie.binary(SVGA 2.x)。
//  字段编号严格对应 SVGAPlayer-iOS 的 Svga.pbobjc.h(见仓库 readme 说明)。
//

import Foundation
import CoreGraphics

/// 极简 protobuf 二进制读取器(wire format)。
struct ProtoReader {
    let data: Data
    var offset = 0

    var isAtEnd: Bool { offset >= data.count }

    mutating func readByte() throws -> UInt8 {
        guard offset < data.count else { throw SVGAError.protoCorrupted("unexpected EOF") }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    /// 读取 varint(最多 10 字节)。
    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let byte = try readByte()
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
            if shift >= 70 { throw SVGAError.protoCorrupted("varint too long") }
        }
        return result
    }

    /// 读取固定 32 位小端浮点(float 字段)。
    mutating func readFloat() throws -> Float {
        var raw: UInt32 = 0
        for i in 0..<4 {
            raw |= UInt32(try readByte()) << (8 * i)
        }
        return Float(bitPattern: raw)
    }

    /// 读取 length-delimited 的原始字节段。
    mutating func readLengthDelimited() throws -> Data {
        let len64 = try readVarint()
        // 防止恶意 varint 导致 Int 溢出 / 超大分配
        guard let len = Int(exactly: len64), len >= 0, len <= maxFieldDataSize else {
            throw SVGAError.protoCorrupted("length-delimited length overflow")
        }
        guard offset <= data.count - len else { throw SVGAError.protoCorrupted("length-delimited overrun") }
        defer { offset += len }
        return data.subdata(in: data.startIndex + offset ..< data.startIndex + offset + len)
    }

    /// 读取字段键,返回 (fieldNumber, wireType)。
    mutating func readKey() throws -> (Int, Int) {
        let key = try readVarint()
        return (Int(key >> 3), Int(key & 0x7))
    }
}

/// protobuf 单个 length-delimited 字段的最大可接受大小(防御恶意输入)。
private let maxFieldDataSize = 512 * 1024 * 1024

/// protobuf 字段读取辅助:从 length-delimited 子数据解析消息字段。
struct ProtoFieldIterator {
    var reader: ProtoReader

    init(data: Data) {
        reader = ProtoReader(data: data)
    }

    /// 遍历所有字段,返回 (fieldNumber, wireType, 字段值)。
    /// value 依据 wireType:0 → UInt64, 1 → Double, 2 → Data, 5 → Float。
    mutating func next() throws -> (Int, Int, Any)? {
        guard !reader.isAtEnd else { return nil }
        let (field, wire) = try reader.readKey()
        switch wire {
        case 0:
            return (field, wire, try reader.readVarint())
        case 1:
            var raw: UInt64 = 0
            for i in 0..<8 { raw |= UInt64(try reader.readByte()) << (8 * i) }
            return (field, wire, Double(bitPattern: raw))
        case 2:
            return (field, wire, try reader.readLengthDelimited())
        case 5:
            return (field, wire, try reader.readFloat())
        default:
            throw SVGAError.protoCorrupted("unsupported wire type \(wire)")
        }
    }
}

enum SVGAError: Error {
    case notSVGA
    case zipCorrupted(String)
    case protoCorrupted(String)
    case jsonCorrupted(String)
    case unsupported(String)
}

/// movie.binary(protobuf)→ SVGAMovie 模型转换。
enum SVGAMovieProtoParser {

    static func parse(data: Data) throws -> SVGAMovie {
        var movie = SVGAMovie()
        var iter = ProtoFieldIterator(data: data)
        while let (field, _, value) = try iter.next() {
            switch field {
            case 1: // version: string
                if case let v as Data = value, let s = String(data: v, encoding: .utf8) {
                    movie.version = s
                }
            case 2: // params: MovieParams
                if case let v as Data = value {
                    movie = try parseParams(v, movie: movie)
                }
            case 3: // images: map<string, bytes>
                if case let v as Data = value {
                    try parseImagesEntry(v, movie: &movie)
                }
            case 4: // spritesArray
                if case let v as Data = value {
                    movie.sprites.append(try parseSprite(v))
                }
            case 5: // audiosArray
                if case let v as Data = value {
                    movie.audios.append(try parseAudio(v))
                }
            default:
                break
            }
        }
        return movie
    }

    private static func parseParams(_ data: Data, movie: SVGAMovie) throws -> SVGAMovie {
        var m = movie
        var iter = ProtoFieldIterator(data: data)
        while let (field, _, value) = try iter.next() {
            switch field {
            case 1: if case let v as Float = value { m.videoSize.width = CGFloat(v) }
            case 2: if case let v as Float = value { m.videoSize.height = CGFloat(v) }
            case 3: if case let v as UInt64 = value, let i = Int(exactly: v) { m.fps = i }
            case 4: if case let v as UInt64 = value, let i = Int(exactly: v) { m.frames = i }
            default: break
            }
        }
        return m
    }

    /// map<string, bytes> 的一个条目:{ 1: key(string), 2: value(bytes) }
    private static func parseImagesEntry(_ data: Data, movie: inout SVGAMovie) throws {
        var key: String?
        var value: Data?
        var iter = ProtoFieldIterator(data: data)
        while let (field, _, v) = try iter.next() {
            switch field {
            case 1:
                if case let d as Data = v { key = String(data: d, encoding: .utf8) }
            case 2:
                if case let d as Data = v { value = d }
            default: break
            }
        }
        if let key = key, let value = value {
            movie.images[key] = value
        }
    }

    private static func parseSprite(_ data: Data) throws -> SVGASprite {
        var sprite = SVGASprite(imageKey: "")
        var iter = ProtoFieldIterator(data: data)
        while let (field, _, value) = try iter.next() {
            switch field {
            case 1:
                if case let v as Data = value { sprite.imageKey = String(data: v, encoding: .utf8) ?? "" }
            case 2:
                if case let v as Data = value { sprite.frames.append(try parseFrame(v)) }
            case 3:
                if case let v as Data = value { sprite.matteKey = String(data: v, encoding: .utf8) }
            default: break
            }
        }
        return sprite
    }

    private static func parseFrame(_ data: Data) throws -> SVGAFrame {
        var frame = SVGAFrame()
        var iter = ProtoFieldIterator(data: data)
        while let (field, _, value) = try iter.next() {
            switch field {
            case 1: // alpha: float
                if case let v as Float = value { frame.alpha = CGFloat(v) }
            case 2: // layout: Layout
                if case let v as Data = value {
                    var li = ProtoFieldIterator(data: v)
                    var l = CGRect.zero
                    while let (lf, _, lv) = try li.next() {
                        switch lf {
                        case 1: if case let x as Float = lv { l.origin.x = CGFloat(x) }
                        case 2: if case let y as Float = lv { l.origin.y = CGFloat(y) }
                        case 3: if case let w as Float = lv { l.size.width = CGFloat(w) }
                        case 4: if case let h as Float = lv { l.size.height = CGFloat(h) }
                        default: break
                        }
                    }
                    frame.layout = l
                }
            case 3: // transform: Transform
                if case let v as Data = value {
                    var ti = ProtoFieldIterator(data: v)
                    var t = CGAffineTransform.identity
                    while let (tf, _, tv) = try ti.next() {
                        switch tf {
                        case 1: if case let x as Float = tv { t.a = CGFloat(x) }
                        case 2: if case let x as Float = tv { t.b = CGFloat(x) }
                        case 3: if case let x as Float = tv { t.c = CGFloat(x) }
                        case 4: if case let x as Float = tv { t.d = CGFloat(x) }
                        case 5: if case let x as Float = tv { t.tx = CGFloat(x) }
                        case 6: if case let x as Float = tv { t.ty = CGFloat(x) }
                        default: break
                        }
                    }
                    frame.transform = t
                }
            case 4: // clipPath: string
                if case let v as Data = value { frame.clipPath = String(data: v, encoding: .utf8) }
            case 5: // shapesArray
                if case let v as Data = value { frame.shapes.append(try parseShape(v)) }
            default: break
            }
        }
        return frame
    }

    private static func parseShape(_ data: Data) throws -> SVGAShape {
        var shape = SVGAShape(type: .shape)
        var iter = ProtoFieldIterator(data: data)
        while let (field, _, value) = try iter.next() {
            switch field {
            case 1: // type: enum int32
                if case let v as UInt64 = value, let i = Int(exactly: v) { shape.type = SVGAShapeType(rawValue: i) ?? .shape }
            case 2: // shape args: { 1: d(string) }
                if case let v as Data = value {
                    var si = ProtoFieldIterator(data: v)
                    while let (sf, _, sv) = try si.next() {
                        if sf == 1, case let d as Data = sv { shape.pathD = String(data: d, encoding: .utf8) }
                    }
                }
            case 3: // rect args
                if case let v as Data = value {
                    var ri = ProtoFieldIterator(data: v)
                    var r = SVGAArgRect(x: 0, y: 0, width: 0, height: 0, cornerRadius: 0)
                    while let (rf, _, rv) = try ri.next() {
                        switch rf {
                        case 1: if case let x as Float = rv { r.x = CGFloat(x) }
                        case 2: if case let x as Float = rv { r.y = CGFloat(x) }
                        case 3: if case let x as Float = rv { r.width = CGFloat(x) }
                        case 4: if case let x as Float = rv { r.height = CGFloat(x) }
                        case 5: if case let x as Float = rv { r.cornerRadius = CGFloat(x) }
                        default: break
                        }
                    }
                    shape.rect = r
                }
            case 4: // ellipse args
                if case let v as Data = value {
                    var ei = ProtoFieldIterator(data: v)
                    var e = SVGAArgEllipse(x: 0, y: 0, radiusX: 0, radiusY: 0)
                    while let (ef, _, ev) = try ei.next() {
                        switch ef {
                        case 1: if case let x as Float = ev { e.x = CGFloat(x) }
                        case 2: if case let x as Float = ev { e.y = CGFloat(x) }
                        case 3: if case let x as Float = ev { e.radiusX = CGFloat(x) }
                        case 4: if case let x as Float = ev { e.radiusY = CGFloat(x) }
                        default: break
                        }
                    }
                    shape.ellipse = e
                }
            case 10: // styles
                if case let v as Data = value { shape.styles = try parseStyle(v) }
            case 11: // transform
                if case let v as Data = value {
                    var ti = ProtoFieldIterator(data: v)
                    var t = CGAffineTransform.identity
                    while let (tf, _, tv) = try ti.next() {
                        switch tf {
                        case 1: if case let x as Float = tv { t.a = CGFloat(x) }
                        case 2: if case let x as Float = tv { t.b = CGFloat(x) }
                        case 3: if case let x as Float = tv { t.c = CGFloat(x) }
                        case 4: if case let x as Float = tv { t.d = CGFloat(x) }
                        case 5: if case let x as Float = tv { t.tx = CGFloat(x) }
                        case 6: if case let x as Float = tv { t.ty = CGFloat(x) }
                        default: break
                        }
                    }
                    shape.transform = t
                }
            default: break
            }
        }
        return shape
    }

    private static func parseStyle(_ data: Data) throws -> SVGAShapeStyle {
        var style = SVGAShapeStyle()
        var iter = ProtoFieldIterator(data: data)
        while let (field, _, value) = try iter.next() {
            switch field {
            case 1: style.fill = try parseColor(value)
            case 2: style.stroke = try parseColor(value)
            case 3: if case let v as Float = value { style.strokeWidth = CGFloat(v) }
            case 4: if case let v as UInt64 = value, let i = Int(exactly: v) { style.lineCap = SVGALineCap(rawValue: i) ?? .butt }
            case 5: if case let v as UInt64 = value, let i = Int(exactly: v) { style.lineJoin = SVGALineJoin(rawValue: i) ?? .miter }
            case 6: if case let v as Float = value { style.miterLimit = CGFloat(v) }
            case 7: if case let v as Float = value { style.lineDashI = CGFloat(v) }
            case 8: if case let v as Float = value { style.lineDashII = CGFloat(v) }
            case 9: if case let v as Float = value { style.lineDashIII = CGFloat(v) }
            default: break
            }
        }
        return style
    }

    private static func parseColor(_ value: Any) throws -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        guard case let v as Data = value else { return nil }
        var c: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0, 0, 0, 1)
        var iter = ProtoFieldIterator(data: v)
        while let (field, _, cv) = try iter.next() {
            guard case let f as Float = cv else { continue }
            switch field {
            case 1: c.r = CGFloat(f)
            case 2: c.g = CGFloat(f)
            case 3: c.b = CGFloat(f)
            case 4: c.a = CGFloat(f)
            default: break
            }
        }
        return c
    }

    private static func parseAudio(_ data: Data) throws -> SVGAAudio {
        var audio = SVGAAudio(audioKey: "", startFrame: 0, endFrame: 0, startTime: 0, totalTime: 0)
        var iter = ProtoFieldIterator(data: data)
        while let (field, _, value) = try iter.next() {
            switch field {
            case 1:
                if case let v as Data = value { audio.audioKey = String(data: v, encoding: .utf8) ?? "" }
            case 2: if case let v as UInt64 = value, let i = Int(exactly: v) { audio.startFrame = i }
            case 3: if case let v as UInt64 = value, let i = Int(exactly: v) { audio.endFrame = i }
            case 4: if case let v as UInt64 = value, let i = Int(exactly: v) { audio.startTime = i }
            case 5: if case let v as UInt64 = value, let i = Int(exactly: v) { audio.totalTime = i }
            default: break
            }
        }
        return audio
    }
}
