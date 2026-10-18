# AirFlow

**A single-file Roblox UI library for executors.**

One file, nothing else to download. No loader to maintain, no globals, no host-script coupling — the whole library ships inside `Library.lua` and returns itself as a table.

It includes: an animated window with sidebar tabs, 20+ widgets, sub-tabs, a search bar, themes, a full config manager (with import/export), a home dashboard, notifications, dialogs, drag styles, minimize-to-island, a weather backdrop and a mobile layout.

## Loading

```lua
local AirFlow = loadstring(game:HttpGet("https://raw.githubusercontent.com/YOURNAME/AirFlow/main/Library.lua"))()
```

A jsDelivr mirror (usually faster, cached):

```lua
local AirFlow = loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/YOURNAME/AirFlow@main/Library.lua"))()
```

> Replace `YOURNAME` with the GitHub account that hosts this repository.

## Quick start

```lua
local AirFlow = loadstring(game:HttpGet("https://raw.githubusercontent.com/YOURNAME/AirFlow/main/Library.lua"))()

local Window = AirFlow:CreateWindow({
    Title = "My Script",
    LoadingTitle = "My Script",
    LoadingSubtitle = "Loading",
    ToggleUIKeybind = "RightControl",
    ConfigurationSaving = { FolderName = "MyScriptConfigs" },
})

local Main = Window:Tab({ Name = "Main", Icon = "home" })

Main:Section("General")

Main:Toggle({
    Name = "Enable feature",
    Flag = "MyToggle",
    Default = false,
    Callback = function(on) print("feature:", on) end,
})

-- Flags give you access to any widget later:
print(AirFlow.Flags.MyToggle.Value)  -- false
AirFlow.Flags.MyToggle:Set(true)     -- also runs the Callback
```

A full demo of every widget is in [`Example.lua`](./Example.lua).

## Window options

`AirFlow:CreateWindow(opts)` — every field is optional.

| Option | Type | Description |
|---|---|---|
| `Title` (alias `Name`) | string | Window title. |
| `Subtitle` | string | Small subtitle under the title. |
| `LoadingTitle` / `LoadingSubtitle` | string | Text on the loading splash. |
| `Keybind` (alias `ToggleUIKeybind`) | `Enum.KeyCode` / string | Show/hide key. Default `RightControl`. |
| `Size` | `UDim2` | Default `760x520`. |
| `Theme` / `DefaultTheme` | string | Theme name from `AirFlow.ThemePresets`. Default `"Cybrion"`. |
| `Weather` | string | Backdrop weather: `Snow`, `Rain`, `Hell Fire`, `Sakura`, `Fireflies`, `Matrix`, `None`. Default `Matrix`. |
| `ConfigurationSaving` | table | `{ FolderName, FileName }` — config folder (needs the executor file API). |
| `ToggleButton` | table | Floating toggle button: `{ Platform = "Mobile" / "Both", Icon }`. |
| `OpenButton` | table / bool | On-screen open button (mobile gets one by default). |
| `Backdrop` | table / bool | Weather + dim backdrop; `false` disables it. |
| `Home` | table / bool | Home dashboard, see below; `false` disables the Home tab. |
| `Icon` | string / `rbxassetid` | Replaces the embedded logo. |
| `UIScale` | number | `0.6` – `1.5`, default `1`. |
| `AdaptiveSize` | bool | Shrinks the window to fit small screens. Default `true`. |
| `Density` | string | `"Compact"`, `"Default"` or `"Comfortable"`. |
| `CornerRadius` | number | UI corner radius in pixels. |
| `IslandDraggable` | bool | `false` locks the minimized island position. |
| `Parent` | Instance | Where the ScreenGui goes. Default: `gethui` → `CoreGui` → `PlayerGui`. |

### Home dashboard

```lua
Home = {
    Discord = "discord.gg/example",                 -- invite shown on the home tab
    Stats = { "Players", "Session", "FPS", "Ping" }, -- live stat chips
    Pages = { { Name = "Changelog", Icon = "list" }, ... }, -- extra home sub-tabs
    HideName = false,
    HideAvatar = false,
}
```

## Tabs

```lua
local Tab = Window:Tab({ Name = "Main", Icon = "crosshair", Desc = "optional", PageTitle = "Main" })
local Sub = Tab:SubTab({ Name = "Extra", Icon = "layers" })
Tab:SelectSubTab(Sub)
```

