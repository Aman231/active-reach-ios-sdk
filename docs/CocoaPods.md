# Install via CocoaPods

## Add the pod

```ruby
# Podfile
platform :ios, '13.0'

target 'YourApp' do
  use_frameworks!

  # Core analytics + identity (event tracking, identify, consent).
  pod 'ActiveReachSDK', '~> 1.6'

  # Optional subspecs — add only the features you need.
  pod 'ActiveReachSDK/InApp', '~> 1.6'
  pod 'ActiveReachSDK/Push',  '~> 1.6'
end

# If you ship a Notification Service Extension (rich push):
target 'YourAppNotificationService' do
  use_frameworks!
  pod 'ActiveReachSDK/NotificationService', '~> 1.6'
end
```

Then:

```bash
pod install --repo-update
open YourApp.xcworkspace
```

## Initialize

```swift
import ActiveReachSDK

@main
struct YourApp: App {
    init() {
        Aegis.shared.initialize(
            writeKey: "pk_live_xxx",
            config: AegisConfig(
                apiHost: "https://api.active-reach.ai",
                encryptLocalStorage: true,      // encrypt the on-disk event queue
                autoSessionTracking: true,      // start/stop sessions on app fg/bg
                enableRemoteConfig: true        // fetch /v1/sdk/config at init
            )
        )
    }

    var body: some Scene { WindowGroup { ContentView() } }
}
```

## Versioning

We use semantic versioning. Pin to a minor range (`'~> 1.6'`) to get
bug-fix updates without breaking changes.

## Troubleshooting

### `pod install` resolves the wrong version
Run `pod repo update` first to refresh the local trunk mirror.

### `Module 'ActiveReachSDK' not found`
Make sure you opened the `.xcworkspace` Xcode generated, not the
`.xcodeproj`.

### Build error about Swift version
The SDK is built with Swift 5.9 / Xcode 15. If your project pins
`SWIFT_VERSION = 5.0`, raise it in **Build Settings**.

## Migration from earlier internal builds

If you integrated an earlier internal build that imported `AegisCore` /
`AegisInApp` / `AegisPush`:

| Old (internal) | New (public) |
|---|---|
| `import AegisCore` | `import ActiveReachSDK` |
| `import AegisInApp` | `import ActiveReachInApp` (SPM) / `pod 'ActiveReachSDK/InApp'` |
| `import AegisPush` | `import ActiveReachPush` (SPM) / `pod 'ActiveReachSDK/Push'` |

The runtime class is still named `Aegis` to keep migration friction
minimal — only the module / pod / import name changes.
