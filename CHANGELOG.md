# Changelog

All notable changes to `ActiveReachSDK` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Version 1.6.0](https://github.com/Aman231/active-reach-ios-sdk/releases/tag/1.6.0) — 2026-05-28

First public release on CocoaPods trunk + Swift Package Manager.

### Added

- **Core analytics**: `Aegis.shared.track`, `screen`, `page`, `identify`,
  `alias`, `group`, `reset`. Events queue to local SQLite (encryption
  optional) and batch-POST to `/v1/batch` over HTTP/2 with certificate
  pinning + multi-region cell selection.
- **E-commerce tracker** (`Aegis.shared.ecommerce`): 19 canonical events
  (`productViewed`, `productListViewed`, `productAddedToCart`,
  `checkoutStarted`, `orderCompleted`, `couponApplied`, etc.) with
  Codable payload types.
- **In-app messaging** (`AegisInAppManager.shared`): five preload-first
  renderers — modal, sticky bar, coach mark, spinner, quiz/rating. Pulls
  campaigns over SSE; survives backgrounding via on-disk prefetch bundle.
- **Push notifications** (`AegisPushManager.shared`): APNs token
  registration; canonical `push.delivered` / `push.clicked` /
  `push.dismissed` lifecycle to `/v1/push/engagement`. Notification
  Service Extension bridge for rich media (image / video / button
  actions).
- **Consent management** (`Aegis.shared.consent`): four canonical
  categories — analytics, marketing, personalisation, functional.
  Marketing events bypass when consent denied; identity events ride
  regardless. ATT outcome wires into marketing consent automatically.
- **Governance** (`TraitGovernor`, `NameGovernor`): client-side guards
  mirroring the server-side ingestion chokepoint. Trait writes are
  validated against length / type / forbidden-key rules; event names
  are bloom-filtered against the published-name set so novel names drop
  locally instead of amplifying server load.
- **Plugin system** (`Aegis.shared.plugins`): first-party plugins (Meta
  App Events bridge) + customer-supplied extensions. Plugins receive
  `onInit` / `onTrack` / `onIdentify` / `onScreen` / `onConsentChange` /
  `onReset` lifecycle hooks.
- **Multi-region cell routing** (`CellSelector`): SDK auto-selects the
  closest healthy regional cell at init time and re-selects on cell
  unhealth. Falls back to single-host (`apiHost`) when `cellEndpoints`
  is empty.

### Package layout

This 1.6.0 release ships the Core pod. Push / InApp /
NotificationService / Location ship as SPM products from the same repo; CocoaPods subspecs for those modules land in a patch release once their compile-time API alignment is complete. For now:

```ruby
pod 'ActiveReachSDK'                       # Core analytics + identity (default)
pod 'ActiveReachSDK/InApp'                 # + In-app message renderers
pod 'ActiveReachSDK/Push'                  # + Push lifecycle
pod 'ActiveReachSDK/NotificationService'   # + NSE integration
pod 'ActiveReachSDK/Location'              # + Geo-fence helpers
```

Swift Package Manager ships the same modules as 5 separate products
(`ActiveReachSDK`, `ActiveReachInApp`, `ActiveReachPush`,
`ActiveReachNotificationService`, `ActiveReachLocation`).

### Privacy + App Store

Ships a `PrivacyInfo.xcprivacy` manifest at
`Sources/AegisCore/Resources/PrivacyInfo.xcprivacy` declaring the data
the SDK collects (User ID, Device ID, Product Interaction events) and
the system APIs it accesses (`UserDefaults` reason `CA92.1`).
`NSPrivacyTracking` is set to `false` — the SDK does not engage in
cross-app or cross-website tracking.

### Notes

- **Runtime class is `Aegis`** (the original internal name) for
  backward compatibility with earlier internal builds. The pod / module
  name (`ActiveReachSDK`) is the customer-facing identifier — that's
  what you `pod install` and `import`.
- Identity (anonymous + user ID) persists in Keychain.
- All outbound HTTP uses TLS with certificate pinning enabled by default
  (set custom `AegisConfig.publicKeyHashes` to pin specific keys).
