# SkyTrack

SkyTrack is a native macOS planetarium. It plots the positions of the eight planets and Pluto for any place and time, and pairs the sky chart with an interactive 3D globe of the selected world. The chart is rendered locally from bundled resources, so no network connection is needed to view the sky.

## Features

- **All-sky planet chart** — an altitude/azimuth chart generated offline by the bundled `sky.html`, with a deterministic star field, hover highlighting, and above/below-horizon states.
- **Location search** — enter a city or address, use your current location, or type coordinates such as `40.7128, -74.0060`. Locations are resolved to readable place names.
- **Predictive suggestions** — matching places appear as you type; navigate with the arrow keys and accept with Return.
- **Date and time travel** — pick any date and time, or jump back to the present with the Today button. The chart updates automatically.
- **Collapsible planet list** — all eight planets plus Pluto in a sidebar that can be hidden to give the chart more room.
- **Interactive 3D inspector** — a rotating SceneKit globe with relative axial tilts, Saturn's rings, and procedurally generated surfaces for most bodies.
- **Detailed Earth** — NASA Blue Marble day, normal, and specular maps, plus a transparent cloud shell and a fixed atmospheric rim.
- **Pop-out 3D window** — open the current planet in its own resizable window.
- **Click-to-inspect** — clicking a planet on the sky chart selects it in the list and opens its 3D view.
- **Native AppKit UI** — built entirely in code, with no storyboards or XIBs.
- **Private by default** — location data stays on the Mac. Place search uses Apple's geocoding services; sky rendering does not require a network.

## Requirements

- macOS 12.0 (Monterey) or later
- Xcode with the macOS SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) only if you want to regenerate the Xcode project after editing `project.yml`

## Build and run

### Xcode

Open the project, select the `SkyTrack` scheme, and press Run:

```sh
open SkyTrack.xcodeproj
```

### Command line

```sh
xcodebuild -project SkyTrack.xcodeproj \
           -scheme SkyTrack \
           -configuration Debug \
           -derivedDataPath build \
           build

open build/Build/Products/Debug/SkyTrack.app
```

The app is ad-hoc signed, so no Apple Developer team or provisioning profile is required.

`SkyTrack.xcodeproj` is generated from `project.yml`. If you change the project definition, regenerate it first:

```sh
brew install xcodegen
xcodegen generate
```

## Usage

1. Launch SkyTrack. It starts in New York City at the current date and time.
2. Set a location by typing a place name and pressing Return, by choosing a suggestion, by entering `latitude, longitude`, or by clicking **Use My Location**.
3. Choose a date and time with the picker, or click **Today** to return to the present.
4. Read the chart: azimuth runs across the bottom, altitude up the sides. Planets below the horizon are dimmed and marked in the legend.
5. Click a planet in the chart or select one in the sidebar to inspect it.
6. Drag the 3D globe to orbit. Scroll and pinch zoom are intentionally disabled to prevent accidental zooming.
7. Click **Pop Out** to keep the 3D view in a separate window. Press `⌘W` to close that window.
8. Click **Planets** to show or hide the sidebar.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Close the focused window | `⌘W` |
| Quit SkyTrack | `⌘Q` |
| Minimize | `⌘M` |
| Select all text in the location field | `⌘A` |
| Previous / next location suggestion | `↑` / `↓` |
| Search or accept a suggestion | `Return` |
| Dismiss suggestions | `Escape` |

Standard Edit menu shortcuts (`⌘Z`, `⇧⌘Z`, `⌘X`, `⌘C`, `⌘V`) work in text fields.

## Project structure

```
SkyTrack/
├── project.yml                  # XcodeGen project definition
├── SkyTrack.xcodeproj/          # Generated Xcode project
└── SkyTrack/
    ├── AppDelegate.[hm]         # App lifecycle and main menu
    ├── MainWindowController.[hm] # Window, chart, sidebar, and 3D inspector
    ├── PlanetModel.[hm]         # Planet data and facts
    ├── main.m                   # Entry point
    ├── Info.plist               # Bundle metadata and location usage string
    └── Resources/
        ├── sky.html             # Bundled canvas sky map
        ├── earth_day.jpg        # NASA Blue Marble day map
        ├── earth_normal.jpg     # Topographic normal map
        ├── earth_specular.jpg   # Ocean and ice specular map
        └── earth_clouds.png     # Transparent cloud layer
```

## How it works

- **UI:** programmatic AppKit. `MainWindowController` builds the location search bar, date picker, collapsible sidebar, `WKWebView` chart, and SceneKit inspector.
- **Sky map:** `Resources/sky.html` computes approximate geocentric positions from JPL mean orbital elements, converts them to local altitude and azimuth, and draws the chart with the Canvas API. Clicked planets are sent to the native app through a `WKScriptMessageHandler`.
- **3D views:** SceneKit renders each planet in a reusable scene builder. Earth uses the bundled Blue Marble texture set, while the other bodies use procedural textures. The inspector and the pop-out window each have their own camera and scene.
- **Geocoding:** `CLGeocoder` resolves place names and reverse-geocodes coordinates; `MKLocalSearchCompleter` supplies typing suggestions.

## Accuracy notes

SkyTrack is designed for education and exploration, not navigation. Positions come from mean orbital elements and omit perturbations, light-time, and topocentric corrections. The date picker uses the Mac's time zone rather than the time zone of the selected location, so daylight saving time at remote locations is not modeled. Place search and autocomplete require network access; the star chart itself is fully local.