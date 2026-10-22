#!/bin/zsh
# Captures raw App Store screenshots in every language, using the debug staging launch arguments, then frames them.
# Usage: scripts/screenshots/capture.sh "iPhone 17 Pro Max" iphone [lang ...]
#        scripts/screenshots/capture.sh "iPad Pro 13-inch (M5)" ipad
# Output: build/screenshots/<device>/<lang>/*.png (raw captures in build/screenshots/raw/...).
set -e
cd "$(dirname "$0")/../.."
device=$1
kind=$2
shift 2
langs=("$@")
(( $#langs )) || langs=(en de fr es it pt-BR nl pl ru uk tr vi id th ja ko zh-Hans zh-Hant hi ar)
bundle=com.hoqqanen.hadron64
derived=build/derived-$kind

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcodebuild -project Hadron64.xcodeproj -scheme Hadron64 -configuration Debug \
  -destination "platform=iOS Simulator,name=$device" -derivedDataPath $derived build -quiet
xcrun simctl install "$device" $derived/Build/Products/Debug-iphonesimulator/Hadron64.app
xcrun simctl status_bar "$device" override --time 9:41 --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 --dataNetwork wifi

for lang in $langs; do
  raw=build/screenshots/raw/$kind/$lang
  mkdir -p $raw
  # name, seconds to wait, launch arguments
  shot() {
    local name=$1 wait=$2; shift 2
    local tutorial=(-hasSeenTutorial YES)
    [[ " $* " == *" -hasSeenTutorial "* ]] && tutorial=()
    xcrun simctl terminate "$device" $bundle 2>/dev/null || true
    xcrun simctl launch "$device" $bundle -AppleLanguages "($lang)" -AppleLocale "${lang/-/_}" \
      $tutorial -hidesFreePlayClock NO "$@" >/dev/null
    sleep $wait
    xcrun simctl io "$device" screenshot "$raw/$name.png" >/dev/null 2>&1
  }
  shot 1-play          11 -debugScreen freePlay -debugFinds 4 -debugClock 141 -debugSelect 2
  shot 2-multiplayer   18 -debugScreen multiplayer -debugFinds 6
  shot 3-timetrial      9 -debugScreen timeTrialHard -debugFinds 3
  shot 4-stats          4 -debugScreen statistics -debugSeedStats YES
  shot 5-training       3 -debugScreen training
  shot 6-remainder      4 -debugScreen remainder -debugSelect 2
  shot 7-hint          13 -debugScreen freePlay -debugFinds 6 -debugClock 263 -debugHint 2
  shot 8-tutorial       4 -hasSeenTutorial NO
  shot 9-home           3
  swift scripts/screenshots/frame.swift $raw build/screenshots/$kind/$lang $lang
done
