#!/bin/bash
set -e

flutter clean
rm -rf build

# iOS
rm -rf ios/Pods ios/Podfile.lock ios/.symlinks

# Android
rm -rf android/.gradle android/app/build android/build
cd android && ./gradlew clean 2>/dev/null || true && cd ..

# Reinstall
flutter pub get
cd ios && pod install --repo-update && cd ..
