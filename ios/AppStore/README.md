# App Store assets — pt.TetrisDuel

Open **[`index.html`](index.html)** in a browser to review the complete collection.
The image galleries link directly to the full-resolution upload files.

**For your iPhone 6.5-inch display slot and iPad:** download
[`promotional-appstore.zip`](promotional-appstore.zip). It contains **20 promotional
screenshots**: five each for iPhone and iPad, in English and Russian. Its folders
are named with the exact display sizes and pixel dimensions.

## Upload-ready images

**Plain app snapshots in the required App Store sizes:**
[`snapshots/README.md`](snapshots/README.md) lists the exact upload slots and
links to size-named folders. [`snapshots/appstore-snapshots.zip`](snapshots/appstore-snapshots.zip)
packages all 20 plain snapshots for English and Russian.

**Promotional screenshots with captions:**

| App Store Connect display slot | English | Russian | PNG size |
| --- | --- | --- | --- |
| **iPhone, 6.5-inch** | [`screenshots/en/iphone-6.5`](screenshots/en/iphone-6.5) | [`screenshots/ru/iphone-6.5`](screenshots/ru/iphone-6.5) | **1284 × 2778** |
| **iPad, 13-inch** | [`screenshots/en/ipad`](screenshots/en/ipad) | [`screenshots/ru/ipad`](screenshots/ru/ipad) | **2064 × 2752** |
| iPhone, 6.9-inch | [`screenshots/en/iphone`](screenshots/en/iphone) | [`screenshots/ru/iphone`](screenshots/ru/iphone) | 1320 × 2868 |

Each folder contains **five ordered images**. Upload them in filename order to
the matching device slot and localization in App Store Connect. All final PNGs
are opaque RGB images, with no alpha channel.

These dimensions are accepted in Apple's
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).
For the **iPhone 6.5-inch** slot shown in your App Store Connect interface, use
the **1284 × 2778** set. This matches one of the slot's accepted portrait sizes
(1242 × 2688 or 1284 × 2778). Upload the iPad set to the **13-inch iPad** slot.
The promotional ZIP includes these two device sets. The additional 6.9-inch
collection is available in its separate folder.

**Screenshot story**

- iPhone: solo gameplay → nearby rivalry → Hold and preview → score and levels → game modes.
- iPad: two players on one iPad → solo gameplay → Hold and preview → nearby rivalry → game modes.

Contact sheets are in [`previews`](previews). They are for review; upload the
individual full-resolution PNGs from `screenshots`.

[`icon/app-icon-1024.png`](icon/app-icon-1024.png) is an opaque copy of the
existing app icon. The shipping icon is supplied through the app's asset catalog.

## App description and listing text

- [`DESCRIPTION.md`](DESCRIPTION.md): readable, copy-and-paste English and Russian descriptions.
- [`metadata/en-US.json`](metadata/en-US.json): English name, subtitle, promotional text, keywords, full description, and review notes.
- [`metadata/ru.json`](metadata/ru.json): Russian listing with the same fields.

Use English (U.S.) for the `en` screenshot collection and Russian for `ru`.
Name and subtitle are within 30 characters, promotional text within 170,
keywords within 100, and descriptions within 4000. Set your support URL,
privacy policy URL, and copyright in App Store Connect using your publishing details.

## Capture provenance

`captures` contains the original **iPhone 13 Pro Max (1284 × 2778)**,
**iPhone 17 Pro Max (1320 × 2868)**, and **iPad Pro 13-inch (M5) (2064 × 2752)**
simulator screenshots, plus JSON capture records. The screens are rendered using
the production UIKit views, `GamePresenter`, theme, and English/Russian string
catalog. A standalone capture host runs deterministic legal engine actions,
then freezes the playing state for capture. Grid cells, scores, levels, previews,
and attacks come from the game's engine. The nearby opponent, **Alex**, is a
sample player used to demonstrate the nearby-game layout.

`tools/CaptureScene.swift` is compiled only into that standalone simulator host.
The capture records describe the rendered board and control regions in points
and the device's pixel scale. `manifest.json` lists the final upload images.

## Regenerate

Run these commands from the repository root on a Mac with Xcode selected and
the two simulator types available:

```sh
python3 -m venv .appstore-venv
.appstore-venv/bin/python -m pip install -r ios/AppStore/tools/requirements.txt

python3 ios/AppStore/tools/capture.py \
  --work-dir "${TMPDIR}tetris-appstore-capture"

.appstore-venv/bin/python ios/AppStore/tools/render.py
.appstore-venv/bin/python ios/AppStore/tools/verify.py
open ios/AppStore/index.html
```

To regenerate only the plain required-size snapshots and their ZIP from the
existing captures:

```sh
.appstore-venv/bin/python ios/AppStore/tools/export_snapshots.py
```

Capture defaults to iPhone 13 Pro Max, iPhone 17 Pro Max, and iPad Pro 13-inch (M5).
To use other installed devices with the same native resolutions, pass
`--iphone-65 <UDID>`, `--iphone <UDID>` and `--ipad <UDID>`.
`--languages en` or `--devices iphone-6.5` captures a subset.
The script leaves the selected simulators booted and clears its status-bar
overrides after capture.

Edit [`screenshot-copy.json`](screenshot-copy.json) to change the promotional
headlines and captions, then rerun `render.py`. Rendering uses the macOS San
Francisco font and requires Pillow; `--font /path/to/font.ttf` selects a
replacement font with English and Cyrillic support. Existing captures are
enough to regenerate the designs without rebuilding the simulator host.
