//
//  SVGABezierPath.swift
//  SVGACore
//
//  SVG 路径数据("d" 属性)解析为 CGPath。
//  移植自 SVGAPlayer-iOS 的 SVGABezierPath.m,并补齐了官方实现缺失的
//  隐式重复命令(SVG 标准: M 后多余坐标对视为 L 等)以及 S/T 平滑曲线。
//

import Foundation
import CoreGraphics

public enum SVGABezierPath {

    /// 解析 SVG path 字符串为 CGPath;解析失败或为空时返回空路径。
    public static func path(from d: String) -> CGPath {
        let path = CGMutablePath()
        guard !d.isEmpty else { return path }

        let tokens = tokenize(d)
        var i = 0

        // 跳过开头的非命令字符,直到遇到第一个命令
        while i < tokens.count, tokens[i].count == 1, let c = tokens[i].first, c.isLetter, !isCommand(c) {
            i += 1
        }

        var current: Character = "M"
        var isRelative = false
        var startPoint = CGPoint.zero
        var currentPoint = CGPoint.zero
        var hasMoved = false
        var lastControl: CGPoint? // S/T 平滑曲线用

        func isNumberToken(_ s: String) -> Bool {
            Float(s) != nil
        }

        func readFloat() -> CGFloat? {
            guard i < tokens.count, let v = Float(tokens[i]) else { return nil }
            i += 1
            return CGFloat(v)
        }

        func readPoint(relative: Bool) -> CGPoint? {
            guard let x = readFloat(), let y = readFloat() else { return nil }
            if relative {
                return CGPoint(x: x + currentPoint.x, y: y + currentPoint.y)
            }
            return CGPoint(x: x, y: y)
        }

        func reflect(_ p: CGPoint, about center: CGPoint) -> CGPoint {
            CGPoint(x: 2 * center.x - p.x, y: 2 * center.y - p.y)
        }

        while i < tokens.count {
            // 读取命令字母(可选,用于隐式重复时的命令切换)
            if tokens[i].count == 1, let c = tokens[i].first, c.isLetter {
                current = c
                isRelative = c.isLowercase
                i += 1
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    currentPoint = startPoint
                    lastControl = nil
                    continue
                }
            }
            if i >= tokens.count { break }

            switch current {
            case "M", "m":
                if let p = readPoint(relative: isRelative) {
                    path.move(to: p)
                    startPoint = p
                    currentPoint = p
                    hasMoved = true
                    lastControl = nil
                    // 隐式:后续坐标对视为直线
                    while i < tokens.count, isNumberToken(tokens[i]) {
                        if let p2 = readPoint(relative: isRelative) {
                            path.addLine(to: p2)
                            currentPoint = p2
                        }
                    }
                } else {
                    i += 1
                }

            case "L", "l":
                while i < tokens.count, isNumberToken(tokens[i]) {
                    if let p = readPoint(relative: isRelative) {
                        path.addLine(to: p)
                        currentPoint = p
                    }
                }
                lastControl = nil

            case "H", "h":
                while i < tokens.count, isNumberToken(tokens[i]) {
                    if let v = readFloat() {
                        let x = isRelative ? v + currentPoint.x : v
                        currentPoint = CGPoint(x: x, y: currentPoint.y)
                        path.addLine(to: currentPoint)
                    }
                }
                lastControl = nil

            case "V", "v":
                while i < tokens.count, isNumberToken(tokens[i]) {
                    if let v = readFloat() {
                        let y = isRelative ? v + currentPoint.y : v
                        currentPoint = CGPoint(x: currentPoint.x, y: y)
                        path.addLine(to: currentPoint)
                    }
                }
                lastControl = nil

            case "C", "c":
                while i < tokens.count, isNumberToken(tokens[i]) {
                    if let c1 = readPoint(relative: isRelative),
                       let c2 = readPoint(relative: isRelative),
                       let p = readPoint(relative: isRelative) {
                        path.addCurve(to: p, control1: c1, control2: c2)
                        currentPoint = p
                        lastControl = c2
                    }
                }

            case "S", "s":
                while i < tokens.count, isNumberToken(tokens[i]) {
                    guard let c2 = readPoint(relative: isRelative), let p = readPoint(relative: isRelative) else { break }
                    let c1 = lastControl.map { reflect($0, about: currentPoint) } ?? currentPoint
                    path.addCurve(to: p, control1: c1, control2: c2)
                    currentPoint = p
                    lastControl = c2
                }

            case "Q", "q":
                while i < tokens.count, isNumberToken(tokens[i]) {
                    if let c = readPoint(relative: isRelative), let p = readPoint(relative: isRelative) {
                        path.addQuadCurve(to: p, control: c)
                        currentPoint = p
                        lastControl = c
                    }
                }

            case "T", "t":
                while i < tokens.count, isNumberToken(tokens[i]) {
                    if let p = readPoint(relative: isRelative) {
                        let c = lastControl.map { reflect($0, about: currentPoint) } ?? currentPoint
                        path.addQuadCurve(to: p, control: c)
                        currentPoint = p
                        lastControl = c
                    }
                }

            default:
                // A / R 等不支持的命令:跳过其参数
                while i < tokens.count, isNumberToken(tokens[i]) {
                    i += 1
                }
                lastControl = nil
            }
            _ = hasMoved
        }
        return path
    }

    private static func isCommand(_ c: Character) -> Bool {
        "MmLlHhVvCcSsQqTtAaZzRr".contains(c)
    }

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" || ch == "\r" {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
