import Foundation
import CoreImage
import AppKit

// usage: swift recolor-icon.swift <in.png> <out.png> <hueRadians>
let args = CommandLine.arguments
guard args.count == 4,
      let inData = try? Data(contentsOf: URL(fileURLWithPath: args[1])),
      let inImg = CIImage(data: inData) else {
    FileHandle.standardError.write("bad args / cannot read input\n".data(using: .utf8)!)
    exit(1)
}
let angle = Float(args[3]) ?? 3.14159

let hue = CIFilter(name: "CIHueAdjust")!
hue.setValue(inImg, forKey: kCIInputImageKey)
hue.setValue(angle, forKey: "inputAngle")
let out = hue.outputImage!

let ctx = CIContext()
guard let cg = ctx.createCGImage(out, from: out.extent) else { exit(2) }
let rep = NSBitmapImageRep(cgImage: cg)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(3) }
try! png.write(to: URL(fileURLWithPath: args[2]))
