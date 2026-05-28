# In-app messaging

The Active Reach iOS SDK ships five preload-first in-app message
renderers — modal, sticky bar, coach mark, spinner, and quiz/rating.
Campaigns are pulled over SSE at SDK init and pre-rendered to disk so
they survive backgrounding without re-fetching.

## Install

### CocoaPods

```ruby
pod 'ActiveReachSDK/InApp', '~> 1.6'
```

### SPM

Add the `ActiveReachInApp` product to your app target.

## Initialize

```swift
import ActiveReachSDK
import ActiveReachInApp

Aegis.shared.initialize(writeKey: "pk_live_xxx")
AegisInAppManager.shared.start()
```

That's it — campaigns scheduled in the Active Reach dashboard now render
automatically based on their trigger rules (event match, time on screen,
exit intent, etc.).

## Render types

| Type | When to use |
|---|---|
| `modal` | High-attention announcements, welcome flows |
| `banner` | Persistent top/bottom-of-screen messaging |
| `sticky_bar` | Promo strips that stay across screens |
| `coach_mark` | Onboarding tours, feature spotlights |
| `spinner` | Engagement / gamification (spin-to-win) |
| `quiz` / `rating` | Survey, NPS, in-app rating prompts |

All types share the same campaign config in the dashboard — you don't
have to commit to a render type at integration time.

## Programmatic triggers

For campaigns scheduled with a `manual` trigger, fire them yourself:

```swift
AegisInAppManager.shared.triggerCampaign("welcome_modal")
```

## Suppression + conversion

If a campaign offers a discount and the user converts, suppress
re-display:

```swift
AegisInAppManager.shared.notifyConversion(campaignId: "cart_recovery_5pct")
```

The SDK then marks that campaign as `converted` in local storage and
the server fan-out stops further sends.

## Custom render callback

To intercept the campaign payload and render with your own UI:

```swift
AegisInAppManager.shared.onCampaignReady = { campaign in
    // Inspect campaign.type, campaign.config, campaign.assignedVariantId
    // Return true to consume (SDK won't render), false to defer to default.
    return showInMyCustomShell(campaign)
}
```

## Backgrounding behaviour

Campaigns are fetched at SDK init and on `app_foreground` via SSE
(`/v1/stream/realtime`). When SSE is unavailable (e.g. cellular drop),
the SDK falls back to polling `/v1/inapp/active` every 60s.

On backgrounding, in-flight renderers complete or dismiss gracefully —
no orphan UI on relaunch.

## Tracking

The SDK automatically tracks:

| Event | When |
|---|---|
| `in_app.displayed` | Renderer becomes visible |
| `in_app.clicked` | User taps a CTA |
| `in_app.dismissed` | User taps close / swipes away |
| `in_app.timed_out` | Auto-dismiss timer fires |

Each event includes the campaign ID, variant ID, and position metadata.

## Troubleshooting

### No campaigns show
- Confirm the write key matches the workspace you're scheduling
  campaigns in.
- Check Console for `[Active Reach] Campaign matched: <id>` — if you
  don't see it, the campaign's trigger rules probably aren't matching.
- Use **Active Reach dashboard → In-app messages → Preview** to render
  the campaign on a connected device.

### Stuck in landscape / wrong layout
- The SDK targets iPhone-portrait by default. For iPad / landscape, set
  `AegisInAppManager.shared.supportedOrientations = .all`.

### Spinner / quiz form submit fails
- These render types POST to `/v1/widgets/*/submit`. Verify the host
  app has Internet access and the write key has the corresponding
  widget capability enabled in the dashboard.
