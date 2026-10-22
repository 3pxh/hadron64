# Game Center integration

Status: **built, not switched on.** Everything is a no-op while `GameCenterService.isEnabled == false`.
The app's own `StatsStore` stays the source of truth; Game Center only receives copies.

| File | What it holds |
|---|---|
| `Hadron64/GameCenter/GameCenterCatalog.swift` | **Every leaderboard, achievement, challenge and activity**: IDs, names, scoring and unlock rules. Edit here. |
| `Hadron64/GameCenter/GameCenterService.swift` | GameKit plumbing: sign-in, score/achievement reporting, friends, activity deep links. |
| `Hadron64/GameCenter/FriendsCard.swift` | Statistics screen card: friends today / all time, Add Friends, Challenge, All Players. |
| `Hadron64Tests/GameCenterCatalogTests.swift` | Catches duplicate IDs, point-limit overruns, and challenges/activities pointing at missing records. |

App Store Connect setup sheet (every ID, name, description and setting to type in):
https://claude.ai/artifact/KnPt12hLbgTNtSARZHEiWV. Keep it in sync with the catalog.

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
midnight). The sheet suggests 08:00 UTC, midnight Pacific in winter.

## Turning it on

1. Add the Game Center entitlement in `project.yml` under the `Hadron64` target, then `xcodegen generate`:
   ```yaml
   entitlements:
     path: Hadron64/Hadron64.entitlements
     properties:
       com.apple.developer.game-center: true
   ```
2. In App Store Connect, enable Game Center and create everything in the setup sheet.
3. Set `GameCenterService.isEnabled = true`.
4. Test on a device with a sandbox Game Center account. Records created in App Store Connect are visible
   to development builds before release. Challenges and activities need iOS 26.

## Notes and edge cases

- **Offline**: GameKit queues and retries score submissions itself; failures are only logged.
- **Cheating**: scores are client-reported. The sheet sets score ranges that reject sub-minute decks.
- **Hints**: hinted Free Play games never reach leaderboards or the deck-time achievements.
- **Rule changes**: if deck size or timings change, add new IDs (e.g. `h64.v2.…`) instead of mixing
  scores that can't be compared. Never rename `GameMode` raw values; activities depend on them.
- **Localization**: names and descriptions players see come from App Store Connect's localizations, not
  the app. The Friends card and results strings are in `Localizable.xcstrings` and need translations.
