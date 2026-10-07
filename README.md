<!--
SPDX-FileCopyrightText: 2019-Present Christian Kußowski
SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat

SPDX-License-Identifier: AGPL-3.0-or-later
-->

[FluffyChat](https://fluffy.chat) is an open source, nonprofit and cute [[matrix](https://matrix.org)] client written in [Flutter](https://flutter.dev). The goal of the app is to create an easy to use instant messenger which is open source and accessible for everyone.

### Links:

- 🌐 [[Weblate] Translate FluffyChat into your language](https://hosted.weblate.org/projects/fluffychat/)
- 🌍 [[m] Join the community](https://matrix.to/#/#fluffy-space:matrix.org)
- 📰 [[Mastodon] Get updates on social media](https://troet.cafe/@krille)
- 💝 [[Liberapay] Support FluffyChat development](https://de.liberapay.com/KrilleChritzelius)

<a href='https://ko-fi.com/krille' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://storage.ko-fi.com/cdn/kofi5.png?v=3' border='0' alt='Buy Me a Coffee at ko-fi.com' /></a>

### Screenshots:

<img src="https://github.com/krille-chan/fluffychat-website/blob/main/public/img/screenshot_mobile.png?raw=true" height="300">
<img src="https://github.com/krille-chan/fluffychat-website/blob/main/public/img/screenshot_desktop.png?raw=true" height="300">

# Features

- 📩 Send all kinds of messages, images and files
- 🤙 Video calls with Matrix RTC
- 🎙️ Voice messages
- 📍 Location sharing
- 🔔 Push notifications
- 💬 Unlimited private and public group chats
- 📣 Public channels with thousands of participants
- 🛠️ Feature rich group moderation including all matrix features
- 🔍 Discover and join public groups
- 🎨 Material You design
- 😄 Custom emotes and stickers
- 🌌 Spaces
- 🔐 End to end encryption
- 🔒 Encrypted chat backup
- 😀 Emoji verification & cross signing
... and much more.


# Installation

Please visit the website for installation instructions:

- https://fluffy.chat

# Configuration and Mobile Device Management (MDM)

FluffyChat supports configuration via MDM on Android&iOS (since v2.10.0) and via a config.json file on web. You can see the populated configuration for MDM on Android in this file under `/android/app/src/main/res/xml/app_restrictions.xml`.
An example configuration can be found in the `config.sample.json` file.

# How to build

1. To build FluffyChat you need [Flutter](https://flutter.dev) and [Rust](https://www.rust-lang.org/tools/install)

2. Clone the repo:
```
git clone https://github.com/krille-chan/fluffychat.git
cd fluffychat
```
3. Choose your target platform below and enable support for it.
3.1 If you want, enable Googles Firebase Cloud Messaging:

`./scripts/add-firebase-messaging.sh`

4. Debug with: `flutter run`

### Android

* Build with: `flutter build apk`

### iOS / iPadOS

* Have a Mac with Xcode installed, and set up for Xcode-managed app signing
* If you want automatic app installation to connected devices, make sure you have Apple Configurator installed, with the Automation Tools (`cfgutil`) enabled
* Set a few environment variables
    * FLUFFYCHAT_NEW_TEAM: the Apple Developer team that your certificates should live under
    * FLUFFYCHAT_NEW_GROUP: the group you want App IDs and such to live under (ie: com.example.fluffychat)
    * FLUFFYCHAT_INSTALL_IPA: set to `1` if you want the IPA to be deployed to connected devices after building, otherwise unset
* Run `./scripts/build-ios.sh`

### Web

* Build with:
```bash
./scripts/prepare-web.sh # To install Vodozemac
flutter build web --release
```

* Optionally configure by serving a `config.json` at the same path as fluffychat.
  An example can be found at `config.sample.json`. All values there are optional.
  **Please only the values, you really need**. If you e.g. only want
  to change the default homeserver, then only modify the `defaultHomeserver` key.

### Desktop (Linux, Windows, macOS)

* Enable Desktop support in Flutter: https://flutter.dev/desktop

#### Install custom dependencies (Linux)

```bash
sudo apt install libjsoncpp1 libsecret-1-dev libsecret-1-0 librhash0 libwebkit2gtk-4.0-dev lld
```

* Build with one of these:
```bash
flutter build linux --release
flutter build windows --release
flutter build macos --release
```

## How to run integration tests

You need to have docker installed locally! Run the preparation script before every test run:

```sh
./scripts/prepare_integration_test.sh
```

Then run all tests with:

```sh
flutter test integration_test/mobile_test.dart
```


# Special thanks

* <a href="https://github.com/fabiyamada">Fabiyamada</a> is a graphics designer and has made the fluffychat logo and the banner. Big thanks for her great designs.

* Also thanks to all translators and testers! With your help, fluffychat is now available in more than 12 languages.

* The Matrix Foundation for making and maintaining the [emoji translations](https://github.com/matrix-org/matrix-spec/blob/main/data-definitions/sas-emoji.json) used for emoji verification, licensed Apache 2.0

* Special thanks to MTRNord, Sorunome and Advocatux.
```
dvchat
├─ .mailmap
├─ .metadata
├─ AGENTS.md
├─ CHANGELOG.md
├─ CONTRIBUTING.md
├─ Dockerfile
├─ LICENSE
├─ LICENSES
│  ├─ AGPL-3.0-or-later.txt
│  ├─ Apache-2.0.txt
│  ├─ CC-BY-4.0.txt
│  └─ LicenseRef-All-Rights-Reserved.txt
├─ PRIVACY.md
├─ README.md
├─ REUSE.toml
├─ SECURITY.md
├─ analysis_options.yaml
├─ android
│  ├─ Gemfile
│  ├─ app
│  │  ├─ build.gradle.kts
│  │  ├─ proguard-rules.pro
│  │  └─ src
│  │     └─ main
│  │        ├─ AndroidManifest.xml
│  │        ├─ kotlin
│  │        │  └─ chat
│  │        │     └─ fluffy
│  │        │        └─ fluffychat
│  │        │           ├─ FcmPushService.kt
│  │        │           ├─ MainActivity.kt
│  │        │           └─ UnifiedPushService.kt
│  │        └─ res
│  │           ├─ drawable
│  │           │  ├─ background.png
│  │           │  ├─ ic_launcher_foreground.xml
│  │           │  ├─ ic_launcher_monochrome.xml
│  │           │  └─ launch_background.xml
│  │           ├─ drawable-hdpi
│  │           │  ├─ ic_launcher_background.png
│  │           │  ├─ ic_launcher_foreground.png
│  │           │  ├─ ic_launcher_monochrome.png
│  │           │  ├─ notifications_icon.png
│  │           │  └─ splash.png
│  │           ├─ drawable-mdpi
│  │           │  ├─ ic_launcher_background.png
│  │           │  ├─ ic_launcher_foreground.png
│  │           │  ├─ ic_launcher_monochrome.png
│  │           │  ├─ notifications_icon.png
│  │           │  └─ splash.png
│  │           ├─ drawable-night
│  │           │  ├─ background.png
│  │           │  └─ launch_background.xml
│  │           ├─ drawable-night-v21
│  │           │  ├─ background.png
│  │           │  └─ launch_background.xml
│  │           ├─ drawable-v21
│  │           │  ├─ background.png
│  │           │  └─ launch_background.xml
│  │           ├─ drawable-xhdpi
│  │           │  ├─ ic_launcher_background.png
│  │           │  ├─ ic_launcher_foreground.png
│  │           │  ├─ ic_launcher_monochrome.png
│  │           │  ├─ notifications_icon.png
│  │           │  └─ splash.png
│  │           ├─ drawable-xxhdpi
│  │           │  ├─ ic_launcher_background.png
│  │           │  ├─ ic_launcher_foreground.png
│  │           │  ├─ ic_launcher_monochrome.png
│  │           │  ├─ notifications_icon.png
│  │           │  └─ splash.png
│  │           ├─ drawable-xxxhdpi
│  │           │  ├─ ic_launcher_background.png
│  │           │  ├─ ic_launcher_foreground.png
│  │           │  ├─ ic_launcher_monochrome.png
│  │           │  ├─ notifications_icon.png
│  │           │  └─ splash.png
│  │           ├─ mipmap-anydpi-v26
│  │           │  └─ ic_launcher.xml
│  │           ├─ mipmap-hdpi
│  │           │  └─ ic_launcher.png
│  │           ├─ mipmap-mdpi
│  │           │  └─ ic_launcher.png
│  │           ├─ mipmap-xhdpi
│  │           │  └─ ic_launcher.png
│  │           ├─ mipmap-xxhdpi
│  │           │  └─ ic_launcher.png
│  │           ├─ mipmap-xxxhdpi
│  │           │  └─ ic_launcher.png
│  │           ├─ values
│  │           │  ├─ ic_launcher_background.xml
│  │           │  └─ styles.xml
│  │           ├─ values-night
│  │           │  └─ styles.xml
│  │           └─ xml
│  │              ├─ app_restrictions.xml
│  │              ├─ automotive_app_desc.xml
│  │              └─ locale_config.xml
│  ├─ build.gradle.kts
│  ├─ fastlane
│  │  ├─ Appfile
│  │  ├─ Fastfile
│  │  ├─ README.md
│  │  ├─ metadata
│  │  │  └─ android
│  │  │     └─ en-US
│  │  │        ├─ changelogs
│  │  │        │  └─ default.txt
│  │  │        ├─ full_description.txt
│  │  │        ├─ images
│  │  │        │  ├─ logo.png
│  │  │        │  └─ phoneScreenshots
│  │  │        │     ├─ 1.png
│  │  │        │     ├─ 2.png
│  │  │        │     ├─ 3.png
│  │  │        │     ├─ 4.png
│  │  │        │     ├─ 5.png
│  │  │        │     └─ 6.png
│  │  │        ├─ short_description.txt
│  │  │        └─ title.txt
│  │  └─ report.xml
│  ├─ gradle
│  │  └─ wrapper
│  │     └─ gradle-wrapper.properties
│  ├─ gradle.properties
│  └─ settings.gradle.kts
├─ assets
│  ├─ logo
│  │  ├─ img
│  │  │  ├─ banner.png
│  │  │  ├─ logo.png
│  │  │  ├─ logo_background.png
│  │  │  ├─ logo_font.png
│  │  │  ├─ logo_foreground.png
│  │  │  ├─ logo_mono.png
│  │  │  ├─ logo_standalone.png
│  │  │  └─ mascot.png
│  │  ├─ mini
│  │  │  ├─ banner.png
│  │  │  ├─ logo_font_mini.png
│  │  │  ├─ logo_mini.png
│  │  │  ├─ logo_mono_mini.png
│  │  │  └─ mascot.png
│  │  └─ vector
│  │     ├─ logo.svg
│  │     ├─ logo_background.svg
│  │     ├─ logo_foreground.svg
│  │     ├─ logo_mono.svg
│  │     ├─ logo_notification.svg
│  │     ├─ logo_standalone.svg
│  │     └─ mascot.svg
│  ├─ sas-emoji.json
│  ├─ sounds
│  │  ├─ call_attention.mp3
│  │  ├─ call_join.mp3
│  │  ├─ call_leave.mp3
│  │  ├─ call_ring.mp3
│  │  ├─ call_wait.mp3
│  │  └─ notification.mp3
│  └─ vodozemac
│     └─ 0.8.1
├─ config.sample.json
├─ dart_dependency_validator.yaml
├─ devtools_options.yaml
├─ fastlane
│  ├─ README.md
│  └─ metadata
│     └─ android
│        └─ en-US
│           ├─ changelogs
│           │  └─ default.txt
│           ├─ full_description.txt
│           ├─ images
│           │  ├─ logo.png
│           │  └─ phoneScreenshots
│           │     ├─ 1.png
│           │     ├─ 2.png
│           │     ├─ 3.png
│           │     ├─ 4.png
│           │     ├─ 5.png
│           │     └─ 6.png
│           ├─ short_description.txt
│           └─ title.txt
├─ integration_test
│  ├─ data
│  │  ├─ environment_constants.dart
│  │  └─ integration_users.env
│  ├─ flows
│  │  ├─ auth_flows.dart
│  │  ├─ basic_messaging.dart
│  │  ├─ chat_flows.dart
│  │  ├─ login_and_chat_backup.dart
│  │  └─ multi_account.dart
│  ├─ mobile_test.dart
│  ├─ synapse
│  │  └─ data
│  │     ├─ homeserver.yaml
│  │     └─ localhost.signing.key
│  └─ utils
│     └─ fluffy_chat_tester.dart
├─ ios
│  ├─ FluffyChat Share
│  │  ├─ Base.lproj
│  │  │  └─ MainInterface.storyboard
│  │  ├─ FluffyChat Share.entitlements
│  │  ├─ Info.plist
│  │  └─ ShareViewController.swift
│  ├─ Flutter
│  │  ├─ AppFrameworkInfo.plist
│  │  ├─ Debug.xcconfig
│  │  └─ Release.xcconfig
│  ├─ Gemfile
│  ├─ Localizable.xcstrings
│  ├─ Notification Service Extension
│  │  ├─ Info.plist
│  │  ├─ Notification Service Extension.entitlements
│  │  └─ NotificationService.swift
│  ├─ Podfile
│  ├─ Runner
│  │  ├─ AppDelegate.swift
│  │  ├─ Assets.xcassets
│  │  │  ├─ AppIcon.appiconset
│  │  │  │  ├─ Contents.json
│  │  │  │  ├─ Icon-App-1024x1024@1x.png
│  │  │  │  ├─ Icon-App-20x20@1x.png
│  │  │  │  ├─ Icon-App-20x20@2x.png
│  │  │  │  ├─ Icon-App-20x20@3x.png
│  │  │  │  ├─ Icon-App-29x29@1x.png
│  │  │  │  ├─ Icon-App-29x29@2x.png
│  │  │  │  ├─ Icon-App-29x29@3x.png
│  │  │  │  ├─ Icon-App-40x40@1x.png
│  │  │  │  ├─ Icon-App-40x40@2x.png
│  │  │  │  ├─ Icon-App-40x40@3x.png
│  │  │  │  ├─ Icon-App-50x50@1x.png
│  │  │  │  ├─ Icon-App-50x50@2x.png
│  │  │  │  ├─ Icon-App-57x57@1x.png
│  │  │  │  ├─ Icon-App-57x57@2x.png
│  │  │  │  ├─ Icon-App-60x60@2x.png
│  │  │  │  ├─ Icon-App-60x60@3x.png
│  │  │  │  ├─ Icon-App-72x72@1x.png
│  │  │  │  ├─ Icon-App-72x72@2x.png
│  │  │  │  ├─ Icon-App-76x76@1x.png
│  │  │  │  ├─ Icon-App-76x76@2x.png
│  │  │  │  └─ Icon-App-83.5x83.5@2x.png
│  │  │  └─ LaunchImage.imageset
│  │  │     ├─ Contents.json
│  │  │     ├─ LaunchImage.png
│  │  │     ├─ LaunchImage@2x.png
│  │  │     ├─ LaunchImage@3x.png
│  │  │     └─ README.md
│  │  ├─ Base.lproj
│  │  │  ├─ LaunchScreen.storyboard
│  │  │  └─ Main.storyboard
│  │  ├─ GoogleService-Info.plist
│  │  ├─ Info.plist
│  │  ├─ Runner-Bridging-Header.h
│  │  ├─ Runner.entitlements
│  │  ├─ ar.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ ca.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ cs.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ de.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ eo.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ es.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ et.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ eu.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ fr.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ gl.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ hr-HR.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ hu-HU.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ hu.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ hy.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ it.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ ja.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ nb-NO.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ notification.caf
│  │  ├─ pl.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ pt.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ ru-RU.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ sk-SK.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ sv-SE.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ tr.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ uk.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  ├─ vi-VN.lproj
│  │  │  ├─ LaunchScreen.strings
│  │  │  └─ Main.strings
│  │  └─ zh-Hans.lproj
│  │     ├─ LaunchScreen.strings
│  │     └─ Main.strings
│  ├─ Runner.xcodeproj
│  │  ├─ project.pbxproj
│  │  ├─ project.xcworkspace
│  │  │  ├─ contents.xcworkspacedata
│  │  │  └─ xcshareddata
│  │  │     ├─ IDEWorkspaceChecks.plist
│  │  │     ├─ WorkspaceSettings.xcsettings
│  │  │     └─ swiftpm
│  │  │        └─ Package.resolved
│  │  └─ xcshareddata
│  │     └─ xcschemes
│  │        └─ Runner.xcscheme
│  ├─ Runner.xcworkspace
│  │  ├─ contents.xcworkspacedata
│  │  └─ xcshareddata
│  │     ├─ IDEWorkspaceChecks.plist
│  │     ├─ WorkspaceSettings.xcsettings
│  │     └─ swiftpm
│  │        └─ Package.resolved
│  └─ fastlane
│     ├─ Appfile
│     ├─ Fastfile
│     ├─ README.md
│     └─ report.xml
├─ l10n.yaml
├─ lib
│  ├─ config
│  │  ├─ app_config.dart
│  │  ├─ isrg_x1.dart
│  │  ├─ isrg_x2.dart
│  │  ├─ routes.dart
│  │  ├─ setting_keys.dart
│  │  └─ themes.dart
│  ├─ l10n
│  │  ├─ intl_ar.arb
│  │  ├─ intl_az.arb
│  │  ├─ intl_be.arb
│  │  ├─ intl_bn.arb
│  │  ├─ intl_bo.arb
│  │  ├─ intl_ca.arb
│  │  ├─ intl_cs.arb
│  │  ├─ intl_da.arb
│  │  ├─ intl_de.arb
│  │  ├─ intl_el.arb
│  │  ├─ intl_en.arb
│  │  ├─ intl_eo.arb
│  │  ├─ intl_es.arb
│  │  ├─ intl_et.arb
│  │  ├─ intl_eu.arb
│  │  ├─ intl_fa.arb
│  │  ├─ intl_fi.arb
│  │  ├─ intl_fil.arb
│  │  ├─ intl_fr.arb
│  │  ├─ intl_ga.arb
│  │  ├─ intl_gl.arb
│  │  ├─ intl_he.arb
│  │  ├─ intl_hi.arb
│  │  ├─ intl_hr.arb
│  │  ├─ intl_hu.arb
│  │  ├─ intl_ia.arb
│  │  ├─ intl_id.arb
│  │  ├─ intl_ie.arb
│  │  ├─ intl_it.arb
│  │  ├─ intl_ja.arb
│  │  ├─ intl_ka.arb
│  │  ├─ intl_kab.arb
│  │  ├─ intl_ko.arb
│  │  ├─ intl_la.arb
│  │  ├─ intl_lt.arb
│  │  ├─ intl_lv.arb
│  │  ├─ intl_nb.arb
│  │  ├─ intl_nl.arb
│  │  ├─ intl_pl.arb
│  │  ├─ intl_pt.arb
│  │  ├─ intl_pt_BR.arb
│  │  ├─ intl_pt_PT.arb
│  │  ├─ intl_ro.arb
│  │  ├─ intl_ru.arb
│  │  ├─ intl_sk.arb
│  │  ├─ intl_sl.arb
│  │  ├─ intl_sq.arb
│  │  ├─ intl_sr.arb
│  │  ├─ intl_sv.arb
│  │  ├─ intl_ta.arb
│  │  ├─ intl_te.arb
│  │  ├─ intl_th.arb
│  │  ├─ intl_tr.arb
│  │  ├─ intl_uk.arb
│  │  ├─ intl_uz.arb
│  │  ├─ intl_vi.arb
│  │  ├─ intl_yue_Hant.arb
│  │  ├─ intl_zh.arb
│  │  └─ intl_zh_Hant.arb
│  ├─ main.dart
│  ├─ pages
│  │  ├─ archive
│  │  │  ├─ archive.dart
│  │  │  └─ archive_view.dart
│  │  ├─ bootstrap
│  │  │  ├─ bootstrap_page.dart
│  │  │  ├─ view_model
│  │  │  │  ├─ bootstrap_state.dart
│  │  │  │  └─ bootstrap_view_model.dart
│  │  │  └─ widgets
│  │  │     ├─ new_passphrase_view.dart
│  │  │     ├─ restore_bootstrap_view.dart
│  │  │     └─ store_recovery_key_view.dart
│  │  ├─ call
│  │  │  ├─ call_page.dart
│  │  │  ├─ call_tile.dart
│  │  │  ├─ call_view_model.dart
│  │  │  ├─ start_time.dart
│  │  │  └─ utils
│  │  │     └─ get_call_tiles.dart
│  │  ├─ chat
│  │  │  ├─ chat.dart
│  │  │  ├─ chat_app_bar_list_tile.dart
│  │  │  ├─ chat_app_bar_title.dart
│  │  │  ├─ chat_emoji_picker.dart
│  │  │  ├─ chat_event_list.dart
│  │  │  ├─ chat_input_row.dart
│  │  │  ├─ chat_view.dart
│  │  │  ├─ command_hints.dart
│  │  │  ├─ encryption_info.dart
│  │  │  ├─ event_info_dialog.dart
│  │  │  ├─ events
│  │  │  │  ├─ audio_player.dart
│  │  │  │  ├─ cute_events.dart
│  │  │  │  ├─ file_send_status_indicator.dart
│  │  │  │  ├─ html_message.dart
│  │  │  │  ├─ image_bubble.dart
│  │  │  │  ├─ map_bubble.dart
│  │  │  │  ├─ message.dart
│  │  │  │  ├─ message_content.dart
│  │  │  │  ├─ message_download_content.dart
│  │  │  │  ├─ message_reactions.dart
│  │  │  │  ├─ poll.dart
│  │  │  │  ├─ reply_content.dart
│  │  │  │  ├─ state_message.dart
│  │  │  │  └─ video_player.dart
│  │  │  ├─ image_edit_geometry.dart
│  │  │  ├─ input_bar.dart
│  │  │  ├─ pinned_events.dart
│  │  │  ├─ recording_input_row.dart
│  │  │  ├─ recording_view_model.dart
│  │  │  ├─ reply_display.dart
│  │  │  ├─ seen_by_row.dart
│  │  │  ├─ send_file_dialog.dart
│  │  │  ├─ send_location_dialog.dart
│  │  │  ├─ start_poll_bottom_sheet.dart
│  │  │  ├─ sticker_picker_dialog.dart
│  │  │  ├─ trust_user_key_dialog.dart
│  │  │  ├─ typing_indicators.dart
│  │  │  ├─ utd_dialog.dart
│  │  │  └─ utils
│  │  │     └─ web_file_to_x_file.dart
│  │  ├─ chat_access_settings
│  │  │  ├─ chat_access_settings_controller.dart
│  │  │  └─ chat_access_settings_page.dart
│  │  ├─ chat_details
│  │  │  ├─ chat_details.dart
│  │  │  ├─ chat_details_view.dart
│  │  │  └─ participant_list_item.dart
│  │  ├─ chat_encryption_settings
│  │  │  ├─ chat_encryption_settings.dart
│  │  │  └─ chat_encryption_settings_view.dart
│  │  ├─ chat_list
│  │  │  ├─ active_call_indicator.dart
│  │  │  ├─ chat_list.dart
│  │  │  ├─ chat_list_body.dart
│  │  │  ├─ chat_list_header.dart
│  │  │  ├─ chat_list_item.dart
│  │  │  ├─ chat_list_view.dart
│  │  │  ├─ client_chooser_button.dart
│  │  │  ├─ dummy_chat_list_item.dart
│  │  │  ├─ navi_rail_item.dart
│  │  │  ├─ navigation_rail.dart
│  │  │  ├─ search_title.dart
│  │  │  ├─ space_view.dart
│  │  │  ├─ start_chat_fab.dart
│  │  │  └─ unread_bubble.dart
│  │  ├─ chat_members
│  │  │  ├─ chat_members.dart
│  │  │  └─ chat_members_view.dart
│  │  ├─ chat_permissions_settings
│  │  │  ├─ chat_permissions_settings.dart
│  │  │  ├─ chat_permissions_settings_view.dart
│  │  │  └─ permission_list_tile.dart
│  │  ├─ chat_search
│  │  │  ├─ chat_search_files_tab.dart
│  │  │  ├─ chat_search_images_tab.dart
│  │  │  ├─ chat_search_message_tab.dart
│  │  │  ├─ chat_search_page.dart
│  │  │  ├─ chat_search_view.dart
│  │  │  └─ search_footer.dart
│  │  ├─ device_settings
│  │  │  ├─ device_settings.dart
│  │  │  ├─ device_settings_view.dart
│  │  │  └─ user_device_list_item.dart
│  │  ├─ image_viewer
│  │  │  ├─ image_viewer.dart
│  │  │  ├─ image_viewer_view.dart
│  │  │  ├─ pointers_listener.dart
│  │  │  └─ video_player.dart
│  │  ├─ intro
│  │  │  ├─ flows
│  │  │  │  └─ restore_backup_flow.dart
│  │  │  ├─ intro_page.dart
│  │  │  └─ intro_page_presenter.dart
│  │  ├─ invitation_selection
│  │  │  ├─ invitation_selection.dart
│  │  │  └─ invitation_selection_view.dart
│  │  ├─ key_verification
│  │  │  └─ key_verification_dialog.dart
│  │  ├─ login
│  │  │  ├─ login.dart
│  │  │  └─ login_view.dart
│  │  ├─ new_group
│  │  │  ├─ new_group.dart
│  │  │  └─ new_group_view.dart
│  │  ├─ new_private_chat
│  │  │  ├─ new_private_chat.dart
│  │  │  ├─ new_private_chat_view.dart
│  │  │  └─ qr_scanner_modal.dart
│  │  ├─ settings
│  │  │  ├─ settings.dart
│  │  │  └─ settings_view.dart
│  │  ├─ settings_3pid
│  │  │  ├─ settings_3pid.dart
│  │  │  └─ settings_3pid_view.dart
│  │  ├─ settings_chat
│  │  │  ├─ settings_chat.dart
│  │  │  └─ settings_chat_view.dart
│  │  ├─ settings_emotes
│  │  │  ├─ import_archive_dialog.dart
│  │  │  ├─ settings_emotes.dart
│  │  │  └─ settings_emotes_view.dart
│  │  ├─ settings_homeserver
│  │  │  ├─ settings_homeserver.dart
│  │  │  └─ settings_homeserver_view.dart
│  │  ├─ settings_ignore_list
│  │  │  ├─ settings_ignore_list.dart
│  │  │  └─ settings_ignore_list_view.dart
│  │  ├─ settings_notifications
│  │  │  ├─ push_rule_extensions.dart
│  │  │  ├─ settings_notifications.dart
│  │  │  └─ settings_notifications_view.dart
│  │  ├─ settings_password
│  │  │  ├─ settings_password.dart
│  │  │  └─ settings_password_view.dart
│  │  ├─ settings_security
│  │  │  ├─ settings_security.dart
│  │  │  └─ settings_security_view.dart
│  │  ├─ settings_style
│  │  │  ├─ settings_style.dart
│  │  │  └─ settings_style_view.dart
│  │  └─ sign_in
│  │     ├─ sign_in_page.dart
│  │     └─ view_model
│  │        ├─ model
│  │        │  └─ public_homeserver_data.dart
│  │        ├─ sign_in_state.dart
│  │        └─ sign_in_view_model.dart
│  ├─ utils
│  │  ├─ account_bundles.dart
│  │  ├─ account_config.dart
│  │  ├─ adaptive_bottom_sheet.dart
│  │  ├─ background_push.dart
│  │  ├─ beautify_string_extension.dart
│  │  ├─ call_kit_params.dart
│  │  ├─ client_download_content_extension.dart
│  │  ├─ client_manager.dart
│  │  ├─ code_highlight_theme.dart
│  │  ├─ color_value.dart
│  │  ├─ custom_http_client.dart
│  │  ├─ custom_image_resizer.dart
│  │  ├─ custom_scroll_behaviour.dart
│  │  ├─ date_time_extension.dart
│  │  ├─ error_reporter.dart
│  │  ├─ event_checkbox_extension.dart
│  │  ├─ file_description.dart
│  │  ├─ file_selector.dart
│  │  ├─ fluffy_share.dart
│  │  ├─ init_with_restore.dart
│  │  ├─ localized_exception_extension.dart
│  │  ├─ markdown_context_builder.dart
│  │  ├─ matrix_live_kit_calls
│  │  │  ├─ call_keys_event_content.dart
│  │  │  ├─ matrix_live_kit_call.dart
│  │  │  └─ matrix_live_kit_call_member.dart
│  │  ├─ matrix_sdk_extensions
│  │  │  ├─ device_extension.dart
│  │  │  ├─ event_extension.dart
│  │  │  ├─ filtered_timeline_extension.dart
│  │  │  ├─ flutter_matrix_dart_sdk_database
│  │  │  │  ├─ builder.dart
│  │  │  │  └─ cipher.dart
│  │  │  ├─ matrix_file_extension.dart
│  │  │  ├─ matrix_locals.dart
│  │  │  └─ oidc_session_json_extension.dart
│  │  ├─ notification_avatar_extension.dart
│  │  ├─ notification_background_handler.dart
│  │  ├─ other_party_can_receive.dart
│  │  ├─ platform_infos.dart
│  │  ├─ position_from_build_context.dart
│  │  ├─ push_helper.dart
│  │  ├─ resize_video.dart
│  │  ├─ room_status_extension.dart
│  │  ├─ show_scaffold_dialog.dart
│  │  ├─ show_update_snackbar.dart
│  │  ├─ sign_in_flows
│  │  │  ├─ calc_redirect_url.dart
│  │  │  ├─ check_homeserver.dart
│  │  │  ├─ oidc_login.dart
│  │  │  └─ sso_login.dart
│  │  ├─ size_string.dart
│  │  ├─ start_push_foreground_service.dart
│  │  ├─ stream_extension.dart
│  │  ├─ string_color.dart
│  │  ├─ sync_status_localization.dart
│  │  ├─ uia_request_manager.dart
│  │  ├─ url_launcher.dart
│  │  └─ verified_room_extension.dart
│  └─ widgets
│     ├─ adaptive_dialogs
│     │  ├─ adaptive_dialog_action.dart
│     │  ├─ dialog_text_field.dart
│     │  ├─ public_room_dialog.dart
│     │  ├─ show_modal_action_popup.dart
│     │  ├─ show_ok_cancel_alert_dialog.dart
│     │  ├─ show_text_input_dialog.dart
│     │  └─ user_dialog.dart
│     ├─ app_lock.dart
│     ├─ avatar.dart
│     ├─ blur_hash.dart
│     ├─ chat_settings_popup_menu.dart
│     ├─ config_viewer.dart
│     ├─ fluffy_chat_app.dart
│     ├─ future_loading_dialog.dart
│     ├─ hover_builder.dart
│     ├─ incoming_call_dialog.dart
│     ├─ layouts
│     │  ├─ call_overlay.dart
│     │  ├─ empty_page.dart
│     │  ├─ login_scaffold.dart
│     │  ├─ max_width_body.dart
│     │  └─ two_column_layout.dart
│     ├─ local_notifications_extension.dart
│     ├─ lock_screen.dart
│     ├─ log_view.dart
│     ├─ matrix.dart
│     ├─ member_actions_popup_menu_button.dart
│     ├─ mxc_image.dart
│     ├─ mxc_image_viewer.dart
│     ├─ permission_slider_dialog.dart
│     ├─ presence_builder.dart
│     ├─ pulsating_widget.dart
│     ├─ qr_code_viewer.dart
│     ├─ settings_switch_list_tile.dart
│     ├─ share_scaffold_dialog.dart
│     ├─ theme_builder.dart
│     ├─ typing_animation.dart
│     ├─ unread_rooms_badge.dart
│     └─ view_model_builder.dart
├─ licenses.yaml
├─ linux
│  ├─ CMakeLists.txt
│  ├─ flutter
│  │  ├─ CMakeLists.txt
│  │  ├─ generated_plugin_registrant.cc
│  │  ├─ generated_plugin_registrant.h
│  │  └─ generated_plugins.cmake
│  ├─ main.cc
│  ├─ my_application.cc
│  └─ my_application.h
├─ macos
│  ├─ Flutter
│  │  ├─ Flutter-Debug.xcconfig
│  │  ├─ Flutter-Release.xcconfig
│  │  └─ GeneratedPluginRegistrant.swift
│  ├─ Runner
│  │  ├─ AppDelegate.swift
│  │  ├─ Assets.xcassets
│  │  │  └─ AppIcon.appiconset
│  │  │     ├─ 1024-mac.png
│  │  │     ├─ 128-mac.png
│  │  │     ├─ 16-mac.png
│  │  │     ├─ 256-mac.png
│  │  │     ├─ 32-mac.png
│  │  │     ├─ 512-mac.png
│  │  │     ├─ 64-mac.png
│  │  │     ├─ Contents.json
│  │  │     ├─ app_icon_1024.png
│  │  │     ├─ app_icon_128.png
│  │  │     ├─ app_icon_16.png
│  │  │     ├─ app_icon_256.png
│  │  │     ├─ app_icon_32.png
│  │  │     ├─ app_icon_512.png
│  │  │     └─ app_icon_64.png
│  │  ├─ Base.lproj
│  │  │  └─ MainMenu.xib
│  │  ├─ Configs
│  │  │  ├─ AppInfo.xcconfig
│  │  │  ├─ Debug.xcconfig
│  │  │  ├─ Release.xcconfig
│  │  │  └─ Warnings.xcconfig
│  │  ├─ DebugProfile.entitlements
│  │  ├─ Info.plist
│  │  ├─ MainFlutterWindow.swift
│  │  └─ Release.entitlements
│  ├─ Runner.xcodeproj
│  │  ├─ project.pbxproj
│  │  ├─ project.xcworkspace
│  │  │  └─ xcshareddata
│  │  │     └─ IDEWorkspaceChecks.plist
│  │  └─ xcshareddata
│  │     └─ xcschemes
│  │        └─ Runner.xcscheme
│  └─ Runner.xcworkspace
│     ├─ contents.xcworkspacedata
│     └─ xcshareddata
│        └─ IDEWorkspaceChecks.plist
├─ pubspec.yaml
├─ recommended_homeservers.json
├─ scripts
│  ├─ add-firebase-messaging.sh
│  ├─ build-ios.sh
│  ├─ build-windows.ps1
│  ├─ generate-locale-config.sh
│  ├─ generate_command_hints_glue.sh
│  ├─ package-windows.ps1
│  ├─ prepare-android-release.sh
│  ├─ prepare-web.sh
│  ├─ prepare-windows.ps1
│  ├─ prepare_integration_test.sh
│  ├─ release-ios-testflight.sh
│  └─ update-license-headers.sh
├─ snap
│  ├─ gui
│  │  ├─ fluffychat.desktop
│  │  └─ fluffychat.png
│  └─ snapcraft.yaml
├─ test
│  ├─ archive_test.dart
│  ├─ command_hint_test.dart
│  ├─ homeserver_picker_test.dart
│  ├─ utils
│  │  └─ test_client.dart
│  └─ widget_test.dart
├─ web
│  ├─ auth.html
│  ├─ favicon.png
│  ├─ icons
│  │  ├─ Icon-16.png
│  │  ├─ Icon-192.png
│  │  ├─ Icon-32.png
│  │  ├─ Icon-48.png
│  │  ├─ Icon-512.png
│  │  ├─ Icon-maskable-192.png
│  │  └─ Icon-maskable-512.png
│  ├─ index.html
│  ├─ manifest.json
│  └─ native_executor.dart
└─ windows
   ├─ CMakeLists.txt
   ├─ flutter
   │  ├─ CMakeLists.txt
   │  ├─ generated_plugin_registrant.cc
   │  ├─ generated_plugin_registrant.h
   │  └─ generated_plugins.cmake
   ├─ installer.iss
   └─ runner
      ├─ CMakeLists.txt
      ├─ Runner.rc
      ├─ flutter_window.cpp
      ├─ flutter_window.h
      ├─ main.cpp
      ├─ resource.h
      ├─ resources
      │  └─ app_icon.ico
      ├─ runner.exe.manifest
      ├─ utils.cpp
      ├─ utils.h
      ├─ win32_window.cpp
      └─ win32_window.h

```