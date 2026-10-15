# StableBar

A native, configurable macOS bar built with Swift, AppKit and SwiftUI. One persistent panel per display holds the widgets; workspace changes update their contents without recreating windows.

The default configuration includes a System Settings shortcut, the active app and a clock. It needs no accounts, network services or third-party tools. Optional shell widgets use a plain-text or JSON output protocol.

## Install and set up

Open `StableBar.dmg`, drag StableBar to Applications, then open the app. The first launch walks you through a bar preview, light or dark widgets, placement, clock format, and opening at login. Setup is also available from the menu-bar icon or by right-clicking the bar.

The starter bar needs no special permissions. Scripts that control other apps may prompt for Automation access when used; setup links to the relevant System Settings. AeroSpace manages its own Accessibility permission. Opening at login uses macOS Login Items and is off until you enable it.

Appearance choices update global widget colors; individual widget styles still take precedence. Setup preserves custom widgets, scripts, and other settings. Closing setup leaves it available on the next launch. New configurations place the bar below the macOS menu bar; existing configurations retain their position.

## Build and run

Requires macOS 14+ and Xcode's Swift 6 toolchain. Optional workspace widgets require AeroSpace 0.21+ at `/opt/homebrew/bin/aerospace`.

Quit the running app before rebuilding its bundle.

```sh
./scripts/build.sh
open dist/StableBar.app
```

For development checks:

```sh
swift test
```

The first launch creates `~/.config/stablebar/config.json` from [Resources/config.json](Resources/config.json), with an offset for your menu bar. Subsequent launches keep your file. Right-click the bar or use its macOS menu-bar icon to open the configuration, reload it, reconnect AeroSpace or quit.

### Build an installer

```sh
./scripts/package.sh
```

This creates `dist/StableBar.dmg` with the app and an Applications shortcut. It builds in a temporary directory, leaving a running `dist/StableBar.app` untouched. The app and installer target the build Mac's processor family.

Local builds are ad-hoc signed. For public distribution without an unidentified-developer warning, use a Developer ID Application certificate and a saved `notarytool` keychain profile:

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='stablebar-notary' ./scripts/package.sh
```

The script signs with the hardened runtime, submits the DMG to Apple, then staples and validates its notarization ticket. See [Apple's notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for certificate and keychain-profile setup. A local DMG is suitable for development; building it alone does not make it a notarized release.

Keep personal settings in `~/.config/stablebar/config.json` and personal scripts in `~/.config/stablebar/widgets/`, outside the repository. Point commands directly at those scripts. `Resources/config.json` is the shared starter configuration; rebuilding the app does not overwrite your personal file. Local scripts should load any supporting files from their own directory. `$STABLEBAR_SCRIPTS` always refers to the bundled scripts.

StableBar sits at the top edge of each display. `bar.offset` moves it down from that edge. It hides on native fullscreen Spaces. AeroSpace gaps and macOS menu-bar settings are managed separately; this app does not change them. Keep the center clear on a notched display. The default configuration uses only the left and right groups.

## Layout and style

Save the configuration to apply changes. Direct saves and atomic file replacements are watched, including files imported with `includes`. Invalid edits retain the last working configuration and show an error indicator. Script instances, their last output, and graph history survive style-only changes, including when a script has an error.

- `bar`: `height`, `offset`, `inset`, `spacing`, `background`, `animationDuration` (seconds).
- `defaults`: styles inherited by every widget.
- `widgets`: ordered widget definitions with unique `id`, `type`, `position` and optional `style`, `icon`, `onClick`, `menu`, `popup`.
- `position`: `left`, `notchLeft`, `center`, `notchRight` or `right`.
- Colors: `#RRGGBB` or `#RRGGBBAA` (alpha last).
- Icons: SF Symbols names.
- Measurements: points.

### Modules, templates and overrides

Split a setup into JSON files and load them from the main configuration:

```json
{
  "includes": ["theme.json", "widgets/system.json", "widgets/music.json"],
  "environment": { "PLAYER": "Spotify" },
  "widgetOverrides": {
    "clock": { "format": "EEE HH:mm", "style": { "fontSize": 14 } },
    "music": { "enabled": false }
  }
}
```

