//
//  render-test.swift — 渲染冒烟测试
//  用法: swiftc -o /tmp/render-test SVGACore/*.swift Scripts/render-test.swift && /tmp/render-test <样本目录> <输出目录>
//

import Foundation
import AppKit

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Samples"
let outDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/svga-render"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let files = (try? fm.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".svga") }.sorted()) ?? []

for file in files {
    let path = (dir as NSString).appendingPathComponent(file)
    guard let data = fm.contents(atPath: path) else { continue }
    do {
        let movie = try SVGAMovieParser.parse(data: data)
        let frame = SVGAMovieRenderer.thumbnailFrame(for: movie)
        let cg = SVGAMovieRenderer.renderFrame(movie: movie, frame: frame, size: CGSize(width: 256, height: 256))
        if let cg = cg {
            let rep = NSBitmapImageRep(cgImage: cg)
            let png = rep.representation(using: .png, properties: [:])
            let outPath = (outDir as NSString).appendingPathComponent(file.replacingOccurrences(of: ".svga", with: ".png"))
            try? png?.write(to: URL(fileURLWithPath: outPath))
            print("✓ \(file) → frame \(frame) (\(cg.width)x\(cg.height)) → \(outPath)")
        } else {
            print("✗ \(file): 渲染失败")
        }
    } catch {
        print("✗ \(file): \(error)")
    }
}
