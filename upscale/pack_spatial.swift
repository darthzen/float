import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Foundation

// pack_spatial <left> <right> <out.heic>
// Stage 3 of the spatial pipeline: wrap L/R equirects into the 2-image HEIC the
// Float app reads by index (SpatialImageEnvironment: CGImage 0 = left, 1 = right).
// NOTE: macOS 27.0 ImageIO writes the two images but silently DROPS the `ster`
// stereo-pair group (verified). The app doesn't need it (reads by index); a true
// Apple-Spatial file for system recognition needs the ster box injected or
// MV-HEVC via AVFoundation — see notes. This writer targets the app path.
let L = CommandLine.arguments[1], R = CommandLine.arguments[2], OUT = CommandLine.arguments[3]
func load(_ p:String)->CGImage { let s=CGImageSourceCreateWithURL(URL(fileURLWithPath:p) as CFURL,nil)!; return CGImageSourceCreateImageAtIndex(s,0,nil)! }
let left = load(L), right = load(R)

guard let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: OUT) as CFURL,
        UTType.heic.identifier as CFString, 2, nil) else { fatalError("no dst") }

let opts: [String:Any] = [kCGImageDestinationLossyCompressionQuality as String: 0.9]
CGImageDestinationAddImage(dst, left, opts as CFDictionary)
CGImageDestinationAddImage(dst, right, opts as CFDictionary)

// Container-level StereoPair group — matches what the imported_spatial files carry.
let groups: [[String:Any]] = [[
    kCGImagePropertyGroupType as String: kCGImagePropertyGroupTypeStereoPair as String,
    kCGImagePropertyGroupImageIndexLeft as String: 0,
    kCGImagePropertyGroupImageIndexRight as String: 1,
    kCGImagePropertyGroupImageIsAlternateImage as String: false,
]]
let props: [String:Any] = [kCGImagePropertyGroups as String: groups]
CGImageDestinationSetProperties(dst, props as CFDictionary)

if CGImageDestinationFinalize(dst) { print("wrote \(OUT)") } else { print("FINALIZE FAILED") }
