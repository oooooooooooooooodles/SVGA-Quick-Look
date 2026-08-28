//
//  core-test.swift — SVGACore 冒烟测试(CLI)
//  用法: swiftc -o /tmp/core-test SVGACore/SVGAModel.swift SVGACore/SVGAProto.swift SVGACore/SVGAMovieParser.swift Scripts/core-test.swift && /tmp/core-test <样本目录>
//

import Foundation

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Samples"
let fm = FileManager.default
let files = (try? fm.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".svga") }.sorted()) ?? []

var failures = 0
for file in files {
    let path = (dir as NSString).appendingPathComponent(file)
    guard let data = fm.contents(atPath: path) else {
        print("✗ \(file): 无法读取文件")
        failures += 1
        continue
    }
    do {
        let movie = try SVGAMovieParser.parse(data: data)
        let bitmapCount = movie.images.values.filter { SVGAMovieParser.isImageData($0) }.count
        print("✓ \(file): v\(movie.version) \(Int(movie.videoSize.width))x\(Int(movie.videoSize.height)) fps=\(movie.fps) frames=\(movie.frames) sprites=\(movie.sprites.count) images=\(movie.images.count)(bitmap \(bitmapCount)) audios=\(movie.audios.count)")
        for (i, s) in movie.sprites.prefix(3).enumerated() {
            print("    sprite\(i): imageKey=\(s.imageKey) matteKey=\(s.matteKey ?? "nil") frames=\(s.frames.count)")
            if let f = s.frames.first {
                print("      frame0: alpha=\(f.alpha) layout=\(f.layout) shapes=\(f.shapes.count) clip=\(f.clipPath ?? "nil")")
            }
        }
    } catch {
        print("✗ \(file): 解析失败 — \(error)")
        failures += 1
    }
}
print(failures == 0 ? "全部通过" : "\(failures) 个失败")
exit(failures == 0 ? 0 : 1)
