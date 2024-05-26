// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "libnetpbm",
    products: [
        .library(name: "libnetpbm", targets: ["libnetpbm"]),
        .library(name: "netpbm", targets: ["netpbm"]), // Swift wrapper over libnetpbm
        .executable(name: "example", targets: ["example"]),
        .executable(name: "flipbit", targets: ["flipbit-example"])
    ],
    targets: [
        .target(
            name: "libnetpbm",
            dependencies: [],
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