Include paths are relative to the file that names them; absolute paths and `~` also work. Includes can have their own includes. Files apply in listed order, followed by the containing file. Objects merge recursively, with later values winning. Arrays replace earlier arrays, except the top-level `widgets` arrays, which concatenate in order. Modules can contain only a theme, templates, popups, environment variables, or overrides; they do not need widgets.

Define reusable widget properties in `templates`, then select one with `template`:

```json
{
  "templates": {
    "metric": {
      "type": "script", "position": "right", "interval": 30, "timeout": 5,
      "style": { "fontSize": 12, "paddingHorizontal": 10 }
    },
    "eventMetric": { "template": "metric", "interval": null }
  },
  "widgets": [
    {
      "id": "build", "template": "eventMetric", "events": ["build_finished"],
      "command": "printf '%s' \"${INFO:-Waiting for a build}\""
    }
  ]
}
```

Widget properties override their template recursively. `widgetOverrides` applies last, by widget ID, so you can customize imported widgets without editing shared files. Set `enabled` to `false` to hide a widget and stop its script and event subscriptions. Set it back to `true` to restore it. Use `null` to clear an inherited optional property, such as `popup` or `interval`. Overrides must not contain an `id` field. Duplicate widget IDs, unknown override targets, include cycles, and missing or cyclic templates referenced by widgets reject the whole edit.

Included files are watched even outside the main directory. A missing module or directory is watched for repair; the last working bar remains visible meanwhile. Setup writes clock choices into the main file's overrides, preserving imported files.

[examples/modular](examples/modular/config.json) is a complete, dependency-free starter with a theme, template, event-only status, and an optional volume widget. Try it without replacing your personal configuration:

```sh
./dist/StableBar.app/Contents/MacOS/StableBar --validate examples/modular/config.json
./dist/StableBar.app/Contents/MacOS/StableBar --config examples/modular/config.json
```

From another terminal, run `./dist/StableBar.app/Contents/MacOS/StableBar --trigger demo 'INFO=Build finished'`. The status changes to the supplied text. Enable the sample volume widget through its override to use click-to-mute and scroll-to-adjust.

Each widget can override any of these styles:

`foreground`, `background`, `hoverBackground`, `borderColor`, `borderWidth`, `cornerRadius`, `fontName`, `fontSize`, `fontWeight`, `iconSize`, `paddingHorizontal`, `paddingVertical`, `spacing`, `width`, `accent`, `accentText`, `shadowRadius`, `shadowColor`.

`fontName` is `system` or an installed font name. `fontWeight` is `regular`, `medium`, `semibold` or `bold`. Set `width` on frequently changing widgets to keep their footprint stable. The workspace highlight uses `accent` and `accentText`; its motion respects Reduce Motion. Set `animationDuration` to `0` to remove transition time.

Styles also accept `hoverForeground`, `height`, `paddingLeading`, `paddingTrailing`, `paddingTop`, `paddingBottom`, `offsetX`, `offsetY` and `opacity`. Side-specific padding overrides horizontal/vertical padding. `ultralight`, `thin` and `light` font weights are available too. Offsets move the drawing without moving its neighbours.

### Displays and notch placement

`notchLeft` ends before the notch and `notchRight` starts after it. `bar.notchSpacing` controls the gap on each side (16 by default). The notch comes from the screen's unobscured top areas; `bar.notchWidth` can override its width. On screens without a notch, `notchLeft`, `center` and `notchRight` form one centered group, measured from the visible content. Hidden groups leave no gap. With a notch, `center` remains at the screen's center and should be left empty.

Each widget accepts `display`: `"all"` (default), `"active"`, `"main"`, `"builtIn"`, `"external"`, `"notched"`, `"unnotched"`, or an array of screen numbers, for example `[1, 2]`. Numbers are one-based positions in `NSScreen.screens`, matching AeroSpace and SketchyBar; they can change when displays are rearranged. `active` follows AeroSpace focus. Use `aerospace list-monitors --format '%{monitor-name}|%{monitor-appkit-nsscreen-screens-id}'` to list them.

`bar.style` accepts `background`, `cornerRadius`, `borderColor` and `borderWidth`. The border is drawn along the bottom edge. Scripts can return `barStyle` to change those properties; later widgets override earlier widgets when they set the same property.

### Composing widgets

