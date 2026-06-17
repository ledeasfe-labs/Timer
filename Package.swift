// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Timer",
    platforms: [
        .iOS("17.0")
    ],
    targets: [
        .executableTarget(
            name: "Timer",
            path: ".",
            exclude: [
                "TimerWidgetExtension",
                "Package.swift",
                "README.md"
            ]
        ),
        .target(
            name: "TimerWidgetExtension",
            path: "TimerWidgetExtension"
        )
    ]
)