Icons are [Lucide](https://lucide.dev) names (`"home"`, `"settings"`, `"shield"`, `"sparkles"`, …), fetched once at runtime.

## Widgets

All widgets live on a tab (or sub-tab) and return a handle. Pass `Flag = "SomeName"` to also register it in `AirFlow.Flags`.

| Widget | Options |
|---|---|
| `Tab:Section(text)` | Section header (string or `{ Name, Visible }`). |
| `Tab:Divider(opts)` | Thin divider, optional `Text`. |
| `Tab:Label({ Text, Color, Update, UpdateRate })` | Rich-text label; `Update` is polled every `UpdateRate` seconds. |
| `Tab:Paragraph({ Name, Content })` | Title + wrapped body text. |
| `Tab:Button({ Name, Desc, Icon, Style = "Primary", Callback })` | Button; `:SetText(text)`. |
| `Tab:ButtonRow({ ... })` | Several buttons in one row. |
| `Tab:Toggle({ Name, Desc, Default, Flag, Callback })` | Switch; `:Set(v, silent)` / `:Get()`. |
| `Tab:Slider({ Name, Desc, Min, Max, Step, Suffix, Default, Flag, Callback, OnRelease })` | Drag slider with a typeable value chip. |
| `Tab:Stepper({ Name, Desc, Min, Max, Step, Suffix, Default, Flag, Callback })` | `−` / `+` number stepper. |
| `Tab:Dropdown({ Name, Desc, Options, Default, Multi, MaxRows, Stacked, Flag, Callback })` | Dropdown. `Multi = true` takes a table `Default` and returns a table to `Callback`. |
| `Tab:Input({ Name, Desc, Default, Placeholder, Numeric, Icon, Flag, Callback })` | Text box; `Numeric = true` parses numbers (`Callback(value, enterPressed)`). |
| `Tab:Keybind({ Name, Desc, Default, Flag, Callback, OnChanged })` | Key picker; `Default = "E"` or a `KeyCode`. `Callback` fires on press, `OnChanged` on rebind. |
| `Tab:ColorPicker({ Name, Desc, Default = Color3, Flag, Callback })` | SV panel + hue slider + hex chip. |
| `Tab:Progress({ Name, Desc, Default, Color, TextColor, Flag })` | Progress bar. |
| `Tab:OrderList({ Name, Desc, Items, MaxRows, Numbered, Arrows, Flag, Callback })` | Drag (or arrow) to reorder. |
| `Tab:Groupbox(opts, icon)` | Groups rows inside a panel, two columns on wide layouts. |
| `Tab:Image(opts)` | Image card. |
| `Tab:Viewport(opts)` | 3D viewport card. |
| `Tab:Table(opts)` | Data table card. |
| `Tab:Status(opts)` / `Tab:StatusList(opts)` / `Tab:Statuses(entries, shared)` | Live status rows with health colors. |
| `Tab:ConfigManager(opts)` | Ready-made config manager UI (save / load / import / export). |
| `Tab:ThemeManager(opts)` | Ready-made theme + weather picker UI. |

`Title`, `Description`, `CurrentValue` / `Value`, `CurrentOption`, `MultipleOptions`, `Values` and `Increment` are accepted as friendly aliases everywhere (`Title` → `Name`, `Desc` → `Name`'s desc field, `Value` → `Default`, `Step` → `Increment`, …).

### Element helpers

Every widget handle supports:

```lua
element:SetVisible(false)
element:SetTooltip("Hover text")      -- string, or { Title, Text, Icon }
element:Set(v, silent)                -- toggles/sliders/dropdowns/inputs/keybinds
element:Get()
element:Destroy()
```

## Flags

```lua
local toggle = AirFlow.Flags.MyToggle
print(toggle.Value)      -- current value
toggle:Set(true, true)   -- true = silent (no Callback)
```

## Window methods

```lua
-- visibility
Window:Toggle(open)  Window:Minimize()  Window:Restore()  Window:SetMinimized(bool)
Window:SetKeybind(Enum.KeyCode.X)  Window:SetKeepOnScreen(bool)  Window:SetTransparent(bool)
Window:SelectTab(tab)  Window:SetHideName(bool)  Window:SetHideAvatar(bool)

-- look
Window:SetTheme(name)  Window:SetDensity(mode)  Window:SetUIScale(n)
Window:SetSize(UDim2)  Window:GetSize()  Window:SetAdaptiveSize(bool)
Window:SetDragStyle(style)  Window:SetIslandStyle(style)  Window:SetDragSkeleton(bool)
Window:SetIslandDraggable(bool)  Window:ResetIslandPosition()
Window:SetBackground(source)  Window:SetBackgroundTransparency(n)  Window:ListBackgrounds()
Window:SetWeather("Rain")  Window:SetWeatherMode(mode)
Window:SetWeatherDensity(n)  Window:SetWeatherSpeed(n)
Window:SetBackdrop(bool)  Window:SetBackdropTint(n)  Window:SetDim(bool)
Window:SetCornerRadius(px)  Window:SaveTheme(name)  Window:LoadTheme(name)  Window:ListThemes()

-- configs
Window:SaveConfig(name)  Window:LoadConfig(name)  Window:ListConfigs()  Window:DeleteConfig(name)
Window:RenameConfig(name, newName)  Window:ResetConfig()  Window:ExportConfig(name)
Window:ImportConfig(code)  Window:DecodeConfig(code)  Window:ConfigExists(name)
Window:SetAutoload(name)  Window:GetAutoload()  Window:LoadAutoload()
Window:OnConfigChanged(fn)

-- misc
Window:Notify({ Title, Content, Icon, Duration, Type })   -- Type: "Success" / "Warning" / "Error"
Window:Dialog(opts)  Window:Confirm(opts)
Window:Rejoin()  Window:ServerHop()  Window:JoinLowestServer()
Window:CopyToClipboard(text, what)
Window:ShowFeatures()
Window:Destroy()
```

## Library (module) methods

```lua
AirFlow:CreateWindow(opts)          AirFlow.Flags
AirFlow:Notify(opts)                AirFlow.ThemePresets
AirFlow:SetTheme(name)              AirFlow.Windows
AirFlow:SetDefaultTheme(name)       AirFlow.DensityModes  -- Compact / Default / Comfortable
AirFlow:SetDensity(mode)            AirFlow:PreloadIcons()
AirFlow:SetCornerRadius(px)         AirFlow:LoadFont({ Name = "ValleySans" })
AirFlow:Destroy()
```

## Themes

Built-in presets (see `AirFlow.ThemePresets` for the full list and exact colors): `Cybrion` (default), `Midnight`, `Nebula`, `Synthwave`, `Sakura`, `Velvet`, `Rose`, `Crimson`, `Sunset`, `Amber`, `Gold` and more.

```lua
AirFlow:SetTheme("Midnight")
Window:SaveTheme("MyTheme")   -- saved into the config folder
```

Themes can also be managed in-game with `Tab:ThemeManager()`.

## Configs

With `ConfigurationSaving = { FolderName = "..." }` set, the window can persist every flagged widget:

```lua
Window:SaveConfig("Default")
Window:LoadConfig("Default")
local code = Window:ExportConfig("Default")   -- shareable string
Window:ImportConfig(code)
```

This needs the executor's file API (`writefile` / `readfile` / `isfile`). Without it, configs and custom fonts simply won't persist — nothing else changes.

## Executor notes

- GUI parent: `gethui()` if present, then `CoreGui`, then `PlayerGui`.
- File API (`writefile`, `isfile`, `getcustomasset`) is only needed for saved configs, saved themes, the embedded logo buffer and custom fonts. Everything degrades gracefully without it.
- Icons (`Lucide`) are fetched once from GitHub; without internet they are simply skipped.
- `Drawing` is not required — the library is 100% Instances.
- Works on mobile: touch layout, floating toggle button, open button.

## Repository layout

```
Library.lua     the library itself (this is the file you load)
Example.lua     demo window using every widget
README.md       this file
CHANGELOG.md
LICENSE         MIT
```

## Publishing

```bash
git init
git add .
git commit -m "AirFlow 1.0.0"
git remote add origin https://github.com/YOURNAME/AirFlow.git
git push -u origin main
```

Then the raw link is:

```
https://raw.githubusercontent.com/YOURNAME/AirFlow/main/Library.lua
```

## Credits

- Built originally as the embedded UI for the **Cybrion** script.
- Background image presets from **Fluent-modded**'s themes (public assets).
- Icons from **Lucide** via [Footagesus/Icons](https://github.com/Footagesus/Icons).

## License

MIT — see [LICENSE](./LICENSE).