A widget's `layout` uses the same blocks as a popup. Use rows and columns to style the label, icon and other elements independently. Bar layouts take their content's width; popup layouts fill their available width. Give graphs, progress blocks and images explicit sizes when they should have a fixed footprint.

`overlay` uses the same blocks, aligned to the widget's bottom edge. It occupies no space and does not intercept clicks. This supports an underline, playback progress or a graph underneath the label.

For example, a music script can return:

```json
{
  "text": "Track title",
  "fields": { "artist": "Artist", "artwork": "https://example.com/cover.jpg" },
  "values": { "playback": 0.25 },
  "targets": { "playback": 0.30 }
}
```

The widget can use:

```json
{
  "layout": {
    "type": "row",
    "style": { "spacing": 6 },
    "children": [
      { "type": "field", "field": "artist", "style": { "fontSize": 11, "foreground": "#8e978f" } },
      { "type": "field", "field": "text", "style": { "fontSize": 13, "fontWeight": "medium" } }
    ]
  },
  "overlay": {
    "type": "progress", "source": "playback", "height": 2,
    "style": { "accent": "#f1efe8", "background": "#f1efe829", "cornerRadius": 0 },
    "animation": { "curve": "linear", "duration": 15 }
  }
}
```

`text` and `icon` are supplied to bar layouts from the widget's normal content. Other fields come from the script. Active-app layouts receive `text` as the app name. Use the normal clock rendering for native clock widgets.

Script output may include `style` to override the widget style, `display` to change its display filter, and `styles` to supply named element styles. A block with `"styleSource": "countdown"` reads `styles.countdown`, overlaid on its configured style. A list row can use `styleField` to read the style name from a field in that row. Scripts can return `widgetStyles`, keyed by widget ID, to style another widget (for example, change a workspace underline when the window-manager mode changes). Later scripts take precedence; a widget's own `style` output takes precedence over those overrides. Omitted overrides return to the configured style on the next update.

Widgets and blocks accept `animation` with `duration` in seconds and `curve`: `linear`, `easeIn`, `easeOut`, `easeInOut`, `smooth` or `spring`. Widget animation defaults to `bar.animationDuration`. Block style animations are opt-in. Progress values use a 0–1 scale, clipped to that range when drawn. A progress block can also read a numeric string from its current list row when there is no matching entry in `values`. With a matching entry in `targets`, a progress rule starts at `values[source]` and animates toward `targets[source]`; without a target it animates between readings. Reduce Motion disables these animations.

### Workspace appearance

An `aerospace` widget accepts `workspace` with:

- `indicator`: `background` (default), `underline` or `none`.
- `indicatorStyle`: underline `height`, `width`, `background`, `cornerRadius`, `offsetX`, `offsetY`.
- `style`, `focusedStyle`, `visibleStyle`, `emptyStyle`: cell typography, foreground, width, height, horizontal/side padding and spacing. The background indicator uses the state's background or border color.
- `showEmpty` and `showApps`: control empty workspaces and app icons.
- `appStyle`, `focusedAppStyle`, `visibleAppStyle`: font and foreground for app glyphs, width and height for native app icons.
- `appGlyphs`: app bundle ID or app name to text glyph. Set `appStyle.fontName` to an installed icon font to use its ligatures. Use `"*"` for the fallback glyph; otherwise unmapped apps retain native icons.

For a sliding underline, set `workspace.indicator` to `underline`, `workspace.style.height` to the bar's height, and `workspace.indicatorStyle` to `{ "height": 2, "background": "#f1efe8" }`. The widget's `animation` controls its motion.

### Script events

Add `events` to a script widget to refresh it on named events, alongside its interval. Set `"interval": null` to run once at startup and then only on events or after a click action. Omitting the interval keeps the default 30-second polling. Numeric intervals must be greater than zero. `frontApp`, `workspace` and `wake` are emitted by StableBar. Other names subscribe to macOS distributed notifications, for example `com.spotify.client.PlaybackStateChanged`.

External hooks can trigger an event without launching another bar:

```sh
/path/to/StableBar.app/Contents/MacOS/StableBar --trigger aerospace_mode_change
/path/to/StableBar.app/Contents/MacOS/StableBar --trigger build_finished 'INFO=Build passed' STATUS=success
```

