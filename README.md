# LumaLink Flutter

LumaLink is a view-only Windows-to-Android screen viewer for trusted Wi-Fi. This version uses **Flutter and Dart for both UIs**, with an intentionally small Python/Pillow Windows capture helper packaged alongside the Flutter app. The host must stay open and approve each device. The Android UI talks directly to the local host; it is not a website or WebView.

## Get the builds from GitHub Actions

1. Push the **contents** of this folder to a new, empty repository (include `.github/workflows/build.yml`). Do not mix it with the earlier native Android project: its existing `android/` directory can interfere with Flutter scaffolding. If reusing the old repository, remove the old tracked `android/` and `windows/` folders and old workflow first, then add this project.
2. Open **Actions → Build LumaLink Flutter** and run the workflow. It generates Flutter's Android and Windows platform scaffolding during CI. No generated platform folders or Flutter SDK are included in this zip.
3. Download `LumaLink-Flutter-Android` and install the debug APK on your phone. Download `LumaLink-Flutter-Windows`, extract **all** its files to the same folder, and run `lumalink.exe`. The helper `lumalink_host.exe` must stay next to it. There is no installer; these builds are unsigned / debug builds and may trigger OS warnings.

The Windows workflow targets the Windows 2022 runner with Visual Studio 2022 instead of windows-latest. The updated workflow has not been run or tested on actual Android or Windows devices in the environment that created this project. If a job fails, send the final error lines from that job. A successful host protocol test is not a Flutter compile or device test.

## Use

1. Put the PC and phone on the same trusted Wi-Fi. In the Windows app check the suggested IP address is your **Wi-Fi IPv4 address**. If not, use `ipconfig` and enter it. Click **Start sharing**. On a firewall prompt permit private networks only.
2. Enter that same IP address, port, and pairing code on Android, then request access.
3. Approve the phone on Windows. Use the quality, pause, and landscape controls on the phone. Stop sharing on the PC to revoke active sessions.

The phone must use the **PC's local IP**, not `localhost` or `127.0.0.1` (those refer to the phone itself). Do not port-forward the service. Client isolation on a router can block the connection. The host captures the primary display; there is no remote control, audio, internet relay or persistent/background service. Frames are JPEGs, not video, so performance is modest.

## Important security limitation

**The local stream uses unencrypted HTTP**. Others who can observe traffic on that network can see your screen, pairing code and session cookie. Use only trusted private networks; do not expose the port to the internet or share confidential content. Approve only devices you recognize. The app is a prototype and is not independently audited. IP-bound, one-hour sessions and rate-limited code attempts are not a replacement for TLS. Windows Firewall permissions cannot be automatically granted by the app. The helper shuts down and revokes sessions when the host is stopped or exits.

## Build locally

Install Flutter 3.27.4, JDK 17, Android SDK, and Windows desktop development prerequisites (including Visual Studio C++). In the project root:

```
flutter create --platforms=android,windows --project-name lumalink .
python tools/configure_android.py
flutter pub get
flutter run -d android
```

For the Windows helper (Windows PowerShell):

```
py -m pip install "Pillow>=10.4,<12" pyinstaller
pyinstaller --noconfirm --onefile --name lumalink_host --distpath backend/dist backend/bridge.py
flutter build windows --release
Copy-Item backend/dist/lumalink_host.exe build/windows/x64/runner/Release/lumalink_host.exe
```

Run the release app from that folder. To run the Flutter Windows app in debug, place `lumalink_host.exe` beside its debug executable. Android debug APK: `flutter build apk --debug`.

## Project map

- `lib/main.dart`: Flutter interface, animations, connection flow and viewer
- `backend/bridge.py`: private stdin/stdout bridge and approval requests
- `backend/server.py`: local server, session handling, and Windows capture
- `tools/configure_android.py`: adds the network manifest settings to generated Android project
- `.github/workflows/build.yml`: Android APK and Windows folder builds
- `assets/icon.png`: LumaLink icon
