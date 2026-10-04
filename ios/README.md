# pt.TetrisDuel — UIKit / VIPER / DI

A native Swift version of the Python game, with the same classic 10 × 20 rules,
lit 3D cubes, landing outline, hold, three-piece preview, score, level progression,
garbage attacks, combos, back-to-back tetrises, perfect clears and rematches.

The playing field is planar; the cubes use 3D geometry, perspective and lighting.
The renderer uses UIKit and Core Graphics, with no external assets or game engine.

## Open and run

1. Copy the `ios` folder to a Mac with **Xcode 15 or newer**.
2. Open **`pt.TetrisDuel.xcodeproj`**. No project generator, CocoaPods or downloads
   are needed to build the app.
3. Select the **pt.TetrisDuel** scheme and an iPhone or iPad simulator.
   Press **⌘R**.
4. For a physical device, select your development team under **Signing &
   Capabilities**. Change `com.example.TetrisDuel` to a unique bundle identifier
   if needed. The deployment target is **iOS / iPadOS 16.0**.

The project uses Swift 5 language mode and the UIKit scene lifecycle. It includes
an app icon, launch background, privacy manifest and shared test scheme.

## Languages

The interface supports **English and Russian** and follows the device's preferred
language, with English as the fallback. You can also select the app's language
in iOS Settings under **pt.TetrisDuel → Language**.

In Xcode, use **Edit Scheme → Run → Options → App Language → Russian** to try
Russian without changing the simulator's system language.

Menus, controls, game results, help, nearby-connection messages and VoiceOver
labels use `TetrisDuel/Resources/Localizable.xcstrings`. The Local Network
permission explanation uses `TetrisDuel/Resources/InfoPlist.xcstrings`.
Player-entered names are preserved. Add translations to these string catalogs
and register new languages in the project generator and `Info.plist`.

## Play modes

| Device / mode | Layout and controls |
| --- | --- |
| iPhone · Solo | One playable board, portrait layout, touch controls |
| iPad · Solo | One playable board |
| iPad · Two players | Two boards side by side, each with independent simultaneous touch controls |
| Nearby · iPhone | Your board and controls, plus your opponent's score and line count |
| Nearby · iPad | Both boards visible, controls for your own seat |

Hold **Left / Right / Down** to repeat. Rotation, Hold and Drop act once per press.
Both clockwise and counterclockwise rotation are available. Touch cancellation
releases held input. The pause button pauses the countdown or the match.

External keyboards also work: **A/D, W/Q, S, Space, left Shift** and
**arrows, /, Enter, right Shift**. In a shared iPad duel these operate separate
players; in solo / nearby modes either key group controls your own seat. **P** or
**Esc** pauses. Sound and haptics can be toggled in the navigation bar.

## Nearby multiplayer — Wi-Fi, no Bluetooth

1. Open the same version of the app on two physical iPhones/iPads.
2. Enable Wi-Fi on both. A common local network is useful; Multipeer Connectivity
   also supports peer-to-peer Wi-Fi without an internet connection.
3. Choose **Host a nearby game** on one device and **Join a nearby game** on the
   other. Allow **Local Network** access when iOS asks.
4. Select the host's displayed name. The host explicitly accepts the invitation.
5. A three-second countdown starts after the guest is ready. Each device controls
   one player, with the host running both boards.

The app uses **Multipeer Connectivity**, as requested. It contains **no Bluetooth
transport or Bluetooth permission request**. The system chooses the Wi-Fi path;
the app does not claim to force a particular radio interface.

If discovery fails, check **Settings → Privacy & Security → Local Network**,
enable Wi-Fi, return to the menu and create a fresh room. Physical devices are
required to validate peer-to-peer radio behavior. Both players must keep the app
in the foreground; a connection lost while backgrounded requires a new room.

Sessions require encryption and accept only one approved opponent. Advertising
and browsing stop once connected. There is no server or account. Nicknames and
match state are exchanged only with the nearby session; the app has no analytics.

## Rules

- Both players share one deterministic seven-bag piece stream, consumed at their
  own pace. The Swift app uses a specified SplitMix64 shuffle; it does not connect
  to the Python app or reproduce Python's random seed sequence.
- Clearing 2 / 3 / 4 lines sends 1 / 2 / 4 garbage rows. A single line does not
  attack by itself. Combos and repeated tetrises add bonuses; a perfect clear adds 6.
- Attacks first cancel your pending garbage. Simultaneous attacks cancel each
  other. Remaining rows arrive after at least 1.5 seconds, on a lock without a
  line clear, with a maximum of eight rows per rise.
