// swift-tools-version: 5.9
import PackageDescription

// Brand canon: customer-facing module names are `ActiveReach*` (set
// via the library `name:`). Internal Swift source directories stay
// at `Sources/Aegis*/` per "Aegis = internal-only" — Swift Package
// Manager allows the target's display name to diverge from its
// `path:`, which keeps the source-tree stable while customers
// `import ActiveReachSDK`.
let package = Package(
    name: "ActiveReachSDK",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6)
    ],
    products: [
        // Core SDK (required)
        .library(
            name: "ActiveReachSDK",
            targets: ["ActiveReachSDK"]
        ),
        // Push Notifications module (optional)
        .library(
            name: "ActiveReachPush",
            targets: ["ActiveReachPush"]
        ),
        // Notification Service Extension (optional)
        .library(
            name: "ActiveReachNotificationService",
            targets: ["ActiveReachNotificationService"]
        ),
        // In-App Messaging module (optional)
        .library(
            name: "ActiveReachInApp",
            targets: ["ActiveReachInApp"]
        ),
        // Location tracking module (optional)
        .library(
            name: "ActiveReachLocation",
            targets: ["ActiveReachLocation"]
        ),
    ],
    dependencies: [
        // SQLite.swift — required by Sources/AegisCore/Core/EventQueue.swift.
        // Matches the version pin in ActiveReachSDK.podspec so SPM + CocoaPods
        // resolve to the same release.
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.1"),
    ],
    targets: [
        // Core SDK target
        .target(
            name: "ActiveReachSDK",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/AegisCore",
            exclude: ["Info.plist"],
            resources: [
                // Apple App Store privacy manifest — required for
                // third-party SDKs on iOS 17+.
                .process("Resources/PrivacyInfo.xcprivacy"),
            ]
        ),

        // Push Notifications target
        .target(
            name: "ActiveReachPush",
            dependencies: ["ActiveReachSDK"],
            path: "Sources/AegisPush",
            exclude: ["Info.plist"]
        ),

        // Notification Service Extension target
        .target(
            name: "ActiveReachNotificationService",
            dependencies: [],
            path: "Sources/AegisNotificationService",
            exclude: ["Info.plist"]
        ),

        // In-App Messaging target
        .target(
            name: "ActiveReachInApp",
            dependencies: ["ActiveReachSDK"],
            path: "Sources/AegisInApp",
            exclude: ["Info.plist"]
        ),

        // Location tracking target
        .target(
            name: "ActiveReachLocation",
            dependencies: ["ActiveReachSDK"],
            path: "Sources/AegisLocation",
            exclude: ["Info.plist"]
        ),

        // Test targets
        .testTarget(
            name: "ActiveReachSDKTests",
            dependencies: ["ActiveReachSDK"],
            path: "Tests/AegisCoreTests",
            // Pinned hash test vectors shared with Python (mmh3) + JS
            // (murmurhash3_x86_32). Any drift in the Swift port fails
            // CI via the GovernanceTests suite.
            resources: [.copy("bloom-test-vectors.json")]
        ),
    ]
)
