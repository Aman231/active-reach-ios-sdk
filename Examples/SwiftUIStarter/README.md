# SwiftUIStarter — Active Reach iOS SDK demo

A minimal SwiftUI iOS app demonstrating Active Reach SDK integration:
init, track, identify, e-commerce events, in-app messaging, and push.

## Setup (one-time)

1. Open Xcode 15+ → **File → New → Project → iOS → App**
2. Product Name: `SwiftUIStarter`, Interface: SwiftUI, Language: Swift,
   Minimum Deployments: iOS 13.0
3. Save into this `Examples/SwiftUIStarter/` directory.
4. **File → Add Package Dependencies** → paste:
   ```
   https://github.com/Aman231/active-reach-ios-sdk.git
   ```
   Add the `ActiveReachSDK`, `ActiveReachInApp`, and `ActiveReachPush`
   products to your target.
5. Replace `SwiftUIStarterApp.swift` with [`SwiftUIStarterApp.swift`](SwiftUIStarterApp.swift).
6. Replace `ContentView.swift` with [`ContentView.swift`](ContentView.swift).
7. In `SwiftUIStarterApp.swift`, replace `pk_live_xxx` with your write key
   from the Active Reach dashboard.
8. Build & run on simulator or device.

## What this demo shows

- **Init**: SDK lifecycle on app launch (`Aegis.shared.initialize`)
- **Identify**: associating events with a user ID + traits
- **Track**: custom events with properties
- **E-commerce**: canonical commerce events via `Aegis.shared.ecommerce`
- **In-app**: campaign-driven modal triggered by `trigger_modal` event
- **Push**: APNs registration + lifecycle event tracking
- **Consent**: toggling marketing consent on/off

## Files

- [`SwiftUIStarterApp.swift`](SwiftUIStarterApp.swift) — app entry point
- [`ContentView.swift`](ContentView.swift) — main demo UI

## Troubleshooting

See the [SDK docs](../../docs/) for module-by-module integration guides.
