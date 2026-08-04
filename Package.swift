// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IsaacPet",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "IsaacPetCore", targets: ["IsaacPetCore"]),
        .executable(name: "IsaacPet", targets: ["IsaacPetApp"]),
        .executable(name: "IsaacPetCoreChecks", targets: ["IsaacPetCoreChecks"]),
    ],
    targets: [
        .target(name: "IsaacPetCore"),
        .executableTarget(
            name: "IsaacPetApp",
            dependencies: ["IsaacPetCore"]
        ),
        .executableTarget(
            name: "IsaacPetCoreChecks",
            dependencies: ["IsaacPetCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
