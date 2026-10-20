# Aster UI

**A single-file Roblox UI library for executors.**

One file, nothing else to download. No loader to maintain, no globals, no host-script coupling — the whole library ships inside `Library.lua` and returns itself as a table.

It includes: an animated window with sidebar tabs, 20+ widgets, sub-tabs, a search bar, themes, a full config manager (with import/export), a home dashboard, notifications, dialogs, drag styles, minimize-to-island, a weather backdrop and a mobile layout.

## Loading

```lua
local Aster = loadstring(game:HttpGet("https://raw.githubusercontent.com/podivichdev/Aster-UI/main/Library.lua"))()
```

A jsDelivr mirror (usually faster, cached):

```lua
local Aster = loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/podivichdev/Aster-UI@main/Library.lua"))()
```

## Quick start

```lua
local Aster = loadstring(game:HttpGet("https://raw.githubusercontent.com/podivichdev/Aster-UI/main/Library.lua"))()

local Window = Aster:CreateWindow({
    Title = "My Script",
    LoadingTitle = "My Script",
    LoadingSubtitle = "Loading",
    ToggleUIKeybind = "RightControl",
    ConfigurationSaving = { FolderName = "MyScriptConfigs" },
})

local Main = Window:Tab({ Name = "Main", Icon = "house" })

Main:Section("General")

Main:Toggle({
    Name = "Enable feature",
    Flag = "MyToggle",
    Default = false,
    Callback = function(on) print("feature:", on) end,
})

-- Flags give you access to any widget later:
print(Aster.Flags.MyToggle.Value)  -- false
Aster.Flags.MyToggle:Set(true)     -- also runs the Callback
```

A demo of the common widgets is in [`Example.lua`](./Example.lua): a paged Main tab (page buttons on top, groupboxes over both columns) and a Config tab with a real script's settings (interface options, config manager and theme manager).

## Window options

`Aster:CreateWindow(opts)` — every field is optional.

| Option | Type | Description |
|---|---|---|
| `Title` (alias `Name`) | string | Window title. |
| `Subtitle` | string | Small subtitle under the title. |
| `LoadingTitle` / `LoadingSubtitle` | string | Text on the loading splash. |
| `Keybind` (alias `ToggleUIKeybind`) | `Enum.KeyCode` / mouse `Enum.UserInputType` / string | Show/hide key. Strings like `"E"`, `"RightControl"`, `"MouseButton2"` or `"MB2"`. Default `RightControl`. |
| `UnlockMouseWhileOpen` | bool | Keeps the cursor usable while the window is open, even when the game locks it to the centre (first person). Default `true`. |
| `ShowCustomCursor` | bool | While the window is open, draws the library's own cross cursor and hides the system one; with it off the system cursor is forced visible instead. Keeps the pointer visible in games that hide it to aim. Default `true`. |
| `AutoTranslate` | bool | Whether Roblox may auto-translate the UI. `false` sets `AutoLocalize = false` on every text element, so text reads exactly as written. Default `true` (can also be preset as `Aster.AutoTranslate = false`). |
| `AlwaysOnTop` | bool | Renders the UI above Roblox's core blur (the overlay behind the Roblox menu) through the hidden `OnTopOfCoreBlur` ScreenGui property. Executor-only; silently ignored where unsupported. Default `false`. |
| `ForceCheckbox` | bool | Renders every `Toggle` as a checkbox instead of a switch, like Obsidian's `Library.ForceCheckbox`. Module-wide; switching it converts live toggles in place (Interface Manager's **Toggle Style** dropdown, `Aster:SetForceCheckbox(bool)`, or a loaded config). Default `false` (can also be preset as `Aster.ForceCheckbox = true`). |
| `KeybindMenu` | bool | Starts the floating Keybind Menu open. Like Obsidian's keybind frame it is hidden by default; open it with `Window:SetKeybindMenu(bool)`, `Window:ToggleKeybindMenu()`, the Interface Manager's **Keybind Menu** toggle, or `Aster.KeybindFrame.Visible = true`. |
| `Size` | `UDim2` | Default `760x520`. |
| `Theme` / `DefaultTheme` | string | Theme name from `Aster.ThemePresets`. Default `"Cybrion"`. |
| `Weather` | string | Backdrop weather: `Snow`, `Rain`, `Hell Fire`, `Sakura`, `Fireflies`, `Matrix`, `None`. Default `Matrix`. |
| `ConfigurationSaving` | table | `{ FolderName, FileName }` — config folder (needs the executor file API). |
| `ToggleButton` | table | Floating toggle button: `{ Platform = "Mobile" / "Both", Icon }`. |
| `OpenButton` | table / bool | On-screen open button (mobile gets one by default). |
| `Backdrop` | table / bool | Weather + dim backdrop; `false` disables it. |
| `Home` | table / bool | Home dashboard, see below; `false` disables the Home tab. |
| `Icon` | string / `rbxassetid` | Replaces the embedded logo. `"None"` removes the logo — the window `Title` / `Subtitle` shift left into its place. |
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

