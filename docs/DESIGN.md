# Hadron 64 — design notes

## The idea

A card is a number 1–63. Its six bits are six dots, so a set (every dot appearing an even number of
times) is a group of cards whose numbers XOR to zero. The game is linear algebra over GF(2)^6
dressed as a calm pattern-matching game.

Consequences the code relies on:

- **Seven cards always contain a set.** Seven vectors in a six-dimensional space are dependent. In
  general an N-dot deck needs N+1 cards, which is where the Simple Cards deals (4/5/6) come from.
- **A deck always finishes.** Each dot is on exactly half of the cards in any `CardMath.deck(mask:)`,
  so the full deck XORs to zero; after any number of sets, whatever is left on the board is a set.
- **Set sizes are 3–7.** Cards are distinct and non-empty, so no set has fewer than three cards.

## Card

`CardGeometry` keeps the print reference's 300 ppi units (2.5" × 3.5" plus 1/16" bleed =
788 × 1088), and everything on screen scales from those numbers, so screen and print match.

Bit `i` is column `i / 3`, row `i % 3`. Rows are yellow `#DDAA33`, red `#BB5566`, blue `#004488`
(Paul Tol's colorblind-safe palette). A dot is solid when row + column is odd, otherwise striped.
Every dot has a black outline.

## Screens

| Screen | File |
|---|---|
| Home | `Views/HomeView.swift` |
| Free Play / Time Trial / Simple Cards | `Views/GameScreen.swift` + `Model/DeckGame.swift` |
| Remainder, Remainder Matching, Set Size | `Training/DrillScreens.swift` + `Training/Drills.swift` |
| Tutorial | `Training/Tutorial.swift` |
| Multiplayer | `Views/MultiplayerScreen.swift` |
| Support / unlock | `Store/SupportView.swift` + `Store/Supporter.swift` |
| Statistics | `Stats/StatisticsView.swift` |

All play screens share `TableLayout` (board slots in 2-3-2 rows with equal gaps, controls row,
collection stack bottom-left, deck bottom-right) and `CardTableView`, which draws every card in one
coordinate space so cards can fly deck → slot → stack. `Table` owns that physical state and its
animations; the game and drill models own the rules.

### Free Play hints

The lightbulb in the Free Play top bar works per round (it resets after each set):

1. First press: shows the size of one of the smallest sets on the board.
2. Second press: sets of 3–4 ring one card that **is** in it; sets of 5–6 cross out one card that
   **isn't**; if the set is the whole board, every card is ringed.

Hinted games still count toward stats but not toward records or leaderboards.

### Training

- **Simple Cards 3/4/5**: decks limited to solids / red+blue / all but yellow-striped, dealt N+1.
- **Remainder**: seven cards; tap the six remainder dots until they match the odd dots across all
  seven. Deals are never all-even, so there is always something to enter.
- **Remainder Matching**: seven full cards. Build a group whose remainder is only yellow, lock it,
  then build a different group with the same remainder. Their union cancels, so the cards in exactly
  one group (the symmetric difference) form a set and are collected; cards in both stay. New cards
  are drawn so the table always has a solution (`CardMath.hasYellowMatch`).
- **Set Size**: seven cards with exactly one set (built from a random basis plus one dependent card);
  answer its size 3–7.

### Tutorial (no words)

Four steps, progress dots at the top: a three-card set with a pointing hand for every tap; four cards
with a decoy; five cards whose only set has four cards; then a real deal. After the first step the
hand only appears when the player stalls, and it points at a wrong card to undo it first. Shown
automatically on first launch, and from `?` on Home or from Training.

### Multiplayer

Up to four people around one phone lying flat. Anyone taps cards; a collected set waits in the middle
(the board is blocked) until it's slid toward the edge of whoever found it, crediting that seat with
the set and its cards. Each edge has a score strip turned to face its player. Multiplayer games don't
go into Statistics.

## Supporter unlock

One non-consumable in-app purchase, `com.hoqqanen.hadron64.supporter` (StoreKit 2, `Supporter`).
Each training mode is free 3 times per calendar day and multiplayer once; Free Play, Time Trial and
the tutorial are always free. Nothing shows until a mode's plays are used up; then it gets a small
lock and tapping it opens the unlock sheet. Home's "Support the Game" opens the same purchase.
Replaying Simple Cards or multiplayer from the results screen counts as another play.
`StoreKit/Hadron64.storekit` backs purchases when running from Xcode.

## Localization

All UI text lives in `Hadron64/Localizable.xcstrings` (plus `InfoPlist.xcstrings`), generated from
`scripts/l10n/translations.py` for 20 languages, with plural variants where a language needs them.
Write UI strings as literals passed to SwiftUI (`Text("…")`, `Label("…", …)`) or `String(localized:)`,
then re-export and rebuild the catalogs:

```sh
xcodebuild -exportLocalizations -project Hadron64.xcodeproj -localizationPath build/loc -exportLanguage en
python3 scripts/l10n/build_catalogs.py "build/loc/en.xcloc/Localized Contents/en.xliff"   # lists missing keys
```

Cards, the table, dot rows and the multiplayer board use `fixedCardLayout()` so right-to-left
languages never mirror them: a dot's column is part of its meaning.

## Statistics

`StatsStore` saves to `Application Support/hadron64-stats.json`:

- `FindEvent`: date, mode, duration, card numbers (the set; for Remainder, all seven), hint level.
- `GameRecord`: date, mode, duration, completed, cards collected, sets found, hints used.

The Statistics screen shows per mode: summary tiles, a histogram of find times (filterable by set
size), and day-by-day trends (7/30/90/365 days) of deck time (or Time Trial cards) and find time,
drawn as two separate charts rather than one dual-axis chart.

## Game Center

See [GAMECENTER.md](GAMECENTER.md).

## Development

```sh
xcodegen generate          # project.yml → Hadron64.xcodeproj
xcodebuild -scheme Hadron64 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
swift scripts/make_icon.swift Hadron64/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

Debug builds accept launch arguments for screenshots and testing:

- `-debugScreen <freePlay|timeTrialHard|simple3|remainder|remainderMatch|setSize|multiplayer|training|statistics>`
  and `-hasSeenTutorial YES` jump straight to a screen.
- `-debugFinds N`, `-debugClock S`, `-debugHint N`, `-debugSelect N` stage a game: collect N sets, push
  the clock forward, press the hint, leave a partial selection (or enter remainder dots).
- `-debugAutoplay 0.9` plays a whole deck, one tap every 0.9s (for the app preview video).
- `-debugSeedStats YES` shows six weeks of generated stats (in memory only).
- `-debugSupporter YES` acts as if the unlock was bought.

App Store assets: see [APPSTORE.md](APPSTORE.md).
