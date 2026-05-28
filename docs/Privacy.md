# Privacy & App Store submission

Active Reach iOS SDK is designed for App Store submission without
additional privacy paperwork on your end. This guide explains what the
SDK collects, why, and how to declare it in your app.

## Privacy manifest (`PrivacyInfo.xcprivacy`)

The SDK ships a `PrivacyInfo.xcprivacy` manifest at
`Sources/AegisCore/Resources/PrivacyInfo.xcprivacy`. CocoaPods bundles
it via `resource_bundles`; SPM via `.process(...)` on the Core target.
You don't need to ship a separate copy in your app.

### What the SDK declares

| Field | Value | Why |
|---|---|---|
| `NSPrivacyTracking` | `false` | The SDK does NOT engage in cross-app or cross-website tracking. No IDFA usage. |
| `NSPrivacyTrackingDomains` | (empty) | No domains in the App Tracking Transparency sense. |
| `NSPrivacyCollectedDataTypeUserID` | linked / not-tracking | Customer-supplied via `Aegis.shared.identify()`. |
| `NSPrivacyCollectedDataTypeDeviceID` | linked / not-tracking | `identifierForVendor` only. No IDFA. |
| `NSPrivacyCollectedDataTypeProductInteraction` | linked / not-tracking | `track` / `screen` / `page` events. |
| `NSPrivacyAccessedAPICategoryUserDefaults` | reason `CA92.1` | SDK config + consent prefs persistence. |

## Data the SDK collects

| Data | Source | Purpose | Storage |
|---|---|---|---|
| User ID | Your `Aegis.shared.identify()` call | Identity resolution, campaign targeting | Keychain (encrypted) |
| Anonymous ID | Auto-generated UUID per install | Pre-login event attribution | Keychain (encrypted) |
| Device ID | `UIDevice.identifierForVendor` | Per-device session attribution | In-memory + Keychain mirror |
| Session ID | Auto-generated per session | Session reconstruction | In-memory + UserDefaults |
| App context | Bundle version / OS version / locale | Crash + behaviour correlation | Sent with each event |
| Network type | `CTTelephonyNetworkInfo` carrier + Reachability | Performance diagnostics | Sent with each event |
| Events | Your `Aegis.shared.track()` calls | Analytics, campaign triggers | SQLite (encrypted optional), batched POST |

### Data NOT collected

- IDFA (Identifier for Advertisers) — the SDK never reads `ASIdentifierManager`
- Contacts, photos, microphone, camera — no permission requests
- Precise location — unless you add `ActiveReachLocation` AND grant
  permission. See [PushSetup.md § Location](#) (TBD section).
- Crash data — use a dedicated crash reporter (Sentry, Crashlytics).

## Consent management

The SDK's `ConsentManager` enforces four canonical consent categories:

| Category | Used for |
|---|---|
| `analytics` | Most `track` / `screen` / `page` events |
| `marketing` | Push notifications, in-app messages, campaign events |
| `personalisation` | Trait writes, segment evaluation |
| `functional` | Always-on (session, identity, crash diagnostics) |

```swift
// Set explicit consent (e.g. from your in-app consent UI):
Aegis.shared.consent.setConsent(
    analytics: true,
    marketing: false,        // user opted out of marketing
    personalisation: true,
    functional: true
)
```

Events with `marketing` category will be DROPPED at the SDK level when
that consent is denied — they never leave the device.

## App Tracking Transparency (ATT)

If you call `ATTrackingManager.requestTrackingAuthorization`, you can
wire the outcome into the SDK's marketing consent automatically:

```swift
ATTrackingManager.requestTrackingAuthorization { status in
    Aegis.shared.consent.applyATTOutcome(status)
}
```

When status is `.denied` or `.notDetermined`, marketing consent flips
to `false`.

## App Store Connect — Privacy "Nutrition Label"

When filling in App Privacy details on App Store Connect:

| App Privacy field | Active Reach SDK contribution |
|---|---|
| Data Used to Track You | None — SDK declares `NSPrivacyTracking=false` |
| Data Linked to You | User ID, Device ID, Product Interaction (events) |
| Data Not Linked to You | None |

The SDK ships the matching declarations in `PrivacyInfo.xcprivacy`, so
App Store Connect's automated cross-check is happy.

## Right to be forgotten (DPDP, GDPR)

To purge a user's local data:

```swift
Aegis.shared.reset()
```

This wipes the user ID, anonymous ID, queued events, and consent state
from Keychain + local storage. To purge server-side data, hit the
`/v1/identity/forget` API documented at
<https://docs.active-reach.ai/api/identity#forget>.

## Cryptographic key handling

- Anonymous + user IDs persist in Keychain with
  `kSecAttrAccessibleAfterFirstUnlock`.
- Local SQLite event queue is optionally encrypted with AES-GCM
  (`AegisConfig.encryptLocalStorage = true`). Key is derived per-device
  via Keychain.
- Outbound HTTPS uses TLS 1.2+ with certificate pinning enabled by
  default. To pin specific public keys, set
  `AegisConfig.publicKeyHashes`.

## Audit / source review

The full SDK source is published at
<https://github.com/Aman231/active-reach-ios-sdk> for security review.
Backend infrastructure remains private; the SDK only sees outbound
HTTPS payloads as documented in the developer docs.
