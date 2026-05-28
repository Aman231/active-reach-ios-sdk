# Install via Swift Package Manager

## Add the dependency

In Xcode: **File → Add Package Dependencies** → paste:

```
https://github.com/Aman231/active-reach-ios-sdk.git
```

Pin to `Up to next major version` from `1.6.0`.

Or in `Package.swift`:

```swift
let package = Package(
    name: "YourApp",
    platforms: [.iOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/Aman231/active-reach-ios-sdk.git", from: "1.6.0"),
    ],
    targets: [
        .target(
            name: "YourApp",
            dependencies: [
                .product(name: "ActiveReachSDK", package: "active-reach-ios-sdk"),
                // Optional modules — add only what you need:
                .product(name: "ActiveReachInApp", package: "active-reach-ios-sdk"),
                .product(name: "ActiveReachPush", package: "active-reach-ios-sdk"),
            ]
        ),
        // Notification Service Extension target — if you ship one:
        .target(
            name: "YourAppNotificationService",
            dependencies: [
                .product(name: "ActiveReachNotificationService", package: "active-reach-ios-sdk"),
            ]
        ),
    ]
)
```

## Available products

| Product | What it ships |
|---|---|
| `ActiveReachSDK` | Core analytics, identity, consent, governance, transport |
| `ActiveReachInApp` | Modal / banner / sticky-bar / coach-mark / spinner / quiz renderers |
| `ActiveReachPush` | APNs token registration + push lifecycle |
| `ActiveReachNotificationService` | NSE bridge for rich-media push |
| `ActiveReachLocation` | Geo-fence helpers + region monitoring |

## Initialize

Same as CocoaPods — see [CocoaPods.md § Initialize](CocoaPods.md#initialize).

## Versioning + breaking changes

We use semantic versioning. Major-version pin (`from: "1.6.0"`) is the
recommended default — it'll auto-update through `1.x.x` without breaking
API.

## Troubleshooting

### `Package resolution failed: no swift-tools-version compatible`
Make sure your Xcode is 15+ (Swift 5.9 required).

### `Resource 'PrivacyInfo.xcprivacy' could not be found`
Run **File → Packages → Reset Package Caches** in Xcode, then rebuild.
The privacy manifest ships as a SPM resource on the Core target.

### Build error on the `ActiveReachLocation` product
This product depends on `CoreLocation.framework`. If your target doesn't
already link CoreLocation, add it explicitly under **Frameworks,
Libraries, and Embedded Content**.
