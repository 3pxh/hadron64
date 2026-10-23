# Game Center integration

Status: **built, not switched on.** Everything is a no-op while `GameCenterService.isEnabled == false`.
The app's own `StatsStore` stays the source of truth; Game Center only receives copies.

| File | What it holds |
|---|---|
| `Hadron64.gamekit` | **The Game Center records themselves**: IDs, names, descriptions, images, formats, links. Edit in Xcode's GameKit editor; Xcode pushes it to App Store Connect. |
| `Hadron64/GameCenter/GameCenterCatalog.swift` | The same IDs from the app's side, plus scoring and unlock rules. |
| `Hadron64Tests/GameKitBundleTests.swift` | Fails if the bundle and the catalog disagree on IDs, points, visibility, formats or links. |
| `scripts/make_gamecenter_art.swift` | Renders the achievement badges and activity/challenge banners into `GameCenterArt/`. |
| `Hadron64/GameCenter/GameCenterService.swift` | GameKit plumbing: sign-in, score/achievement reporting, friends, activity deep links. |
| `Hadron64/GameCenter/FriendsCard.swift` | Statistics screen card: friends today / all time, Add Friends, Challenge, All Players. |
| `Hadron64Tests/GameCenterCatalogTests.swift` | Catches duplicate IDs, point-limit overruns, and challenges/activities pointing at missing records. |

To add or change a record, change it in both the bundle (in Xcode) and the catalog; the bundle test keeps
them honest. The old App Store Connect setup sheet (https://claude.ai/artifact/KnPt12hLbgTNtSARZHEiWV)
is superseded by the bundle.

## What players get

| Feature | How |
|---|---|
| All-time + daily leaderboards | Classic + Recurring board per public mode (Free Play, Time Trial ×3) |
| Achievements | 14, rules in the catalog, backfilled from local history on sign-in |
| Friends' scores | Friends card on Statistics; "2nd of 5 friends today" on the results card |
| Challenges (iOS 26) | One per public mode on its all-time board; Challenge button on the Friends card |
| Activities (iOS 26) | Games app deep links into a mode via the `mode` property |
| Dashboard | `GKAccessPoint` badge on the home screen (hidden during play) |

## Flow

1. **Launch**: `Hadron64App` calls `authenticate(stats:)`. On sign-in it shows the access point, registers
   the activity listener, loads achievement progress, and reports anything local history has earned.
2. **Finds**: `StatsStore.log(_ event:)` → `syncAchievements()`. Progress is reported in whole percents,
   only when it moves forward, so this is cheap.
3. **Finish**: `DeckGame.finish` → `StatsStore.log(_ game:)` → `submit` (scores to both of the mode's
   boards in one call, plus achievements). Free Play submits only completed, hint-free decks.
4. **Results**: `ResultsView` awaits the submission, then shows today's rank among friends if any friend
   has played today and friends access is already granted (it never prompts there).
5. **Statistics**: `FriendsCard` asks for friends access the first time, then lists friends' entries
   sorted by rank, with Game Center's own score formatting.
6. **Activities**: `player(_:wantsToPlay:)` sets `requestedMode`; `HomeView` opens that game.

Daily boards reset once a day at the same moment worldwide (the platform has no per-player local
midnight). The bundle starts them at 08:00 UTC, midnight Pacific in winter.

## Turning it on

1. Add the Game Center entitlement in `project.yml` under the `Hadron64` target, then `xcodegen generate`:
   ```yaml
   entitlements:
     path: Hadron64/Hadron64.entitlements
     properties:
       com.apple.developer.game-center: true
   ```
2. In App Store Connect, enable Game Center for the app, then open `Hadron64.gamekit` in Xcode and push
   it to App Store Connect from the GameKit editor.
3. Set `GameCenterService.isEnabled = true`.
4. Test on a device with a sandbox Game Center account. Debug builds can use the bundle's records before
   they're pushed. Challenges and activities need iOS 26.

## Notes and edge cases

- **Offline**: GameKit queues and retries score submissions itself; failures are only logged.
- **Cheating**: scores are client-reported. Consider a score range on the Free Play boards that rejects
  sub-minute decks (not set yet).
- **Hints**: hinted Free Play games never reach leaderboards or the deck-time achievements.
- **Rule changes**: if deck size or timings change, add new IDs (e.g. `h64.v2.…`) instead of mixing
  scores that can't be compared. Never rename `GameMode` raw values; activities depend on them.
- **Localization**: names and descriptions players see come from the bundle's localizations (en-US only so
  far), not the app. The Friends card and results strings are in `Localizable.xcstrings` and need translations.