Use that event name in the widget's `events`. Extra `KEY=VALUE` arguments become environment variables, preserving spaces, quotes and equals signs as data. Events finish the currently running update and coalesce pending refreshes to the latest event and payload. A widget never runs overlapping update commands. This queue is intended for refreshing current state, not recording every event.

Commands inherit the app's environment, then top-level `environment`, then the widget's `environment`, then event data. Values must be strings. StableBar supplies these variables:

| Variable | Value |
| --- | --- |
| `NAME` | Widget ID; event data cannot replace it |
| `CONFIG_DIR` | Directory containing the main configuration; event data cannot replace it |
| `STABLEBAR_SCRIPTS` | Bundled widget script directory |
| `SENDER` | `startup`, `routine`, the subscribed event name, `action` after an action completes, or a mouse event below |
| `INFO` | Explicit trigger value; front-app name for `frontApp`; focused workspace name for `workspace`; otherwise the distributed notification's JSON payload when available |
| `SID` | Display number for pointer actions and workspace events |
| `BUTTON` | `left`, `right` or `middle` for widget mouse clicks |
| `MODIFIER` | Space-separated `shift`, `ctrl`, `alt`, `cmd`, `fn` for pointer actions |
| `SCROLL_DELTA` | Signed vertical scroll delta for scroll actions |

Script output can also set `onClick` for a state-dependent click action; popups and menus still take precedence. Named graph data goes in `series`, a dictionary of arrays; only the latest 60 samples of each graph are retained.

### Mouse actions

Keep `onClick` for the primary action. Add `actions` to any widget for additional controls:

```json
"actions": {
  "rightClick": "open -a 'System Settings'",
  "middleClick": "open -a 'Activity Monitor'",
  "scrollUp": "\"$CONFIG_DIR/volume.sh\" up",
  "scrollDown": "\"$CONFIG_DIR/volume.sh\" down",
  "mouseEntered": "\"$CONFIG_DIR/hover.sh\" enter",
  "mouseExited": "\"$CONFIG_DIR/hover.sh\" exit"
}
```

These commands receive `SENDER=mouse.clicked`, `mouse.scrolled`, `mouse.entered` or `mouse.exited`. Scroll direction follows the signed native vertical delta. Only configured mouse actions intercept input; an unconfigured right click opens the bar's management menu. Actions run in order per widget, while other widgets remain independent. Successful actions refresh the same script instance with `SENDER=action`. Quitting cancels running and queued actions.

### Command-line controls

- `--config PATH`: launch with a separate configuration, including its modules.
- `--validate [PATH]`: load and validate without opening a bar or executing scripts; exits nonzero on errors. Defaults to your personal config.
- `--trigger EVENT [KEY=VALUE ...]`: notify running bars subscribed to that event.
- `--reload`: ask running bars to reload their configuration.
- `--help`: print usage. Invalid arguments exit with an error instead of launching another bar.

## Built-in widgets

| Type | Content | Additional fields |
| --- | --- | --- |
| `aerospace` | Occupied or visible workspaces on this display, with app icons; click to switch | — |
| `activeApp` | Frontmost app name and icon | — |
| `clock` | Local date/time, updated each minute | `format`: DateFormatter format |
| `text` | Static text and optional icon | `text` |
| `script` | Output of a shell command | `command`, `interval` in seconds or `null` for event-only updates |

The AeroSpace connection subscribes to workspace, monitor, window and focus events. It loads an initial snapshot, coalesces pending events and reconnects after a disconnect. The accent color marks the focused workspace; an outline marks a workspace visible on another monitor. Empty, inactive workspaces are hidden. App icons are deduplicated per workspace. Active-app updates come from NSWorkspace notifications. The clock updates once a minute.

## Optional scripts

The scripts in [Resources/widgets](Resources/widgets) are bundled but disabled by default. They require `jq` and use local system data. `$STABLEBAR_SCRIPTS` points to their bundled directory when a widget or click command runs.

| Widget | Source and behavior | Refresh |
| --- | --- | --- |
| CPU | `ps` and `sysctl`; 60-sample graph, load averages, five busiest processes with CPU and memory | 2 s |
| Volume | Output volume/mute | 5 s |
| Battery | `pmset`; charge, power source and remaining time | 120 s |

Enable a script by adding a `script` widget with a command such as `"\"$STABLEBAR_SCRIPTS/cpu.sh\""` and an interval. Widget menus use themed popups. The app's management menus (right-click and macOS status icon) remain native.

