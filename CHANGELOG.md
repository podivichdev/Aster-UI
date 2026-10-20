# Changelog

## Unreleased

- `Library`: `Tab:InterfaceManager({ Name, Side, Flag, ... })` — the third ready-made manager, for the menu's own settings: menu keybind, backdrop, custom cursor, watermark, Keybind Menu, Toggle Style and a confirmed Unload button. It creates a draggable FPS/ping watermark on demand (hidden by default) or drives one passed as `Watermark`; the whole panel is saved through a hidden `__Interface` flag so configs restore it without counting each row as a running feature. `manager.Watermark` and `manager:Refresh()` are available.
- `Library`: `Tab:ThemeManager`'s Toggle Style and Keybind Menu controls moved to `Tab:InterfaceManager`. Old theme configs that still carry those fields keep applying them.
- `Library`: `Aster:AddDraggableLabel` accepts `Window = Window` in the table form, attaching the label to that window instead of the newest one.
- `Library`: Keybind Menu - Obsidian's `KeybindFrame` rebuilt with Aster's draggable-overlay chrome. One floating list per window (`Window.KeybindFrame` / `Window.KeybindMenu`; `Aster.KeybindFrame` / `Aster.KeybindMenu` point at the newest), hidden by default, at Obsidian's default spot (left edge, vertically centred). Lists every `Tab:Keybind` across tabs, sub tabs and groupboxes as `[Key] Name` / `[None] Name`, drags by the header and folds with the chevron. Rows are persistent, one per bind, created with the widget and updated in place: captures, `Set` calls and destroyed elements never rebuild the list, and opening/closing only changes `Frame.Visible`. Open with `Window:SetKeybindMenu(bool)`, `Window:ToggleKeybindMenu()`, `CreateWindow({ KeybindMenu = true })`, or the Interface Manager's Keybind Menu toggle.
- `Window`: `UnlockMouseWhileOpen` option (default `true`) and `Window:SetUnlockMouseWhileOpen(bool)` — while the window is open the cursor stays usable even when the game locks it to the centre (first person), powered by `GuiButton.Modal` (no per-frame fight with `MouseBehavior`).
- `Window`: `ShowCustomCursor` option (default `true`) and `Window:SetShowCustomCursor(bool)` — the window draws its own cross cursor and keeps `MouseIconEnabled` in check, so the freed mouse stays visible in games that hide it to aim; the original icon state is restored on close. Same solution Obsidian uses.
- `Library`: `Aster:AddDraggableLabel(text, icon, iconPosition)` — Obsidian's draggable watermark rebuilt for Aster: themed colours and fonts, follows the theme and the UI scale (drawn 10% larger than the window), drags with mouse or touch, stacks below labels already on screen, or starts at a given `Position`. Methods: `SetText`, `SetIcon`, `SetIconPosition`, `SetVisible`, `Destroy`.
- `Library`: fixed `AddDraggableLabel`'s `Position` collapsing to the top-left corner when the label is created before the screen gui is measured (bound was clamped against a zero size); it now keeps the requested spot and re-clamps once the screen has a size.
- `Library`: fixed `AddDraggableLabel` stopping short of the right and bottom screen edges — the drag delta and the clamp divided by the label's UI scale, which enlarges the pill but never moves its offset; the label now tracks the pointer 1:1 and reaches every screen edge.
- `Example.lua`: Config tab uses `Tab:InterfaceManager()` — menu keybind, backdrop, custom cursor, the draggable FPS/ping watermark (off by default), Keybind Menu, Toggle Style and Unload — beside `ConfigManager` and `ThemeManager`.
- `Example.lua`: Main tab rebuilt as a paged showcase, like a real script's Combat tab — buttons on top switch pages (`Tab:CreateSubTab`) and each page spreads its groupboxes over the left and right columns.
- Docs: quick-start uses a valid icon name (`"house"` — the icon set has no `"home"`).

## 1.0.0 — 2026-10-17

Initial public release.

- Single-file `Library.lua`, loadable straight from GitHub (`loadstring` + `game:HttpGet`).
- Fully self-contained chunk: no globals created, no dependencies on the host script.
- Window: teardown/intro animations, search bar, home dashboard, minimize-to-island,
  floating toggle button, adaptive sizing, drag styles, weather backdrop.
- Widgets: sections, dividers, labels, paragraphs, buttons, button rows, toggles,
  sliders, steppers, dropdowns (single and multi), inputs, keybinds, color pickers,
  progress bars, order lists, groupboxes, images, viewports, tables, status lists.
- Sub-tabs per tab, plus `ConfigManager` and `ThemeManager` built-in UIs.
- Themes: presets (Cybrion and more), save/load, saved defaults.
- Configs: save/load/rename/delete, import/export codes, autoload, per-window folders.
- Notifications, dialogs, confirm prompts.
- Server helpers: rejoin, server hop, join lowest server, copy to clipboard.
- Embedded logo, Lucide icon support, optional custom fonts.
