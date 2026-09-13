# MultiPlash

A web page as your wallpaper, **a different one on every screen** — in the
spirit of [Plash](https://github.com/sindresorhus/Plash), but built for
multi-monitor setups.

Native macOS app: Swift + AppKit + WKWebView, **no external dependencies**,
macOS 14 or later. It lives in the menu bar, with no Dock icon.

> The app's user interface (menus, dialogs, logs) is in French. Menu labels are
> quoted below with their English meaning.

---

## Installation

```bash
./build.sh          # release build, assembles and signs dist/MultiPlash.app
open ./dist/MultiPlash.app
```

`build.sh` produces `dist/MultiPlash.app`, signed **ad hoc** (`codesign --sign -`).
No special permission is requested (neither Accessibility nor Screen
Recording) and no private API is used.

To run the tests:

```bash
./test.sh
```

## Usage

The menu bar icon offers, **for each detected screen**:

| Menu item | Effect |
| --- | --- |
| Choisir un dossier local… (*Choose a local folder…*) | loads the `index.html` of the chosen folder |
| Saisir une URL… (*Enter a URL…*) | loads a web address (`https://` may be omitted) |
| Paramètres… (*Parameters…*) | string appended as a query string, e.g. `fps=30&q=0.7` |
| Recharger (*Reload*) | reloads this screen's page |
| Désactiver / Activer (*Disable / Enable*) | hides or shows this screen's wallpaper |

And globally: **Tout mettre en pause / Reprendre** (*Pause all / Resume*),
**Lancer au démarrage** (*Launch at login*, via `SMAppService`), **Lancer
l'économiseur d'écran** (*Start screen saver*), **Économiseur après
inactivité** (*Screen saver after idle time*), **Mesurer les images/s**
(*Measure frame rate*) and **Quitter** (*Quit*).

A chosen folder is loaded with `loadFileURL(_:allowingReadAccessTo:)`, granting
read access to the whole folder: neighbouring resources (shaders, textures,
JS modules) load normally and **WebGL works**.

### Configuration

Everything is stored in:

```
~/Library/Application Support/MultiPlash/config.json
```

keyed by the **display UUID** (`CGDisplayCreateUUIDFromDisplayID`), which
survives restarts, unplugging and screen reordering:

```json
{
  "schemaVersion": 1,
  "isPaused": false,
  "screenSaverAfterMinutes": 0,
  "screens": {
    "11111111-2222-3333-4444-555555555555": {
      "displayName": "External display",
      "source": { "type": "folder", "value": "/Users/me/Wallpapers/Trou noir" },
      "parameters": "fps=30&q=0.7",
      "isEnabled": true
    }
  }
}
```

`source.type` is `folder`, `url` or `none`. A screen never seen before gets a
default configuration (enabled, no source); nothing is written until you pick a
source.

`config.json` is also **reloaded live**: edit it in any editor and the
wallpapers adjust within two seconds, without restarting the app.

### Screens plugged / unplugged, sleep

- `didChangeScreenParametersNotification`: windows are recreated and
  repositioned (resolution, arrangement, screen added or removed) without
  restarting the app. An unplugged screen's configuration is kept and
  reapplied when it comes back.
- `NSWorkspace.didWakeNotification`: after sleep, windows are revalidated and
  animation resumes.

## Bundled wallpapers

The project's `Fonds/` folder contains the pages used:

| Folder | Content | Cost |
| --- | --- | --- |
| `Trou noir` (*Black hole*) | black hole with gravitational lensing, accretion disk, orbiting star and planet | heavy (see below) |
| `Galaxies` | two colliding galaxies, 320,000-star simulation | light |
| `Ciel étoilé` (*Starry sky*) | rotating night sky: Milky Way, twinkling stars, the seven planets, satellites, shooting stars and the Moon | light: 60 fps at 2560×1440 |

To look at one without installing anything:

```bash
open "Fonds/Ciel étoilé/index.html"
```

### Black hole and Galaxies parameters

| Parameter | Black hole | Galaxies |
| --- | --- | --- |
| `q` | render scale: `1` = native screen resolution, `0.8` = 80 %, `>1` = supersampling | same |
| `fps` | frame-rate cap | same |
| `dtk` | ray integration step size (smaller = more accurate, heavier) | — |
| `steps` | number of lensing integration steps | — |
| `n` | — | number of simulated stars |
| others | `spin`, `dist`, `fov`, `elev`, `cam`, `exp` | `speed`, `bright` |

The `Galaxies` stars are rendered with a tight core and a narrow sprite
(`vSoft = 6`, `gl_PointSize = 1.7 × px`): sharp points rather than halos. The
two galaxies' hues never change abruptly — they are targets the current colours
glide towards over about twenty seconds, and the gas colour is a continuous
blend between blue and pink.

### Starry sky parameters

The `Ciel étoilé` sky **rotates as a whole around a celestial pole**, like the
real one: stars, Milky Way, planets and Moon rise and set together. A full turn
takes **5 minutes** by default, so the motion is visible immediately. On top of
that the **pole itself drifts**, over two different periods (41 s and 59 s,
amplitude 12 % of the screen): no star is ever still, not even the one at the
centre of rotation. The planets also wander among the stars along the ecliptic
(one lap in 30 minutes for Mercury, 109 for Neptune) and the Moon drifts over 22
minutes. The seven planets are drawn to scale with each other and **all smaller
than the Moon**: bands and Great Red Spot for Jupiter, rings for Saturn, polar
caps for Mars, phases for Venus and Mercury.

| Parameter | Effect | Default |
| --- | --- | --- |
| `turnmin` | minutes for a full sky rotation (smaller = faster; 20 for a calm sky) | 5 |
| `drift` | sky drift, so that no star is ever still, even at the pole (0 = none) | 1 |
| `polex`, `poley` | celestial pole position, as a fraction of the screen | 0.5, 0.35 |
| `planets`, `labels` | planets; planet names | 1, 0 |
| `moon`, `moondrift` | Moon; minutes of drift relative to the stars | 1, 22 |
| `stars`, `twinkle` | background stars; of which twinkling | 2200, 620 |
| `sat`, `meteor` | simultaneous satellites; seconds between shooting stars | 3, 4 |
| `haze`, `seed` | Milky Way; sky seed (reproducible) | 1, 7 |

The sky layer is a square that covers the screen whatever the rotation: count
about 40 MB of memory at 2560×1440 — released as soon as the wallpaper reaches
the "page unloaded" tier (see *Energy saving*).

## Performance

### Measuring the frame rate

The **Mesurer les images/s** menu item makes each screen measure the frame rate
its page actually achieves and write it to the log:

```bash
log show --predicate 'subsystem == "MultiPlash"' --last 2m | grep "images/s"
```

### What actually costs, measured

Measurements are done on the page alone, uncapped (`fps=240`), at a forced
resolution to get past the 60 Hz ceiling — otherwise everything reads 60 and
nothing can be learned.

| Scene | Load | fps |
| --- | --- | --- |
| Galaxies | 5632×3168 (17.8 Mpx) | **60** (always at the ceiling) |
| Black hole | 4096×2304 (9.4 Mpx) | **20** |
| Black hole without the procedural sky | same | 26 |
| Black hole without the disk noise | same | 21 |
| Black hole, 90 steps instead of 160 | same | 21 |

The sky has since been **pre-computed into a panoramic texture** at startup
(nebulae only depend on the ray direction and never change): measured head to
head, 7.36 → 5.95 ms/Mpx, i.e. **19 % less time**. Stars remain procedural to
stay sharp.

Counter-intuitive conclusions: **the galaxies cost almost nothing** despite
their hundreds of thousands of bodies, and the black hole is about ten times
more expensive per pixel. For the black hole, neither the number of steps nor
the per-step work matters — the cost follows the **pixels**. The only effective
lever is therefore `q`, and the procedural sky (nebulae and star fields) is a
quarter of the total.

**Measurements on an Apple M4 Mac, two 2560×1440 screens driven at the same
time:**

| Setting | Black hole | Galaxies | fps |
| --- | --- | --- | --- |
| Maximum resolution | `q=1&dtk=0.12` | `q=1&n=360000` | 26 / 33 |
| Balanced | `q=0.9&dtk=0.45&steps=180` | `q=1&n=280000` | 51 / 53 |
| **Chosen** | `fps=60&q=0.6&dtk=0.5&steps=120` | `fps=60&q=1&n=320000` | **60 / 60** |

The chosen setting renders the black hole at 1536×864 and then scales the
image up; the galaxies run at native 2560×1440 — they can afford it. Frame
budget breakdown (16.7 ms at 60 Hz):

| Scene | Cost per frame | Share of budget |
| --- | --- | --- |
| Black hole | ≈ 4.6 ms | ≈ 28 % |
| Galaxies | ≈ 1.5 ms | ≈ 9 % |

Use `fps=30` to roughly halve GPU and CPU load if 60 fps is not needed.

### Measuring without fooling yourself

Three traps led to wrong conclusions before they were spotted — avoid them:

1. **Pause the wallpapers** (`isPaused` set to `true` in `config.json`):
   otherwise the app's scenes compete with the page being measured.
2. **Disable the screen saver timer** (`screenSaverAfterMinutes` set to `0`):
   otherwise it starts after a minute of inactivity, hides the test window —
   `requestAnimationFrame` then drops to 1 fps — and skews everything.
3. **Close previous test tabs**: a tab left on a heavy scene keeps computing in
   the background.

Above all: compare two versions **back to back**, a few seconds apart. Absolute
values vary a lot with whatever else the machine is doing; only ratios measured
in quick succession mean anything.

### Energy saving

A wallpaper nobody can see should cost nothing. MultiPlash applies **tiers**:
the longer a screen stays hidden, the more resources it gives back.

| Tier | Trigger | Effect |
| --- | --- | --- |
| Active | wallpaper visible | normal animation |
| Animation stopped | immediately, as soon as the wallpaper is hidden | the page switches to `document.visibilityState == "hidden"`: no more `requestAnimationFrame`, the GPU stops working |
| Page unloaded | 3 minutes | the WebGL context, textures and page memory are freed |
| Web view released | 15 minutes | the WebKit rendering process is destroyed (several hundred MB returned) |

Everything reloads and resumes automatically as soon as the wallpaper becomes
visible again.

A wallpaper is considered hidden when:

- its window is covered (`NSWindow.occlusionState`);
- **an app fills the whole screen** (full screen, or a window covering the
  entire area) — checked every 5 seconds from window geometry
  (`CGWindowListCopyWindowInfo`, public API, no permission required: no window
  title or content is read);
- the displays are asleep or the session is locked;
- you chose "Pause all" or disabled that screen.

Every transition is logged:

```bash
log show --predicate 'subsystem == "MultiPlash"' --last 5m
```

## Animated lock screen

macOS does not display web pages on the lock screen: MultiPlash's windows are
removed as soon as the session locks, and no public API allows drawing there.
The only supported path is a **screen saver**, which macOS does show on the
locked screen.

```bash
./build-economiseur.sh                              # produces dist/CielEtoile.saver
cp -R dist/CielEtoile.saver ~/Library/Screen\ Savers/
```

Then System Settings → Screen Saver → "Other" section → **Ciel étoilé**. The
screen saver embeds its own copy of the page and animates it full screen.

### Starting the screen saver despite apps that keep the display awake

Some apps (video players, dashboards…) hold a `PreventUserIdleDisplaySleep`
system assertion that prevents macOS from starting its screen saver — and
nothing can release another app's assertion. MultiPlash works around this: it
**measures keyboard and mouse idle time itself**
(`CGEventSource.secondsSinceLastEventType`, public API) and starts the screen
saver directly, bypassing the macOS timer.

In the menu: "Lancer l'économiseur d'écran" (*start now*) and "Économiseur
après inactivité" (*after idle time*: never, 1, 2, 5, 10 or 20 minutes). The
setting is stored in `config.json` as `screenSaverAfterMinutes` (0 = never).

To check which assertion is blocking the screen saver:

```bash
pmset -g assertions | grep PreventUserIdleDisplaySleep
```

### Screen saver cost

A screen saver draws on the CPU, not in WebGL: *how* things are drawn matters
more than *what* is drawn. Measured on three screens, `legacyScreenSaver`
process:

| Version | CPU |
| --- | --- |
| Everything redrawn every frame, 60 fps | 92–99 % |
| Background handed to a Core Animation layer (rotation on the GPU), 30 fps | 45 % |
| Moon and planets as layers, twinkling at reduced resolution | **34 %** |

The principle: anything that only changes *position* becomes a layer the GPU
moves; only what changes *shape* is redrawn, and at low resolution since those
are blurry halos.

Two limitations to know about:

- when locking, macOS first shows the **wallpaper image**; the screen saver
  only starts after the idle delay (set in the same settings pane);
- to make the lock image a starry sky too, install a still capture of the page
  as the desktop picture:

```bash
swift Outils/capture-fond.swift <page url> 2560 1440 7 sky.png
swift Outils/definir-fond.swift sky.png
```

## Future work: pre-computed deflection table

An optimisation not done yet, but the only one left with a big payoff on the
black hole: **×5 to ×10**, versus 28 % of the frame budget today.

### Observation

After the sky cache, the remaining time goes almost entirely into step-by-step
ray integration (`for(int i = 0; i < STEPS; i++)` in
`Fonds/Trou noir/index.html`). Two measurements frame the problem:

- lowering the **maximum number** of steps changes nothing (160 or 90: same) —
  rays terminate before the limit;
- lowering the step **size** (`dtk`) helps a lot — so it really is the number of
  steps actually taken that costs.

### Principle

In the Schwarzschild metric, a photon's trajectory depends only on **its impact
parameter** `b` (and the starting radius, here the camera distance). Two rays
with the same `b` follow the same curve, up to a rotation. So one can compute,
once and for all, for a few hundred values of `b`:

- whether the ray is captured (`b` below the critical parameter
  `b_c = 3√3/2 · Rs ≈ 2.598`);
- otherwise, the **total deflection angle** — which gives the sky direction to
  sample;
- the **equatorial plane crossing radii** (1st, 2nd, possibly 3rd), which give
  the disk sampling points.

The shader then replaces the whole loop with a texture lookup plus one to three
calls to `diskSample` (which stays procedural: it is only 5 % of the cost).

**Why it is valid here**: the camera keeps a constant distance (`dist=40`, only
azimuth and a slight elevation vary), the metric is static and the disk lies in
a fixed plane. Rotational symmetry does the rest — the table lives in the ray's
own plane.

### How to build it

Reuse the existing integrator offline: at startup in JavaScript for 512 to 1024
values of `b` (a few milliseconds), results stored in a 1D texture. Same recipe
as the sky: paint once, read afterwards.

### Pitfalls

- **Near the critical parameter**, the deflection diverges and the number of
  plane crossings explodes (the ray winds around). Sample `b` non-uniformly,
  denser in `log(b − b_c)`, otherwise the photon ring will be wrong or aliased.
  This is the delicate part: it is precisely what makes the image beautiful.
- **Cap at two or three disk images**; beyond that it is invisible.
- **The orbiting star and planet do not fit this scheme**: they are 3D objects
  outside the equatorial plane. Keep step-by-step marching for them, triggered
  by the proximity test already in the loop, or accept a small approximation.
- **Keep the old path** behind a URL parameter (`?lut=0`) to compare both
  renders side by side: any table error shows first on the photon ring and on
  the thin, high-contrast secondary disk image.

### How to validate

Measure following the method above (wallpapers paused, screen saver disabled,
back-to-back comparison), at `?fps=240&q=1.6` on both versions, and compare
**ms/Mpx**. Then check visually at a wide field of view (`?fov=55`), where the
photon ring and multiple images are easiest to read.

## How it works

```
Sources/MultiPlashCore/     configuration model, persistence, source resolution (tested)
Sources/MultiPlash/         AppKit app: desktop windows, WKWebView, menu
Tests/MultiPlashCoreTests/  swift-testing tests
Fonds/                      bundled web wallpapers
Economiseur/                "Ciel étoilé" screen saver (lock screen)
Outils/                     capture a page to a still image, set the desktop picture
build.sh                    release build + dist/MultiPlash.app assembly + ad hoc signing
build-economiseur.sh        dist/CielEtoile.saver assembly + ad hoc signing
test.sh                     runs the tests, with or without Xcode
```

One borderless window per screen, exactly the size of `screen.frame`, placed at
`CGWindowLevelForKey(.desktopWindow)` — so **above the system wallpaper and
below the desktop icons** — with
`collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]` and
`ignoresMouseEvents = true`: it never takes focus, never shows up in Cmd-Tab or
Mission Control, and clicks go through to the desktop.

## Known limitations

- **No interaction** with the page: the window lets all clicks through (that is
  the point of a wallpaper). There is no "interactive" mode.
- **Not sandboxed**: the app reads the folders you choose. It only writes its
  own `config.json`.
- **Ad hoc signature**: on first launch macOS may ask for confirmation
  (right-click → Open). The app is neither notarised nor distributed.
- **Launch at login** relies on `SMAppService.mainApp`: the app must live in a
  stable location (e.g. `/Applications`); moving the bundle invalidates the
  registration.
- **Power usage**: one WebGL page per screen remains GPU-intensive. Frame rate
  also depends on what your other apps are doing (a playing video takes its
  share). Measure with "Mesurer les images/s", tune `q`, `fps`, `n`, `steps`,
  and use "Pause all" when needed.
- **Mirrored displays**: mirrored displays share the image but remain two
  screens for the system; each gets its own window.
- **`swift test` without Xcode**: with only the Command Line Tools, SwiftPM
  builds the tests but does not run them, because it cannot find
  `Testing.framework` unless given a `-F` on the command line. `./test.sh` adds
  what is needed; with Xcode installed, it simply calls `swift test`.
- **http://**: only local pages and `https://` load without extra settings; the
  `Info.plist` additionally allows plain http on the local network (for a local
  development server).
