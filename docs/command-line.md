# Command-line controls

The executable is `StableBar.app/Contents/MacOS/StableBar`. Prefix commands with `--config PATH` to address a specific running configuration; otherwise live commands target the default configuration. Replies are JSON, and errors exit with status 1. Each configuration has one local control endpoint per user.

```sh
StableBar --query
StableBar --query clock
StableBar --set clock '{"format":"HH:mm:ss","style":{"fontSize":15}}'
StableBar --add '{"id":"note","type":"text","position":"left","text":"Hello"}'
StableBar --reorder note clock
StableBar --remove note
StableBar --profile dark
StableBar --profile auto
StableBar --reset
StableBar --customize
```

Command-line changes are live for the current session. Settings shows a notice with **Save** and **Discard** for these temporary changes. Changes made in Settings save separately and leave temporary command-line changes applied on top. Add `--persist` to save the session changes into the root file. `--reset` discards unsaved session changes and reloads the files. Session edits reapply over external file changes. Imports and package source files are preserved.

Use one batch for changes that must appear together:

```sh
StableBar --batch '[
  {"action":"set","id":"clock","properties":{"position":"left"}},
  {"action":"bar","properties":{"height":44}},
  {"action":"defaults","properties":{"fontSize":13}}
]' --persist
```

A batch validates the whole resulting configuration before replacing the running bar or writing the file. A failed batch leaves both intact. Supported edit actions are `set` (`id`, `properties`), `add` (`properties`, including `id`), `remove` (`id`), `reorder` (`ids`), `screens`/`bar`/`defaults`/`popupDefaults`/`roles`/`workspaceDefaults`/`modeAliases`/`tokens` (`properties`, merged into those keys), `workspaceSource` (`name`: `aerospace`, `yabai` or `spaces`, omitted for the default AeroSpace source), `unset` (`properties` naming the keys to remove from the main file, with `id` for a widget, for example `{"action":"unset","id":"clock","properties":{"style":{"foreground":null}}}`), `profile` (`name`, omitted for automatic), `profiles` (`profiles`, definitions merged by name; set `enabled` to `false` to disable one), `package` (`properties`: `id`, `version`, optional `enabled` and `settings`), `packageSource` (`properties`: a whole [source](packages.md#private-sources) with `id`, `name` and `url`, which replaces the source with that `id` or is added; `id` without `properties` removes it, for example `{"action":"packageSource","id":"acme"}`), and `theme` (the same `properties`, with only `id` for a theme that ships with StableBar, omitted for Built-in).

Without `id`, `unset` can also address widget definitions by their ID and profiles by their name in the main file. For example, `{"action":"unset","properties":{"widgets":{"clock":{"style":{"foreground":null}}},"profiles":{"night":{"configuration":{"bar":{"height":null}}}}}}` removes the clock’s text color and the night profile’s bar height in one edit. Empty objects are removed, except an emptied profile `configuration` stays as `{}`.

- `--validate [PATH]`: compose and validate files without starting scripts.
- `--refresh ID`: refresh a running widget. Hidden, suspended providers must first be made visible or explicitly resumed with **Settings → Status → Resume for testing**.
- `--popup ID`: open the popup or menu of a widget, or close it when it's open. It opens on the active display, as `"display": "active"` defines it; a widget in the **More widgets** menu opens its popup under that menu. Key bindings can call it, for example in `aerospace.toml`: `alt-c = 'exec-and-forget /Applications/StableBar.app/Contents/MacOS/StableBar --popup agenda'`.
- `--trigger EVENT [KEY=VALUE ...]`: send an event. Without `--config`, this broadcasts to all subscribed bars for compatibility; with `--config`, it targets that configuration.
- `--reload`: reload configuration; without `--config`, notify all running bars.
- `--packages`, `--inspect-package PATH`, `--install-package PATH|ID [--source SOURCE]`, `--enable-package ID VERSION [--persist]`, `--uninstall-package ID VERSION`: review and manage packages. `--packages` lists installed packages; `source` names the source that installed each one (`stablebar`, a private source's `id`, or `local` for a folder) and is absent for packages installed before StableBar recorded sources. `--install-package` installs a folder, or a package from the [store](packages.md#store) or a [private source](packages.md#private-sources) in the configuration file when its argument is not a folder. When more than one source lists the ID, it names them; add `--source` with a source's `id`. It refuses a package that another source installed. Installation does not enable commands. Uninstall requires the bar to be running and always saves configuration edits before removing that version. Package selections belong in the root file or its includes; use profile widget overrides to hide package widgets contextually.
- `--build-source PACKAGES OUT [--previous FILE] [--url URL --name NAME]`: build a [private package source](packages.md#publishing-a-source) from a folder of packages. It writes an archive for each package version that isn't published yet, and `index.json`, into `OUT`, then prints what to upload. `--previous` is the index you published last time; its versions that are still in `PACKAGES` keep their entries and no archive is written for them, and a package whose folder is gone leaves the index. With `--url` (the index's `https` address) and `--name`, it also prints a join link. It checks each package like `--inspect-package`, needs StableBar 0.6.0 or later, and doesn't use a configuration file or a running bar.
