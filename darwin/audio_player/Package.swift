// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "audio_player",
    platforms: [
        .iOS("15.0"),
        .macOS("11.0")
    ],
    products: [
        .library(name: "audio-player", targets: ["audio_player"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        // The generated Objective-C wrapper Dart calls AudioPlayerApi through (see tool/ffigen.dart).
        .target(
            name: "audio_player_c",
            path: "Sources/audio_player_c",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include")
            ]
        ),
        .target(
            name: "audio_player",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "audio_player_c"
            ],
            path: "Sources/audio_player"
        )
    ]
)