## Create a widget

Add an entry to `widgets`:

```json
{
  "id": "my-widget",
  "type": "script",
  "position": "right",
  "command": "~/.config/stablebar/widgets/my-widget.sh",
  "interval": 30,
  "icon": "bolt",
  "onClick": "open -a 'Activity Monitor'",
  "style": {
    "background": "#22252b",
    "foreground": "#eeeeee",
    "width": 100,
    "cornerRadius": 8
  }
}
```

Commands run through `/bin/zsh -lc`. Use absolute paths or `~` for your own scripts, and make them executable. Widgets can be written in shell, Python, Swift, Rust or anything that prints to stdout.

Return plain text, or one JSON object:

```json
{"text":"Ready","icon":"checkmark.circle","color":"#228844","tooltip":"All checks passed"}
```

`text` is required; the other output fields are optional:

- `hidden`: removes the widget when true (unless it has an error).
- `interval`: overrides the next polling delay in seconds; must be greater than zero. Omit it to use the configured interval.
- `menu`: an array of `{ "title": "Issue", "detail": "In progress", "onClick": "open …" }`, displayed in a themed popup. Rows without `onClick` show information. A menu takes precedence over the widget's click command. Static widgets can also define `menu` in their configuration.
- `value`: a graph sample, displayed on a 0–1 scale with the last 60 samples.
- `fields`: named display strings for popup field blocks.
- `lists`: named arrays of objects containing display strings for popup list blocks.

A nonzero exit, timeout, excessive output or invalid JSON preserves the previous output and adds a warning with the error in its tooltip. Polling scripts retry at their configured interval; event-only scripts retry on their next event or action. A completed click action requests an immediate refresh. `onClick` runs only when clicked.

Commands have a 10-second timeout by default. Set a widget's `timeout` to another positive number of seconds; it applies to both updates and actions. Stdout and stderr are each limited to 1 MiB. Successful stderr logging does not corrupt the widget's stdout JSON. Failures display stderr, stdout, or the exit status when neither contains a message.

Commands must finish; do not start background daemons from widget scripts. Timeout, cancellation, and shutdown kill the command's process group and direct process. A descendant that deliberately starts another session or process group can outlive it, but cannot hold the widget's output pipe open past its timeout.

## Custom popups

Add `popup` to any widget. For a popup shared by multiple widgets, define it once in the top-level `popups` object and set each widget's `popupName` to its key. Each anchor uses its own script data. An inline `popup` takes precedence over `popupName`. It takes precedence over `menu` and `onClick`. Its layout is independent of the script, so you can change the layout without changing the data source or rebuilding the app. The example below uses fields from [cpu.sh](Resources/widgets/cpu.sh).

Widgets with `menu` entries already open a shared popup without additional configuration. To customize that popup, add `popup` with your preferred height and style and `"layout": { "type": "menu" }`. You can also place a `menu` block alongside other blocks in a custom layout. Entries retain their titles, details and click commands, and refresh while the popup is open.

```json
"popup": {
  "height": 240,
  "style": {
    "width": 360,
    "paddingHorizontal": 18,
    "paddingVertical": 18,
    "spacing": 12
  },
  "layout": {
    "type": "column",
    "children": [
      {
        "type": "row",
        "children": [
          { "type": "text", "text": "CPU usage" },
          { "type": "field", "field": "usage", "alignment": "trailing", "style": { "fontSize": 28 } }
        ]
      },
      { "type": "graph", "height": 80 },
      { "type": "button", "title": "Activity Monitor", "onClick": "open -a 'Activity Monitor'" }
    ]
  }
}
```

`height`, `style` and `layout` are required. Use `"style": {}` to inherit the widget's theme. Popup colors, typography, borders, corners and shadow inherit widget styles and then global defaults. Popup width defaults to 360 points independently of the bar widget width; set it with `popup.style.width`. Padding and spacing can be overridden separately. Height is capped to the space below the bar; long content scrolls.

Layout blocks:

