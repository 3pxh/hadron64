#!/bin/zsh
# Records the 6.9" iPhone App Store preview: a Simple Cards 3 deck played slowly by autoplay, then Free Play.
# Records on iPhone Air (same aspect as the 6.9" class) and encodes 886×1920, 30fps, H.264 with a silent stereo track.
# Usage: scripts/screenshots/record_preview.sh   → build/appstore/app-preview-iphone-6.9.mp4
set -e
cd "$(dirname "$0")/../.."
device="iPhone Air"
bundle=com.hoqqanen.hadron64
out=build/video
mkdir -p $out build/appstore

xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" -b >/dev/null
xcodebuild -project Hadron64.xcodeproj -scheme Hadron64 -destination "platform=iOS Simulator,name=$device" \
  -derivedDataPath build/derived-video build -quiet
xcrun simctl install "$device" build/derived-video/Build/Products/Debug-iphonesimulator/Hadron64.app

record() {
  local name=$1 secs=$2; shift 2
  xcrun simctl terminate "$device" $bundle 2>/dev/null || true
  xcrun simctl io "$device" recordVideo --codec h264 --force $out/$name.mov >/dev/null 2>&1 &
  local pid=$!
  sleep 1.5
  xcrun simctl launch "$device" $bundle -hasSeenTutorial YES -AppleLanguages "(en)" "$@" >/dev/null
  sleep $secs
  kill -INT $pid
  wait $pid 2>/dev/null || true
}
record simple 17 -debugScreen simple3 -debugAutoplay 0.9
record free 20 -debugScreen freePlay -debugAutoplay 0.75

# The game appears ~4s into each recording; Simple Cards clears its deck and shows the result card by ~9s,
# which then holds for ~2s (the recording stops at the last change, so tpad repeats that frame).
ffmpeg -loglevel error -y \
  -ss 4.0 -t 11.5 -i $out/simple.mov -ss 3.4 -t 17.0 -i $out/free.mov \
  -f lavfi -t 28.0 -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -filter_complex "[0:v]fps=30,scale=886:-2,crop=886:1920,setsar=1,format=yuv420p,tpad=stop_mode=clone:stop_duration=3,trim=duration=11.5,setpts=PTS-STARTPTS[a];\
[1:v]fps=30,scale=886:-2,crop=886:1920,setsar=1,format=yuv420p,tpad=stop_mode=clone:stop_duration=2,trim=duration=17,setpts=PTS-STARTPTS[b];\
[a][b]xfade=transition=fade:duration=0.5:offset=11.0[v]" \
  -map "[v]" -map 2:a -c:v libx264 -profile:v high -level 4.0 -preset slow -b:v 10M -maxrate 12M -bufsize 20M -r 30 \
  -c:a aac -b:a 256k -ar 48000 -movflags +faststart -pix_fmt yuv420p build/appstore/app-preview-iphone-6.9.mp4
echo "wrote build/appstore/app-preview-iphone-6.9.mp4"