Icons are [Lucide](https://lucide.dev) names (`"house"`, `"settings"`, `"shield"`, `"sparkles"`, …), fetched once at runtime; the set tracks current Lucide names (e.g. `"house"`, not the older `"home"`). Passing `Icon = "None"` (any case) means no icon: the icon slot collapses, the title/subtitle move into its place, and **no default icon is substituted** — everywhere an icon is accepted (`CreateWindow`, tabs, sub tabs, groupboxes, buttons, inputs, dialogs, notifications, flags, …).

## Widgets

All widgets live on a tab (or sub-tab) and return a handle. Pass `Flag = "SomeName"` to also register it in `Aster.Flags`. Every method also has a Fluent-style `Create*` alias (`Tab:CreateToggle` == `Tab:Toggle`, `Tab:CreateConfigManager` == `Tab:ConfigManager`, `Tab:CreateInterfaceManager` == `Tab:InterfaceManager`), and the same calls work inside groupboxes.

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
| `Tab:Keybind({ Name, Desc, Default, Flag, Callback, OnChanged })` | Key picker. Accepts keyboard keys and mouse buttons: `Default = "E"`, a `KeyCode`, `Enum.UserInputType.MouseButton2` or `"MB2"` (`MB1`/`MB2`/`MB3`). `Callback` fires on press (key stays quiet while the window is open). While rebinding, `Esc` cancels. `OnChanged` on rebind. |
| `Tab:ColorPicker({ Name, Desc, Default = Color3, Flag, Callback })` | SV panel + hue slider + hex chip. |
| `Tab:Progress({ Name, Desc, Default, Color, TextColor, Flag })` | Progress bar. |
| `Tab:OrderList({ Name, Desc, Items, MaxRows, Numbered, Arrows, Flag, Callback })` | Drag (or arrow) to reorder. |
| `Tab:Groupbox(opts, icon)` | Groups rows inside a panel, two columns on wide layouts. |
| `Tab:Image(opts)` | Image card. |
| `Tab:Viewport(opts)` | 3D viewport card. |
| `Tab:Table(opts)` | Data table card. |
| `Tab:Status(opts)` / `Tab:StatusList(opts)` / `Tab:Statuses(entries, shared)` | Live status rows with health colors. |
| `Tab:ConfigManager({ Name, Side })` | Ready-made config manager UI (create / save / load / delete / rename / autoload / import / export). |
| `Tab:ThemeManager({ Name, Side })` | Ready-made theme, background, weather and look-settings picker UI. |
| `Tab:InterfaceManager({ Name, Side })` | Ready-made menu-settings panel: keybind, backdrop, custom cursor, FPS/ping watermark, Toggle Style, Keybind Menu and Unload. |

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
local toggle = Aster.Flags.MyToggle
print(toggle.Value)      -- current value
toggle:Set(true, true)   -- true = silent (no Callback)
```

## Window methods

```lua
-- visibility
Window:Toggle(open)  Window:Minimize()  Window:Restore()  Window:SetMinimized(bool)
Window:SetKeybind(Enum.KeyCode.X)  -- or "MB2" / Enum.UserInputType.MouseButton2
Window:SetKeepOnScreen(bool)  Window:SetTransparent(bool)  Window:SetAlwaysOnTop(bool)
Window:SetUnlockMouseWhileOpen(bool)  Window:SetShowCustomCursor(bool)  Window:SetAutoTranslate(bool)
Window:SetKeybindMenu(bool)  Window:ToggleKeybindMenu()
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
Window:RenameConfig(name, newName)  Window:ResetConfig()  Window:ClearWorkspace()
Window:ExportConfig(name)  Window:ImportConfig(code, saveAs, force)  Window:DecodeConfig(code)  Window:ConfigExists(name)
Window:SetAutoload(name)  Window:GetAutoload()  Window:LoadAutoload()  Window:GetAutoloadMode()  Window:SetAutoloadMode(mode)
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
Aster:CreateWindow(opts)          Aster.Flags
Aster:Notify(opts)                Aster.ThemePresets
Aster:AddDraggableLabel(...)      Aster.Windows
Aster.KeybindFrame                Aster.KeybindMenu
Aster:SetTheme(name)              Aster.DensityModes  -- Compact / Default / Comfortable
Aster:SetDefaultTheme(name)       Aster:PreloadIcons()
Aster:SetDensity(mode)            Aster:LoadFont({ Name = "ValleySans" })
Aster:SetCornerRadius(px)         Aster:Destroy()
Aster.ForceCheckbox = false       -- true: every Toggle renders as a checkbox
Aster:SetForceCheckbox(bool)      -- flips that and converts live toggles in place
```

### Draggable labels

`Aster:AddDraggableLabel(text, icon, iconPosition)` drops a small draggable pill on screen — Obsidian's watermark, rebuilt with the window's colours and font, so it follows every theme change; it draws 10% larger than the window's UI scale and follows it live. Create a window first: the label lives in the window's screen gui (above the window body, below the pop-outs, the toggle button, the tooltip and the cursor) and is destroyed together with it. Extra labels stack below the ones already there instead of overlapping. Pass `Position` in the table form — `Vector2.new(x, y)` or `{x, y}` — to give a label an exact starting spot, and `Window = Window` to attach it to a specific window when several are open. `Tab:InterfaceManager()` creates and maintains one of these for the menu's Watermark toggle.

```lua
local Watermark = Aster:AddDraggableLabel("FPS: 240 | PING: 32 ms")
-- Aster:AddDraggableLabel({ Text = "Watermark", Icon = "activity" })  -- table form
-- Aster:AddDraggableLabel({ Text = "Watermark", Position = Vector2.new(120, 420) })  -- custom start spot
-- Aster:AddDraggableLabel({ Text = "Watermark", Window = Window })  -- owner window

Watermark:SetText("FPS: 240 | PING: 24 ms")   -- refresh it on a timer
Watermark:SetIcon("activity")                 -- lucide name, asset id or URL
Watermark:SetIconPosition("right")            -- "left" (default) or "right"
Watermark:SetVisible(false)
Watermark:Destroy()
```

### Keybind menu

Every `Keybind` widget in the script is listed on one floating menu, Obsidian-style: `[F] Flight`, `[None] Speed`, in creation order across every tab, sub tab and groupbox. Like Obsidian, each row is created once with its widget and updated in place: key captures, `Set` calls and destroyed elements never rebuild the list, and opening or closing the menu is only a `Visible` change. The menu is draggable by its title bar, folds to the title bar with the chevron, draws 10% larger than the window's UI scale, follows the theme, and starts at Obsidian's default spot — left edge, vertically centred. It is hidden by default.

```lua
Window:SetKeybindMenu(true)          -- open
Window:ToggleKeybindMenu()           -- open / close
Aster.KeybindFrame.Visible = true    -- the same frame, raw Roblox style
Aster.KeybindMenu:SetCollapsed(true) -- fold to the title bar
Aster.KeybindMenu:Refresh()          -- force a row repaint; rows update themselves
```

`CreateWindow({ KeybindMenu = true })` starts it open. `Tab:InterfaceManager()` also gets a **Keybind Menu** toggle. Each window owns one (`Window.KeybindFrame` / `Window.KeybindMenu`); `Aster.KeybindFrame` and `Aster.KeybindMenu` point at the newest window's, like Obsidian.

### Interface manager

`Tab:InterfaceManager()` builds the menu's own settings panel, the counterpart to `ConfigManager` and `ThemeManager`: the menu keybind, backdrop, custom cursor, watermark, Toggle Style, Keybind Menu and a confirmed Unload button. The watermark is created on demand as an `Aster:AddDraggableLabel` chip showing live FPS and ping (hidden by default), so the script does not have to maintain its own Heartbeat loop. The panel is saved through a hidden `__Interface` flag, so configs restore it without counting each row as a running feature.

```lua
local manager = Config:InterfaceManager({ Side = "Left" })
manager.Watermark:SetVisible(true)   -- the chip the manager created
manager:Refresh()                    -- pull the rows back in line with Window

-- Or drive a label you already made:
-- Config:InterfaceManager({
--     Watermark = myLabel,
--     WatermarkName = "Aster Hub",  -- text before " | FPS | ping ms"
--     WatermarkVisible = true,
--     MenuKeybind = false,          -- hide individual rows when needed
-- })
```

## Themes

Built-in presets (see `Aster.ThemePresets` for the full list and exact colors): `Cybrion` (default), `Midnight`, `Nebula`, `Synthwave`, `Sakura`, `Velvet`, `Rose`, `Crimson`, `Sunset`, `Amber`, `Gold` and more.

```lua
Aster:SetTheme("Midnight")
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

`Tab:ConfigManager()` builds the whole UI for it (create / save / load / delete / rename / reset / autoload, global or per account, plus share codes with copy and paste). `Window:ClearWorkspace()` deletes the script's entire folder.

## Executor notes

- GUI parent: `gethui()` if present, then `CoreGui`, then `PlayerGui`.
- File API (`writefile`, `isfile`, `getcustomasset`) is only needed for saved configs, saved themes, the embedded logo buffer and custom fonts. Everything degrades gracefully without it.
- Icons (`Lucide`) are fetched once from GitHub; without internet they are simply skipped.
- `Drawing` is not required — the library is 100% Instances.
- Works on mobile: touch layout, floating toggle button, open button.

## Repository layout

```
Library.lua     the library itself (this is the file you load)
Example.lua     demo window with the common widgets
README.md       this file
CHANGELOG.md
LICENSE         MIT
```

## Publishing

```bash
git init
git add .
git commit -m "Aster UI 1.0.0"
git remote add origin https://github.com/podivichdev/Aster-UI.git
git push -u origin main
```

Then the raw link is:

```
https://raw.githubusercontent.com/podivichdev/Aster-UI/main/Library.lua
```

## Credits

- Built originally as the embedded UI for the **Cybrion** script.
- Background image presets from **Fluent-modded**'s themes (public assets).
- Icons from **Lucide** via [Footagesus/Icons](https://github.com/Footagesus/Icons).

## License

MIT — see [LICENSE](./LICENSE).
