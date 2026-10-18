# Changelog

## Unreleased

- `Example.lua`: full Config tab mirroring a real script's settings: interface options, config manager, theme manager and the direct config API.

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
