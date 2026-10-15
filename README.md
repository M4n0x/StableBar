# StableBar

A native, configurable macOS bar built with Swift, AppKit and SwiftUI. One persistent panel per display holds the widgets; workspace changes update their contents without recreating windows.

The default configuration includes a System Settings shortcut, the active app and a clock. It needs no accounts, network services or third-party tools. Optional shell widgets use a plain-text or JSON output protocol.

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

The first launch copies [Resources/config.json](Resources/config.json) to `~/.config/stablebar/config.json`. Subsequent launches keep your file. Right-click the bar or use its macOS menu-bar icon to open the configuration, reload it, reconnect AeroSpace or quit.

Keep personal settings in `~/.config/stablebar/config.json` and personal scripts in `~/.config/stablebar/widgets/`, outside the repository. Point commands directly at those scripts. `Resources/config.json` is the shared starter configuration; rebuilding the app does not overwrite your personal file. Local scripts should load any supporting files from their own directory. `$STABLEBAR_SCRIPTS` always refers to the bundled scripts.

StableBar sits at the top edge of each display. `bar.offset` moves it down from that edge. It hides on native fullscreen Spaces. AeroSpace gaps and macOS menu-bar settings are managed separately; this app does not change them. Keep the center clear on a notched display. The default configuration uses only the left and right groups.

## Layout and style

Save the configuration to apply changes. Direct saves and atomic file replacements are watched. Invalid edits retain the last working configuration and show an error indicator. Script instances survive style-only changes.

- `bar`: `height`, `offset`, `inset`, `spacing`, `background`, `animationDuration` (seconds).
- `defaults`: styles inherited by every widget.
- `widgets`: ordered widget definitions with unique `id`, `type`, `position` and optional `style`, `icon`, `onClick`, `menu`, `popup`.
- `position`: `left`, `center` or `right`. The center group stays at the display's center.
- Colors: `#RRGGBB` or `#RRGGBBAA` (alpha last).
- Icons: SF Symbols names.
- Measurements: points.

Each widget can override any of these styles:

`foreground`, `background`, `hoverBackground`, `borderColor`, `borderWidth`, `cornerRadius`, `fontName`, `fontSize`, `fontWeight`, `iconSize`, `paddingHorizontal`, `paddingVertical`, `spacing`, `width`, `accent`, `accentText`, `shadowRadius`, `shadowColor`.

`fontName` is `system` or an installed font name. `fontWeight` is `regular`, `medium`, `semibold` or `bold`. Set `width` on frequently changing widgets to keep their footprint stable. The workspace highlight uses `accent` and `accentText`; its motion respects Reduce Motion. Set `animationDuration` to `0` to remove transition time.

## Built-in widgets

| Type | Content | Additional fields |
| --- | --- | --- |
| `aerospace` | Occupied or visible workspaces on this display, with app icons; click to switch | — |
| `activeApp` | Frontmost app name and icon | — |
| `clock` | Local date/time, updated each minute | `format`: DateFormatter format |
| `text` | Static text and optional icon | `text` |
| `script` | Output of a shell command | `command`, `interval` in seconds, greater than zero |

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
- `menu`: an array of `{ "title": "Issue", "detail": "In progress", "onClick": "open …" }`, displayed in a themed popup. Rows without `onClick` show information. A menu takes precedence over the widget's click command. Static widgets can also define `menu` in their configuration.
- `value`: a graph sample, displayed on a 0–1 scale with the last 60 samples.
- `fields`: named display strings for popup field blocks.
- `lists`: named arrays of objects containing display strings for popup list blocks.

A nonzero exit or invalid JSON preserves the previous output and adds a warning with the error in its tooltip. Scripts retry at their configured interval. A completed click action refreshes its script immediately. Commands must finish; do not start background daemons from widget scripts. `onClick` runs only when clicked.

## Custom popups

Add `popup` to any widget. It takes precedence over `menu` and `onClick`. Its layout is independent of the script, so you can change the layout without changing the data source or rebuilding the app. The example below uses fields from [cpu.sh](Resources/widgets/cpu.sh).

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
| `graph` | `height` | The widget's existing 60 samples on the 0–1 scale |
| `list` | `source`, `row` | Repeat the `row` block for each object in `lists[source]` |
| `button` | `title`, `onClick` | Run a command and close the popup |
| `menu` | — | The widget's script or configured menu entries, with their existing actions |
| `divider` | — | A horizontal rule |

Every block accepts `style` and `alignment` (`leading`, `center`, `trailing`). Fonts, text color, accent and spacing inherit from the containing block. Width, padding, background, hover background and border apply only when set on that block. Set a width on numeric fields and their headings to align columns. Blocks without a width use the available space.

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