- The speed increases every ten lines. Wall kicks, a 0.5-second lock delay and a
  15-reset limit permit placement adjustments without stalling indefinitely.
- A top-out loses the duel; simultaneous top-outs draw. Score does not decide
  the winner. Solo play ends when its board tops out.
- Both nearby players must request a rematch. Shared-device / solo rematches
  start directly. Match wins persist until you leave the game screen.
- Pause and foreground availability are synchronized. A disconnect or an
  eight-second heartbeat timeout stops the match without awarding a new win.

## Architecture

| Layer | Responsibility |
| --- | --- |
| View | UIKit layout, touch / keyboard events, accessibility, projected cube drawing |
| Interactor | Menu preferences, lobby lifecycle, or game simulation and nearby session rules |
| Presenter | Maps entities to display models and forwards user intentions |
| Entity | Platform-independent board, piece stream, match, snapshots and wire messages |
| Router | Navigation and module transitions |

`App/AppContainer.swift` is the composition root. It injects the `GameClock`,
`NearbyTransport`, `FeedbackServing`, `SeedProviding` and preferences through
constructors. Routers receive module factory closures. Views do not create
network services or resolve dependencies globally. Presenter/view and
interactor/output references are weak; display links use a weak proxy.

`Core` imports only Foundation and also builds as a standalone Swift package.
The `MultipeerTransport` adapter owns the Apple networking API; all delegate
callbacks are marshalled to the main queue. No background task mutates boards.

The host is authoritative. Inputs and control messages use reliable delivery;
compact playing snapshots (under 320 bytes for two boards) are sent at 12 Hz using
unreliable delivery. Countdown, paused and finished states use reliable delivery;
pauses and rematches are sent immediately. Round IDs and monotonically increasing revisions reject
stale or reordered snapshots. Input sequence numbers reject duplicates. Payload
sizes, piece coordinates, board cell values and command rates are bounded.
Guests render received state without simulating a competing authority. This
keeps outcomes consistent, with guest control latency depending on the network.

## Tests and validation

The checked-in scheme includes **33 unit tests** and **4 UI tests**. On a Mac:

```sh
cd ios
swift test
open pt.TetrisDuel.xcodeproj
# Select an iPhone or iPad simulator and press Command-U.
```

`swift test` runs the **22 portable core tests**. Xcode also runs nine interactor
tests with injected fake clocks, transports and feedback, two localization tests,
and the UI tests. UI tests cover English and Russian menus and gameplay screens.
The shared-iPad UI test skips on an iPhone simulator.

From the command line, list available destinations and choose one:

```sh
xcodebuild -project pt.TetrisDuel.xcodeproj -scheme pt.TetrisDuel \
  -showdestinations
xcodebuild -project pt.TetrisDuel.xcodeproj -scheme pt.TetrisDuel \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

The repository includes a GitHub Actions workflow that runs the Swift package
tests and Xcode tests on both iPhone and iPad simulators when pushed to GitHub.
It does not publish or deploy the app.

**Validation performed in the Windows authoring environment:** all 31 Swift
files parsed with a Swift grammar; the Xcode project parsed with 102 valid
objects and all sources linked; plists, scheme, icon resources and networking
permissions checked. **Xcode compilation, XCTest execution, rendered iOS UI and
physical-device networking have not been run here.** Parser checks do not replace
Swift type checking or an iOS build.

Before using the app on devices, run the acceptance cases in
[`DEVICE_TESTS.md`](DEVICE_TESTS.md).

## Maintenance

The Xcode project is committed and immediately openable. If files are added or
removed, regenerate it with the included dependency-free script:

```sh
python3 Scripts/generate_project.py
python3 Scripts/validate_project.py
```

Full static parsing optionally uses `tree-sitter`, `tree-sitter-swift` and
`openstep-parser`. These are validation tools only; the iOS app has no external
package dependencies. `Scripts/make_icon.py` regenerates the geometric icon
using Pillow; the finished PNG is already included.

## Apple references

- [Multipeer Connectivity](https://developer.apple.com/documentation/multipeerconnectivity)
- [Local Network and Bonjour configuration](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Wi-Fi rather than Bluetooth transport clarification](https://developer.apple.com/forums/thread/749346)
- [UIKit scene lifecycle](https://developer.apple.com/documentation/uikit/app_and_environment/scenes)

Recent Apple SDKs may issue deprecation warnings for Multipeer Connectivity.
The requested framework is isolated behind `NearbyTransport`, so a future
Network framework adapter can be injected without changing the game engine.
