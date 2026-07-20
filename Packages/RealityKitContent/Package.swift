// swift-tools-version:5.9
// RealityKitContent — houses Reality Composer Pro assets (ShaderGraph materials, scenes) for
// Float. Currently: the `Stereo360` material (camera-index switch) for per-eye stereo 360
// rendering of the imported Apple Spatial skies. See Float/Immersive/SpatialImageEnvironment.swift.
// Structure copied from Apple's "Construct an immersive environment for visionOS" sample.

import PackageDescription

let package = Package(
    name: "RealityKitContent",
    products: [
        .library(
            name: "RealityKitContent",
            targets: ["RealityKitContent"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "RealityKitContent",
            dependencies: [])
    ]
)
