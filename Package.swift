// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "libnetpbm",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "libnetpbm", targets: ["libnetpbm"]),
        .library(name: "netpbm", targets: ["netpbm"]), // Swift wrapper over libnetpbm
        .executable(name: "example", targets: ["example"]),
        .executable(name: "flipbit", targets: ["flipbit-example"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.1.4")
    ],
    targets: [
        .target(
            name: "libnetpbm",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms")
            ],
            exclude: ["libsystem_dummy.c"],
            publicHeadersPath: "importinc",
            cSettings: [
                .unsafeFlags(
                    [
                    "-O3", "-ffast-math",  "-pedantic", "-fno-common", "-Wall",
                    "-Wno-uninitialized", "-Wmissing-declarations", "-Wimplicit",
                    "-Wwrite-strings", "-Wmissing-prototypes", "-Wundef",
                    "-Wno-unknown-pragmas", "-Wno-strict-overflow",
                    "-Wno-implicit-function-declaration", "-Wmacro-redefined",
                    "-Wno-conversion", "-Wno-strict-prototypes"
                    ]
                ),
                .headerSearchPath("importinc/netpbm"),
            ]
        ),
        .target(
            name: "netpbm",
            dependencies: ["libnetpbm"]
        ),
        .executableTarget(
            name: "example",
            dependencies: [
                "libnetpbm"
            ]
        ),
        .executableTarget(
            name: "flipbit-example",
            dependencies: [
                "libnetpbm"
            ]
        ),
        .testTarget(
            name: "libnetpbmTests",
            dependencies: [
                "libnetpbm"
            ]
        ),
        .testTarget(
            name: "netpbmTests",
            dependencies: [
                "netpbm"
            ]
        )
    ]
)
