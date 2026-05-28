# Push notification setup

The Active Reach iOS SDK supports rich push (image, video, button
actions) via a Notification Service Extension (NSE), plus full lifecycle
tracking (`push.delivered`, `push.clicked`, `push.dismissed`).

## 1. Enable Push Capability

In Xcode: select your app target → **Signing & Capabilities** → **+
Capability** → **Push Notifications**.

Also enable **Background Modes** → **Remote notifications**.

## 2. Add the Push subspec / product

### CocoaPods

```ruby
pod 'ActiveReachSDK/Push', '~> 1.6'
```

### SPM

Add the `ActiveReachPush` product to your app target.

## 3. Register for notifications

```swift
import ActiveReachSDK
import ActiveReachPush
import UserNotifications

@main
struct YourApp: App {
    init() {
        Aegis.shared.initialize(writeKey: "pk_live_xxx")
        registerForPush()
    }
    var body: some Scene { WindowGroup { ContentView() } }
}

func registerForPush() {
    UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound, .badge]
    ) { granted, _ in
        guard granted else { return }
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
```

The SDK swizzles `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
to capture the APNs token automatically. If you've disabled swizzling
(`AegisConfig.disablePushSwizzling = true`), call
`AegisPushManager.shared.setDeviceToken(_:)` manually.

## 4. Notification Service Extension (rich push)

Add a new target in Xcode: **File → New → Target → Notification Service Extension**.

In the NSE's `Podfile` target:

```ruby
target 'YourAppNotificationService' do
  use_frameworks!
  pod 'ActiveReachSDK/NotificationService', '~> 1.6'
end
```

Edit the auto-generated `NotificationService.swift`:

```swift
import UserNotifications
import ActiveReachNotificationService

class NotificationService: UNNotificationServiceExtension {

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        // Active Reach NSE handles media fetch + button actions:
        ActiveReachNotificationService.handle(
            request: request,
            withContentHandler: contentHandler
        )
    }

    override func serviceExtensionTimeWillExpire() {
        ActiveReachNotificationService.serviceExtensionTimeWillExpire()
    }
}
```

## 5. App Group (shared between app + NSE)

For consent state + push delivery counters to flow between the main app
and the NSE, configure an App Group:

1. **Signing & Capabilities** → **+ Capability** → **App Groups** on
   BOTH the main app target and the NSE target.
2. Use the same group ID (e.g. `group.com.yourcompany.activereach`).
3. In the main app's `AegisConfig`:
   ```swift
   AegisConfig(
       apiHost: "https://api.active-reach.ai",
       appGroupSuiteName: "group.com.yourcompany.activereach"
   )
   ```

Without an App Group, push delivered/clicked events still fire from the
main app, but the NSE-side `push.delivered` event is suppressed (the
extension can't read the consent prefs from the main process).

## 6. Tracking lifecycle events

The SDK automatically tracks:

| Event | When |
|---|---|
| `push.delivered` | NSE fires (rich push) OR app receives in foreground |
| `push.clicked` | User taps the notification |
| `push.dismissed` | User swipes away (iOS 14+) |

Each event includes the campaign ID, push ID, and platform metadata in
its properties.

## Troubleshooting

### Token not registering
- Ensure Push Notifications + Background Modes capabilities are enabled.
- Check Console for `[Active Reach] APNs token registered: <token>`.
- Verify `Aegis.shared.initialize(writeKey:)` ran before
  `registerForRemoteNotifications()`.

### Rich media not loading in NSE
- Confirm the NSE target imports `ActiveReachNotificationService`.
- Check that the push payload includes `mutable-content: 1` in `aps`.
- NSE time budget is ~30s — slow networks may time out; the SDK fetches
  with a 20s timeout to leave headroom.

### `push.delivered` not firing
- Most likely no App Group is configured — NSE can't talk to the main
  app. Either set up an App Group (recommended) or accept that you only
  get `delivered` for foreground pushes.
