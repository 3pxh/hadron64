# App Store submission

## In-app purchase (App Store Connect → Monetization → In-App Purchases)

| Field | Value |
|---|---|
| Type | Non-Consumable |
| Product ID | `com.hoqqanen.hadron64.supporter` (must match `Supporter.productID`) |
| Reference name | Supporter |
| Display name | Supporter |
| Description | Support the game and unlock unlimited training and multiplayer. |
| Family Sharing | On (matches `StoreKit/Hadron64.storekit`) |
| Price | Your choice; the local StoreKit file uses 2.99 for testing only |

Add display name and description localizations for the same 20 languages as the app. Attach the
purchase to the first app version you submit, and include a review screenshot of the unlock sheet
(`SupportView`): `build/appstore/iap-review-screenshot.png`. To retake it (simulator runs don't load the
StoreKit file, so `-debugPrice` fills in the button's price):

```sh
xcrun simctl launch "iPhone 17 Pro Max" com.hoqqanen.hadron64 -hasSeenTutorial YES -debugScreen support -debugPrice 2.99
xcrun simctl io "iPhone 17 Pro Max" screenshot build/appstore/iap-review-screenshot.png
```

**Review notes** (paste into App Review Information):
> Training modes are free 3 times per day each and Multiplayer once per day. To see the purchase,
> open Training → Remainder → close it, three times; the fourth tap shows the unlock sheet. It is
> also always available from "Support the Game" on the home screen. Restore Purchase is on the same sheet.

## Screenshots

```sh
scripts/screenshots/capture.sh "iPhone 17 Pro Max" iphone        # 1320×2868 (6.9")
scripts/screenshots/capture.sh "iPad Pro 13-inch (M5)" ipad      # 2064×2752 (13")
scripts/screenshots/capture.sh "iPhone 17 Pro Max" iphone de ja  # just some languages
```

Output: `build/screenshots/<iphone|ipad>/<language>/1-play.png … 9-home.png`, captioned in that
language (captions: `scripts/screenshots/captions.json`). Upload them in order; the first three
appear in search results, so they're gameplay, multiplayer and Time Trial.

Language folder → App Store Connect localization: `pt-BR` → Portuguese (Brazil), `zh-Hans` →
Chinese (Simplified), `zh-Hant` → Chinese (Traditional), `es` → Spanish (Spain or Mexico),
`fr` → French, and so on.

## App preview

```sh
scripts/screenshots/record_preview.sh   # → build/appstore/app-preview-iphone-6.9.mp4
```

886×1920, 30fps, H.264, about 28s, silent stereo track. It shows a Simple Cards 3 deck being played
slowly (four cards, so the rule is easy to follow), then Free Play. It has no text, so one file works
for every localization. Pick a poster frame with cards selected (around 0:07).