| `type` | Required fields | Content |
| --- | --- | --- |
| `row` | `children` | Blocks arranged horizontally |
| `column` | `children` | Blocks arranged vertically |
| `text` | `text` | Static text |
| `field` | `field` | A string from the script's `fields` object, or the current list row |
| `graph` | `height` | The widget's existing 60 samples on the 0–1 scale; optional `source` reads `series[source]` instead and `lineWidth` sets stroke width |
| `list` | `source`, `row` | Repeat the `row` block for each object in `lists[source]` |
| `button` | `title`, `onClick` | Run a command and close the popup |
| `menu` | — | The widget's script or configured menu entries, with their existing actions |
| `divider` | — | A horizontal rule |
| `image` | `path` or `source` | Local path, `file://`, or HTTP(S) image; `source` reads a path from `fields`. `fit` is `fit` or `fill`; size defaults to 52 × 52. |
| `symbol` | `name` or `source` | SF Symbol; `source` reads its name from `fields`. `style.iconSize` sets its size. |
| `progress` | `source`, `height` | A rule using `values[source]`, optionally moving toward `targets[source]`. `style.accent` is the fill and `style.background` the track. |

Every block accepts `style` and `alignment` (`leading`, `center`, `trailing`). Fonts, text color, accent and spacing inherit from the containing block. Width, padding, background, hover background and border apply only when set on that block. Set a width on numeric fields and their headings to align columns. Blocks without a width use the available space.

Text and field blocks can set `scrollSpeed` in points per second with a fixed `style.width`. Overflow scrolls back and forth with a pause at each end; fitting text and Reduce Motion do not scroll. `hideWhenEmpty` names a field: the block occupies no space when that field is absent or empty, which is useful for optional list-row headings and pipeline details.

Any block can also have `onClick`, or `onClickField` to read a command from the current fields/list row. This allows a symbol button or a clickable agenda row. A popup accepts `alignment` (`leading`, `center`, `trailing`) and `offset` for placement relative to its widget. A popup's optional `animation` controls its opening/closing fold and fade. Reduce Motion keeps only the fade. Native panel animation maps `smooth` and `spring` to ease-in-out; other curves retain their names. `dismissOnAction` defaults to `true`; set it to `false` for player controls that should keep the popup open. Images load asynchronously and update when their source path changes. Use a different local filename for each cover, or supply its URL.

For example, a script can return:

```json
{
  "text": "30%",
  "value": 0.3,
  "fields": { "usage": "30%", "load": "3.2 2.8 2.1" },
  "lists": {
    "processes": [
      { "name": "WindowServer", "pid": "423", "cpu": "90.1%", "memory": "108 MB" }
    ]
  }
}
```

Field and list values are display strings; scripts supply units and formatting. Missing fields display `—` and missing lists are empty while data loads. Values and graphs update while the popup stays open. Click the widget again, click outside, or press Escape to close it. Saving configuration closes the popup; reopen it to see the new layout. Style and layout changes keep healthy scripts and their graph history running.

To use this popup, add it to a CPU script widget in your personal configuration.

For new native widget types, add a case to `WidgetContent`, decode its settings in `WidgetConfiguration`, and render it in `WidgetView.content`. New popup components belong in `PopupContent` and `PopupBlockView`. Runtime SwiftUI plugins, arbitrary chart types and a graphical widget editor are not implemented.

The three layout groups can overlap if their combined content exceeds the available display width. Overflow priorities and automatic hiding are not implemented.

## Architecture

- [Configuration.swift](Sources/StableBar/Configuration.swift): config, widget definitions and style inheritance.
- [BarStore.swift](Sources/StableBar/BarStore.swift): live reload and widget lifetimes.
- [AeroSpace.swift](Sources/StableBar/AeroSpace.swift): event subscription and workspace actions.
- [ScriptWidget.swift](Sources/StableBar/ScriptWidget.swift): custom widget output and refresh tasks.
- [BarView.swift](Sources/StableBar/BarView.swift): native rendering and selection animation.
- [PopupConfiguration.swift](Sources/StableBar/PopupConfiguration.swift): popup layout blocks.
- [PopupView.swift](Sources/StableBar/PopupView.swift): shared popup rendering and script bindings.
- [WidgetPopup.swift](Sources/StableBar/WidgetPopup.swift): anchored panel, dismissal and screen placement.
- [StableBarApp.swift](Sources/StableBar/StableBarApp.swift): non-activating panels and application lifecycle.

There is no web view, custom drawing loop or private window-server API. Styling and data updates are separate from window placement. Performance and long-term stability still need measurement with your actual widgets and displays.
