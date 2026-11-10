// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SidebarTodos",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TodoCore", path: "Sources/TodoCore"),
        .executableTarget(
            name: "SidebarTodos",
            dependencies: ["TodoCore"],
            path: "Sources/SidebarTodos"
        ),
        .testTarget(
            name: "TodoCoreTests",
            dependencies: ["TodoCore"],
            path: "Tests/TodoCoreTests"
        ),
    ]
)
