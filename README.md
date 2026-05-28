# Active Reach iOS SDK

[![Pod Version](https://img.shields.io/cocoapods/v/ActiveReachSDK.svg)](https://cocoapods.org/pods/ActiveReachSDK)
[![Platform](https://img.shields.io/cocoapods/p/ActiveReachSDK.svg)](https://cocoapods.org/pods/ActiveReachSDK)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/cocoapods/l/ActiveReachSDK.svg)](LICENSE)

Official iOS SDK for the **[Active Reach Platform](https://active-reach.ai)** —
event tracking, identity resolution, in-app messaging, push notifications,
consent management, and journey orchestration.

## Requirements

- iOS 13.0+
- Swift 5.9 / Xcode 15+

## Install

The SDK ships as a single pod with feature subspecs (or as Swift Package
Manager products):

| Module | CocoaPods | SPM product |
|---|---|---|
| Core analytics + identity | `ActiveReachSDK` *(default)* | `ActiveReachSDK` |
| In-app messaging | `ActiveReachSDK/InApp` | `ActiveReachInApp` |
| Push notifications | `ActiveReachSDK/Push` | `ActiveReachPush` |
| Notification Service Extension | `ActiveReachSDK/NotificationService` | `ActiveReachNotificationService` |
| Geo-fence / location | `ActiveReachSDK/Location` | `ActiveReachLocation` |

### CocoaPods

```ruby
# Podfile
pod 'ActiveReachSDK', '~> 1.6'
# Add the features you need:
pod 'ActiveReachSDK/InApp', '~> 1.6'
pod 'ActiveReachSDK/Push',  '~> 1.6'
```

Then `pod install`. See [docs/CocoaPods.md](docs/CocoaPods.md) for the
full integration walk-through.

### Swift Package Manager

```swift
.package(url: "https://github.com/Aman231/active-reach-ios-sdk.git", from: "1.6.0")
```

Add the products you need to your target's dependencies. See
[docs/SwiftPackageManager.md](docs/SwiftPackageManager.md).

## Quick start

```swift
import ActiveReachSDK

@main
struct MyApp: App {
    init() {
        Aegis.shared.initialize(
            writeKey: "pk_live_xxx",
            config: AegisConfig(apiHost: "https://api.active-reach.ai")
        )

        Aegis.shared.track("app_opened", properties: [
            "channel": "organic"
        ])

        Aegis.shared.identify("user_123", traits: [
            "email": "user@example.com",
            "plan": "pro"
        ])
    }

    var body: some Scene { WindowGroup { ContentView() } }
}
```

> The runtime class is `Aegis` for backward compatibility with earlier
> internal builds. The pod / SPM product name (`ActiveReachSDK`) is the
> customer-facing identifier.

## Features

| Area | Public API |
|---|---|
| **Events** | `Aegis.shared.track()`, `screen()`, `identify()`, `alias()`, `group()`, `reset()` |
| **E-commerce** | `Aegis.shared.ecommerce` — 19 canonical events (productViewed, addToCart, checkoutStarted, …) |
| **In-app** | `AegisInAppManager.shared` — modal / banner / sticky bar / coach mark / spinner / quiz |
| **Push** | `AegisPushManager.shared` + NSE integration |
| **Consent** | `Aegis.shared.consent` — 4 canonical categories (analytics, marketing, personalisation, functional) |
| **Governance** | `TraitGovernor`, `NameGovernor` — client-side guards mirroring the server-side chokepoint |
| **Plugins** | `Aegis.shared.plugins` — first-party + custom plugin extension surface |

## Documentation

- **[CocoaPods install](docs/CocoaPods.md)**
- **[Swift Package Manager install](docs/SwiftPackageManager.md)**
- **[Push notification setup](docs/PushSetup.md)**
- **[In-app messaging](docs/InAppMessaging.md)**
- **[Privacy + App Store submission](docs/Privacy.md)**

Full developer portal: **<https://docs.active-reach.ai/developers/sdks/ios-sdk>**

## Sample app

A SwiftUI starter is included under `Examples/SwiftUIStarter/` — clone
the repo and open `Examples/SwiftUIStarter/SwiftUIStarter.xcodeproj`.

## Related SDKs

The Active Reach Platform ships SDKs across 5 runtimes — all share the
same event contract, identity graph, and in-app/push topology:

| Runtime | Package | Registry |
|---|---|---|
| Web (browser) | `@active-reach/web-sdk` | [npm](https://www.npmjs.com/package/@active-reach/web-sdk) |
| React Native | `@active-reach/react-native-sdk` | [npm](https://www.npmjs.com/package/@active-reach/react-native-sdk) |
| Android (Kotlin) | `ai.active-reach:android-sdk` | [Maven Central](https://central.sonatype.com/artifact/ai.active-reach/android-sdk) |
| **iOS (Swift)** | **`ActiveReachSDK`** | **[CocoaPods](https://cocoapods.org/pods/ActiveReachSDK) + SPM** |
| Flutter (Dart) | `active_reach_sdk` | [pub.dev](https://pub.dev/packages/active_reach_sdk) |

## Privacy

The SDK ships a `PrivacyInfo.xcprivacy` manifest declaring the data
collected, the system APIs accessed, and the absence of cross-app
tracking. See [docs/Privacy.md](docs/Privacy.md) for the full breakdown.

## Support

- **Email:** [hello@active-reach.ai](mailto:hello@active-reach.ai)
- **Docs:** <https://docs.active-reach.ai>
- **Status:** <https://status.active-reach.ai>

## License

MIT © Active Reach Intelligence LLP — see [LICENSE](LICENSE)
