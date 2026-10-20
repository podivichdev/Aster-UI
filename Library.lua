--[[
    Aster UI
    ========

    A single-file Roblox UI library for executors. No downloads besides this
    file, no globals, no host-script dependencies.

    Usage:

        local Aster = loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/podivichdev/Aster-UI/main/Library.lua"))()
        local Window = Aster:CreateWindow({ Title = "My Script" })
        local Tab = Window:Tab({ Name = "Main", Icon = "home" })
        Tab:Toggle({ Name = "Example", Flag = "MyToggle", Default = false,
            Callback = function(value) print(value) end })

    The chunk returns the library table. Widgets, themes, configs and the
    full option reference: see README.md and Example.lua in this repository.

    Credits: theme background images from Fluent-modded (public assets),
    Lucide icon set (github.com/Footagesus/Icons), BuilderSans via Roblox.
]]
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local MarketplaceService = game:GetService("MarketplaceService")
local StatsService = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

local Library = {}

Library.Flags = {}
Library.Windows = {}

-- Roblox auto-translates GUI text when the game has localization enabled.
-- CreateWindow's AutoTranslate option (or Window:SetAutoTranslate) turns that
-- off: every text element created while it is false gets AutoLocalize = false.
Library.AutoTranslate = true

-- ForceCheckbox swaps every Toggle's switch for a checkbox, like Obsidian's
-- Library.ForceCheckbox. Set it through CreateWindow's ForceCheckbox option,
-- the Interface Manager's Toggle Style dropdown, or SetForceCheckbox below.
Library.ForceCheckbox = false

-- Every toggle registers a skin rebuild here, so a Toggle Style switch
-- converts the live toggles in place instead of only the ones created next.
Library._toggleSkins = {}

-- One floating Keybind Menu per window. Library.KeybindFrame and
-- Library.KeybindMenu point at the newest one, like Obsidian.
Library._keybindMenus = {}

function Library:SetForceCheckbox(enabled)
    enabled = enabled == true
    Library.ForceCheckbox = enabled
    for button, rebuild in pairs(Library._toggleSkins) do
        if button:IsDescendantOf(game) then
            rebuild()
        else
            Library._toggleSkins[button] = nil
        end
    end
end

-- AlwaysOnTop lifts the UI above Roblox's core blur (the overlay behind the
-- Roblox menu) through a hidden ScreenGui property. It is executor-only; where
-- the executor does not expose it the pcall simply does nothing. Same approach
-- as Obsidian's SetAlwaysOnTop.
function Library._SetAlwaysOnTop(gui, enabled)
    if not gui then
        return
    end
    pcall(function()
        if sethiddenproperty then
            sethiddenproperty(gui, "OnTopOfCoreBlur", enabled)
        elseif setscriptable then
            setscriptable(gui, "OnTopOfCoreBlur", true)
            gui.OnTopOfCoreBlur = enabled
            setscriptable(gui, "OnTopOfCoreBlur", false)
        end
    end)
end

-- "None" as an icon name means an explicit no-icon: elements that reserve a
-- slot for an icon drop it and their text sits where the icon would be. The
-- sentinel is `false` (not nil) so `icon or fallback` chains keep their
-- fallback for "not set" but never bring a default icon back for "None".
local function cleanIcon(icon)
    if type(icon) == "string" and icon:lower():gsub("^lucide:", "") == "none" then
        return false
    end
    return icon
end

local function normalize(source, map)
    local opts = {}
    if type(source) == "string" then
        opts.Name = source
    elseif type(source) == "table" then
        for key, value in pairs(source) do
            opts[key] = value
        end
    end
    for from, to in pairs(map or {}) do
        if opts[to] == nil and opts[from] ~= nil then
            opts[to] = opts[from]
        end
    end
    if opts.Icon ~= nil then
        opts.Icon = cleanIcon(opts.Icon)
    end
    if opts.Range then
        opts.Min = opts.Min or opts.Range[1]
        opts.Max = opts.Max or opts.Range[2]
    end
    return opts
end

local function finishElement(tab, opts, element, frame, kind)
    element._type = kind
    element._frame = frame
    element._listeners = element._listeners or {}
    local window = tab and tab.Window
    local searchText = opts.Name or opts.Text or opts.Title
    element._searchName = type(searchText) == "string" and searchText or ""
    element._searchKey = string.lower(element._searchName)
    if tab and tab._items then
        table.insert(tab._items, element)
    end
    if opts.Flag then
        Library.Flags[opts.Flag] = element
        if window then
            window:_flagCreated(opts.Flag, element)
        end
    end
    element._userVisible = opts.Visible ~= false
    function element:IsVisible()
        return element._userVisible
    end
    function element:_isShown()
        return element._userVisible and not (tab and tab._userVisible == false)
    end
    function element:SetVisible(visible)
        visible = visible and true or false
        if visible == element._userVisible or element._destroyed then
            return
        end
        element._userVisible = visible
        if not visible then
            if element._onHide then
                element._onHide()
            end
            if element.Open and type(element.SetOpen) == "function" then
                element:SetOpen(false)
            end
        end
        if frame then
            frame.Visible = visible
        end
        if window then
            window._controlsDirty = true
        end
    end
    if frame and not element._userVisible then
        frame.Visible = false
    end
    -- Tooltip: a string, or { Title, Text, Icon }. nil, false or "" hides it.
    function element:SetTooltip(tip)
        element._tooltip = tip
        if frame and window and not element._tooltipBound then
            element._tooltipBound = true
            window:_attachTooltip(element, frame)
        end
    end
    function element:GetTooltip()
        return element._tooltip
    end
    if opts.Tooltip ~= nil and opts.Tooltip ~= false then
        element:SetTooltip(opts.Tooltip)
    end
    function element:Destroy()
        if element._destroyed then
            return
        end
        element._destroyed = true
        if window and window._tipOwner == element then
            window:_hideTooltip()
        end
        for _, disconnect in ipairs(element._listeners) do
            disconnect()
        end
        element._listeners = {}
        if tab and tab._items then
            local index = table.find(tab._items, element)
            if index then
                table.remove(tab._items, index)
            end
        end
        if opts.Flag and Library.Flags[opts.Flag] == element then
            Library.Flags[opts.Flag] = nil
        end
        if window then
            window._controlsDirty = true
        end
        if frame then
            frame:Destroy()
        end
    end
    return element
end

Library.Theme = {
    Background = Color3.fromRGB(12, 14, 12),
    Surface = Color3.fromRGB(16, 20, 17),
    Surface2 = Color3.fromRGB(22, 28, 23),
    Surface3 = Color3.fromRGB(32, 44, 34),
    Stroke = Color3.fromRGB(28, 44, 31),
    StrokeHover = Color3.fromRGB(50, 105, 65),
    Accent = Color3.fromRGB(50, 230, 150),
    AccentDark = Color3.fromRGB(12, 28, 18),
    Text = Color3.fromRGB(235, 248, 238),
    Muted = Color3.fromRGB(115, 145, 125),
    Warning = Color3.fromRGB(240, 190, 75),
    Success = Color3.fromRGB(50, 230, 150),
    Error = Color3.fromRGB(245, 85, 85),
}

-- Order decides which key wins when two theme colors are identical.
local THEME_KEYS = {
    "Accent", "AccentDark", "Background", "Surface", "Surface2", "Surface3",
    "Stroke", "StrokeHover", "Text", "Muted", "Warning", "Success", "Error",
}

local function rgb(r, g, b)
    return Color3.fromRGB(r, g, b)
end

local function preset(background, surface, surface2, surface3, strokeColor, strokeHover, accent, accentDark, text, muted)
    return {
        Background = rgb(table.unpack(background)),
        Surface = rgb(table.unpack(surface)),
        Surface2 = rgb(table.unpack(surface2)),
        Surface3 = rgb(table.unpack(surface3)),
        Stroke = rgb(table.unpack(strokeColor)),
        StrokeHover = rgb(table.unpack(strokeHover)),
        Accent = rgb(table.unpack(accent)),
        AccentDark = rgb(table.unpack(accentDark)),
        Text = rgb(table.unpack(text)),
        Muted = rgb(table.unpack(muted)),
    }
end

Library.ThemePresets = {
    -- Colours here must not be pure white, pure black or any other colour the
    -- library hard-codes, or those objects would get bound to the theme.
    Cybrion = preset({ 12, 14, 12 }, { 16, 20, 17 }, { 22, 28, 23 }, { 32, 44, 34 }, { 28, 44, 31 }, { 50, 105, 65 }, { 50, 230, 150 }, { 12, 28, 18 }, { 235, 248, 238 }, { 115, 145, 125 }),
    Midnight = preset({ 15, 18, 26 }, { 18, 22, 31 }, { 22, 26, 37 }, { 37, 44, 60 }, { 34, 40, 55 }, { 70, 84, 112 }, { 128, 160, 246 }, { 14, 18, 30 }, { 228, 232, 242 }, { 116, 126, 148 }),
    Ocean = preset({ 12, 20, 24 }, { 15, 24, 29 }, { 18, 29, 35 }, { 31, 48, 56 }, { 29, 44, 52 }, { 58, 92, 104 }, { 110, 214, 222 }, { 10, 24, 28 }, { 226, 238, 240 }, { 108, 134, 140 }),
    Rose = preset({ 22, 15, 18 }, { 27, 18, 22 }, { 32, 21, 26 }, { 48, 34, 40 }, { 45, 30, 37 }, { 98, 64, 78 }, { 246, 160, 186 }, { 30, 14, 20 }, { 240, 228, 232 }, { 138, 112, 120 }),
    Emerald = preset({ 13, 20, 17 }, { 16, 24, 20 }, { 20, 29, 24 }, { 33, 47, 40 }, { 30, 44, 37 }, { 62, 96, 78 }, { 132, 226, 170 }, { 12, 26, 18 }, { 228, 240, 233 }, { 110, 136, 122 }),
    Amber = preset({ 22, 18, 13 }, { 27, 22, 16 }, { 32, 26, 19 }, { 49, 41, 31 }, { 46, 38, 28 }, { 100, 82, 58 }, { 246, 196, 120 }, { 30, 22, 10 }, { 242, 236, 226 }, { 140, 126, 106 }),
    Mono = preset({ 16, 16, 17 }, { 20, 20, 21 }, { 25, 25, 26 }, { 40, 40, 42 }, { 38, 38, 40 }, { 84, 84, 88 }, { 236, 236, 240 }, { 20, 20, 22 }, { 234, 234, 236 }, { 122, 122, 128 }),
    Nebula = preset({ 14, 12, 28 }, { 18, 15, 35 }, { 23, 19, 43 }, { 39, 32, 68 }, { 35, 29, 62 }, { 84, 68, 140 }, { 199, 125, 255 }, { 22, 10, 40 }, { 236, 230, 252 }, { 124, 114, 160 }),
    Synthwave = preset({ 20, 12, 30 }, { 25, 15, 37 }, { 31, 18, 45 }, { 52, 30, 72 }, { 47, 27, 66 }, { 110, 58, 150 }, { 255, 94, 198 }, { 38, 8, 30 }, { 250, 232, 246 }, { 150, 118, 160 }),
    Sakura = preset({ 24, 14, 20 }, { 29, 17, 24 }, { 35, 20, 29 }, { 54, 32, 45 }, { 50, 29, 41 }, { 112, 66, 92 }, { 255, 158, 200 }, { 36, 12, 24 }, { 248, 232, 240 }, { 150, 112, 132 }),
    Velvet = preset({ 20, 10, 16 }, { 25, 12, 20 }, { 31, 15, 25 }, { 50, 25, 40 }, { 46, 23, 37 }, { 104, 52, 82 }, { 222, 110, 170 }, { 30, 8, 20 }, { 244, 228, 238 }, { 142, 106, 126 }),
    Crimson = preset({ 18, 10, 12 }, { 23, 12, 15 }, { 28, 14, 18 }, { 46, 24, 29 }, { 42, 22, 27 }, { 104, 46, 56 }, { 244, 74, 94 }, { 32, 8, 12 }, { 244, 230, 232 }, { 142, 106, 112 }),
    Sunset = preset({ 22, 13, 14 }, { 27, 16, 17 }, { 33, 19, 21 }, { 52, 31, 32 }, { 48, 28, 30 }, { 112, 62, 58 }, { 255, 138, 92 }, { 34, 14, 8 }, { 248, 234, 228 }, { 150, 118, 110 }),
    Gold = preset({ 14, 13, 11 }, { 18, 17, 14 }, { 23, 21, 17 }, { 38, 35, 28 }, { 35, 32, 26 }, { 92, 80, 54 }, { 232, 196, 122 }, { 30, 22, 8 }, { 240, 234, 222 }, { 136, 126, 106 }),
    Cyber = preset({ 13, 13, 15 }, { 17, 17, 19 }, { 21, 21, 24 }, { 36, 36, 40 }, { 33, 33, 37 }, { 86, 84, 70 }, { 250, 226, 72 }, { 30, 26, 4 }, { 240, 240, 232 }, { 126, 124, 118 }),
    Toxic = preset({ 11, 14, 11 }, { 14, 18, 14 }, { 18, 23, 18 }, { 31, 39, 30 }, { 28, 36, 28 }, { 74, 98, 60 }, { 184, 255, 74 }, { 18, 30, 6 }, { 232, 242, 228 }, { 116, 134, 110 }),
    Matcha = preset({ 16, 19, 14 }, { 20, 23, 17 }, { 24, 28, 21 }, { 40, 46, 34 }, { 37, 42, 31 }, { 84, 98, 70 }, { 176, 214, 140 }, { 18, 26, 10 }, { 236, 240, 228 }, { 128, 136, 116 }),
    Aurora = preset({ 10, 20, 22 }, { 12, 25, 27 }, { 15, 30, 33 }, { 26, 50, 53 }, { 24, 45, 48 }, { 50, 104, 104 }, { 94, 240, 180 }, { 6, 30, 22 }, { 224, 246, 240 }, { 102, 142, 134 }),
    Frost = preset({ 13, 17, 23 }, { 16, 21, 28 }, { 20, 26, 34 }, { 34, 43, 56 }, { 31, 40, 52 }, { 72, 92, 118 }, { 164, 214, 255 }, { 12, 22, 34 }, { 230, 238, 246 }, { 114, 128, 146 }),
    Abyss = preset({ 7, 11, 22 }, { 9, 14, 28 }, { 12, 18, 35 }, { 22, 31, 58 }, { 20, 28, 52 }, { 44, 64, 120 }, { 72, 148, 255 }, { 6, 14, 34 }, { 226, 234, 250 }, { 100, 116, 152 }),
    -- Seasonal and themed palettes.
    Halloween = preset({ 18, 12, 20 }, { 23, 15, 25 }, { 28, 18, 30 }, { 46, 30, 48 }, { 43, 28, 44 }, { 104, 62, 40 }, { 255, 138, 36 }, { 36, 16, 4 }, { 246, 234, 224 }, { 146, 120, 128 }),
    Haunted = preset({ 14, 12, 20 }, { 18, 15, 26 }, { 22, 18, 32 }, { 38, 31, 54 }, { 35, 29, 50 }, { 70, 96, 64 }, { 156, 255, 110 }, { 14, 30, 8 }, { 232, 240, 228 }, { 120, 116, 140 }),
    Christmas = preset({ 12, 20, 15 }, { 15, 25, 19 }, { 19, 30, 23 }, { 32, 50, 38 }, { 30, 46, 35 }, { 100, 54, 56 }, { 236, 72, 80 }, { 34, 8, 10 }, { 240, 244, 236 }, { 120, 142, 128 }),
    Valentine = preset({ 24, 12, 17 }, { 30, 14, 21 }, { 36, 17, 25 }, { 58, 27, 40 }, { 54, 25, 37 }, { 130, 56, 84 }, { 255, 92, 140 }, { 40, 8, 20 }, { 252, 232, 240 }, { 160, 112, 132 }),
    Lunar = preset({ 22, 10, 10 }, { 28, 12, 12 }, { 34, 15, 14 }, { 54, 24, 22 }, { 50, 22, 20 }, { 130, 92, 40 }, { 246, 196, 84 }, { 38, 16, 6 }, { 250, 236, 222 }, { 160, 120, 108 }),
    Tropical = preset({ 10, 22, 24 }, { 12, 27, 30 }, { 15, 33, 36 }, { 26, 54, 58 }, { 24, 50, 54 }, { 44, 110, 110 }, { 255, 170, 90 }, { 36, 18, 6 }, { 232, 246, 244 }, { 104, 144, 142 }),
    Dracula = preset({ 24, 25, 33 }, { 29, 30, 40 }, { 34, 36, 47 }, { 52, 55, 70 }, { 48, 50, 64 }, { 98, 114, 164 }, { 189, 147, 249 }, { 26, 18, 44 }, { 246, 246, 238 }, { 126, 132, 168 }),
    Coffee = preset({ 20, 16, 13 }, { 25, 20, 16 }, { 30, 24, 19 }, { 48, 39, 31 }, { 45, 36, 29 }, { 104, 82, 62 }, { 214, 170, 124 }, { 32, 22, 12 }, { 240, 230, 218 }, { 142, 124, 108 }),
}

Library.ThemeName = "Cybrion"
Library.DefaultTheme = "Cybrion"

Library.Assets = {
    Shadow = "rbxassetid://6014261993",
    Glow = "rbxassetid://8992230677",
    Logo = "rbxassetid://103859712365480",
}

local LUCIDE_URL = "https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/lucide/dist/Icons.lua"
local lucideSet = nil

local function loadLucide()
    if lucideSet ~= nil then
        return lucideSet
    end
    local ok, result = pcall(function()
        local source = game:HttpGet(LUCIDE_URL)
        return loadstring(source)()
    end)
    if ok and type(result) == "table" then
        lucideSet = result
    else
        lucideSet = false
        warn("[Aster UI] lucide icons unavailable: " .. tostring(result))
    end
    return lucideSet
end

local FONT_PRESETS = {
    ValleySans = {
        Regular = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Regular.ttf",
        Medium = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-Medium.ttf",
        SemiBold = "https://raw.githubusercontent.com/HelsinkiTypeStudio/valley-sans/main/fonts/ttf/ValleySans-SemiBold.ttf",
    },
}

local FONT_WEIGHTS = {
    Regular = { 400, Enum.FontWeight.Regular },
    Medium = { 500, Enum.FontWeight.Medium },
    SemiBold = { 600, Enum.FontWeight.SemiBold },
    Bold = { 700, Enum.FontWeight.Bold },
}

function Library:LoadFont(opts)
    opts = normalize(opts, {})
    if type(writefile) ~= "function" or type(isfile) ~= "function" or typeof(getcustomasset) ~= "function" then
        warn("[Aster UI] custom fonts need writefile, isfile and getcustomasset")
        return false
    end
    local name = opts.Name or "CustomFont"
    local weights = opts.Weights or FONT_PRESETS[name]
    if type(weights) ~= "table" then
        warn("[Aster UI] no font weights for " .. name)
        return false
    end
    local folder = opts.Folder or "AsterFonts"
    pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(folder) then
            makefolder(folder)
        end
    end)
    local faces = {}
    for weightName, url in pairs(weights) do
        local info = FONT_WEIGHTS[weightName]
        if info then
            local path = folder .. "/" .. name .. "-" .. weightName .. ".ttf"
            local ok = true
            if not isfile(path) then
                ok = pcall(function()
                    writefile(path, game:HttpGet(url))
                end)
            end
            if ok then
                table.insert(faces, { name = weightName, weight = info[1], style = "normal", assetId = getcustomasset(path) })
            else
                warn("[Aster UI] could not download " .. weightName .. " weight of " .. name)
            end
        end
    end
    if #faces == 0 then
        return false
    end
    local familyPath = folder .. "/" .. name .. ".json"
    local okWrite = pcall(function()
        writefile(familyPath, HttpService:JSONEncode({ name = name, faces = faces }))
    end)
    if not okWrite then
        return false
    end
    local family = getcustomasset(familyPath)
    local function face(weightName, fallback)
        local info = FONT_WEIGHTS[weightName]
        if info and weights[weightName] then
            return Font.new(family, info[2])
        end
        return fallback
    end
    Library.Fonts.Regular = face("Regular", Library.Fonts.Regular)
    Library.Fonts.Medium = face("Medium", face("Regular", Library.Fonts.Medium))
    Library.Fonts.Bold = face("SemiBold", face("Bold", Library.Fonts.Bold))
    return true
end

function Library:PreloadIcons()
    return loadLucide() ~= false
end

-- Numbers, digit strings and asset URLs are custom images; anything else is
-- a lucide name.
local function assetId(value)
    if type(value) == "number" then
        return "rbxassetid://" .. string.format("%.0f", value)
    end
    if type(value) == "string" then
        if value:match("^%d+$") then
            return "rbxassetid://" .. value
        end
        if value:find("^rbxassetid://") or value:find("^rbxasset://") or value:find("^rbxthumb://") or value:find("^http") or (Assets and value == Assets.Logo) then
            return value
        end
    end
    return nil
end

-- Returns image, rect offset, rect size, whether it is a custom image, and
-- whether that custom image should still take the theme tint.
local function resolveIcon(icon)
    if typeof(icon) == "table" then
        return assetId(icon.Image) or icon.Image, icon.RectOffset, icon.RectSize, true, icon.Tint == true
    end
    local asset = assetId(icon)
    if asset then
        return asset, nil, nil, true, false
    end
    if type(icon) ~= "string" then
        return nil
    end
    local name = icon:gsub("^lucide:", "")
    local set = loadLucide()
    if not set then
        return nil
    end
    local entry = (set.Icons and set.Icons[name]) or set[name]
    if type(entry) == "table" then
        local image = entry.Image
        if type(image) == "number" then
            image = "rbxassetid://" .. tostring(image)
        end
        local sheet = (set.Spritesheets and set.Spritesheets[tostring(image)]) or image
        return sheet, entry.ImageRectPosition, entry.ImageRectSize
    elseif type(entry) == "string" then
        return entry
    end
    warn("[Aster UI] unknown lucide icon: " .. name)
    return nil
end

local BUTTON_HINT_ICON = "chevron-right"

local FONT_FAMILY = "rbxasset://fonts/families/BuilderSans.json"
Library.Fonts = {
    Regular = Font.new(FONT_FAMILY, Enum.FontWeight.Regular),
    Medium = Font.new(FONT_FAMILY, Enum.FontWeight.Medium),
    Bold = Font.new(FONT_FAMILY, Enum.FontWeight.SemiBold),
}

local Theme = Library.Theme
local Assets = Library.Assets

-- The Aster UI mark, embedded as a PNG so it needs no external upload.
-- It is written to the workspace once and loaded with getcustomasset.
local EMBEDDED_LOGO = "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L7rwnmUXKjRcdumqpZdcPIBLz7lv6fnn3btUdfXjwgvuWXrJ+SuXXnLR3Usvv2jF0ssuWXHwhefflWPp5Zdm8WUXXXBXhksuvHPpReffueSCc+9ccu7Zdy0555srllz8zRWq7+6DLrloheHgC867a9nFF9y5/Pxz7lh+wbm3Gw654Nw7DCY7+Lyz71h6zll3LP3mN+486IKz71xy/jfvXHLuWXdZfOmF59y57JLz7zjkwotuP/Sic28/7JLzbzv04vNuW37B2bcffPF5dxx04TkZllxw9h1W7uCLzr9z+cUX3Xno5Rfcfshl59++7JJzbzfZwZedf9eySy6849DLLr1j+WUX337wpedpXBfcffBll92z7PLL7znkkovvPvTyy1YccsmFdy+98jyN/8J7F198/r0HXnbJqsWXX3L/0isvX3XQJRfed+glV6485FtXrTzs6ivvOfSqS+495LJL7jv46stWLbnk4gcWX3ThA4svvOCBAy/owxXnP3igZAcpT7zdv/Qquz+X3nvIVVesPNRw9ZV3H3LF5Xcvu+zSu5defNHKJRdfuHLxheevPPCC81cuU3jYFeetOOLyi+887KrL71h21YV3LL308rsWn3/ZyiUX6N6ov8svveKuQ6656s5l37n0joO+ff6dB11x/oqDLj57pTjL6lp+zaUrll125R2HX3XFrUd964pbT7ri8tuedcV5t73krK/8YvHTnvIyPY2B4E/PwLAMeIM+LDU+wzMwTgaWLJnZ+aEXfWT5m177uZsCzL531kzc09GO+9racU+7wo42rGrvwH2dbVjZ1Ya7Fd7VUcbd7cNjpcqMCNWxsqMDKxvCu63OPpjc2lmhdI6Vit8r/TracW9nO1bO6MA9Cu/tqocr+9rN+7airQSDpVeqvznuyevpald5jUvpxvbvaivCsKK9BJObvuFe6d/b2Qnr+91qa4XqtDCDuMrDTJ6nxeXdwgrhrgxlWLhSba6c0Y5VGsN9szqz0NLWzgrjWeO1cEVnByy8u6sT987swCrTndmF+2Z21jFLceEepVcq7x7hrk61YVAdd2oMdr9WWHvCver3KulamytUz50z23Gn2rP8u9XnlSqzauYM3Kt6VqpNa/vOjhJWtLfhnrZyHdK7b/Ys3Kv8u5IIK9Sve4XV4nudI1auffhHP7jg4levuup7X9bTuFXwp2dgWAa8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"

local function decodeBase64(data)
    local lookup = {}
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, #alphabet do
        lookup[alphabet:byte(i)] = i - 1
    end
    local out = {}
    for i = 1, #data, 4 do
        local a, b, c, d = data:byte(i, i + 3)
        local n = lookup[a] * 262144 + lookup[b] * 4096 + (lookup[c] or 0) * 64 + (lookup[d] or 0)
        local x, y, z = n // 65536, n // 256 % 256, n % 256
        if d ~= 61 then
            out[#out + 1] = string.char(x, y, z)
        elseif c ~= 61 then
            out[#out + 1] = string.char(x, y)
        else
            out[#out + 1] = string.char(x)
        end
    end
    return table.concat(out)
end

pcall(function()
    local getasset = (typeof(getcustomasset) == "function" and getcustomasset)
        or (typeof(getsynasset) == "function" and getsynasset)
    if type(writefile) ~= "function" or typeof(getasset) ~= "function" then
        return
    end
    local folder = "AsterAssets"
    if type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(folder) then
        makefolder(folder)
    end
    local path = folder .. "/AsterLogo.png"
    local png = decodeBase64(EMBEDDED_LOGO)
    local fresh = type(isfile) == "function" and type(readfile) == "function" and isfile(path) and readfile(path) == png
    if not fresh then
        writefile(path, png)
    end
    local asset = getasset(path)
    if type(asset) == "string" and asset ~= "" then
        Assets.Logo = asset
    end
end)
local Fonts = Library.Fonts

local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
Library.Touch = TOUCH

local SIDEBAR_WIDTH = 188
local HEADER_HEIGHT = 62
local TAB_TILE_HEIGHT = 34
local CARD_HEIGHT = TOUCH and 54 or 48
local CARD_HEIGHT_DESC = TOUCH and 70 or 64
local DROPDOWN_OPTION_HEIGHT = TOUCH and 40 or 34
local CHIP_HEIGHT = TOUCH and 34 or 28
local PROFILE_HEIGHT = 64
local SEARCH_WIDTH = 176
local STACK_BELOW = 440

-- Elements read their geometry from one of these. Cards stand alone on a tab,
-- rows sit flush inside a groupbox.
local METRICS = {
    Card = {
        Compact = false,
        Height = CARD_HEIGHT,
        DescHeight = CARD_HEIGHT_DESC,
        Chip = CHIP_HEIGHT,
        Option = DROPDOWN_OPTION_HEIGHT,
        TextSize = 14,
        DescSize = 13,
        TitleHeight = 18,
        DescGap = 20,
        DescLine = 17,
        Slider = CARD_HEIGHT_DESC,
    },
    Row = {
        Compact = true,
        Height = TOUCH and 40 or 32,
        DescHeight = TOUCH and 54 or 46,
        Chip = TOUCH and 30 or 24,
        Option = TOUCH and 34 or 28,
        TextSize = 13,
        DescSize = 12,
        TitleHeight = 16,
        DescGap = 17,
        DescLine = 15,
        Slider = TOUCH and 54 or 46,
    },
}

local tweenInfoCache = {}

-- Theme bindings: every instance property painted with a theme color is
-- remembered by theme key, so SetTheme can repaint the whole UI live.
-- Held strongly: an Instance's Lua handle can be collected while the Instance
-- still exists, which would silently drop it from a weak table. Destroyed
-- objects are pruned instead, once they have been parentless for two sweeps.
local themeBindings = {}
local themeHooks = {}
local themeLookup = {}
local orphanMarks = {}
local bindingCount = 0
local sweepAt = 4000

local function pruneTable(map, counted)
    for object in pairs(map) do
        if object.Parent == nil then
            if orphanMarks[object] then
                map[object] = nil
                orphanMarks[object] = nil
                if counted then
                    bindingCount -= 1
                end
            else
                orphanMarks[object] = true
            end
        else
            orphanMarks[object] = nil
        end
    end
end

local function sweepBindings()
    pruneTable(themeBindings, true)
    pruneTable(themeHooks, false)
    sweepAt = math.max(4000, bindingCount * 2)
end

local function colorKey(color)
    return math.floor(color.R * 255 + 0.5) .. "," .. math.floor(color.G * 255 + 0.5) .. "," .. math.floor(color.B * 255 + 0.5)
end

local function rebuildThemeLookup()
    table.clear(themeLookup)
    for index = #THEME_KEYS, 1, -1 do
        local name = THEME_KEYS[index]
        themeLookup[colorKey(Library.Theme[name])] = name
    end
end
rebuildThemeLookup()

local function bindColors(object, props)
    for property, value in pairs(props) do
        if typeof(value) == "Color3" then
            local name = themeLookup[colorKey(value)]
            local bound = themeBindings[object]
            if name then
                if not bound then
                    bound = {}
                    themeBindings[object] = bound
                    bindingCount += 1
                    if bindingCount >= sweepAt then
                        sweepBindings()
                    end
                end
                bound[property] = name
            elseif bound then
                bound[property] = nil
            end
        end
    end
end

-- Repaints every bound property from the colours on screen to the new theme.
-- One Heartbeat loop lerps each theme key once per frame and assigns the
-- result, instead of creating a tween per object, which hitched the frame the
-- theme changed on large UIs. A change mid-fade picks up from what is shown.
local shownTheme = table.clone(Library.Theme)
local themeDriver = nil

local function paintBinding(object, bound, colors)
    for property, name in pairs(bound) do
        local color = colors[name]
        if color then
            object[property] = color
        end
    end
end

local function paintBindings(colors)
    for object, bound in pairs(themeBindings) do
        pcall(paintBinding, object, bound, colors)
    end
end

local function driveTheme(duration)
    if themeDriver then
        themeDriver:Disconnect()
        themeDriver = nil
    end
    local from, colors = {}, {}
    for _, name in ipairs(THEME_KEYS) do
        local target = Library.Theme[name]
        local current = shownTheme[name] or target
        if current ~= target then
            from[name] = current
            colors[name] = current
        end
    end
    local function finish()
        for _, name in ipairs(THEME_KEYS) do
            colors[name] = Library.Theme[name]
            shownTheme[name] = Library.Theme[name]
        end
        paintBindings(colors)
    end
    if duration <= 0 or next(from) == nil then
        finish()
        return
    end
    local elapsed = 0
    themeDriver = RunService.Heartbeat:Connect(function(deltaTime)
        elapsed += deltaTime
        if elapsed >= duration then
            themeDriver:Disconnect()
            themeDriver = nil
            finish()
            return
        end
        local alpha = 1 - (1 - elapsed / duration) ^ 5
        for name, start in pairs(from) do
            local color = start:Lerp(Library.Theme[name], alpha)
            colors[name] = color
            shownTheme[name] = color
        end
        paintBindings(colors)
    end)
end

-- Runs fn now and again whenever the theme changes, while owner exists.
local function onTheme(owner, fn)
    themeHooks[owner] = fn
    fn()
end

local function tween(object, props, duration, style, direction, raw)
    duration = duration or 0.2
    if not raw then
        bindColors(object, props)
    end
    if duration <= 0 then
        for key, value in pairs(props) do
            object[key] = value
        end
        return nil
    end
    style = style or Enum.EasingStyle.Quart
    direction = direction or Enum.EasingDirection.Out
    local key = duration .. style.Name .. direction.Name
    local info = tweenInfoCache[key]
    if not info then
        info = TweenInfo.new(duration, style, direction)
        tweenInfoCache[key] = info
    end
    local t = TweenService:Create(object, info, props)
    t:Play()
    return t
end

local function create(className, props, children)
    local inst = Instance.new(className)
    for key, value in pairs(props) do
        if key ~= "Parent" then
            inst[key] = value
        end
    end
    if not Library.AutoTranslate and (className == "TextLabel" or className == "TextButton" or className == "TextBox") then
        -- The UI opted out of Roblox's automatic translation.
        pcall(function()
            inst.AutoLocalize = false
        end)
    end
    bindColors(inst, props)
    if children then
        for _, child in ipairs(children) do
            child.Parent = inst
        end
    end

    if props.Parent then
        inst.Parent = props.Parent
    end
    return inst
end

-- Corners in pixels follow the player's corner radius setting: each one
-- remembers the radius it was drawn at, and Library:SetCornerRadius rescales
-- them all. Scale corners (pills, circles) stay as they are.
Library.Roundness = 1
-- A strong table: weak keys would drop the Lua handles for corners nothing
-- else in Lua holds, and those corners would never rescale. Destroyed ones
-- are pruned whenever the radius changes.
Library._cornerBases = {}

local function corner(parent, radius)
    radius = radius or UDim.new(0, 8)
    local object = create("UICorner", {
        CornerRadius = radius.Scale == 0 and UDim.new(0, math.floor(radius.Offset * Library.Roundness + 0.5)) or radius,
        Parent = parent,
    })
    if radius.Scale == 0 then
        Library._cornerBases[object] = radius.Offset
    end
    return object
end

-- A corner that ignores the setting, for shapes that animate their own
-- radius (the minimized island, the morph panels).
function Library._fixedCorner(parent, radius)
    return create("UICorner", { CornerRadius = radius, Parent = parent })
end

-- The radius the window's own corners are drawn at right now.
function Library._radius(pixels)
    return math.floor(pixels * Library.Roundness + 0.5)
end

local function stroke(parent, color, transparency, thickness)
    return create("UIStroke", {
        Color = color or Theme.Stroke,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = parent,
    })
end

local function padding(parent, left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
        Parent = parent,
    })
end

local function label(props)
    local defaults = {
        BackgroundTransparency = 1,
        TextColor3 = Theme.Text,
        TextSize = 14,
        FontFace = Fonts.Medium,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for key, value in pairs(props) do
        defaults[key] = value
    end
    return create("TextLabel", defaults)
end

local function glow(parent, size, position, transparency, rotation)
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = position,
        Size = size,
        BackgroundTransparency = 1,
        Image = Assets.Glow,
        ImageColor3 = Color3.fromRGB(226, 218, 230),
        ImageTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = parent,
    })
    local gradient = create("UIGradient", {
        Rotation = rotation or 90,
        Parent = image,
    })
    onTheme(gradient, function()
        gradient.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Theme.Accent)
    end)
    return image
end

local function edgeHighlight(parent)
    return create("Frame", {
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = parent,
    })
end

local CUSTOM_ICON_SCALE = 1.35

local function applyIcon(imageLabel, icon, fixedSize)
    if icon == false then
        -- Explicit no-icon: clear the slot so a recycled label never keeps a
        -- stale image.
        imageLabel.Image = ""
        imageLabel.ImageRectOffset = Vector2.zero
        imageLabel.ImageRectSize = Vector2.zero
        imageLabel:SetAttribute("CustomIcon", nil)
        local stale = imageLabel:FindFirstChild("CustomIconScale")
        if stale then
            stale:Destroy()
        end
        return
    end
    local image, rectOffset, rectSize, custom, tint = resolveIcon(icon)
    if not image then
        return
    end
    imageLabel.Image = image
    imageLabel.ImageRectOffset = rectOffset or Vector2.zero
    imageLabel.ImageRectSize = rectSize or Vector2.zero
    -- Aster UI logo preserves its original gradient colours
    if icon == Assets.Logo then
        tint = false
    end
    local keepColours = custom and not tint
    imageLabel:SetAttribute("CustomIcon", keepColours or nil)
    if keepColours then
        -- Original colours, and out of the theme's reach.
        local bound = themeBindings[imageLabel]
        if bound then
            bound.ImageColor3 = nil
        end
        tween(imageLabel, { ImageColor3 = Color3.new(1, 1, 1) }, 0)
    end
    -- Uploaded images usually carry transparent padding and read smaller than
    -- the lucide set, so they are drawn larger. A table icon can pick its own
    -- Scale. Brand logos pass fixedSize, their slots are already sized for them.
    local scale = custom and not fixedSize and icon ~= Assets.Logo and (typeof(icon) == "table" and tonumber(icon.Scale) or CUSTOM_ICON_SCALE) or 1
    local scaler = imageLabel:FindFirstChild("CustomIconScale")
    if scale ~= 1 then
        scaler = scaler or create("UIScale", { Name = "CustomIconScale", Parent = imageLabel })
        scaler.Scale = scale
    elseif scaler then
        scaler:Destroy()
    end
end

-- Selection state for icons: tinted icons change colour, custom images keep
-- their colours and dim instead.
local function tintIcon(imageLabel, color, active, duration)
    if imageLabel:GetAttribute("CustomIcon") then
        tween(imageLabel, { ImageTransparency = active and 0 or 0.4 }, duration)
    else
        tween(imageLabel, { ImageColor3 = color }, duration)
    end
end

local function defaultParent()
    local hidden
    pcall(function()
        if typeof(gethui) == "function" then
            hidden = gethui()
        end
    end)
    if typeof(hidden) == "Instance" then
        return hidden
    end
    local core
    pcall(function()
        core = game:GetService("CoreGui")
        local probe = Instance.new("Folder")
        probe.Parent = core
        probe:Destroy()
    end)
    if core then
        return core
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local insetFrame, insetValue = nil, Vector2.zero
local function pointerPosition()
    local frame = time()
    if insetFrame ~= frame then
        insetFrame = frame
        insetValue = GuiService:GetGuiInset()
    end
    return UserInputService:GetMouseLocation() - insetValue
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function usingTouch()
    return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

-- A press that turned into a scroll is not a tap. Returns a check to call
-- from the click handler.
local function tapGuard(button, getScroller)
    local startCanvas
    button.InputBegan:Connect(function(input)
        if isPress(input) then
            local frame = getScroller()
            startCanvas = frame and frame.CanvasPosition
        end
    end)
    return function()
        local frame = getScroller()
        return not (startCanvas and frame and (frame.CanvasPosition - startCanvas).Magnitude > 4)
    end
end

local function pointInside(point, object)
    local position, size = object.AbsolutePosition, object.AbsoluteSize
    return point.X >= position.X and point.X <= position.X + size.X
        and point.Y >= position.Y and point.Y <= position.Y + size.Y
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function glowIcon(parent, icon, color, position)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = position,
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageColor3 = color,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(image, icon)
    return holder, image
end

local function arrowIndicator(parent, anchorX, offsetX)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(anchorX, 0.5),
        Position = UDim2.new(anchorX, offsetX, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local indicator = {}
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(image, "chevron-down")
    if image.Image ~= "" then
        function indicator:Set(open)
            tween(image, {
                Rotation = open and 180 or 0,
                ImageColor3 = open and Theme.Accent or Theme.Muted,
            }, 0.3, Enum.EasingStyle.Quint)
        end
        return indicator
    end
    image:Destroy()
    local function glyph(rotation, transparency)
        return label({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(18, 18),
            Text = "›",
            TextSize = 22,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextColor3 = Theme.Muted,
            TextTransparency = transparency,
            Rotation = rotation,
            Parent = holder,
        })
    end
    local down = glyph(90, 0)
    local up = glyph(270, 1)
    function indicator:Set(open)
        tween(down, { TextTransparency = open and 1 or 0 }, 0.2)
        tween(up, { TextTransparency = open and 0 or 1, TextColor3 = open and Theme.Accent or Theme.Muted }, 0.2)
    end
    return indicator
end

local ripplePool = {}

local function ripple(button)
    local mouse = pointerPosition()
    local diameter = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2.2
    local circle = table.remove(ripplePool)
    -- A pooled circle can't be reparented if it was destroyed along the way.
    if circle and not pcall(function()
        circle.Parent = nil
    end) then
        circle = nil
    end
    if not circle then
        circle = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
        })
        corner(circle, UDim.new(1, 0))
    end
    circle.Position = UDim2.fromOffset(mouse.X - button.AbsolutePosition.X, mouse.Y - button.AbsolutePosition.Y)
    circle.Size = UDim2.fromOffset(0, 0)
    circle.BackgroundColor3 = Theme.Accent
    circle.BackgroundTransparency = 0.82
    circle.ZIndex = button.ZIndex + 1
    circle.Parent = button
    tween(circle, { Size = UDim2.fromOffset(diameter, diameter), BackgroundTransparency = 1 }, 0.55)
    task.delay(0.55, function()
        -- A button destroyed mid-ripple takes the circle with it: drop it.
        if circle.Parent ~= button or not button.Parent then
            pcall(circle.Destroy, circle)
            return
        end
        circle.Parent = nil
        if #ripplePool < 4 then
            table.insert(ripplePool, circle)
        else
            circle:Destroy()
        end
    end)
end

local function flashStroke(strokeObject)
    if not strokeObject or strokeObject:GetAttribute("Hidden") then
        return
    end
    tween(strokeObject, { Color = Theme.Accent, Transparency = 0.2 }, 0.08)
    task.delay(0.12, function()
        tween(strokeObject, { Color = Theme.Stroke, Transparency = 0 }, 0.35)
    end)
end

local function hoverStroke(target, strokeObject)
    target.MouseEnter:Connect(function()
        tween(strokeObject, { Color = Theme.StrokeHover }, 0.12)
    end)
    target.MouseLeave:Connect(function()
        tween(strokeObject, { Color = Theme.Stroke }, 0.25)
    end)
end

local KEY_NAMES = {
    [Enum.KeyCode.LeftControl] = "LCtrl",
    [Enum.KeyCode.RightControl] = "RCtrl",
    [Enum.KeyCode.LeftShift] = "LShift",
    [Enum.KeyCode.RightShift] = "RShift",
    [Enum.KeyCode.LeftAlt] = "LAlt",
    [Enum.KeyCode.RightAlt] = "RAlt",
    [Enum.KeyCode.Return] = "Enter",
    [Enum.KeyCode.Escape] = "Esc",
    [Enum.KeyCode.Backspace] = "Backspace",
    [Enum.UserInputType.MouseButton1] = "MB1",
    [Enum.UserInputType.MouseButton2] = "MB2",
    [Enum.UserInputType.MouseButton3] = "MB3",
}

local function keyName(keyCode)
    if typeof(keyCode) ~= "EnumItem" then
        return "None"
    end
    return KEY_NAMES[keyCode] or keyCode.Name
end

-- Keybinds hold a KeyCode for keyboard keys or a UserInputType for the three
-- mouse buttons. MB1..MB3 are the display and config names.
local Keybinds = {
    Mouse = {
        [Enum.UserInputType.MouseButton1] = true,
        [Enum.UserInputType.MouseButton2] = true,
        [Enum.UserInputType.MouseButton3] = true,
    },
    Aliases = {
        MB1 = Enum.UserInputType.MouseButton1,
        MB2 = Enum.UserInputType.MouseButton2,
        MB3 = Enum.UserInputType.MouseButton3,
    },
}

-- The value a keybind stores for a user input: the KeyCode for keyboard, the
-- UserInputType for a mouse button. nil for anything not bindable.
function Keybinds.FromInput(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        return input.KeyCode
    end
    if Keybinds.Mouse[input.UserInputType] then
        return input.UserInputType
    end
    return nil
end

-- Accepts a bind as an EnumItem (KeyCode or mouse UserInputType) or by name:
-- "E", "MouseButton2", "MB2".
function Keybinds.Resolve(value)
    if typeof(value) == "EnumItem" then
        if value.EnumType == Enum.UserInputType and not Keybinds.Mouse[value] then
            return nil
        end
        return value
    end
    if type(value) ~= "string" then
        return nil
    end
    local key = Enum.KeyCode[value]
    if key then
        return key
    end
    local inputType = Enum.UserInputType[value]
    if inputType and Keybinds.Mouse[inputType] then
        return inputType
    end
    return Keybinds.Aliases[value] or Keybinds.Aliases[string.upper(value)]
end

local function safeCall(callback, ...)
    if type(callback) ~= "function" then
        return
    end
    local ok, err = pcall(callback, ...)
    if not ok then
        warn("[Aster UI] callback error: " .. tostring(err))
    end
end

-- Runs a user callback on its own thread and waits for it with task.wait.
-- A callback that yields inside an engine call (InvokeServer and the like)
-- resumes at game identity, which can no longer touch the GUI in CoreGui;
-- keeping that on a separate thread leaves the caller's identity intact.
local function isolatedCall(callback)
    local result = nil
    task.spawn(function()
        result = table.pack(pcall(callback))
    end)
    while result == nil do
        task.wait()
    end
    return table.unpack(result, 1, result.n)
end

local function numberFormat(min, max, step)
    local decimals = 0
    local text = tostring(step)
    local dot = text:find("%.")
    if dot then
        decimals = #text - dot
    end
    local pattern = "%." .. decimals .. "f"
    return {
        snap = function(value)
            value = math.floor(value / step + 0.5) * step
            return math.clamp(value, min, max)
        end,
        format = function(value)
            return string.format(pattern, value)
        end,
    }
end

local function metricsOf(tab)
    return tab._metrics or METRICS.Card
end

-- Width of a value control inside a groupbox row. Every dropdown and input in
-- a groupbox uses the same share of the row, so their left edges line up.
local function rowControlWidth(frame, window)
    local width = frame.AbsoluteSize.X / window.Scale.Scale
    return math.clamp(math.floor(width * 0.48), 90, 220)
end

local function card(tab, className, height, opts)
    local compact = metricsOf(tab).Compact
    local props = {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = compact and 1 or 0,
        BorderSizePixel = 0,
        LayoutOrder = tab:_nextOrder(),
        Parent = tab.List,
    }
    if className == "TextButton" then
        props.AutoButtonColor = false
        props.Text = ""
    end
    local frame = create(className, props)
    frame:SetAttribute("NoDrag", true)
    corner(frame)
    local frameStroke = stroke(frame, Theme.Stroke, compact and 1 or 0)
    if compact then
        frameStroke:SetAttribute("Hidden", true)
    end
    return frame, frameStroke
end

local function titleDesc(parent, name, desc, rightReserve, metrics)
    metrics = metrics or METRICS.Card
    local title, descLabel
    if desc then
        local top = math.floor((metrics.DescHeight - (metrics.DescGap + metrics.DescLine)) / 2)
        title = label({
            Position = UDim2.fromOffset(14, top),
            Size = UDim2.new(1, -(14 + rightReserve), 0, metrics.TitleHeight),
            Text = name,
            TextSize = metrics.TextSize,
            Parent = parent,
        })
        descLabel = label({
            Position = UDim2.fromOffset(14, top + metrics.DescGap),
            Size = UDim2.new(1, -(14 + rightReserve), 0, metrics.DescLine),
            Text = desc,
            TextSize = metrics.DescSize,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = parent,
        })
    else
        title = label({
            Position = UDim2.fromOffset(14, 0),
            Size = UDim2.new(1, -(14 + rightReserve), 1, 0),
            Text = name,
            TextSize = metrics.TextSize,
            Parent = parent,
        })
    end
    return title, descLabel
end

local function beginElement(tab, opts, map, className, rightReserve, fallbackName)
    opts = normalize(opts, map)
    local metrics = metricsOf(tab)
    local height = opts.Desc and metrics.DescHeight or metrics.Height
    local frame, frameStroke = card(tab, className or "Frame", height, opts)
    hoverStroke(frame, frameStroke)
    local title, descLabel
    if rightReserve then
        title, descLabel = titleDesc(frame, opts.Name or fallbackName, opts.Desc, rightReserve, metrics)
    end
    return opts, frame, frameStroke, height, title, descLabel
end

local function reserveRight(title, descLabel, width)
    if title then
        title.Size = UDim2.new(1, -(14 + width), title.Size.Y.Scale, title.Size.Y.Offset)
    end
    if descLabel then
        descLabel.Size = UDim2.new(1, -(14 + width), 0, descLabel.Size.Y.Offset)
    end
end

local Tab = {}
Tab.__index = Tab

function Tab:_nextOrder()
    self._order = self._order + 1
    return self._order
end

function Tab:Section(text)
    local visible = not (type(text) == "table" and text.Visible == false)
    if type(text) == "table" then
        text = text.Name or text.Title or ""
    end
    local inset = metricsOf(self).Compact and 14 or 2
    local holder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    local text_ = label({
        Position = UDim2.fromOffset(inset, 8),
        Size = UDim2.new(0, 0, 0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = string.upper(text),
        TextSize = 12,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        Parent = holder,
    })
    local ruleInset = inset == 2 and 0 or inset
    local rule = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -ruleInset, 0, 16),
        Size = UDim2.new(1, -12, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = holder,
    })
    local function fitRule()
        rule.Size = UDim2.new(1, -(text_.AbsoluteSize.X / self.Window.Scale.Scale + inset + 12 + ruleInset), 0, 1)
    end
    text_:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRule)
    task.defer(fitRule)
    return finishElement(self, { Visible = visible }, {
        Set = function(_, value)
            text_.Text = string.upper(value)
        end,
    }, holder, "Section")
end

function Tab:Divider(opts)
    local caption = type(opts) == "table" and (opts.Text or opts.Name) or type(opts) == "string" and opts or nil
    if caption then
        -- A centred caption with a rule on each side.
        local inset = metricsOf(self).Compact and 14 or 2
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 18),
            BackgroundTransparency = 1,
            LayoutOrder = self:_nextOrder(),
            Parent = self.List,
        })
        local text_ = label({
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(0, 0, 0, 14),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = caption,
            TextSize = 11,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Parent = holder,
        })
        padding(text_, 8, 8)
        local rules = {}
        for index, anchor in ipairs({ 0, 1 }) do
            rules[index] = create("Frame", {
                AnchorPoint = Vector2.new(anchor, 0.5),
                Position = UDim2.new(anchor, anchor == 0 and inset or -inset, 0.5, 0),
                Size = UDim2.new(0.5, -inset, 0, 1),
                BackgroundColor3 = Theme.Stroke,
                BorderSizePixel = 0,
                Parent = holder,
            })
        end
        local function fitRules()
            local half = text_.AbsoluteSize.X / self.Window.Scale.Scale / 2
            for _, rule in ipairs(rules) do
                rule.Size = UDim2.new(0.5, -(inset + half), 0, 1)
            end
        end
        text_:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRules)
        task.defer(fitRules)
        return finishElement(self, { Visible = not (type(opts) == "table" and opts.Visible == false) }, {
            Set = function(_, value)
                text_.Text = tostring(value)
            end,
        }, holder, "Divider")
    end
    local line = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    if metricsOf(self).Compact then
        line.BackgroundTransparency = 1
        line.Size = UDim2.new(1, 0, 0, 9)
        create("Frame", {
            Position = UDim2.fromOffset(14, 4),
            Size = UDim2.new(1, -28, 0, 1),
            BackgroundColor3 = Theme.Stroke,
            BorderSizePixel = 0,
            Parent = line,
        })
    end
    return finishElement(self, { Visible = not (type(opts) == "table" and opts.Visible == false) }, {}, line, "Divider")
end

function Tab:Label(opts)
    opts = normalize(opts, { Name = "Text", Title = "Text" })
    local text_ = label({
        Size = UDim2.new(1, 0, 0, 18),
        Text = Library._rich(opts.Text or ""),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Library._color(opts.Color) or Theme.Muted,
        RichText = true,
        LayoutOrder = self:_nextOrder(),
        Parent = self.List,
    })
    if metricsOf(self).Compact then
        text_.TextSize = 12
        padding(text_, 14, 14)
    else
        padding(text_, 2)
    end
    local handle = {
        Set = function(_, value)
            text_.Text = Library._rich(value)
        end,
        Get = function()
            return text_.Text
        end,
        SetColor = function(_, color)
            tween(text_, { TextColor3 = Library._color(color) or Theme.Muted }, 0.25)
        end,
    }
    if type(opts.Update) == "function" then
        local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
        local running = true
        handle._listeners = handle._listeners or {}
        table.insert(handle._listeners, function()
            running = false
        end)
        task.spawn(function()
            while running and text_.Parent do
                local ok, value = isolatedCall(opts.Update)
                if ok and value ~= nil then
                    text_.Text = Library._rich(value)
                elseif not ok then
                    warn("[Aster UI] label update error: " .. tostring(value))
                end
                task.wait(rate)
            end
        end)
        function handle:SetUpdateRate(seconds)
            rate = math.max(tonumber(seconds) or rate, 0.05)
        end
    end
    return finishElement(self, opts, handle, text_, "Label")
end

function Tab:Paragraph(opts)
    opts = normalize(opts, { Title = "Name" })
    local frame = card(self, "Frame", 0, opts)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    if metricsOf(self).Compact then
        padding(frame, 14, 14, 6, 8)
    else
        padding(frame, 14, 14, 11, 12)
    end
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = frame,
    })
    label({
        Size = UDim2.new(1, 0, 0, 14),
        Text = opts.Name or "",
        LayoutOrder = 1,
        Parent = frame,
    })
    local content = label({
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = Library._rich(opts.Content or ""),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        RichText = true,
        LayoutOrder = 2,
        Parent = frame,
    })
    return finishElement(self, opts, {
        Set = function(_, value)
            content.Text = Library._rich(value)
        end,
    }, frame, "Paragraph")
end

local function rowButton(tab, opts)
    local primary = opts.Style == "Primary"
    local boxHeight = TOUCH and 34 or 28
    local height = boxHeight + 6 + (opts.Desc and 16 or 0)
    local button = card(tab, "TextButton", height, opts)

    local box = create("Frame", {
        Position = UDim2.fromOffset(14, 3),
        Size = UDim2.new(1, -28, 0, boxHeight),
        BackgroundColor3 = primary and Theme.Accent or Theme.Surface3,
        BackgroundTransparency = primary and 0.12 or 0.45,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = button,
    })
    corner(box, UDim.new(0, 6))
    local boxStroke = stroke(box, primary and Theme.Accent or Theme.Stroke, primary and 0.4 or 0)

    local row = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = box,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = row,
    })
    local textColor = primary and Theme.AccentDark or Theme.Text
    if opts.Icon then
        local image = create("ImageLabel", {
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = primary and Theme.AccentDark or Theme.Accent,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = row,
        })
        applyIcon(image, opts.Icon)
    end
    local title = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = opts.Name or "Button",
        TextSize = 13,
        TextColor3 = textColor,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = row,
    })
    if opts.Desc then
        label({
            Position = UDim2.fromOffset(14, boxHeight + 6),
            Size = UDim2.new(1, -28, 0, 14),
            Text = opts.Desc,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = button,
        })
    end

    local restBg = primary and 0.12 or 0.45
    button.MouseEnter:Connect(function()
        tween(box, { BackgroundTransparency = primary and 0 or 0.2 }, 0.12)
        tween(boxStroke, primary and { Transparency = 0 } or { Color = Theme.StrokeHover }, 0.12)
    end)
    button.MouseLeave:Connect(function()
        tween(box, { BackgroundTransparency = restBg }, 0.25)
        tween(boxStroke, primary and { Transparency = 0.4 } or { Color = Theme.Stroke }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        ripple(box)
        safeCall(opts.Callback)
    end)

    return finishElement(tab, opts, {
        SetText = function(_, value)
            title.Text = value
        end,
    }, button, "Button")
end

function Tab:Button(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    if metricsOf(self).Compact then
        return rowButton(self, opts)
    end
    local primary = opts.Style == "Primary"
    local height = opts.Desc and CARD_HEIGHT_DESC or CARD_HEIGHT
    local button, buttonStroke = card(self, "TextButton", height, opts)
    button.ClipsDescendants = true

    if primary then
        tween(button, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.12 }, 0)
        tween(buttonStroke, { Color = Theme.Accent }, 0)
        buttonStroke.Transparency = 0.4
        button.MouseEnter:Connect(function()
            tween(button, { BackgroundTransparency = 0 }, 0.12)
            tween(buttonStroke, { Transparency = 0 }, 0.12)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { BackgroundTransparency = 0.12 }, 0.25)
            tween(buttonStroke, { Transparency = 0.4 }, 0.25)
        end)
    else
        hoverStroke(button, buttonStroke)
    end

    local textColor = primary and Theme.AccentDark or Theme.Text
    local iconOffset = 0
    if opts.Icon then
        glowIcon(button, opts.Icon, primary and Theme.AccentDark or Theme.Accent, UDim2.new(0, 14, 0.5, 0))
        iconOffset = 26
    end
    local title = titleDesc(button, opts.Name or "Button", opts.Desc, 30)
    if iconOffset > 0 then
        for _, child in ipairs(button:GetChildren()) do
            if child:IsA("TextLabel") then
                child.Position = child.Position + UDim2.fromOffset(iconOffset, 0)
                child.Size = child.Size - UDim2.fromOffset(iconOffset, 0)
            end
        end
    end
    if primary then
        for _, child in ipairs(button:GetChildren()) do
            if child:IsA("TextLabel") then
                tween(child, { TextColor3 = textColor }, 0)
            end
        end
    end

    glowIcon(button, BUTTON_HINT_ICON, primary and Theme.AccentDark or Theme.Muted, UDim2.new(1, -30, 0.5, 0))

    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(opts.Callback)
    end)

    return finishElement(self, opts, {
        SetText = function(_, value)
            title.Text = value
        end,
    }, button, "Button")
end

function Tab:Toggle(opts)
    local button, buttonStroke
    opts, button, buttonStroke = beginElement(self, opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default" }, "TextButton", 56, "Toggle")

    local self_ = { Value = opts.Default == true }
    local skin

    -- The visuals rebuild in place, so the Interface Manager's Toggle Style
    -- dropdown can convert live toggles: each toggle registers a rebuild
    -- below and swaps between the switch and the tick box on call.
    local function buildSkin()
        if skin then
            skin.destroy()
            skin = nil
        end
        if Library.ForceCheckbox then
            -- Checkbox: a tick box, styled after the multi-select checkboxes.
            local box = create("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -14, 0.5, 0),
                Size = TOUCH and UDim2.fromOffset(24, 24) or UDim2.fromOffset(20, 20),
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                Parent = button,
            })
            corner(box, UDim.new(0, 5))
            local boxStroke = stroke(box, Theme.Stroke)
            local check = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = TOUCH and UDim2.fromOffset(14, 14) or UDim2.fromOffset(12, 12),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.AccentDark,
                ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                Parent = box,
            })
            applyIcon(check, "check")
            local checkScale = create("UIScale", { Parent = check })
            skin = {
                destroy = function()
                    box:Destroy()
                end,
                render = function(animate)
                    local on = self_.Value
                    local duration = animate and 0.18 or 0
                    tween(box, { BackgroundColor3 = on and Theme.Accent or Theme.Surface2 }, duration)
                    tween(boxStroke, { Color = on and Theme.Accent or Theme.Stroke }, duration)
                    tween(check, { ImageTransparency = on and 0 or 1 }, duration)
                    if animate and on then
                        checkScale.Scale = 0.5
                        tween(checkScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
                    else
                        checkScale.Scale = 1
                    end
                end,
            }
        else
            -- Switch: the pill and its knob.
            local pill = create("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -14, 0.5, 0),
                Size = TOUCH and UDim2.fromOffset(44, 24) or UDim2.fromOffset(36, 20),
                BackgroundColor3 = Theme.Surface3,
                BorderSizePixel = 0,
                Parent = button,
            })
            corner(pill, UDim.new(1, 0))
            stroke(pill, Theme.Stroke)

            local knob = create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 3, 0.5, 0),
                Size = TOUCH and UDim2.fromOffset(18, 18) or UDim2.fromOffset(14, 14),
                BackgroundColor3 = Theme.Muted,
                BorderSizePixel = 0,
                Parent = pill,
            })
            corner(knob, UDim.new(1, 0))
            local pillGlow = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.new(1, 24, 1, 24),
                BackgroundTransparency = 1,
                Image = Assets.Glow,
                ImageColor3 = Theme.Accent,
                ImageTransparency = 1,
                ZIndex = 0,
                Parent = pill,
            })
            skin = {
                destroy = function()
                    pill:Destroy()
                end,
                render = function(animate)
                    local on = self_.Value
                    local duration = animate and 0.25 or 0
                    tween(pill, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3 }, duration)
                    tween(pillGlow, { ImageTransparency = on and 0.75 or 1 }, duration)
                    local knobSize = TOUCH and 18 or 14
                    tween(knob, {
                        Position = on and UDim2.new(0, (TOUCH and 44 or 36) - 3 - knobSize, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
                        BackgroundColor3 = on and Theme.AccentDark or Theme.Muted,
                    }, duration, Enum.EasingStyle.Back)
                    if animate then
                        tween(knob, { Size = UDim2.fromOffset(knobSize + 4, knobSize - 2) }, 0.08)
                        task.delay(0.08, function()
                            tween(knob, { Size = UDim2.fromOffset(knobSize, knobSize) }, 0.2, Enum.EasingStyle.Back)
                        end)
                    end
                end,
            }
        end
    end
    buildSkin()

    Library._toggleSkins[button] = function()
        if button:IsDescendantOf(game) then
            buildSkin()
            skin.render(false)
        end
    end

    local function render(animate)
        skin.render(animate)
    end

    local fromClick = false
    function self_:Set(value, silent)
        value = value == true
        if value == self_.Value then
            return
        end
        self_.Value = value
        render(true)
        if not fromClick then
            flashStroke(buttonStroke)
        end
        if not silent then
            safeCall(opts.Callback, value)
        end
    end

    function self_:Get()
        return self_.Value
    end

    render(false)
    button.MouseButton1Click:Connect(function()
        fromClick = true
        self_:Set(not self_.Value)
        fromClick = false
    end)

    local handle = finishElement(self, opts, self_, button, "Toggle")
    if self_.Value then
        safeCall(opts.Callback, true)
    end
    return handle
end

function Tab:Slider(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default", Increment = "Step" })
    local min = opts.Min or 0
    local max = opts.Max or 100
    local step = opts.Step or 1
    local suffix = opts.Suffix or ""
    local numbers = numberFormat(min, max, step)

    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local height = metrics.Slider
    local frame, frameStroke = card(self, "Frame", height, opts)
    hoverStroke(frame, frameStroke)

    label({
        Position = UDim2.fromOffset(14, compact and 5 or 12),
        Size = UDim2.new(1, -120, 0, 18),
        Text = opts.Name or "Slider",
        TextSize = metrics.TextSize,
        Parent = frame,
    })

    local valueChip = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, compact and -14 or -10, 0, compact and 2 or 9),
        Size = UDim2.fromOffset(40, 24),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(valueChip, UDim.new(0, 6))
    local chipStroke = stroke(valueChip)
    local valueLabel = label({
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        Parent = valueChip,
    })
    local valueBox = create("TextBox", {
        Position = UDim2.fromOffset(9, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "",
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Medium,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Visible = false,
        Parent = valueChip,
    })
    create("UISizeConstraint", { MinSize = Vector2.new(14, 0), Parent = valueBox })
    local suffixLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = suffix,
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextTruncate = Enum.TextTruncate.None,
        Visible = false,
        Parent = valueChip,
    })
    local chipButton = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
        Parent = valueChip,
    })
    local editing = false
    local function fitChip(instant)
        local width
        if editing then
            width = 9 + valueBox.AbsoluteSize.X / (self.Window.Scale.Scale) + suffixLabel.TextBounds.X + 9
            suffixLabel.Position = UDim2.fromOffset(9 + valueBox.AbsoluteSize.X / (self.Window.Scale.Scale), 0)
        else
            width = valueLabel.TextBounds.X + 18
        end
        width = math.max(width, 36)
        if instant then
            valueChip.Size = UDim2.fromOffset(width, 24)
        else
            tween(valueChip, { Size = UDim2.fromOffset(width, 24) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        if not editing then
            fitChip(false)
        end
    end)
    valueBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if editing then
            fitChip(false)
        end
    end)

    local track = create("Frame", {
        Position = UDim2.new(0, 14, 0, height - (compact and 13 or 18)),
        Size = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(track, UDim.new(1, 0))
    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, UDim.new(1, 0))

    local knobGlow = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        BackgroundTransparency = 1,
        Image = Assets.Glow,
        ImageColor3 = Theme.Accent,
        ImageTransparency = 0.85,
        ZIndex = 2,
        Parent = track,
    })
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 3,
        Parent = track,
    })
    corner(knob, UDim.new(1, 0))

    local hit = create("TextButton", {
        Position = UDim2.new(0, 8, 0, height - (compact and 13 or 18) - (TOUCH and 19 or 13)),
        Size = UDim2.new(1, -16, 0, TOUCH and 40 or 28),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 4,
        Parent = frame,
    })

    local self_ = { Value = math.clamp(opts.Default or min, min, max) }
    local dragging = false
    chipButton.MouseEnter:Connect(function()
        tween(chipStroke, { Color = Theme.StrokeHover }, 0.12)
    end)
    chipButton.MouseLeave:Connect(function()
        if not valueBox:IsFocused() then
            tween(chipStroke, { Color = Theme.Stroke }, 0.2)
        end
    end)
    chipButton.MouseButton1Click:Connect(function()
        editing = true
        valueBox.Text = numbers.format(self_.Value)
        valueLabel.Visible = false
        valueBox.Visible = true
        suffixLabel.Visible = suffix ~= ""
        chipButton.Visible = false
        tween(chipStroke, { Color = Theme.StrokeHover }, 0.12)
        valueBox:CaptureFocus()
        task.defer(fitChip, false)
    end)
    valueBox.FocusLost:Connect(function()
        local typed = tonumber(valueBox.Text)
        editing = false
        valueBox.Visible = false
        suffixLabel.Visible = false
        valueLabel.Visible = true
        chipButton.Visible = true
        tween(chipStroke, { Color = Theme.Stroke }, 0.2)
        if typed then
            self_:Set(typed)
        end
        fitChip(false)
    end)
    hit.MouseEnter:Connect(function()
        if not dragging then
            tween(knobGlow, { ImageTransparency = 0.78, Size = UDim2.fromOffset(34, 34) }, 0.15)
        end
    end)
    hit.MouseLeave:Connect(function()
        if not dragging then
            tween(knobGlow, { ImageTransparency = 0.85, Size = UDim2.fromOffset(28, 28) }, 0.2)
        end
    end)

    local snap = numbers.snap

    local function fraction()
        return (max - min) == 0 and 0 or (self_.Value - min) / (max - min)
    end

    local function moveTo(frac, duration, style)
        style = style or Enum.EasingStyle.Linear
        tween(fill, { Size = UDim2.new(frac, 0, 1, 0) }, duration, style)
        tween(knob, { Position = UDim2.new(frac, 0, 0.5, 0) }, duration, style)
        tween(knobGlow, { Position = UDim2.new(frac, 0, 0.5, 0) }, duration, style)
    end

    local function render(duration, style)
        moveTo(fraction(), duration, style)
        valueLabel.Text = numbers.format(self_.Value) .. suffix
    end

    local function settleTo(previousFrac)
        local target = fraction()
        local width = math.max(track.AbsoluteSize.X, 1)
        local overshoot = (target >= previousFrac and 1 or -1) * (5 / width)
        moveTo(math.clamp(target + overshoot, 0, 1), 0.22, Enum.EasingStyle.Quint)
        task.delay(0.22, function()
            if not dragging then
                moveTo(fraction(), 0.18, Enum.EasingStyle.Quint)
            end
        end)
        valueLabel.Text = numbers.format(self_.Value) .. suffix
    end

    local function bounceKnob()
        tween(knob, { Size = UDim2.fromOffset(14, 12) }, 0.08)
        tween(knobGlow, { Size = UDim2.fromOffset(32, 32), ImageTransparency = 0.78 }, 0.12)
        task.delay(0.1, function()
            tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.25, Enum.EasingStyle.Quint)
            tween(knobGlow, { Size = UDim2.fromOffset(28, 28), ImageTransparency = 0.85 }, 0.25)
        end)
    end

    function self_:Set(value, silent)
        value = snap(tonumber(value) or min)
        if value == self_.Value then
            return
        end
        local previousFrac = fraction()
        self_.Value = value
        if dragging then
            render(0.05)
        else
            settleTo(previousFrac)
            bounceKnob()
            flashStroke(frameStroke)
        end
        if not silent then
            safeCall(opts.Callback, value)
        end
    end

    function self_:Get()
        return self_.Value
    end

    local function updateFromX(x)
        local frac = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        self_:Set(min + (max - min) * frac)
    end

    hit.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            self_.Dragging = true
            tween(knob, { Size = UDim2.fromOffset(16, 16) }, 0.15, Enum.EasingStyle.Back)
            tween(knobGlow, { Size = UDim2.fromOffset(44, 44), ImageTransparency = 0.7 }, 0.15)
            updateFromX(pointerPosition().X)
        end
    end)

    self.Window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            updateFromX(pointerPosition().X)
        end
    end, self_)

    self.Window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            dragging = false
            self_.Dragging = false
            tween(knob, { Size = UDim2.fromOffset(12, 12) }, 0.2)
            tween(knobGlow, { Size = UDim2.fromOffset(28, 28), ImageTransparency = 0.85 }, 0.2)
            safeCall(opts.OnRelease, self_.Value)
        end
    end, self_)

    self_.Value = snap(self_.Value)
    render(0)
    task.defer(fitChip, true)
    return finishElement(self, opts, self_, frame, "Slider")
end

function Tab:Dropdown(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", CurrentOption = "Default", Value = "Default", MultipleOptions = "Multi", Values = "Options" })
    if opts.Multi and type(opts.Default) ~= "table" and opts.Default ~= nil then
        opts.Default = { opts.Default }
    elseif not opts.Multi and type(opts.Default) == "table" then
        opts.Default = opts.Default[1]
    end
    local multi = opts.Multi == true
    local options = opts.Options or {}
    local frame, frameStroke, height
    opts, frame, frameStroke, height = beginElement(self, opts, {}, "Frame")
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local chipHeight = metrics.Chip
    local window = self.Window
    local ROW = TOUCH and 40 or 30
    local MAX_ROWS = opts.MaxRows or 6
    -- Stacked: the chip spans the whole row, with the name (if any) above it.
    local stacked = compact and opts.Stacked == true
    local stackTop = 2
    if stacked then
        stackTop = (opts.Name or "") ~= "" and 20 or 2
        chipHeight = TOUCH and 34 or 30
        height = stackTop + chipHeight + 4
        frame.Size = UDim2.new(1, 0, 0, height)
    end

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })
    local titleLabel, descLabel
    if not stacked then
        titleLabel, descLabel = titleDesc(header, opts.Name or "Dropdown", opts.Desc, 180, metrics)
    elseif stackTop > 2 then
        titleLabel = label({
            Position = UDim2.fromOffset(14, 1),
            Size = UDim2.new(1, -28, 0, 16),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = header,
        })
    end

    local chip = create("Frame", {
        AnchorPoint = stacked and Vector2.zero or Vector2.new(1, 0.5),
        Position = stacked and UDim2.fromOffset(14, stackTop) or UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(60, chipHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = header,
    })
    corner(chip, UDim.new(0, 6))
    local chipStroke = stroke(chip)
    local valueLabel = label({
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -34, 1, 0),
        TextColor3 = Theme.Muted,
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = true,
        Parent = chip,
    })
    local arrow = arrowIndicator(chip, 1, -6)
    local measure = label({
        Size = UDim2.fromOffset(0, chipHeight),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 13,
        Visible = false,
        Parent = chip,
    })
    local fullText = ""
    local function trimmed()
        local maxText = (stacked and frame.AbsoluteSize.X / window.Scale.Scale - 28 or compact and rowControlWidth(frame, window) or 190) - 10 - 34
        measure.Text = fullText
        if measure.TextBounds.X <= maxText then
            return fullText
        end
        local text = fullText
        while #text > 1 do
            text = text:sub(1, -2)
            measure.Text = text .. ".."
            if measure.TextBounds.X <= maxText then
                return text .. ".."
            end
        end
        return ".."
    end
    local function fitChip(instant)
        if stacked then
            chip.Size = UDim2.new(1, -28, 0, chipHeight)
            return
        end
        local width
        if compact then
            width = rowControlWidth(frame, window)
        else
            width = math.clamp(valueLabel.TextBounds.X + 10 + 34, 60, 190)
        end
        reserveRight(titleLabel, descLabel, width + (compact and 24 or 20))
        if instant then
            chip.Size = UDim2.fromOffset(width, chipHeight)
        else
            tween(chip, { Size = UDim2.fromOffset(width, chipHeight) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        if not compact then
            fitChip(false)
        end
    end)
    if compact then
        -- The chip follows the row every frame; re-measuring the text waits
        -- until the width stops changing so resizing stays cheap.
        local lastWidth, pending = 0, false
        frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            local width = frame.AbsoluteSize.X
            if width == lastWidth then
                return
            end
            lastWidth = width
            fitChip(true)
            if not pending then
                pending = true
                task.delay(0.12, function()
                    pending = false
                    valueLabel.Text = trimmed()
                end)
            end
        end)
    end

    -- Popup: floats over the window under the chip, with search, bulk
    -- actions for multi selection and a scrolling list of checkbox rows.
    -- The popup is a plain clipped frame that unfolds out of the chip, so text
    -- stays crisp. The shadow sits outside the clip.
    local popup = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Size = UDim2.fromOffset(220, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 45,
        Parent = window.Body,
    })
    popup:SetAttribute("NoDrag", true)
    local popupShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-18, -12),
        Size = UDim2.new(1, 36, 1, 36),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = popup,
    })
    local panel = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = popup,
    })
    corner(panel, UDim.new(0, 10))
    local panelStroke = stroke(panel, Theme.Stroke, 1)
    edgeHighlight(panel)
    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 120),
        BackgroundTransparency = 1,
        Parent = panel,
    })
    padding(inner, 8, 8, 8, 8)

    local searchHolder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = inner,
    })
    corner(searchHolder, UDim.new(0, 7))
    local searchStroke = stroke(searchHolder)
    local searchIconHolder, searchIcon = glowIcon(searchHolder, "search", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
    searchIconHolder.Size = UDim2.fromOffset(14, 14)
    local searchBox = create("TextBox", {
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -40, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = opts.SearchPlaceholder or "Search",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = searchHolder,
    })
    searchBox.Focused:Connect(function()
        tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    searchBox.FocusLost:Connect(function()
        tween(searchStroke, { Color = Theme.Stroke }, 0.2)
        tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
    end)

    local actions = create("Frame", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundTransparency = 1,
        Visible = multi,
        Parent = inner,
    })
    local function actionButton(text, position)
        local button = create("TextButton", {
            Position = position,
            Size = UDim2.new(0.5, -3, 1, 0),
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            Parent = actions,
        })
        corner(button, UDim.new(0, 6))
        local buttonStroke = stroke(button)
        label({
            Size = UDim2.fromScale(1, 1),
            Text = text,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = button,
        })
        button.MouseEnter:Connect(function()
            tween(button, { BackgroundTransparency = 0.05 }, 0.15)
            tween(buttonStroke, { Color = Theme.StrokeHover }, 0.15)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { BackgroundTransparency = 0.35 }, 0.25)
            tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
        end)
        button.MouseButton1Click:Connect(function()
            ripple(button)
        end)
        return button
    end
    local selectAll = actionButton(opts.SelectAllText or "Select all", UDim2.fromOffset(0, 0))
    local clearAll = actionButton(opts.ClearAllText or "Clear all", UDim2.new(0.5, 3, 0, 0))

    local list = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 100),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        -- Sized by hand: AutomaticCanvasSize under the window's UIScale
        -- sometimes leaves the canvas short, so the list would not scroll.
        CanvasSize = UDim2.new(),
        Parent = inner,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = list,
    })
    local noResults = label({
        Size = UDim2.new(1, 0, 0, ROW),
        Text = opts.NoResultsText or "No results",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 0,
        Visible = false,
        Parent = list,
    })

    local self_ = { Open = false }
    local selected = {}
    local optionButtons = {}
    local filter = ""

    local function matches(option)
        return filter == "" or string.find(string.lower(tostring(option)), filter, 1, true) ~= nil
    end

    -- Option labels are rich text, so the part matching the search can light up.
    local function escapeRich(text)
        return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end
    local function optionText(option)
        local text = tostring(option)
        local at = filter ~= "" and string.find(string.lower(text), filter, 1, true)
        if not at then
            return escapeRich(text)
        end
        local stop = at + #filter - 1
        return escapeRich(text:sub(1, at - 1))
            .. '<font color="#' .. Theme.Accent:ToHex() .. '"><b>' .. escapeRich(text:sub(at, stop)) .. "</b></font>"
            .. escapeRich(text:sub(stop + 1))
    end

    if multi then
        for _, value in ipairs(opts.Default or {}) do
            selected[value] = true
        end
    elseif opts.Default ~= nil then
        selected[opts.Default] = true
    end

    local function currentValue()
        if multi then
            local picked = {}
            for _, option in ipairs(options) do
                if selected[option] then
                    table.insert(picked, option)
                end
            end
            return picked
        end
        for _, option in ipairs(options) do
            if selected[option] then
                return option
            end
        end
        return nil
    end

    -- A picked row rests on a faint accent tint; hovering lifts either kind.
    local function restRow(entry, duration)
        local on, hover = entry.On == true, entry.Hover == true
        tween(entry.Frame, {
            BackgroundColor3 = on and Theme.Accent or Theme.Surface3,
            BackgroundTransparency = on and (hover and 0.8 or 0.88) or (hover and 0.55 or 1),
        }, duration)
        tween(entry.Label, { TextColor3 = (on or hover) and Theme.Text or Theme.Muted }, duration)
    end

    local function paintOption(button, animate)
        local on = selected[button.Option] == true
        if button.On == on and animate then
            return
        end
        button.On = on
        local duration = animate and 0.18 or 0
        restRow(button, duration)
        if multi then
            tween(button.Box, { BackgroundColor3 = on and Theme.Accent or Theme.Surface2 }, duration)
            tween(button.BoxStroke, { Color = on and Theme.Accent or Theme.Stroke }, duration)
        else
            tween(button.Bar, {
                BackgroundTransparency = on and 0 or 1,
                Size = UDim2.fromOffset(3, on and ROW - 14 or 4),
            }, animate and 0.3 or 0, Enum.EasingStyle.Quint)
        end
        tween(button.Check, { ImageTransparency = on and 0 or 1 }, duration)
        if animate and on then
            button.CheckScale.Scale = 0.5
            tween(button.CheckScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Back)
        else
            button.CheckScale.Scale = 1
        end
    end

    local function renderValue(animate)
        local value = currentValue()
        if #options == 0 then
            fullText = opts.EmptyText or "None"
        elseif multi then
            -- Two names at most, then a count, so a long pick stays readable.
            if #value > 2 then
                fullText = tostring(value[1]) .. ", " .. tostring(value[2]) .. "  +" .. (#value - 2)
            else
                fullText = #value > 0 and table.concat(value, ", ") or (opts.NoneText or "None")
            end
        else
            fullText = value ~= nil and tostring(value) or (opts.NoneText or "None")
        end
        valueLabel.Text = trimmed()
        -- A picked value reads in full colour; "None" stays muted.
        local picked = #options > 0 and (if multi then #value > 0 else value ~= nil)
        tween(valueLabel, { TextColor3 = picked and Theme.Text or Theme.Muted }, animate and 0.15 or 0)
        for _, button in pairs(optionButtons) do
            paintOption(button, animate)
        end
    end

    local function visibleCount()
        local count = 0
        for _, option in ipairs(options) do
            if matches(option) then
                count += 1
            end
        end
        return count
    end

    local searchShown = true
    local targetSize = Vector2.new(220, 120)
    local opened = false
    local function layoutPopup(instant)
        searchShown = opts.Searchable ~= false and #options > (opts.SearchAfter or 0)
        searchHolder.Visible = searchShown
        local top = 0
        if searchShown then
            top += 38
        end
        actions.Position = UDim2.fromOffset(0, top)
        if multi and #options > 0 then
            actions.Visible = true
            top += 34
        else
            actions.Visible = false
        end
        local count = visibleCount()
        noResults.Visible = count == 0
        local rows = math.clamp(count, 1, MAX_ROWS)
        local listHeight = rows * ROW + (rows - 1) * 2
        list.CanvasSize = UDim2.fromOffset(0, math.max(count, 1) * (ROW + 2) - 2)
        local scale = window.Scale.Scale
        -- Shrink the list to whichever side of the chip has more room, so the
        -- popup never runs off a short window (phones in landscape).
        local host = window:_popupHost(frame)
        local bodyHeight = host.AbsoluteSize.Y / scale
        local chipTop = (chip.AbsolutePosition.Y - host.AbsolutePosition.Y) / scale
        local room = math.max(bodyHeight - (chipTop + chip.AbsoluteSize.Y / scale) - 14, chipTop - 14) - top - 16
        if room >= ROW then
            listHeight = math.min(listHeight, room)
        end
        list.Position = UDim2.fromOffset(0, top)
        list.Size = UDim2.new(1, 0, 0, listHeight)
        local width = math.max(math.floor(chip.AbsoluteSize.X / scale), opts.PopupWidth or 210)
        local bodyWidth = host.AbsoluteSize.X / scale
        width = math.min(width, math.max(bodyWidth - 16, 120))
        targetSize = Vector2.new(width, top + listHeight + 16)
        inner.Size = UDim2.new(1, 0, 0, targetSize.Y)
        if not opened then
            return
        end
        if instant then
            popup.Size = UDim2.fromOffset(targetSize.X, targetSize.Y)
        else
            tween(popup, { Size = UDim2.fromOffset(targetSize.X, targetSize.Y) }, 0.22, Enum.EasingStyle.Quint)
        end
    end

    local function applyFilter()
        for option, button in pairs(optionButtons) do
            local shown = matches(option)
            button.Frame.Visible = shown
            if shown then
                button.Label.Text = optionText(option)
            end
        end
    end

    local scroller = nil
    local function place()
        local body = window:_popupHost(frame)
        local scale = window.Scale.Scale
        if scroller then
            local centre = chip.AbsolutePosition + chip.AbsoluteSize / 2
            if not pointInside(centre, scroller) then
                self_:SetOpen(false)
                return
            end
        end
        local bodySize = body.AbsoluteSize / scale
        local chipPosition = (chip.AbsolutePosition - body.AbsolutePosition) / scale
        local chipSize = chip.AbsoluteSize / scale
        local right = math.clamp(chipPosition.X + chipSize.X, targetSize.X + 8, math.max(bodySize.X - 8, targetSize.X + 8))
        local below = chipPosition.Y + chipSize.Y + 6
        -- Opening upward pins the content to the bottom edge so it unfolds from the chip.
        if below + targetSize.Y > bodySize.Y - 8 and chipPosition.Y - 6 - targetSize.Y >= 8 then
            popup.AnchorPoint = Vector2.new(1, 1)
            popup.Position = UDim2.fromOffset(right, chipPosition.Y - 6)
            inner.AnchorPoint = Vector2.new(0, 1)
            inner.Position = UDim2.fromScale(0, 1)
        else
            popup.AnchorPoint = Vector2.new(1, 0)
            popup.Position = UDim2.fromOffset(right, below)
            inner.AnchorPoint = Vector2.zero
            inner.Position = UDim2.fromScale(0, 0)
        end
    end

    local stopFollowing = nil
    local closeGeneration = 0
    -- The page behind stops scrolling while the popup is open, so wheel and
    -- swipe input always reach the list instead of dragging the page away.
    local lockedScroller = nil
    local function unlockScroller()
        if lockedScroller then
            lockedScroller.ScrollingEnabled = true
            lockedScroller = nil
        end
    end
    local function scrollToSelected()
        list.CanvasPosition = Vector2.zero
        if multi then
            return
        end
        local value = currentValue()
        if value == nil then
            return
        end
        for index, option in ipairs(options) do
            if option == value then
                list.CanvasPosition = Vector2.new(0, math.max(0, (index - 2) * (ROW + 2)))
                return
            end
        end
    end
    local function setOpen(open)
        if open == self_.Open then
            return
        end
        self_.Open = open
        arrow:Set(open)
        tween(chipStroke, { Color = open and Theme.Accent or Theme.Stroke, Transparency = open and 0.35 or 0 }, 0.2)
        tween(chip, { BackgroundColor3 = open and Theme.Surface2 or Theme.Surface }, 0.2)
        closeGeneration += 1
        if open then
            if window._closePopup and window._closePopup ~= self_._close then
                window._closePopup()
            end
            window._closePopup = self_._close
            scroller = frame:FindFirstAncestorWhichIsA("ScrollingFrame")
            if scroller and scroller.ScrollingEnabled then
                lockedScroller = scroller
                scroller.ScrollingEnabled = false
            end
            -- Drawn over a floating panel when the dropdown lives in one.
            popup.Parent = window:_popupHost(frame)
            filter = ""
            searchBox.Text = ""
            searchBox.PlaceholderText = opts.SearchPlaceholder or (#options > 6 and ("Search " .. #options .. " options") or "Search")
            applyFilter()
            layoutPopup(true)
            renderValue(false)
            scrollToSelected()
            opened = true
            popup.Size = UDim2.fromOffset(targetSize.X, 0)
            place()
            popup.Visible = true
            tween(popup, { Size = UDim2.fromOffset(targetSize.X, targetSize.Y) }, 0.3, Enum.EasingStyle.Quint)
            tween(panelStroke, { Transparency = 0 }, 0.12)
            tween(popupShadow, { ImageTransparency = 0.4 }, 0.3)
            if not stopFollowing then
                stopFollowing = window:_listen("Render", place)
            end
        else
            if window._closePopup == self_._close then
                window._closePopup = nil
            end
            unlockScroller()
            if searchBox:IsFocused() then
                searchBox:ReleaseFocus()
            end
            opened = false
            tween(popup, { Size = UDim2.fromOffset(targetSize.X, 0) }, 0.2, Enum.EasingStyle.Quint)
            tween(popupShadow, { ImageTransparency = 1 }, 0.16)
            local generation = closeGeneration
            task.delay(0.14, function()
                if closeGeneration == generation and not self_.Open then
                    tween(panelStroke, { Transparency = 1 }, 0.06)
                end
            end)
            task.delay(0.21, function()
                if closeGeneration == generation and not self_.Open then
                    popup.Visible = false
                    if stopFollowing then
                        stopFollowing()
                        stopFollowing = nil
                    end
                end
            end)
        end
    end
    self_._close = function()
        setOpen(false)
    end

    local function commit()
        renderValue(true)
        safeCall(opts.Callback, currentValue())
    end

    local function buildOptions()
        local keep = {}
        for index, option in ipairs(options) do
            keep[option] = index
        end
        for option, button in pairs(optionButtons) do
            if not keep[option] then
                button.Frame:Destroy()
                optionButtons[option] = nil
            end
        end
        for index, option in ipairs(options) do
            local existing = optionButtons[option]
            if existing then
                existing.Frame.LayoutOrder = index
                continue
            end
            local row = create("TextButton", {
                Size = UDim2.new(1, -6, 0, ROW),
                BackgroundColor3 = Theme.Surface3,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = list,
            })
            corner(row, UDim.new(0, 7))
            -- Multi selection ticks a checkbox on the left. A single pick
            -- gets an accent bar on the left edge and a check on the right.
            local box, boxStroke, bar, check
            if multi then
                box = create("Frame", {
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 8, 0.5, 0),
                    Size = UDim2.fromOffset(18, 18),
                    BackgroundColor3 = Theme.Surface2,
                    BorderSizePixel = 0,
                    Parent = row,
                })
                corner(box, UDim.new(0, 5))
                boxStroke = stroke(box, Theme.Stroke)
                check = create("ImageLabel", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(12, 12),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.AccentDark,
                    ImageTransparency = 1,
                    ScaleType = Enum.ScaleType.Fit,
                    Parent = box,
                })
            else
                bar = create("Frame", {
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 3, 0.5, 0),
                    Size = UDim2.fromOffset(3, 4),
                    BackgroundColor3 = Theme.Accent,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Parent = row,
                })
                corner(bar, UDim.new(1, 0))
                check = create("ImageLabel", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -10, 0.5, 0),
                    Size = UDim2.fromOffset(14, 14),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Accent,
                    ImageTransparency = 1,
                    ScaleType = Enum.ScaleType.Fit,
                    Parent = row,
                })
            end
            applyIcon(check, "check")
            local checkScale = create("UIScale", { Parent = check })
            local text_ = label({
                Position = UDim2.fromOffset(multi and 36 or 14, 0),
                Size = UDim2.new(1, multi and -44 or -46, 1, 0),
                Text = optionText(option),
                TextSize = 13,
                TextColor3 = Theme.Muted,
                RichText = true,
                Parent = row,
            })
            local entry = { Option = option, Frame = row, Box = box, BoxStroke = boxStroke, Bar = bar, Check = check, CheckScale = checkScale, Label = text_, On = nil, Hover = false }
            local isTap = tapGuard(row, function()
                return list
            end)
            row.MouseEnter:Connect(function()
                -- Touch fires enter without a matching leave; skip the hover.
                if usingTouch() then
                    return
                end
                entry.Hover = true
                restRow(entry, 0.15)
                if boxStroke and not selected[option] then
                    tween(boxStroke, { Color = Theme.StrokeHover }, 0.15)
                end
            end)
            row.MouseLeave:Connect(function()
                entry.Hover = false
                restRow(entry, 0.25)
                if boxStroke and not selected[option] then
                    tween(boxStroke, { Color = Theme.Stroke }, 0.25)
                end
            end)
            row.MouseButton1Click:Connect(function()
                if not isTap() then
                    return
                end
                if selected[option] then
                    if not multi and opts.AllowNone == false then
                        setOpen(false)
                        return
                    end
                    selected[option] = nil
                else
                    if not multi then
                        selected = {}
                    end
                    selected[option] = true
                end
                commit()
                if not multi then
                    setOpen(false)
                end
            end)
            optionButtons[option] = entry
            paintOption(entry, false)
        end
        applyFilter()
        if self_.Open then
            layoutPopup(false)
        end
    end

    selectAll.MouseButton1Click:Connect(function()
        for _, option in ipairs(options) do
            if matches(option) then
                selected[option] = true
            end
        end
        commit()
    end)
    clearAll.MouseButton1Click:Connect(function()
        selected = {}
        commit()
    end)

    function self_:Set(value, silent)
        selected = {}
        if multi then
            for _, item in ipairs(type(value) == "table" and value or { value }) do
                selected[item] = true
            end
        elseif value ~= nil then
            selected[value] = true
        end
        renderValue(self_.Open)
        flashStroke(frameStroke)
        if not silent then
            safeCall(opts.Callback, currentValue())
        end
    end

    function self_:Get()
        return currentValue()
    end

    local function sameValue(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then
            return a == b
        end
        if #a ~= #b then
            return false
        end
        for index, item in ipairs(a) do
            if b[index] ~= item then
                return false
            end
        end
        return true
    end

    -- A kept pick only counts once its option exists, so a list filled in after a
    -- config load changes the value; the callback runs so scripts see it.
    function self_:Refresh(newOptions, keepSelection, silent)
        local before = currentValue()
        options = newOptions or {}
        if not keepSelection then
            selected = {}
        end
        buildOptions()
        renderValue(false)
        if not silent and not sameValue(before, currentValue()) then
            safeCall(opts.Callback, currentValue())
        end
    end

    -- Every pick, including ones whose option isn't in the list right now, so
    -- saving never drops them.
    function self_:_saveValue()
        local picked = currentValue()
        if multi then
            local seen = {}
            for _, item in ipairs(picked) do
                seen[item] = true
            end
            for item in pairs(selected) do
                if not seen[item] then
                    table.insert(picked, item)
                end
            end
            return picked
        end
        if picked == nil then
            picked = next(selected)
        end
        return picked
    end

    function self_:SetOpen(open)
        setOpen(open == true)
    end

    local headerTap = tapGuard(header, function()
        return frame:FindFirstAncestorWhichIsA("ScrollingFrame")
    end)
    header.MouseButton1Click:Connect(function()
        if headerTap() then
            setOpen(not self_.Open)
        end
    end)
    -- The chip answers the pointer before it is opened.
    header.MouseEnter:Connect(function()
        if not self_.Open and not usingTouch() then
            tween(chipStroke, { Color = Theme.StrokeHover }, 0.15)
            tween(chip, { BackgroundColor3 = Theme.Surface2 }, 0.15)
        end
    end)
    header.MouseLeave:Connect(function()
        if not self_.Open then
            tween(chipStroke, { Color = Theme.Stroke }, 0.25)
            tween(chip, { BackgroundColor3 = Theme.Surface }, 0.25)
        end
    end)
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        filter = string.lower(searchBox.Text)
        applyFilter()
        if self_.Open then
            layoutPopup(false)
        end
    end)
    self_._listeners = {
        function()
            setOpen(false)
            unlockScroller()
            if stopFollowing then
                stopFollowing()
                stopFollowing = nil
            end
            popup:Destroy()
        end,
    }
    window:_listen("Began", function(input)
        if not self_.Open then
            return
        end
        if input.KeyCode == Enum.KeyCode.Escape then
            setOpen(false)
        elseif isPress(input) then
            local point = pointerPosition()
            if not pointInside(point, popup) and not pointInside(point, header) then
                setOpen(false)
            end
        end
    end, self_)

    buildOptions()
    renderValue(false)
    task.defer(fitChip, true)
    return finishElement(self, opts, self_, frame, "Dropdown")
end

Library._amountSuffixes = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15, qi = 1e18 }

function Library._parseAmount(text)
    text = string.lower(tostring(text)):gsub("[%s,_%$]", "")
    text = text:gsub("kg$", ""):gsub("/s$", "")
    local number = tonumber(text)
    if number then
        return number
    end
    local digits, suffix = text:match("^(.-)(%a+)$")
    local scale = suffix and Library._amountSuffixes[suffix]
    number = digits and tonumber(digits)
    if number and scale then
        return number * scale
    end
    return nil
end

function Tab:Input(opts)
    local frame, frameStroke, _, titleLabel, descLabel
    opts, frame, frameStroke, _, titleLabel, descLabel = beginElement(self, opts, { Title = "Name", Description = "Desc", PlaceholderText = "Placeholder", CurrentValue = "Default", Value = "Default" }, "Frame", 160, "Input")
    local compact = metricsOf(self).Compact
    local boxHeight = compact and metricsOf(self).Chip + 2 or 30

    local boxHolder = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(170, boxHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(boxHolder, UDim.new(0, 6))
    local boxStroke = stroke(boxHolder)

    local boxIcon = opts.Icon
    if boxIcon then
        glowIcon(boxHolder, boxIcon, Theme.Muted, UDim2.new(0, 8, 0.5, 0))
    end
    local box = create("TextBox", {
        Position = UDim2.fromOffset(boxIcon and 30 or 8, 0),
        Size = UDim2.new(1, boxIcon and -38 or -16, 1, 0),
        BackgroundTransparency = 1,
        Text = opts.Default or "",
        PlaceholderText = opts.Placeholder or "",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = compact and 13 or 14,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = true,
        Parent = boxHolder,
    })
    boxHolder.ClipsDescendants = true

    local lastText = box.Text
    local value = opts.Numeric and Library._parseAmount(lastText) or nil
    if opts.Numeric and not value then
        lastText = ""
    end
    local focused = false
    local textInset = (boxIcon and 30 or 8) + 8
    local function fitBox(instant)
        local width
        if compact then
            width = rowControlWidth(frame, self.Window)
        else
            local cardWidth = frame.AbsoluteSize.X / self.Window.Scale.Scale
            local maxWidth = math.clamp(cardWidth - 14 - 110 - 20, 100, 200)
            local measured = box.TextBounds.X
            if #box.Text == 0 then
                measured = math.min(box.TextBounds.X, 90)
            end
            width = math.clamp(measured + textInset + 12, 90, maxWidth) + (focused and 8 or 0)
            width = math.min(width, maxWidth + 8)
        end
        reserveRight(titleLabel, descLabel, width + (compact and 24 or 20))
        if instant then
            boxHolder.Size = UDim2.fromOffset(width, boxHeight)
        else
            tween(boxHolder, { Size = UDim2.fromOffset(width, boxHeight) }, 0.18)
        end
    end
    local lastWidth = 0
    frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if frame.AbsoluteSize.X ~= lastWidth then
            lastWidth = frame.AbsoluteSize.X
            fitBox(true)
        end
    end)
    box:GetPropertyChangedSignal("Text"):Connect(function()
        fitBox(false)
    end)
    box:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitBox(false)
    end)
    task.defer(fitBox, true)

    box.Focused:Connect(function()
        focused = true
        tween(boxStroke, { Color = Theme.StrokeHover }, 0.15)
        fitBox(false)
    end)
    box.FocusLost:Connect(function(enterPressed)
        focused = false
        tween(boxStroke, { Color = Theme.Stroke }, 0.15)
        fitBox(false)
        if opts.Numeric then
            local number = Library._parseAmount(box.Text)
            if not number then
                box.Text = lastText
                return
            end
            lastText, value = box.Text, number
            safeCall(opts.Callback, number, enterPressed)
            return
        end
        safeCall(opts.Callback, box.Text, enterPressed)
    end)

    return finishElement(self, opts, {
        Set = function(_, newValue)
            box.Text = tostring(newValue)
            if opts.Numeric then
                local number = Library._parseAmount(box.Text)
                if number then
                    lastText, value = box.Text, number
                else
                    box.Text = lastText
                end
            end
            flashStroke(frameStroke)
        end,
        Get = function()
            if opts.Numeric then
                return value
            end
            return box.Text
        end,
        _saveValue = opts.Numeric and function()
            return lastText
        end or nil,
    }, frame, "Input")
end

function Tab:Keybind(opts)
    local frame, frameStroke, _, titleLabel, descLabel
    opts, frame, frameStroke, _, titleLabel, descLabel = beginElement(self, opts, { Title = "Name", Description = "Desc", CurrentKeybind = "Default", Value = "Default" }, "Frame", 110, "Keybind")
    if opts.Default ~= nil then
        opts.Default = Keybinds.Resolve(opts.Default)
    end
    local compact = metricsOf(self).Compact
    local chipHeight = metricsOf(self).Chip

    local chip = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(44, chipHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(chip, UDim.new(0, 6))
    local chipStroke = stroke(chip)
    local chipLabel = label({
        Size = UDim2.new(1, 0, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        Parent = chip,
    })

    local self_ = { Value = opts.Default, Listening = false }

    local function fitChip(instant)
        local width = math.max(chipLabel.TextBounds.X + 20, TOUCH and 44 or 36)
        reserveRight(titleLabel, descLabel, width + (compact and 24 or 20))
        if instant then
            chip.Size = UDim2.fromOffset(width, chipHeight)
        else
            tween(chip, { Size = UDim2.fromOffset(width, chipHeight) }, 0.2)
        end
    end
    chipLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitChip(false)
    end)

    local function render()
        chipLabel.Text = self_.Listening and "..." or keyName(self_.Value)
        tween(chipStroke, { Color = self_.Listening and Theme.StrokeHover or Theme.Stroke }, 0.15)
        tween(chipLabel, { TextColor3 = self_.Listening and Theme.Accent or Theme.Muted }, 0.15)
    end

    function self_:Set(keyCode, silent)
        local wasListening = self_.Listening
        self_.Value = Keybinds.Resolve(keyCode)
        self_.Listening = false
        render()
        if not wasListening then
            flashStroke(frameStroke)
        end
        if not silent then
            safeCall(opts.OnChanged, self_.Value)
        end
        -- The Keybind Menu owns exactly one row per bind. Update only this
        -- bind's row; captures and config loads can call Set many times and
        -- none of them rebuild the list.
        local keybindMenu = self_._keybindMenu
        if keybindMenu and not keybindMenu.Destroyed then
            keybindMenu:_updateRow(self_)
        end
    end

    chip.MouseButton1Click:Connect(function()
        -- The release that closes a mouse-button capture is the same click
        -- that opened it; it must not toggle listening again.
        local wasCapture = self_._capturedBind ~= nil
            or os.clock() - (self_._capturedAt or 0) < 0.4
        self_._capturedBind = nil
        if wasCapture and not self_.Listening then
            return
        end
        self_.Listening = not self_.Listening
        render()
    end)

    self.Window:_listen("Began", function(input, gameProcessed)
        local bind = Keybinds.FromInput(input)
        if bind == nil then
            return
        end
        if self_.Listening then
            self.Window._consumedKey = bind
            self.Window._consumedAt = os.clock()
            if bind == Enum.KeyCode.Escape then
                self_.Listening = false
                render()
            else
                if Keybinds.Mouse[bind] then
                    self_._capturedBind = bind
                    self_._capturedAt = os.clock()
                end
                self_:Set(bind)
            end
            return
        end
        -- Mouse binds stay quiet while the window is open, so clicks meant
        -- for the UI never fire the bound action.
        if not gameProcessed and self_.Value ~= nil and bind == self_.Value
            and not (Keybinds.Mouse[bind] and self.Window.Open and not self.Window.Minimized) then
            safeCall(opts.Callback, bind)
        end
    end, self_)

    self.Window:_listen("Ended", function(input)
        if self_._capturedBind ~= nil and Keybinds.FromInput(input) == self_._capturedBind then
            self_._capturedBind = nil
        end
    end, self_)

    render()
    task.defer(fitChip, true)
    function self_:Get()
        return self_.Value
    end
    self_._onHide = function()
        if self_.Listening then
            self_.Listening = false
            render()
        end
    end
    local element = finishElement(self, opts, self_, frame, "Keybind")
    -- One persistent row per bind, created with the widget and updated in
    -- place afterwards. The display name is the same one the element
    -- registered for search, with the widget's own fallback when the script
    -- left Name empty. The Keybind Menu exists before the window's tabs, so
    -- it is ready here.
    element._keybindName = element._searchName ~= "" and element._searchName or "Keybind"
    local keybindMenu = self.Window.KeybindMenu
    if keybindMenu and not keybindMenu.Destroyed then
        keybindMenu:AddRow(element)
    end
    local destroyElement = element.Destroy
    function element.Destroy(instance)
        local menu = element._keybindMenu
        destroyElement(instance)
        if menu and not menu.Destroyed then
            menu:RemoveRow(element)
        end
    end
    return element
end

function Tab:ColorPicker(opts)
    local PANEL_HEIGHT = 194
    local frame, frameStroke, height
    opts, frame, frameStroke, height = beginElement(self, opts, { Title = "Name", Description = "Desc", Color = "Default", CurrentValue = "Default", Value = "Default" }, "Frame")
    frame.ClipsDescendants = true
    local metrics = metricsOf(self)
    local compact = metrics.Compact

    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = frame,
    })
    titleDesc(header, opts.Name or "Color", opts.Desc, 140, metrics)

    -- Closed, the row shows the hex code beside a rounded swatch.
    local swatch = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -38 or -34, 0.5, 0),
        Size = UDim2.fromOffset(22, 22),
        BorderSizePixel = 0,
        Parent = header,
    })
    corner(swatch, UDim.new(0, 6))
    stroke(swatch, Theme.Stroke)
    local swatchHex = label({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -68 or -64, 0.5, 0),
        Size = UDim2.fromOffset(64, 16),
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = header,
    })
    local arrow = arrowIndicator(header, 1, compact and -14 or -12)

    local panel = create("Frame", {
        Position = UDim2.fromOffset(14, height + 2),
        Size = UDim2.new(1, -28, 0, PANEL_HEIGHT - 12),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = frame,
    })

    -- Saturation runs left to right, brightness top to bottom.
    local svBox = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 118),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = panel,
    })
    corner(svBox, UDim.new(0, 8))
    stroke(svBox, Theme.Stroke)
    local svHueGradient = create("UIGradient", {
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 0, 0)),
        Parent = svBox,
    })
    local svDark = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        Parent = svBox,
    })
    corner(svDark, UDim.new(0, 8))
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Rotation = 90,
        Parent = svDark,
    })

    -- Both handles are a white ring filled with the colour under them, with a
    -- faint dark edge so they read on light and dark spots alike.
    local function knob(parent, size)
        local ring = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = parent,
        })
        corner(ring, UDim.new(1, 0))
        stroke(ring, Color3.new(0, 0, 0), 0.7)
        local fill = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, -4, 1, -4),
            BorderSizePixel = 0,
            ZIndex = 3,
            Parent = ring,
        })
        corner(fill, UDim.new(1, 0))
        return ring, fill
    end
    local svCursor, svFill = knob(svBox, 14)

    -- Hue is a slim horizontal track under the square.
    local hueBar = create("TextButton", {
        Position = UDim2.fromOffset(0, 132),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = panel,
    })
    corner(hueBar, UDim.new(1, 0))
    create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
        }),
        Parent = hueBar,
    })
    local hueCursor, hueFill = knob(hueBar, 16)
    hueCursor.Position = UDim2.fromScale(0, 0.5)

    -- Bottom row: a preview chip and hex field on the left, RGB on the right.
    local hexHolder = create("Frame", {
        Position = UDim2.fromOffset(0, 154),
        Size = UDim2.fromOffset(compact and 110 or 124, 28),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = panel,
    })
    corner(hexHolder, UDim.new(0, 7))
    local hexStroke = stroke(hexHolder)
    local preview = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 6, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        BorderSizePixel = 0,
        Parent = hexHolder,
    })
    corner(preview, UDim.new(0, 4))
    stroke(preview, Theme.Stroke)
    local hexBox = create("TextBox", {
        Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -38, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        TextTruncate = Enum.TextTruncate.None,
        ClipsDescendants = false,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        Parent = hexHolder,
    })
    local rgbLabel = label({
        Position = UDim2.fromOffset(compact and 118 or 134, 154),
        Size = UDim2.new(1, compact and -118 or -134, 0, 28),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = panel,
    })

    local self_ = { Open = false }
    local hue, sat, val = Color3.toHSV(opts.Default or Theme.Accent)
    local dragTarget = nil

    local function toHex(color)
        return string.format("#%02X%02X%02X",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5))
    end

    local function render(duration)
        local color = Color3.fromHSV(hue, sat, val)
        self_.Value = color
        swatch.BackgroundColor3 = color
        preview.BackgroundColor3 = color
        svFill.BackgroundColor3 = color
        hueFill.BackgroundColor3 = Color3.fromHSV(hue, 1, 1)
        swatchHex.Text = toHex(color)
        svHueGradient.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(hue, 1, 1))
        tween(svCursor, { Position = UDim2.fromScale(sat, 1 - val) }, duration, Enum.EasingStyle.Quint)
        tween(hueCursor, { Position = UDim2.fromScale(hue, 0.5) }, duration, Enum.EasingStyle.Quint)
        if not hexBox:IsFocused() then
            hexBox.Text = toHex(color)
        end
        rgbLabel.Text = string.format("%d  %d  %d",
            math.floor(color.R * 255 + 0.5),
            math.floor(color.G * 255 + 0.5),
            math.floor(color.B * 255 + 0.5))
    end

    local function commit(duration, silent)
        render(duration)
        if not silent then
            safeCall(opts.Callback, self_.Value)
        end
    end

    function self_:Set(color, silent)
        hue, sat, val = Color3.toHSV(color)
        commit(0.25, silent)
        flashStroke(frameStroke)
    end

    function self_:Get()
        return self_.Value
    end

    local function setOpen(open)
        self_.Open = open
        tween(frame, { Size = UDim2.new(1, 0, 0, open and (height + PANEL_HEIGHT) or height) }, 0.35, Enum.EasingStyle.Quint)
        arrow:Set(open)
        if open then
            panel.Visible = true
        else
            task.delay(0.35, function()
                if not self_.Open then
                    panel.Visible = false
                end
            end)
        end
    end

    function self_:SetOpen(open)
        setOpen(open == true)
    end

    header.MouseButton1Click:Connect(function()
        setOpen(not self_.Open)
    end)

    local function updateSV(position)
        sat = math.clamp((position.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
        val = 1 - math.clamp((position.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
        commit(0.04)
    end
    local function updateHue(position)
        hue = math.clamp((position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 0.999)
        commit(0.04)
    end

    svBox.InputBegan:Connect(function(input)
        if isPress(input) then
            dragTarget = "sv"
            tween(svCursor, { Size = UDim2.fromOffset(18, 18) }, 0.2, Enum.EasingStyle.Quint)
            updateSV(pointerPosition())
        end
    end)
    hueBar.InputBegan:Connect(function(input)
        if isPress(input) then
            dragTarget = "hue"
            tween(hueCursor, { Size = UDim2.fromOffset(20, 20) }, 0.2, Enum.EasingStyle.Quint)
            updateHue(pointerPosition())
        end
    end)
    self.Window:_listen("Changed", function(input)
        if not dragTarget or not isMove(input) then
            return
        end
        local position = pointerPosition()
        if dragTarget == "sv" then
            updateSV(position)
        else
            updateHue(position)
        end
    end, self_)
    self.Window:_listen("Ended", function(input)
        if dragTarget and isPress(input) then
            dragTarget = nil
            tween(svCursor, { Size = UDim2.fromOffset(14, 14) }, 0.25, Enum.EasingStyle.Quint)
            tween(hueCursor, { Size = UDim2.fromOffset(16, 16) }, 0.25, Enum.EasingStyle.Quint)
        end
    end, self_)

    hexBox.Focused:Connect(function()
        tween(hexStroke, { Color = Theme.StrokeHover }, 0.15)
    end)
    hexBox.FocusLost:Connect(function()
        tween(hexStroke, { Color = Theme.Stroke }, 0.15)
        local r, g, b = hexBox.Text:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            self_:Set(Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)))
        else
            hexBox.Text = toHex(self_.Value)
        end
    end)

    render(0)
    return finishElement(self, opts, self_, frame, "ColorPicker")
end

function Tab:Stepper(opts)
    local frame, frameStroke, _, titleLabel, descLabel
    opts, frame, frameStroke, _, titleLabel, descLabel = beginElement(self, opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default", Increment = "Step" }, "Frame", 150, "Stepper")
    local min = opts.Min or 0
    local max = opts.Max or 100
    local step = opts.Step or 1
    local suffix = opts.Suffix or ""
    local numbers = numberFormat(min, max, step)
    local compact = metricsOf(self).Compact
    local chipHeight = metricsOf(self).Chip

    local group = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, compact and -14 or -10, 0.5, 0),
        Size = UDim2.fromOffset(0, chipHeight),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(group, UDim.new(0, 6))
    local groupStroke = stroke(group)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = group,
    })

    local function stepButton(text, order)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(chipHeight, chipHeight),
            BackgroundTransparency = 1,
            Text = text,
            TextColor3 = Theme.Muted,
            TextSize = 18,
            FontFace = Fonts.Medium,
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = group,
        })
        button.MouseEnter:Connect(function()
            tween(button, { TextColor3 = Theme.Accent }, 0.12)
        end)
        button.MouseLeave:Connect(function()
            tween(button, { TextColor3 = Theme.Muted }, 0.2)
        end)
        return button
    end
    local minus = stepButton("−", 1)
    local valueLabel = label({
        Size = UDim2.new(0, 30, 1, 0),
        TextSize = 13,
        TextColor3 = Theme.Accent,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = group,
    })
    local plus = stepButton("+", 3)
    local function fitValue(instant)
        local width = math.max(valueLabel.TextBounds.X + 12, 30)
        if instant then
            valueLabel.Size = UDim2.new(0, width, 1, 0)
        else
            tween(valueLabel, { Size = UDim2.new(0, width, 1, 0) }, 0.2)
        end
    end
    valueLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        fitValue(false)
    end)
    group:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        reserveRight(titleLabel, descLabel, group.AbsoluteSize.X / self.Window.Scale.Scale + (compact and 24 or 20))
    end)

    local self_ = { Value = math.clamp(opts.Default or min, min, max) }
    local snap = numbers.snap
    local fromButton = false
    local function render()
        valueLabel.Text = numbers.format(self_.Value) .. suffix
        tween(minus, { TextTransparency = self_.Value <= min and 0.6 or 0 }, 0.15)
        tween(plus, { TextTransparency = self_.Value >= max and 0.6 or 0 }, 0.15)
    end
    function self_:Set(value, silent)
        value = snap(tonumber(value) or min)
        if value == self_.Value then
            return
        end
        self_.Value = value
        render()
        if not fromButton then
            flashStroke(frameStroke)
        end
        if not silent then
            safeCall(opts.Callback, value)
        end
    end
    function self_:Get()
        return self_.Value
    end

    local function bump(direction)
        fromButton = true
        self_:Set(self_.Value + direction * step)
        fromButton = false
        tween(groupStroke, { Color = Theme.StrokeHover }, 0.08)
        task.delay(0.12, function()
            tween(groupStroke, { Color = Theme.Stroke }, 0.2)
        end)
    end
    local function holdRepeat(button, direction)
        local holding = false
        button.InputBegan:Connect(function(input)
            if not isPress(input) then
                return
            end
            holding = true
            bump(direction)
            task.delay(0.4, function()
                while holding do
                    bump(direction)
                    task.wait(0.07)
                end
            end)
        end)
        button.InputEnded:Connect(function(input)
            if isPress(input) then
                holding = false
            end
        end)
        button.MouseLeave:Connect(function()
            holding = false
        end)
    end
    holdRepeat(minus, -1)
    holdRepeat(plus, 1)

    render()
    task.defer(fitValue, true)
    return finishElement(self, opts, self_, frame, "Stepper")
end

function Tab:Progress(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", CurrentValue = "Default", Value = "Default" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local extra = compact and 6 or 10
    local frame, frameStroke = card(self, "Frame", (opts.Desc and metrics.DescHeight or metrics.Height) + extra, opts)
    hoverStroke(frame, frameStroke)
    local top
    if opts.Desc then
        top = math.floor((metrics.DescHeight - (metrics.DescGap + metrics.DescLine)) / 2) - 2
    else
        top = compact and 5 or 12
    end

    label({
        Position = UDim2.fromOffset(14, top),
        Size = UDim2.new(1, -110, 0, 18),
        Text = opts.Name or "Progress",
        TextSize = metrics.TextSize,
        Parent = frame,
    })
    if opts.Desc then
        label({
            Position = UDim2.fromOffset(14, top + metrics.DescGap),
            Size = UDim2.new(1, -110, 0, metrics.DescLine),
            Text = opts.Desc,
            TextSize = metrics.DescSize,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = frame,
        })
    end
    local valueLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, top),
        Size = UDim2.fromOffset(90, 18),
        TextXAlignment = Enum.TextXAlignment.Right,
        TextSize = 13,
        TextColor3 = Library._color(opts.TextColor) or Theme.Accent,
        RichText = true,
        Parent = frame,
    })
    local track = create("Frame", {
        Position = UDim2.new(0, 14, 1, compact and -12 or -16),
        Size = UDim2.new(1, -28, 0, 5),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(track, UDim.new(1, 0))
    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = Library._color(opts.Color) or Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(fill, UDim.new(1, 0))

    local self_ = { Value = math.clamp(opts.Default or 0, 0, 1) }
    local formatter = opts.Format
    local function render(duration)
        local frac = self_.Value
        tween(fill, { Size = UDim2.new(frac, 0, 1, 0) }, duration, Enum.EasingStyle.Quint)
        if type(formatter) == "function" then
            valueLabel.Text = Library._rich(formatter(frac))
        else
            valueLabel.Text = string.format("%d%%", math.floor(frac * 100 + 0.5))
        end
    end
    function self_:Set(value, silent)
        value = math.clamp(tonumber(value) or 0, 0, 1)
        if value == self_.Value then
            return
        end
        self_.Value = value
        render(0.35)
        if not silent then
            safeCall(opts.Callback, value)
        end
    end
    function self_:Get()
        return self_.Value
    end
    function self_:SetColor(color)
        tween(fill, { BackgroundColor3 = Library._color(color) or Theme.Accent }, 0.25)
    end
    -- The percentage's colour; nil goes back to the accent.
    function self_:SetTextColor(color)
        tween(valueLabel, { TextColor3 = Library._color(color) or Theme.Accent }, 0.25)
    end
    -- Runs render now, and again on a theme change for theme tags in Format.
    onTheme(valueLabel, function()
        render(0)
    end)
    return finishElement(self, opts, self_, frame, "Progress")
end

-- An always-open list the player puts in order: drag a row (by its grip on
-- touch, anywhere on PC) or nudge it with the arrows. Past MaxRows the list
-- scrolls, and dragging near its top or bottom edge scrolls it along.
function Tab:OrderList(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", Options = "Items", Values = "Items" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local window = self.Window
    local ROW = TOUCH and 40 or 32
    local GAP = 4
    local STEP = ROW + GAP
    local GRIP = TOUCH and 34 or 26
    local ARROW = TOUCH and 30 or 22
    local maxRows = math.max(math.floor(tonumber(opts.MaxRows) or 6), 1)
    local numbered = opts.Numbered ~= false
    local arrows = opts.Arrows ~= false

    local frame = card(self, "Frame", 0, opts)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    if compact then
        padding(frame, 14, 14, 6, 8)
    else
        padding(frame, 14, 14, 11, 12)
    end
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = frame,
    })
    local name = tostring(opts.Name or "")
    label({
        Size = UDim2.new(1, 0, 0, 18),
        Text = name,
        TextSize = metrics.TextSize,
        Visible = name ~= "",
        LayoutOrder = 1,
        Parent = frame,
    })
    if opts.Desc then
        label({
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = opts.Desc,
            TextSize = metrics.DescSize,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = frame,
        })
    end
    local scroller = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, ROW + 2),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        -- Sized by hand, like the dropdown list, so it scrolls under UIScale.
        CanvasSize = UDim2.new(),
        ScrollingEnabled = false,
        LayoutOrder = 3,
        Parent = frame,
    })
    scroller:SetAttribute("NoDrag", true)
    local content = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = scroller,
    })
    local empty = label({
        Size = UDim2.new(1, 0, 0, ROW),
        Text = tostring(opts.EmptyText or "Nothing to order"),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Visible = false,
        Parent = content,
    })

    -- A lucide icon, or a text glyph when the icon set didn't load.
    local function iconButton(parent, icon, glyph, rotation, props)
        props.BackgroundTransparency = 1
        props.Text = ""
        props.AutoButtonColor = false
        props.Parent = parent
        local button = create("TextButton", props)
        local image = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = TOUCH and UDim2.fromOffset(16, 16) or UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = button,
        })
        applyIcon(image, icon)
        if image.Image ~= "" then
            return button, { Object = image, Color = "ImageColor3", Fade = "ImageTransparency" }
        end
        image:Destroy()
        local text_ = label({
            Size = UDim2.fromScale(1, 1),
            Text = glyph,
            TextSize = 18,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            Rotation = rotation,
            Parent = button,
        })
        return button, { Object = text_, Color = "TextColor3", Fade = "TextTransparency" }
    end
    local function tint(icon, color, transparency, duration)
        tween(icon.Object, { [icon.Color] = color, [icon.Fade] = transparency }, duration)
    end

    local self_ = {}
    local entries = {}
    -- The last order Set asked for, including items not in the list right now,
    -- so a saved order still applies once Refresh brings those items in.
    local remembered = {}
    local dragging = nil
    local nudge, beginDrag

    local function slotY(slot)
        return 1 + (slot - 1) * STEP
    end

    local function values()
        local list = {}
        for index, entry in ipairs(entries) do
            list[index] = entry.Value
        end
        return list
    end

    local function layout(instant)
        local count = #entries
        for slot, entry in ipairs(entries) do
            entry.Index.Text = tostring(slot)
            if entry ~= dragging then
                tween(entry.Frame, { Position = UDim2.fromOffset(3, slotY(slot)) }, instant and 0 or 0.22, Enum.EasingStyle.Quint)
            end
            if entry.UpIcon then
                tween(entry.UpIcon.Object, { [entry.UpIcon.Fade] = slot == 1 and 0.7 or 0 }, instant and 0 or 0.15)
                tween(entry.DownIcon.Object, { [entry.DownIcon.Fade] = slot == count and 0.7 or 0 }, instant and 0 or 0.15)
            end
        end
    end

    local function fit()
        local count = #entries
        local canvas = math.max(count, 1) * STEP - GAP + 2
        local shown = math.clamp(count, 1, maxRows)
        local height = shown * STEP - GAP + 2
        local scrolling = count > maxRows
        scroller.Size = UDim2.new(1, 0, 0, height)
        scroller.CanvasSize = UDim2.fromOffset(0, canvas)
        content.Size = UDim2.new(1, scrolling and -8 or 0, 0, canvas)
        if not dragging then
            scroller.ScrollingEnabled = scrolling
        end
        empty.Visible = count == 0
        local maxScroll = math.max(canvas - height, 0)
        if scroller.CanvasPosition.Y > maxScroll then
            scroller.CanvasPosition = Vector2.new(0, maxScroll)
        end
    end

    local function changed(silent)
        self_.Value = values()
        if not silent then
            safeCall(opts.Callback, values())
        end
    end

    local function listScroller()
        if scroller.ScrollingEnabled then
            return scroller
        end
        return frame:FindFirstAncestorWhichIsA("ScrollingFrame")
    end

    local function newEntry(value)
        local row = create("Frame", {
            Size = UDim2.new(1, -6, 0, ROW),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Parent = content,
        })
        corner(row, UDim.new(0, 7))
        local entry = { Value = value, Frame = row }
        entry.Stroke = stroke(row)
        entry.Scale = create("UIScale", { Parent = row })
        local grip
        grip, entry.GripIcon = iconButton(row, "grip-vertical", "=", 0, {
            Size = UDim2.new(0, GRIP, 1, 0),
        })
        local x = GRIP
        entry.Index = label({
            Position = UDim2.fromOffset(x, 0),
            Size = UDim2.new(0, 22, 1, 0),
            TextSize = 12,
            TextColor3 = Theme.Accent,
            TextTruncate = Enum.TextTruncate.None,
            Visible = numbered,
            Parent = row,
        })
        if numbered then
            x += 22
        end
        local right = arrows and ARROW * 2 + 8 or 10
        entry.Text = label({
            Position = UDim2.fromOffset(x, 0),
            Size = UDim2.new(1, -(x + right), 1, 0),
            Text = tostring(value),
            TextSize = 13,
            Parent = row,
        })
        local buttons = {}
        if arrows then
            local up, down
            up, entry.UpIcon = iconButton(row, "chevron-up", "›", -90, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -(ARROW + 6), 0, 0),
                Size = UDim2.new(0, ARROW, 1, 0),
            })
            down, entry.DownIcon = iconButton(row, "chevron-down", "›", 90, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -4, 0, 0),
                Size = UDim2.new(0, ARROW, 1, 0),
            })
            for button, direction in pairs({ [up] = -1, [down] = 1 }) do
                local icon = direction < 0 and entry.UpIcon or entry.DownIcon
                local isTap = tapGuard(button, listScroller)
                button.MouseEnter:Connect(function()
                    if not usingTouch() then
                        tween(icon.Object, { [icon.Color] = Theme.Accent }, 0.12)
                    end
                end)
                button.MouseLeave:Connect(function()
                    tween(icon.Object, { [icon.Color] = Theme.Muted }, 0.2)
                end)
                button.MouseButton1Click:Connect(function()
                    if isTap() then
                        nudge(entry, direction)
                    end
                end)
                table.insert(buttons, button)
            end
        end
        grip.InputBegan:Connect(function(input)
            if isPress(input) then
                beginDrag(entry)
            end
        end)
        -- On PC the whole row drags; on touch only the grip does, so a swipe
        -- across the rows still scrolls.
        row.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                return
            end
            local point = pointerPosition()
            for _, button in ipairs(buttons) do
                if pointInside(point, button) then
                    return
                end
            end
            beginDrag(entry)
        end)
        row.MouseEnter:Connect(function()
            if not usingTouch() and entry ~= dragging then
                tween(entry.Stroke, { Color = Theme.StrokeHover }, 0.12)
                tint(entry.GripIcon, Theme.Text, 0, 0.12)
            end
        end)
        row.MouseLeave:Connect(function()
            if entry ~= dragging then
                tween(entry.Stroke, { Color = Theme.Stroke }, 0.25)
                tint(entry.GripIcon, Theme.Muted, 0, 0.25)
            end
        end)
        return entry
    end

    -- Reuses the rows whose item is still in the list, so a reorder slides
    -- rows instead of rebuilding them.
    local function build(list)
        local pool = {}
        for _, entry in ipairs(entries) do
            pool[entry.Value] = pool[entry.Value] or {}
            table.insert(pool[entry.Value], entry)
        end
        local nextEntries = {}
        for index, value in ipairs(list) do
            local bucket = pool[value]
            local entry = bucket and table.remove(bucket, 1)
            if not entry then
                entry = newEntry(value)
                entry.Frame.Position = UDim2.fromOffset(3, slotY(index))
            end
            nextEntries[index] = entry
        end
        for _, bucket in pairs(pool) do
            for _, entry in ipairs(bucket) do
                entry.Frame:Destroy()
            end
        end
        entries = nextEntries
    end

    -- items sorted by where they sit in ranking; the rest keep their order after.
    local function arrange(items, ranking)
        local left = {}
        for _, value in ipairs(items) do
            left[value] = (left[value] or 0) + 1
        end
        local result = {}
        for _, pass in ipairs({ ranking, items }) do
            for _, value in ipairs(pass) do
                if (left[value] or 0) > 0 then
                    left[value] -= 1
                    table.insert(result, value)
                end
            end
        end
        return result
    end

    local function scrollIntoView(slot)
        local top = slotY(slot) - 1
        local view = scroller.AbsoluteWindowSize.Y / window.Scale.Scale
        local y = scroller.CanvasPosition.Y
        if top < y then
            y = top
        elseif top + ROW + 2 > y + view then
            y = top + ROW + 2 - view
        end
        if y ~= scroller.CanvasPosition.Y then
            tween(scroller, { CanvasPosition = Vector2.new(0, math.max(y, 0)) }, 0.2)
        end
    end

    function nudge(entry, direction)
        if dragging then
            return
        end
        local from = table.find(entries, entry)
        local to = from and from + direction
        if not to or to < 1 or to > #entries then
            return
        end
        entries[from], entries[to] = entries[to], entries[from]
        layout(false)
        tween(entry.Stroke, { Color = Theme.Accent }, 0.08)
        task.delay(0.18, function()
            if entry ~= dragging then
                tween(entry.Stroke, { Color = Theme.Stroke }, 0.3)
            end
        end)
        scrollIntoView(to)
        changed(false)
    end

    local grabOffset, lastPointer = 0, nil
    local startEntries, stopRender, lockedPage = nil, nil, nil

    -- Moves the held row under the pointer and slides the others out of its way.
    local function follow(pointer)
        local scale = window.Scale.Scale
        local y = (pointer.Y - grabOffset - scroller.AbsolutePosition.Y) / scale + scroller.CanvasPosition.Y
        y = math.clamp(y, slotY(1), slotY(#entries))
        dragging.Frame.Position = UDim2.fromOffset(3, y)
        local slot = math.clamp(math.floor((y - 1) / STEP + 0.5) + 1, 1, #entries)
        local current = table.find(entries, dragging)
        if current ~= slot then
            table.remove(entries, current)
            table.insert(entries, slot, dragging)
            layout(false)
        end
    end

    -- Holding the row near the list's top or bottom edge scrolls it, faster
    -- the closer the pointer gets.
    local function autoScroll(deltaTime)
        if not dragging or not lastPointer then
            return
        end
        local scale = window.Scale.Scale
        local top = scroller.AbsolutePosition.Y
        local bottom = top + scroller.AbsoluteSize.Y
        local zone = ROW * scale
        local speed = 0
        if lastPointer.Y < top + zone then
            speed = -(top + zone - lastPointer.Y) / zone
        elseif lastPointer.Y > bottom - zone then
            speed = (lastPointer.Y - (bottom - zone)) / zone
        end
        if speed == 0 then
            return
        end
        local maxScroll = math.max(scroller.CanvasSize.Y.Offset - scroller.AbsoluteWindowSize.Y / scale, 0)
        local y = math.clamp(scroller.CanvasPosition.Y + math.clamp(speed, -1.5, 1.5) * 360 * deltaTime, 0, maxScroll)
        if y ~= scroller.CanvasPosition.Y then
            scroller.CanvasPosition = Vector2.new(0, y)
            follow(lastPointer)
        end
    end

    function beginDrag(entry)
        if dragging or #entries < 2 or self_._destroyed then
            return
        end
        dragging = entry
        startEntries = table.clone(entries)
        lastPointer = pointerPosition()
        grabOffset = lastPointer.Y - entry.Frame.AbsolutePosition.Y
        entry.Frame.ZIndex = 5
        tween(entry.Frame, { BackgroundColor3 = Theme.Surface3 }, 0.12)
        tween(entry.Stroke, { Color = Theme.Accent }, 0.12)
        tween(entry.Scale, { Scale = 1.02 }, 0.18, Enum.EasingStyle.Back)
        tint(entry.GripIcon, Theme.Accent, 0, 0.12)
        -- Neither the list nor the page scrolls under the finger while dragging.
        scroller.ScrollingEnabled = false
        local page = frame:FindFirstAncestorWhichIsA("ScrollingFrame")
        if page and page.ScrollingEnabled then
            lockedPage = page
            page.ScrollingEnabled = false
        end
        stopRender = window:_listen("Render", autoScroll)
    end

    local function endDrag(silent)
        local entry = dragging
        if not entry then
            return
        end
        dragging = nil
        lastPointer = nil
        if stopRender then
            stopRender()
            stopRender = nil
        end
        if lockedPage then
            lockedPage.ScrollingEnabled = true
            lockedPage = nil
        end
        tween(entry.Frame, { BackgroundColor3 = Theme.Surface }, 0.2)
        tween(entry.Stroke, { Color = Theme.Stroke }, 0.25)
        tween(entry.Scale, { Scale = 1 }, 0.2)
        tint(entry.GripIcon, Theme.Muted, 0, 0.25)
        task.delay(0.22, function()
            if entry ~= dragging then
                entry.Frame.ZIndex = 1
            end
        end)
        layout(false)
        fit()
        for index, other in ipairs(entries) do
            if startEntries[index] ~= other then
                changed(silent)
                break
            end
        end
    end

    window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            lastPointer = pointerPosition()
            follow(lastPointer)
        end
    end, self_)
    window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            endDrag(false)
        end
    end, self_)
    table.insert(self_._listeners, function()
        endDrag(true)
    end)
    self_._onHide = function()
        endDrag(false)
    end

    -- Reorders the items already in the list. Unknown items are remembered for
    -- a later Refresh; items missing from the list keep their order after.
    function self_:Set(list, silent)
        if type(list) ~= "table" then
            return
        end
        endDrag(true)
        remembered = table.clone(list)
        build(arrange(values(), remembered))
        layout(false)
        fit()
        changed(silent)
    end

    function self_:Get()
        return values()
    end

    -- Replaces the items. Items that were already there keep the player's
    -- order unless keepOrder is false; new ones go to the end.
    function self_:Refresh(items, keepOrder, silent)
        endDrag(true)
        items = type(items) == "table" and table.clone(items) or {}
        if keepOrder ~= false then
            items = arrange(items, self_:_saveValue())
        else
            remembered = {}
        end
        build(items)
        layout(false)
        fit()
        changed(silent)
    end

    -- The shown order, then remembered items that aren't in the list right now.
    function self_:_saveValue()
        local list = values()
        local left = {}
        for _, value in ipairs(list) do
            left[value] = (left[value] or 0) + 1
        end
        for _, value in ipairs(remembered) do
            if (left[value] or 0) > 0 then
                left[value] -= 1
            else
                table.insert(list, value)
            end
        end
        return list
    end

    build(type(opts.Items) == "table" and opts.Items or {})
    layout(true)
    fit()
    self_.Value = values()
    return finishElement(self, opts, self_, frame, "OrderList")
end


for name, method in pairs(table.clone(Tab)) do
    if type(method) == "function" and name:sub(1, 1) ~= "_" and name:sub(1, 6) ~= "Create" then
        Tab["Create" .. name] = method
    end
end

local function detectExecutor()
    local name
    pcall(function()
        if typeof(identifyexecutor) == "function" then
            name = (identifyexecutor())
        elseif typeof(getexecutorname) == "function" then
            name = getexecutorname()
        end
    end)
    if type(name) == "string" and #name > 0 then
        return name
    end
    return RunService:IsStudio() and "Studio" or "Unknown"
end

local function executorReport(opts)
    local executor = detectExecutor()
    local supported = opts.SupportedExecutors
    if type(supported) == "table" then
        local lowered = string.lower(executor)
        for _, name in ipairs(supported) do
            if string.find(lowered, string.lower(tostring(name)), 1, true) then
                return executor, true, "Your executor is supported and fully compatible."
            end
        end
        return executor, false, "Not on the supported list. Some features may not work."
    end
    local capabilities = {
        { "writefile", writefile },
        { "readfile", readfile },
        { "getcustomasset", getcustomasset },
        { "setclipboard", setclipboard or toclipboard },
        { "request", request or http_request or (syn and syn.request) },
    }
    local missing = {}
    for _, entry in ipairs(capabilities) do
        if type(entry[2]) ~= "function" then
            table.insert(missing, entry[1])
        end
    end
    if #missing == 0 then
        return executor, true, "Your executor is supported and fully compatible."
    end
    return executor, false, "Missing " .. table.concat(missing, ", ") .. ". Some features may not work."
end

-- "Don't ask again" on the unsupported executor warning: the executor's
-- name goes in a file in the script folder, and the warning is skipped while
-- the same executor is in use. Resetting the folder brings it back.
-- A table, not separate locals: the main chunk is at Luau's 200 local limit.
local UnsupportedSkip = {}

function UnsupportedSkip.Path(folder)
    return tostring(folder) .. "/unsupported_skip.txt"
end

function UnsupportedSkip.Available()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

function UnsupportedSkip.Saved(folder, executor)
    if not UnsupportedSkip.Available() then
        return false
    end
    local path = UnsupportedSkip.Path(folder)
    local ok, saved = pcall(function()
        return isfile(path) and readfile(path) or nil
    end)
    return ok and saved == executor
end

function UnsupportedSkip.Write(folder, path, content)
    if not UnsupportedSkip.Available() then
        return false
    end
    return pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local built = ""
            for segment in tostring(folder):gmatch("[^/\\]+") do
                built = built == "" and segment or built .. "/" .. segment
                if not isfolder(built) then
                    makefolder(built)
                end
            end
        end
        writefile(path, content)
    end)
end

function UnsupportedSkip.Save(folder, executor)
    return UnsupportedSkip.Write(folder, UnsupportedSkip.Path(folder), executor)
end

-- Custom disclaimers ticked "Don't show again": one key per line in
-- disclaimers.txt. The key is the disclaimer's Id, or a hash of its title
-- and text, so rewording a disclaimer shows it again.
function UnsupportedSkip.DisclaimerKey(entry)
    if entry.Id ~= nil then
        return (tostring(entry.Id):gsub("[\r\n]", " "))
    end
    local source = tostring(entry.Title) .. "\0" .. tostring(entry.Text)
    local hash = 5381
    for index = 1, #source do
        hash = (hash * 33 + source:byte(index)) % 4294967296
    end
    return string.format("%08x", hash)
end

function UnsupportedSkip.DisclaimerAccepted(folder, key)
    if not UnsupportedSkip.Available() then
        return false
    end
    local path = tostring(folder) .. "/disclaimers.txt"
    local ok, saved = pcall(function()
        return isfile(path) and readfile(path) or ""
    end)
    if not ok or type(saved) ~= "string" then
        return false
    end
    for line in saved:gmatch("[^\r\n]+") do
        if line == key then
            return true
        end
    end
    return false
end

function UnsupportedSkip.AcceptDisclaimer(folder, key)
    if UnsupportedSkip.DisclaimerAccepted(folder, key) then
        return true
    end
    local path = tostring(folder) .. "/disclaimers.txt"
    local ok, saved = pcall(function()
        return isfile(path) and readfile(path) or ""
    end)
    saved = ok and type(saved) == "string" and saved or ""
    if saved ~= "" and not saved:match("\n$") then
        saved ..= "\n"
    end
    return UnsupportedSkip.Write(folder, path, saved .. key .. "\n")
end

local gameInfoCache = nil

local function fetchGameInfo()
    if gameInfoCache == nil then
        local ok, info = pcall(function()
            return MarketplaceService:GetProductInfo(game.PlaceId)
        end)
        gameInfoCache = ok and type(info) == "table" and info or false
    end
    return gameInfoCache or nil
end

local function detectGameName()
    local info = fetchGameInfo()
    if info and info.Name then
        return info.Name
    end
    return RunService:IsStudio() and "Studio" or "Unknown game"
end

local REGION_NAMES = {
    US = "United States", GB = "United Kingdom", DE = "Germany", FR = "France",
    NL = "Netherlands", SG = "Singapore", JP = "Japan", AU = "Australia",
    BR = "Brazil", IN = "India", HK = "Hong Kong", CA = "Canada",
}

local function detectRegion(callback)
    task.spawn(function()
        local requester = request or http_request or (syn and syn.request) or (http and http.request)
        local region
        if type(requester) == "function" then
            pcall(function()
                local response = requester({ Url = "https://ipinfo.io/json", Method = "GET" })
                local body = type(response) == "table" and (response.Body or response.body) or nil
                if type(body) == "string" then
                    local data = HttpService:JSONDecode(body)
                    if type(data) == "table" and data.country then
                        local label = REGION_NAMES[data.country] or data.country
                        region = data.city and (data.city .. ", " .. label) or label
                    end
                end
            end)
        end
        callback(region or "Unavailable")
    end)
end

local NOTIFY_COLORS = setmetatable({}, {
    __index = function(_, kind)
        if kind == "Success" or kind == "Warning" or kind == "Error" then
            return Theme[kind]
        end
        return nil
    end,
})

local Window = {}
Window.__index = Window

function Library.Window(_, opts)
    opts = normalize(opts, { Name = "Title", LoadingSubtitle = "Subtitle", ToggleUIKeybind = "Keybind" })

    if type(opts.AutoTranslate) == "boolean" then
        Library.AutoTranslate = opts.AutoTranslate
    end

    if type(opts.ForceCheckbox) == "boolean" then
        Library:SetForceCheckbox(opts.ForceCheckbox)
    end

    opts.Keybind = Keybinds.Resolve(opts.Keybind)
    local size = opts.Size or UDim2.fromOffset(760, 520)
    local keybind = opts.Keybind or Enum.KeyCode.RightControl

    local logoIcon = opts.Icon
    if logoIcon == nil then
        logoIcon = Assets.Logo
    end
    local self = setmetatable({
        Tabs = {},
        CurrentTab = nil,
        Open = true,
        Keybind = keybind,
        _connections = {},
        _controls = {},
        _inputListeners = { Began = {}, Changed = {}, Ended = {}, Render = {} },
        _frameSteps = {},
        _destroyed = false,
        _identity = { Names = {}, Avatars = {} },
        _pinned = {},
        Minimized = false,
        _hideName = false,
        _hideAvatar = false,
        Title = opts.Title or opts.Name or "Aster UI",
        _logoIcon = logoIcon,
        _sessionStart = os.clock(),
        _islandLocked = opts.IslandDraggable == false,
    }, Window)
    local saving = type(opts.ConfigurationSaving) == "table" and opts.ConfigurationSaving or {}
    self.ConfigFolder = saving.FolderName or "AsterUI"
    self.ConfigName = saving.FileName
    self._configListeners = {}
    self._pendingFlags = {}

    local startTheme = opts.DefaultTheme or opts.Theme
    if startTheme ~= nil then
        Library.DefaultTheme = startTheme
    end
    self:_applyDefaultTheme()
    self._uiScale = math.clamp(tonumber(opts.UIScale) or 1, 0.6, 1.5)
    self._adaptive = opts.AdaptiveSize ~= false
    self.UIScale = self._uiScale
    if opts.Density ~= nil then
        Library:SetDensity(opts.Density)
    end
    if opts.CornerRadius ~= nil then
        Library:SetCornerRadius(opts.CornerRadius, true)
    end
    local function dispatch(kind)
        return function(...)
            for _, handler in ipairs(self._inputListeners[kind]) do
                handler(...)
            end
        end
    end
    local renderDispatch = dispatch("Render")
    table.insert(self._connections, RunService.RenderStepped:Connect(function(deltaTime)
        renderDispatch(deltaTime)
        for _, step in ipairs(self._frameSteps) do
            step(deltaTime)
        end
    end))
    table.insert(self._connections, UserInputService.InputBegan:Connect(dispatch("Began")))
    table.insert(self._connections, UserInputService.InputChanged:Connect(dispatch("Changed")))
    table.insert(self._connections, UserInputService.InputEnded:Connect(dispatch("Ended")))

    local gui = create("ScreenGui", {
        Name = opts.Name or "AsterUI",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        DisplayOrder = 999,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    self.Gui = gui
    self.AlwaysOnTop = opts.AlwaysOnTop == true
    Library._SetAlwaysOnTop(gui, self.AlwaysOnTop)

    -- Engine-level cursor release: while a visible button with Modal = true
    -- exists, the mouse stays movable even when the game holds it locked to
    -- the centre (first person). Kept zero-sized so it can never swallow a
    -- click; only the flag matters.
    self._modal = create("TextButton", {
        Name = "Modal",
        BackgroundTransparency = 1,
        Modal = false,
        Size = UDim2.fromScale(0, 0),
        Text = "",
        ZIndex = -999,
        Parent = gui,
    })

    -- Drawn cursor: a game that hides the system cursor to aim would leave
    -- the freed mouse invisible. While the window is open the library draws
    -- its own cross and follows the pointer, the same build as Obsidian's:
    -- 3px dark bars with 1px white inner lines.
    local cursor = create("Frame", {
        Name = "Cursor",
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(1, 1),
        Visible = false,
        ZIndex = 11000,
        Parent = gui,
    })
    local cross = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(11, 11),
        Parent = cursor,
    })
    create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.new(0, 0, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, 0, 0, 3),
        ZIndex = 1,
        Parent = cross,
    })
    create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -2, 0, 1),
        ZIndex = 2,
        Parent = cross,
    })
    create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.new(0, 0, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 3, 1, 0),
        ZIndex = 1,
        Parent = cross,
    })
    create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 1, 1, -2),
        ZIndex = 2,
        Parent = cross,
    })
    self._cursor = cursor
    self._cursorBinding = "AsterCursor_" .. string.sub(tostring({}), 10)
    self._originalMouseIconEnabled = UserInputService.MouseIconEnabled

    local root = create("Frame", {
        Name = "Window",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = size,
        BackgroundTransparency = 1,
        Parent = gui,
    })
    self.Root = root
    local scale = create("UIScale", { Parent = root })
    self.Scale = scale

    local shadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-25, -25),
        Size = UDim2.new(1, 50, 1, 50),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.6,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = root,
    })
    self.Shadow = shadow
    self._shadowRest = 0.6

    -- The body is a plain Frame so resizing never re-renders the window into a
    -- texture. It only moves into the fader CanvasGroup while fading.
    local fader = create("CanvasGroup", {
        Name = "Fader",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        GroupTransparency = 1,
        ZIndex = 2,
        Parent = root,
    })
    self._fader = fader
    self._bodyAlpha = 1
    local body = create("Frame", {
        Name = "Body",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = fader,
    })
    self.Body = body
    corner(body, UDim.new(0, 10))
    self.BodyStroke = stroke(body, Theme.Stroke)
    edgeHighlight(body)
    -- Background image: made first so everything else in the body draws over it.
    self._backgroundImage = create("ImageLabel", {
        Name = "BackgroundImage",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Crop,
        ImageTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = body,
    })
    corner(self._backgroundImage, UDim.new(0, 10))
    self.BackgroundTransparency = math.clamp(tonumber(opts.BackgroundTransparency) or 0.35, 0, 1)
    self._backgroundGeneration = 0

    -- The sidebar is a flush, solid rail down the left edge, split from the
    -- content by a single hairline.
    local sidebar = create("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = body,
    })
    self.Sidebar = sidebar
    -- One rounded fill that runs past the rail's right edge, where the rail
    -- clips it: the left corners round with the window, the right edge is
    -- square, and nothing overlaps, so it fades evenly when see-through.
    local sidebarFill = create("Frame", {
        Name = "Fill",
        Size = UDim2.new(1, 24, 1, 0),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = sidebar,
    })
    corner(sidebarFill, UDim.new(0, 10))
    self.SidebarFill = sidebarFill
    create("Frame", {
        Name = "Divider",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = sidebar,
    })

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
        BackgroundTransparency = 1,
        Parent = sidebar,
    })
    if opts.Icon ~= false then
        local logo = create("ImageLabel", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 14, 0.5, 0),
            Size = UDim2.fromOffset(32, 32),
            BackgroundTransparency = 1,
            Image = "",
            ImageColor3 = Color3.new(1, 1, 1),
            ScaleType = Enum.ScaleType.Fit,
            Parent = header,
        })
        applyIcon(logo, opts.Icon or Assets.Logo, true)
    end
    -- No logo: the title and subtitle take its place, aligned with the tab
    -- labels' column.
    local TEXT_X = opts.Icon ~= false and 56 or 22
    local subtitle = opts.Version or opts.Subtitle
    label({
        Position = UDim2.new(0, TEXT_X, 0.5, subtitle and -15 or -9),
        Size = UDim2.new(1, -(TEXT_X + 12), 0, 18),
        Text = self.Title,
        TextSize = 14,
        FontFace = Fonts.Bold,
        Parent = header,
    })
    if subtitle then
        label({
            Position = UDim2.new(0, TEXT_X, 0.5, 3),
            Size = UDim2.new(1, -(TEXT_X + 12), 0, 14),
            Text = tostring(subtitle),
            TextSize = 11,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = header,
        })
    end

    local profileEnabled = opts.Profile ~= false
    local tabList = create("ScrollingFrame", {
        Name = "Tabs",
        Position = UDim2.fromOffset(0, HEADER_HEIGHT),
        Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + (profileEnabled and PROFILE_HEIGHT + 4 or 12))),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = sidebar,
    })
    self.TabList = tabList
    -- The highlight sits beside the stack of buttons, so it scrolls and clips
    -- with them and glides between tiles.
    local indicator = create("Frame", {
        Position = UDim2.fromOffset(8, 2),
        Size = UDim2.new(1, -16, 0, TAB_TILE_HEIGHT),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        Parent = tabList,
    })
    corner(indicator, UDim.new(0, 7))
    -- The active tab is just a quiet neutral fill with white text; the bar
    -- is kept for callers but stays hidden.
    local pill = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(2, 14),
        BackgroundColor3 = Theme.Accent,
        Visible = false,
        BorderSizePixel = 0,
        Parent = indicator,
    })
    corner(pill, UDim.new(1, 0))
    self._indicatorPill = pill
    self.Indicator = indicator
    local stack = create("Frame", {
        Name = "Stack",
        Position = UDim2.fromOffset(8, 2),
        Size = UDim2.new(1, -16, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = tabList,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = stack,
    })
    self._tabStack = stack

    -- More tabs than fit: a fade and a small "more" chip at the hidden end.
    self:_overflowHint(sidebar, tabList, stack, true, Theme.Surface)

    if profileEnabled then
        self:_buildProfile(sidebar)
    end

    local content = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(SIDEBAR_WIDTH + 1, 0),
        Size = UDim2.new(1, -(SIDEBAR_WIDTH + 1), 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = body,
    })
    self.Content = content
    self:_sidebarResize(sidebar, tonumber(opts.SidebarWidth) or SIDEBAR_WIDTH)
    self._outLayer = create("CanvasGroup", {
        Name = "TransitionOut",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 2,
        Parent = content,
    })
    self._inLayer = create("CanvasGroup", {
        Name = "TransitionIn",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 3,
        Parent = content,
    })

    local minimizeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0, 14),
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = content,
    })
    minimizeButton:SetAttribute("NoDrag", true)
    -- A bare "minimize" arrows glyph, no box: muted at rest, full text
    -- colour and a touch smaller on hover, as if pulling in.
    local minimizeGlyph = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = minimizeButton,
    })
    applyIcon(minimizeGlyph, "minimize-2")
    minimizeButton.MouseEnter:Connect(function()
        tween(minimizeGlyph, { ImageColor3 = Theme.Text, Size = UDim2.fromOffset(18, 18) }, 0.2, Enum.EasingStyle.Quint)
    end)
    minimizeButton.MouseLeave:Connect(function()
        tween(minimizeGlyph, { ImageColor3 = Theme.Muted, Size = UDim2.fromOffset(20, 20) }, 0.25, Enum.EasingStyle.Quint)
    end)
    minimizeButton.MouseButton1Click:Connect(function()
        self:Minimize()
    end)
    self.MinimizeButton = minimizeButton

    if opts.Search ~= false then
        self:_buildSearch(content)
    end

    local notifyHolder = create("Frame", {
        Name = "Notifications",
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -20, 1, -20),
        Size = UDim2.new(0, 280, 1, -40),
        BackgroundTransparency = 1,
        Parent = gui,
    })
    local function fitToasts()
        notifyHolder.Size = UDim2.new(0, math.min(280, gui.AbsoluteSize.X - 40), 1, -40)
    end
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToasts))
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        Padding = UDim.new(0, 4),
        Parent = notifyHolder,
    })
    self.NotifyHolder = notifyHolder
    self._notifyOrder = 0
    self._toasts = {}
    self.MaxNotifications = opts.MaxNotifications or 4

    self._controlsDirty = true
    table.insert(self._connections, body.DescendantAdded:Connect(function()
        self._controlsDirty = true
    end))
    table.insert(self._connections, body.DescendantRemoving:Connect(function()
        self._controlsDirty = true
    end))

    self:SetDragStyle(opts.DragStyle or (opts.DragSkeleton == false and "Off" or "Outline"))
    self:SetIslandStyle(opts.IslandStyle)
    if opts.Transparent then
        self:SetTransparent(true)
    end
    if opts.Background then
        task.spawn(self.SetBackground, self, opts.Background)
    end
    self:_enableDrag()
    self.MaxSize = opts.MaxSize
    self.KeepOnScreen = opts.KeepOnScreen ~= false
    self.UnlockMouseWhileOpen = opts.UnlockMouseWhileOpen ~= false
    self.ShowCustomCursor = opts.ShowCustomCursor ~= false
    self:_enableResize(opts.MinSize or Vector2.new(480, 360))
    -- The window's exact size rides along in configs as a hidden flag.
    if opts.SaveSize ~= false then
        local window = self
        local sizeFlag = { _type = "WindowSize", _listeners = {} }
        function sizeFlag:Get()
            local current = window:GetSize()
            return { Width = current.X, Height = current.Y }
        end
        function sizeFlag:Set(value)
            if type(value) == "table" and tonumber(value.Width) and tonumber(value.Height) then
                window:SetSize(Vector2.new(tonumber(value.Width), tonumber(value.Height)))
            end
        end
        local flag = type(opts.SaveSize) == "string" and opts.SaveSize or "__WindowSize"
        Library.Flags[flag] = sizeFlag
        self:_flagCreated(flag, sizeFlag)
    end

    table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then
            return
        end
        local bind = Keybinds.FromInput(input)
        if bind ~= nil and bind == self.Keybind then
            task.defer(function()
                local consumed = self._consumedKey == bind and os.clock() - (self._consumedAt or 0) < 0.2
                self._consumedKey = nil
                if not consumed and not self._destroyed then
                    if self.Minimized then
                        self:Restore()
                    else
                        self:Toggle(not self.Open)
                    end
                end
            end)
        end
    end))

    pcall(function()
        if typeof(syn) == "table" and typeof(syn.protect_gui) == "function" then
            syn.protect_gui(gui)
        end
    end)
    gui.Parent = opts.Parent or defaultParent()

    scale.Scale = 0.9
    shadow.ImageTransparency = 1
    self.BodyStroke.Transparency = 1
    root.Visible = false
    self:_fitToScreen(true)
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        self:_fitToScreen()
        self:_clampToScreen()
    end))
    local toggleOpts = opts.ToggleButton
    if toggleOpts == nil or toggleOpts == true then
        toggleOpts = {}
    end
    if type(toggleOpts) == "table" then
        self:_createToggleButton(toggleOpts)
    end
    -- The toggle button already brings a hidden window back.
    local toggleShown = self.ToggleButton ~= nil and self:_toggleButtonAllowed()
    if (opts.OpenButton ~= nil and opts.OpenButton ~= false) or (opts.OpenButton == nil and TOUCH and not toggleShown) then
        self:_createOpenButton(type(opts.OpenButton) == "table" and opts.OpenButton or {})
    end
    if opts.Backdrop ~= false then
        local backdrop = type(opts.Backdrop) == "table" and opts.Backdrop or {}
        -- A top-level Weather option feeds the backdrop unless the Backdrop
        -- table carries its own; the caller's table is left untouched.
        if opts.Weather ~= nil and backdrop.Weather == nil then
            local merged = {}
            for key, value in pairs(backdrop) do
                merged[key] = value
            end
            merged.Weather = opts.Weather
            backdrop = merged
        end
        self:_buildBackdrop(backdrop)
    end
    self._introDone = false

    table.insert(Library.Windows, self)

    -- Obsidian's Keybind Menu: a floating list of every Keybind in this
    -- window, hidden until opened (Window:SetKeybindMenu, the Theme Manager
    -- toggle, or KeybindMenu = true here).
    local keybindMenu = Library:_createKeybindMenu(self)
    if opts.KeybindMenu == true then
        keybindMenu:SetVisible(true)
    end

    if opts.Home ~= false then
        self:_buildHome(type(opts.Home) == "table" and opts.Home or {})
    end

    local loading = opts.Loading
    if type(loading) == "table" then
        opts.LoadingDuration = loading.Duration or opts.LoadingDuration
        opts.LoadingText = loading.Text or loading.Subtitle or opts.LoadingText
        opts.LoadingSteps = loading.Steps or opts.LoadingSteps
        opts.LoadingTitle = loading.Title or opts.LoadingTitle
        loading = loading.Enabled ~= false
    end
    -- An executor off the supported list (or missing the file / asset API)
    -- stops at a warning card before the window opens.
    local prompts = {}
    local gate = opts.UnsupportedExecutor
    if gate ~= false then
        gate = type(gate) == "table" and gate or {}
        local list = opts.SupportedExecutors or (type(opts.Home) == "table" and opts.Home.SupportedExecutors or nil)
        local executor, supported, message = executorReport({ SupportedExecutors = list })
        if not supported and not UnsupportedSkip.Saved(self.ConfigFolder, executor) then
            local block = gate.Block == true
            local folder = self.ConfigFolder
            table.insert(prompts, {
                Title = gate.Title or "Unsupported executor",
                Subtitle = executor,
                Text = block and ((gate.Text or message) .. " This script can't run here.") or (gate.Text or message),
                Icon = "shield-alert",
                Color = Theme.Warning,
                ContinueText = "Continue anyway",
                ExitText = "Exit",
                Block = block,
                RememberText = "Don't ask again on this executor",
                Remember = function()
                    UnsupportedSkip.Save(folder, executor)
                end,
            })
        end
    end
    -- Custom disclaimers queue up after the executor warning, in order. Each
    -- one must be accepted (or skipped by an earlier "Don't show again").
    local disclaimers = opts.Disclaimer or opts.Disclaimers
    if type(disclaimers) == "string" or (type(disclaimers) == "table" and (disclaimers.Title ~= nil or disclaimers.Text ~= nil)) then
        disclaimers = { disclaimers }
    end
    if type(disclaimers) == "table" then
        for _, entry in ipairs(disclaimers) do
            if type(entry) == "string" then
                entry = { Text = entry }
            end
            if type(entry) == "table" then
                local key = UnsupportedSkip.DisclaimerKey(entry)
                local folder = self.ConfigFolder
                local block = entry.Block == true
                local rememberable = entry.Remember ~= false and not block
                if not (rememberable and UnsupportedSkip.DisclaimerAccepted(folder, key)) then
                    local callback = entry.Callback
                    local entryIcon = cleanIcon(entry.Icon)
                    if entryIcon == nil then
                        entryIcon = "info"
                    end
                    table.insert(prompts, {
                        Title = entry.Title or "Disclaimer",
                        Subtitle = entry.Subtitle,
                        Text = entry.Text or "",
                        Icon = entryIcon,
                        Color = entry.Color or Theme.Accent,
                        ContinueText = entry.AcceptText or "I understand",
                        ExitText = entry.DeclineText == nil and "Exit" or entry.DeclineText,
                        RememberText = rememberable and (entry.RememberText or "Don't show again") or nil,
                        Remember = function()
                            UnsupportedSkip.AcceptDisclaimer(folder, key)
                        end,
                        Callback = type(callback) == "function" and callback or nil,
                        Block = block,
                    })
                end
            end
        end
    end
    if #prompts > 0 then
        opts._prompts = prompts
    end
    if loading == false and opts._prompts then
        opts.LoadingDuration = opts.LoadingDuration or 0.5
        loading = true
    end
    if loading == false then
        task.defer(function()
            self:_playIntro()
        end)
    else
        self:_showLoader(opts)
    end
    return self
end

Library.CreateWindow = Library.Window



function Library:Notify(opts)
    local window = Library.Windows[#Library.Windows]
    if window then
        return window:Notify(opts)
    end
end

function Library:Confirm(opts)
    local window = Library.Windows[#Library.Windows]
    if window then
        return window:Confirm(opts)
    end
end

function Library:Dialog(opts)
    local window = Library.Windows[#Library.Windows]
    if window then
        return window:Dialog(opts)
    end
end

-- Draggable overlays: Obsidian's watermark chip rebuilt with the window's own
-- colours and font, so it follows every theme change. Overlays draw 10%
-- larger than the window's UI scale and follow it live (library default). They
-- live in the newest window's screen gui (above the window body and its dim,
-- below the pop-out layer, the toggle button, the tooltip and the cursor),
-- drag with mouse or touch, and are destroyed together with the window. The
-- Keybind Menu registers here too, so it shares the same scale and clamping.
Library._draggableLabels = {}
-- Overlay UI scale: a touch above the window's own scale, so watermarks stay
-- readable over the game.
local OVERLAY_UI_SCALE = 1.1

function Library:AddDraggableLabel(...)
    local params = select(1, ...)
    local text, icon, iconPosition, startPosition, requestedWindow
    if typeof(params) == "table" then
        text = params.Text
        icon = params.Icon
        iconPosition = params.IconPosition
        startPosition = params.Position
        -- Optional owner window: with more than one window on screen the
        -- newest one is not always the one the caller means.
        requestedWindow = params.Window
    elseif typeof(params) == "string" then
        text = params
        icon = select(2, ...)
        iconPosition = select(3, ...)
    end
    icon = cleanIcon(icon)
    if typeof(startPosition) == "table" then
        local x = tonumber(startPosition.X or startPosition[1])
        local y = tonumber(startPosition.Y or startPosition[2])
        startPosition = (x and y) and Vector2.new(x, y) or nil
    end
    if typeof(startPosition) ~= "Vector2" then
        startPosition = nil
    end
    if type(requestedWindow) ~= "table" then
        requestedWindow = nil
    end
    if typeof(iconPosition) ~= "string" then
        iconPosition = "left"
    end
    iconPosition = string.lower(iconPosition)
    if iconPosition ~= "right" then
        iconPosition = "left"
    end

    local window = requestedWindow or Library.Windows[#Library.Windows]
    if not window or not window.Gui or window._destroyed then
        warn("[Aster UI] AddDraggableLabel needs a window: create one first.")
        return nil
    end
    local gui = window.Gui
    local offset = Vector2.new(6, 6)

    local entry = {
        Connections = {},
        Destroyed = false,
    }

    local pill = create("TextButton", {
        Name = "DraggableLabel",
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 5,
        Parent = gui,
    })
    entry.Label = pill

    corner(pill, UDim.new(0, 6))
    stroke(pill, Theme.Stroke)
    local pad = padding(pill, 12, 12, 6, 6)
    local scale = create("UIScale", { Scale = window:GetUIScale() * OVERLAY_UI_SCALE, Parent = pill })
    entry._scale = scale

    local textLabel = label({
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        Text = text ~= nil and tostring(text) or "",
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.None,
        ZIndex = 2,
        Parent = pill,
    })

    local iconImage
    local function hasIcon()
        return icon ~= nil and icon ~= false and tostring(icon):match("%S") ~= nil
    end

    -- The pill grows a 34px strip on the icon's side and the icon sits in it,
    -- the same layout Obsidian uses.
    local function updateIconLayout()
        local filled = hasIcon()
        pad.PaddingLeft = UDim.new(0, (filled and iconPosition == "left") and 34 or 12)
        pad.PaddingRight = UDim.new(0, (filled and iconPosition == "right") and 34 or 12)
        if iconImage then
            if iconPosition == "left" then
                iconImage.AnchorPoint = Vector2.new(0, 0.5)
                iconImage.Position = UDim2.new(0, -22, 0.5, 0)
            else
                iconImage.AnchorPoint = Vector2.new(1, 0.5)
                iconImage.Position = UDim2.new(1, 22, 0.5, 0)
            end
        end
    end

    local function applyCurrentIcon()
        if hasIcon() then
            iconImage = iconImage or create("ImageLabel", {
                Name = "Icon",
                BackgroundTransparency = 1,
                ImageColor3 = Theme.Text,
                Size = UDim2.fromOffset(16, 16),
                ZIndex = 2,
                Parent = pill,
            })
            applyIcon(iconImage, icon, true)
        end
        if iconImage then
            iconImage.Visible = hasIcon()
        end
        updateIconLayout()
    end

    local dragging = false
    local dragOrigin = Vector2.zero
    local dragStart = Vector2.zero

    local measureClampQueued = false
    local function placeAt(point)
        local viewport = gui.AbsoluteSize
        if viewport.X <= 0 or viewport.Y <= 0 then
            -- The screen gui has no size on its first frames (the window keeps
            -- an AbsoluteSize listener for the same reason). Clamping against
            -- a zero viewport collapses every bound to zero and pins the
            -- label to the corner, so the point is taken as asked and gets
            -- re-clamped the moment the screen can be measured.
            offset = Vector2.new(math.max(point.X, 0), math.max(point.Y, 0))
            if not measureClampQueued then
                measureClampQueued = true
                RunService.RenderStepped:Once(function()
                    measureClampQueued = false
                    if not entry.Destroyed and pill.Parent then
                        placeAt(offset)
                    end
                end)
            end
        else
            -- A UIScale enlarges an element without moving it: offsets stay in
            -- plain pixels, so the bound is the screen minus the rendered
            -- pill. Dividing by the scale as well left a dead strip on the
            -- right and bottom edges.
            local bound = viewport - pill.AbsoluteSize
            offset = Vector2.new(
                math.clamp(point.X, 0, math.max(bound.X, 0)),
                math.clamp(point.Y, 0, math.max(bound.Y, 0))
            )
        end
        pill.Position = UDim2.fromOffset(offset.X, offset.Y)
    end

    table.insert(entry.Connections, pill.InputBegan:Connect(function(input)
        if entry.Destroyed or not isPress(input) then
            return
        end
        dragging = true
        dragOrigin = offset
        dragStart = pointerPosition()
    end))

    local dragChanged = UserInputService.InputChanged:Connect(function(input)
        if entry.Destroyed or not dragging or not isMove(input) then
            return
        end
        -- The pill's own scale does not move its offset: plain pixel delta.
        placeAt(dragOrigin + (pointerPosition() - dragStart))
    end)
    local dragEnded = UserInputService.InputEnded:Connect(function(input)
        if entry.Destroyed or not dragging then
            return
        end
        if isPress(input) then
            dragging = false
        end
    end)
    table.insert(entry.Connections, dragChanged)
    table.insert(entry.Connections, dragEnded)
    table.insert(window._connections, dragChanged)
    table.insert(window._connections, dragEnded)

    function entry:SetText(newText)
        textLabel.Text = newText ~= nil and tostring(newText) or ""
    end

    function entry:SetIcon(newIcon)
        icon = cleanIcon(newIcon)
        applyCurrentIcon()
    end

    function entry:SetIconPosition(newPosition)
        iconPosition = (typeof(newPosition) == "string" and string.lower(newPosition) == "right") and "right" or "left"
        updateIconLayout()
    end

    function entry:SetVisible(visible)
        pill.Visible = visible ~= false
    end

    function entry:Destroy()
        if entry.Destroyed then
            return
        end
        entry.Destroyed = true
        for _, connection in ipairs(entry.Connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(entry.Connections)
        for index, item in ipairs(Library._draggableLabels) do
            if item == entry then
                table.remove(Library._draggableLabels, index)
                break
            end
        end
        pill:Destroy()
    end

    applyCurrentIcon()
    table.insert(Library._draggableLabels, entry)

    -- One frame may pass first so the AutomaticSize has measured the pill.
    local function measurePill()
        if pill.AbsoluteSize.X <= 0 then
            pcall(function()
                RunService.RenderStepped:Wait()
            end)
        end
    end

    -- Without a Position the label starts at the top-left corner, dropped
    -- below whatever label is already there (the same stacking Obsidian
    -- uses); with one it goes exactly where it was asked to.
    local function firstFreeSpot()
        measurePill()
        local size = pill.AbsoluteSize
        if size.X <= 0 then
            size = Vector2.new(150, 34) * scale.Scale
        end
        local bounds = gui.AbsoluteSize
        local margin = 6
        local x, y = margin, margin
        local column = size.X
        for _ = 1, 256 do
            local hitPosition, hitSize
            for _, other in ipairs(Library._draggableLabels) do
                local otherPill = other.Label
                if other ~= entry and otherPill and otherPill.Parent and otherPill.Visible then
                    local otherPosition = otherPill.AbsolutePosition - gui.AbsolutePosition
                    local otherSize = otherPill.AbsoluteSize
                    if x < otherPosition.X + otherSize.X and x + size.X > otherPosition.X
                        and y < otherPosition.Y + otherSize.Y and y + size.Y > otherPosition.Y then
                        hitPosition, hitSize = otherPosition, otherSize
                        break
                    end
                end
            end
            if not hitPosition then
                return Vector2.new(x, y)
            end
            column = math.max(column, hitSize.X)
            local nextY = hitPosition.Y + hitSize.Y + margin
            if nextY + size.Y > bounds.Y - margin then
                local nextX = x + column + margin
                if nextX + size.X > bounds.X - margin then
                    return Vector2.new(x, y)
                end
                x, y = nextX, margin
                column = size.X
            else
                y = nextY
            end
        end
        return Vector2.new(x, y)
    end

    if startPosition then
        measurePill()
        placeAt(startPosition)
    else
        placeAt(firstFreeSpot())
    end

    entry._reclamp = function()
        placeAt(offset)
    end

    return entry
end

-- Keeps every draggable overlay on the newest window's UI scale, always 10%
-- above it.
function Library._syncDraggableLabels()
    local window = Library.Windows[#Library.Windows]
    local target = ((window and window:GetUIScale()) or 1) * OVERLAY_UI_SCALE
    for index = #Library._draggableLabels, 1, -1 do
        local entry = Library._draggableLabels[index]
        local pill = entry and entry.Label
        if not entry or entry.Destroyed or not pill or not pill.Parent then
            table.remove(Library._draggableLabels, index)
        else
            entry._scale.Scale = target
            if entry._reclamp then
                entry._reclamp()
            end
        end
    end
end

-- The Keybind Menu: Obsidian's KeybindFrame rebuilt with the overlay chrome
-- this library already uses for draggable labels. It floats over the window,
-- starts at the same spot as Obsidian's (left edge, vertically centred),
-- lists every Keybind widget of its window as "[Key] Name" (or "[None] Name"),
-- drags by the title bar and folds to the title bar when the chevron is
-- pressed. Like Obsidian, there is one row per Keybind, created with the
-- widget and updated in place, so opening/closing the menu and changing a key
-- never rebuild the list. It is created hidden with every window;
-- Window:SetKeybindMenu opens it and CreateWindow's KeybindMenu = true starts
-- it open.
function Library:_createKeybindMenu(window)
    local gui = window.Gui
    local HEADER_H = 34
    local ROW_H = 16
    local ROW_GAP = 6
    local BODY_PAD_X = 12
    local BODY_PAD_Y = 8
    local MIN_WIDTH = 140

    -- AutoSize is the whole layout: rows are auto-width labels, the body
    -- wraps their width and height, and the frame wraps the body. Nothing
    -- measures text or resizes the panel by hand, so a key change is one
    -- label update and opening the menu is just a Visible change.
    local frame = create("Frame", {
        Name = "KeybindFrame",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 6, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 6,
        Parent = gui,
    })
    corner(frame, UDim.new(0, 6))
    stroke(frame, Theme.Stroke)
    create("UISizeConstraint", {
        MinSize = Vector2.new(MIN_WIDTH, 0),
        MaxSize = Vector2.new(100000, 100000),
        Parent = frame,
    })
    local scaleObject = create("UIScale", {
        Scale = window:GetUIScale() * OVERLAY_UI_SCALE,
        Parent = frame,
    })

    local header = create("TextButton", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, HEADER_H),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
        Parent = frame,
    })
    local title = label({
        Position = UDim2.fromOffset(BODY_PAD_X, 0),
        Size = UDim2.fromOffset(0, HEADER_H),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "Keybinds",
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        ZIndex = 2,
        Parent = header,
    })

    local collapseButton = create("TextButton", {
        Name = "Collapse",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -6, 0.5, 0),
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 3,
        Parent = header,
    })
    local chevron = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 3,
        Parent = collapseButton,
    })
    applyIcon(chevron, "chevron-down")

    local rule = create("Frame", {
        Position = UDim2.fromOffset(0, HEADER_H),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = frame,
    })
    local body = create("Frame", {
        Position = UDim2.fromOffset(0, HEADER_H + 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        Size = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1,
        ZIndex = 1,
        Parent = frame,
    })
    padding(body, BODY_PAD_X, BODY_PAD_X, BODY_PAD_Y, BODY_PAD_Y)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, ROW_GAP),
        Parent = body,
    })

    local menu = {
        Window = window,
        Frame = frame,
        Container = body,
        Collapsed = false,
        Destroyed = false,
        Label = frame,
        _scale = scaleObject,
        _entries = {},
        _rowCount = 0,
        _nextRowOrder = 0,
        _emptyRow = nil,
        _connections = {},
    }

    -- One placeholder while the list is empty. It is created and destroyed
    -- with the 0<->1 transitions instead of staying hidden: some Roblox
    -- versions still reserve layout space for invisible children.
    function menu:_syncEmpty()
        if menu.Destroyed or not body.Parent then
            return
        end
        if menu._rowCount == 0 then
            if not menu._emptyRow then
                menu._emptyRow = label({
                    Size = UDim2.fromOffset(0, ROW_H),
                    AutomaticSize = Enum.AutomaticSize.X,
                    LayoutOrder = 0,
                    Text = "No keybinds yet",
                    TextSize = 13,
                    TextColor3 = Theme.Muted,
                    TextTruncate = Enum.TextTruncate.None,
                    ZIndex = 2,
                    Parent = body,
                })
            end
        elseif menu._emptyRow then
            menu._emptyRow:Destroy()
            menu._emptyRow = nil
        end
    end

    -- The only work a key change does: rewrite this bind's row. The label is
    -- already parented; AutoSize handles the new width and height.
    function menu:_updateRow(element)
        local row = element._keybindRow
        if not row or not row.Parent then
            return
        end
        local value = element.Value
        local text = "[" .. keyName(value) .. "] " .. (element._keybindName or "Keybind")
        if row.Text ~= text then
            row.Text = text
        end
        local bound = typeof(value) == "EnumItem"
        if element._keybindBound ~= bound then
            element._keybindBound = bound
            local color = bound and Theme.Text or Theme.Muted
            row.TextColor3 = color
            bindColors(row, { TextColor3 = color })
        end
    end

    function menu:AddRow(element)
        if menu.Destroyed or not body.Parent or element._keybindRow or menu._entries[element] then
            return
        end
        if menu._emptyRow then
            menu._emptyRow:Destroy()
            menu._emptyRow = nil
        end
        menu._nextRowOrder += 1
        local row = label({
            Size = UDim2.fromOffset(0, ROW_H),
            AutomaticSize = Enum.AutomaticSize.X,
            LayoutOrder = menu._nextRowOrder,
            Text = "",
            TextSize = 13,
            TextTruncate = Enum.TextTruncate.None,
            ZIndex = 2,
            Parent = body,
        })
        element._keybindRow = row
        element._keybindMenu = menu
        element._keybindBound = nil
        menu._entries[element] = row
        menu._rowCount += 1
        menu:_updateRow(element)
    end

    function menu:RemoveRow(element)
        local row = element._keybindRow
        element._keybindRow = nil
        element._keybindMenu = nil
        element._keybindBound = nil
        if menu._entries[element] then
            menu._entries[element] = nil
            menu._rowCount = math.max(menu._rowCount - 1, 0)
        end
        if row then
            row:Destroy()
        end
        menu:_syncEmpty()
    end

    -- Kept for callers that want to force a repaint. It only rewrites the
    -- existing rows; it never destroys and recreates them.
    function menu:Refresh()
        if menu.Destroyed then
            return
        end
        local stale
        for element, row in pairs(menu._entries) do
            if element._destroyed or not element._keybindRow or not row or not row.Parent then
                stale = stale or {}
                table.insert(stale, element)
            else
                menu:_updateRow(element)
            end
        end
        if stale then
            for _, element in ipairs(stale) do
                menu:RemoveRow(element)
            end
        end
        menu:_syncEmpty()
    end

    -- The frame keeps its AnchorPoint (0, 0.5), exactly like Obsidian's. The
    -- engine keeps the menu vertically centred as AutoSize grows it, so only
    -- dragging needs position work, and that work is a clamp.
    local function clampPosition(xOffset, yOffset)
        if menu.Destroyed then
            return
        end
        local view = gui.AbsoluteSize
        local position
        if view.X <= 0 or view.Y <= 0 then
            position = UDim2.new(0, math.max(xOffset, 0), 0.5, yOffset)
        else
            local size = frame.AbsoluteSize
            local x = math.clamp(xOffset, 0, math.max(view.X - size.X, 0))
            local top = view.Y * 0.5 + yOffset - size.Y * 0.5
            top = math.clamp(top, 0, math.max(view.Y - size.Y, 0))
            position = UDim2.new(0, x, 0.5, (top + size.Y * 0.5) - view.Y * 0.5)
        end
        -- Position writes reached from AbsoluteSize can otherwise re-enter
        -- rendering even when the clamp did not move the frame.
        if frame.Position ~= position then
            frame.Position = position
        end
    end

    menu._reclamp = function()
        if not menu.Destroyed then
            clampPosition(frame.Position.X.Offset, frame.Position.Y.Offset)
        end
    end

    local function renderCollapse()
        rule.Visible = not menu.Collapsed
        body.Visible = not menu.Collapsed
        tween(chevron, { Rotation = menu.Collapsed and 0 or 180 }, 0.18, Enum.EasingStyle.Quint)
    end

    function menu:SetCollapsed(collapsed)
        collapsed = collapsed == true
        if menu.Destroyed or collapsed == menu.Collapsed then
            return
        end
        -- Read the width before hiding the body: once the body is invisible
        -- AutoSize may already have shrunk the frame.
        local width
        if collapsed then
            width = frame.AbsoluteSize.X / math.max(scaleObject.Scale, 0.01)
        end
        menu.Collapsed = collapsed
        renderCollapse()
        if collapsed then
            frame.AutomaticSize = Enum.AutomaticSize.None
            frame.Size = UDim2.fromOffset(math.max(width, MIN_WIDTH), HEADER_H)
        else
            frame.AutomaticSize = Enum.AutomaticSize.XY
            frame.Size = UDim2.fromOffset(0, 0)
        end
        menu:_reclamp()
    end

    function menu:ToggleCollapsed()
        menu:SetCollapsed(not menu.Collapsed)
    end

    function menu:SetVisible(visible)
        if menu.Destroyed then
            return
        end
        frame.Visible = visible ~= false
    end

    function menu:ToggleVisible()
        menu:SetVisible(not frame.Visible)
    end

    function menu:Destroy()
        if menu.Destroyed then
            return
        end
        menu.Destroyed = true
        table.clear(menu._entries)
        menu._emptyRow = nil
        for index = #Library._keybindMenus, 1, -1 do
            if Library._keybindMenus[index] == menu then
                table.remove(Library._keybindMenus, index)
                break
            end
        end
        for index = #Library._draggableLabels, 1, -1 do
            if Library._draggableLabels[index] == menu then
                table.remove(Library._draggableLabels, index)
                break
            end
        end
        for _, connection in ipairs(menu._connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(menu._connections)
        if Library.KeybindMenu == menu then
            local newest = Library._keybindMenus[#Library._keybindMenus]
            Library.KeybindMenu = newest
            Library.KeybindFrame = newest and newest.Frame or nil
        end
        if window.KeybindMenu == menu then
            window.KeybindMenu = nil
            window.KeybindFrame = nil
        end
        pcall(function()
            frame:Destroy()
        end)
    end

    local function track(connection)
        table.insert(menu._connections, connection)
        table.insert(window._connections, connection)
        return connection
    end

    local dragging = false
    local dragOriginX, dragOriginY = 6, 0
    local dragStart = Vector2.zero

    track(header.InputBegan:Connect(function(input)
        if menu.Destroyed or not isPress(input) then
            return
        end
        -- The chevron is its own button; pressing it must not start a drag.
        if pointInside(pointerPosition(), collapseButton) then
            return
        end
        dragging = true
        dragOriginX = frame.Position.X.Offset
        dragOriginY = frame.Position.Y.Offset
        dragStart = pointerPosition()
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if menu.Destroyed or not dragging or not isMove(input) then
            return
        end
        local delta = pointerPosition() - dragStart
        clampPosition(dragOriginX + delta.X, dragOriginY + delta.Y)
    end))

    track(UserInputService.InputEnded:Connect(function(input)
        if menu.Destroyed or not dragging then
            return
        end
        if isPress(input) then
            dragging = false
        end
    end))

    track(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if not menu.Destroyed then
            menu:_reclamp()
        end
    end))

    -- AutoSize changes the frame on row edits, fold/unfold and UI scale
    -- changes; keep the anchored frame inside the screen without any fitting.
    track(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if not menu.Destroyed then
            menu:_reclamp()
        end
    end))

    track(frame:GetPropertyChangedSignal("Visible"):Connect(function()
        -- Keep the Theme Manager toggle honest whether the menu was opened
        -- from the API, the toggle or a raw Frame.Visible change. Opening
        -- does no row work: every row is already current.
        local toggle = window._keybindMenuToggle
        if toggle and not toggle._destroyed then
            toggle:Set(frame.Visible, true)
        end
    end))

    collapseButton.MouseButton1Click:Connect(function()
        menu:ToggleCollapsed()
    end)
    collapseButton.MouseEnter:Connect(function()
        tween(chevron, { ImageColor3 = Theme.Text }, 0.12)
    end)
    collapseButton.MouseLeave:Connect(function()
        tween(chevron, { ImageColor3 = Theme.Muted }, 0.2)
    end)

    table.insert(Library._keybindMenus, menu)
    table.insert(Library._draggableLabels, menu)
    window.KeybindFrame = frame
    window.KeybindMenu = menu
    Library.KeybindFrame = frame
    Library.KeybindMenu = menu
    renderCollapse()
    menu:_syncEmpty()
    return menu
end

local function isShown(object, stopAt, point)
    local child = object
    while child and child ~= stopAt and child:IsA("GuiObject") do
        if not child.Visible then
            return false
        end
        local parent = child.Parent
        if parent and parent ~= stopAt and parent:IsA("GuiObject") and (parent.ClipsDescendants or parent:IsA("ScrollingFrame")) and not pointInside(point, parent) then
            return false
        end
        child = parent
    end
    return true
end

function Window:_refreshControls()
    local controls = {}
    for _, object in ipairs(self.Body:GetDescendants()) do
        if object:IsA("GuiButton") or object:IsA("TextBox") or object:GetAttribute("NoDrag") then
            table.insert(controls, object)
        end
    end
    self._controls = controls
    self._controlsDirty = false
end

function Window:_overControl(point)
    if self._dialog or self:_overPopout(point) then
        return true
    end
    -- The Keybind Menu is a sibling of the window in the screen gui, so it is
    -- not in the body's control list. Without this, dragging the menu while
    -- it overlaps the window would drag the window underneath too.
    local keybindMenu = self.KeybindMenu
    if keybindMenu and not keybindMenu.Destroyed and keybindMenu.Frame
        and keybindMenu.Frame.Visible and pointInside(point, keybindMenu.Frame) then
        return true
    end
    if self._controlsDirty then
        self:_refreshControls()
    end
    for _, object in ipairs(self._controls) do
        if object.Parent and pointInside(point, object) and isShown(object, self.Body, point) then
            return true
        end
    end
    return false
end

-- Tooltips: one shared card per window that follows the pointer over any
-- element built with Tooltip = "..." or { Title, Text, Icon }. It appears
-- after a short hover (straight away when moving from one tooltip to the
-- next), hides on press, and shows on a long press on touch screens.
function Window:_tooltipCard()
    if self._tip then
        return self._tip
    end
    local holder = create("CanvasGroup", {
        Name = "Tooltip",
        Size = UDim2.fromOffset(0, 0),
        BackgroundTransparency = 1,
        GroupTransparency = 1,
        Visible = false,
        ZIndex = 60,
        Parent = self.Gui,
    })
    local tipScale = create("UIScale", { Parent = holder })
    -- Bare text, no card: a dark outline keeps it readable over anything.
    -- The holder is sized from the text by hand, since scale sizes inside an
    -- automatic size would stretch it across the screen.
    local PAD = 4
    local panel = create("Frame", {
        Position = UDim2.fromOffset(PAD, PAD),
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        Parent = holder,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = panel,
    })
    local function outline(object)
        create("UIStroke", {
            Color = Color3.new(0, 0, 0),
            Transparency = 0.35,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
            Parent = object,
        })
    end
    local head = create("Frame", {
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = panel,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = head,
    })
    local icon = create("ImageLabel", {
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        LayoutOrder = 1,
        Parent = head,
    })
    local title = label({
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = head,
    })
    outline(title)
    local body = label({
        Size = UDim2.fromOffset(0, 0),
        AutomaticSize = Enum.AutomaticSize.XY,
        TextSize = 12,
        FontFace = Fonts.Medium,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        LineHeight = 1.1,
        LayoutOrder = 2,
        Parent = panel,
    })
    outline(body)
    create("UISizeConstraint", { MaxSize = Vector2.new(240, math.huge), Parent = body })
    local function fit()
        local scale = math.max(tipScale.Scale, 0.01)
        local size = panel.AbsoluteSize / scale
        holder.Size = UDim2.fromOffset(size.X + PAD * 2, size.Y + PAD * 2)
    end
    panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    local tip = {
        Holder = holder,
        Scale = tipScale,
        Pad = PAD,
        Head = head,
        Icon = icon,
        Title = title,
        Body = body,
        Shown = false,
        Fit = fit,
    }
    self._tip = tip
    -- Follow the pointer, and drop the card once its element is gone or off
    -- screen (tab switched, window hidden or minimized).
    self:_listen("Render", function(deltaTime)
        local owner = self._tipOwner
        if not owner then
            return
        end
        local frame = owner._frame
        if owner._destroyed or not self.Open or self.Minimized or not frame or not frame.Parent
            or (owner._isShown and not owner:_isShown()) or not isShown(frame, self.Body, frame.AbsolutePosition + frame.AbsoluteSize / 2) then
            self:_hideTooltip()
            return
        end
        local pointer = pointerPosition() - self.Gui.AbsolutePosition
        local pad = tip.Pad * tipScale.Scale
        local size = holder.AbsoluteSize - Vector2.one * pad * 2
        local view = self.Gui.AbsoluteSize
        local x, y
        if tip.Touch then
            x, y = pointer.X - size.X / 2, pointer.Y - size.Y - 30
        else
            x, y = pointer.X + 14, pointer.Y + 20
            if x + size.X > view.X - 8 then
                x = pointer.X - size.X - 10
            end
            if y + size.Y > view.Y - 8 then
                y = pointer.Y - size.Y - 12
            end
        end
        local target = Vector2.new(
            math.clamp(x, 8, math.max(8, view.X - size.X - 8)),
            math.clamp(y, 8, math.max(8, view.Y - size.Y - 8))
        )
        local current = tip.Position
        if not current or tip.Snap then
            -- Rises a few pixels into place as it fades in.
            current = target + Vector2.new(0, 6)
            tip.Snap = false
        else
            current = current:Lerp(target, math.min(deltaTime * 22, 1))
        end
        tip.Position = current
        holder.Position = UDim2.fromOffset(math.floor(current.X - pad + 0.5), math.floor(current.Y - pad + 0.5))
    end)
    -- A press anywhere (a dropdown chip inside the card, a key) hides it.
    self:_listen("Began", function(input)
        if self._tipOwner and not tip.Touch and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Keyboard) then
            self:_hideTooltip()
        end
    end)
    return tip
end

function Window:_showTooltip(element, touch)
    local value = element._tooltip
    local text, titleText, iconName
    if type(value) == "table" then
        text, titleText, iconName = value.Text or value.Content or value.Desc, value.Title or value.Name, value.Icon
    elseif value ~= nil and value ~= false then
        text = tostring(value)
    end
    if (text == nil or text == "") and (titleText == nil or titleText == "") then
        return
    end
    local tip = self:_tooltipCard()
    tip.Title.Text = titleText or ""
    tip.Title.Visible = titleText ~= nil and titleText ~= ""
    tip.Icon.Visible = iconName ~= nil
    if iconName ~= nil then
        applyIcon(tip.Icon, iconName)
    end
    tip.Head.Visible = tip.Title.Visible or iconName ~= nil
    tip.Body.Text = text or ""
    tip.Body.Visible = text ~= nil and text ~= ""
    tip.Fit()
    tip.Body.TextColor3 = Theme.Text
    tip.Scale.Scale = math.max(self.Scale.Scale, 0.75)
    tip.Touch = touch == true
    local wasShown = tip.Shown
    self._tipOwner = element
    tip.Shown = true
    tip.Generation = (tip.Generation or 0) + 1
    local holder = tip.Holder
    if not wasShown then
        tip.Snap = true
        holder.Visible = true
        holder.GroupTransparency = 1
        tip.Scale.Scale = tip.Scale.Scale * 0.96
    end
    tween(holder, { GroupTransparency = 0 }, 0.14, Enum.EasingStyle.Quad)
    tween(tip.Scale, { Scale = math.max(self.Scale.Scale, 0.75) }, 0.18, Enum.EasingStyle.Back)
end

function Window:_hideTooltip(element)
    local tip = self._tip
    if not tip or not tip.Shown or (element and self._tipOwner ~= element) then
        return
    end
    self._tipOwner = nil
    self._tipHiddenAt = os.clock()
    tip.Shown = false
    tip.Generation = (tip.Generation or 0) + 1
    local generation = tip.Generation
    tween(tip.Holder, { GroupTransparency = 1 }, 0.1, Enum.EasingStyle.Quad)
    task.delay(0.1, function()
        if tip.Generation == generation then
            tip.Holder.Visible = false
        end
    end)
end

function Window:_attachTooltip(element, frame)
    local hovering, token, pressAt = false, 0, nil
    local function begin(delay, touch)
        token += 1
        local mine = token
        task.delay(delay, function()
            if token ~= mine or not hovering or element._destroyed or self._destroyed then
                return
            end
            -- A finger that moved was scrolling, not holding.
            if touch and pressAt and (pointerPosition() - pressAt).Magnitude > 10 then
                return
            end
            self:_showTooltip(element, touch)
        end)
    end
    table.insert(element._listeners, (function()
        local connections = {
            frame.MouseEnter:Connect(function()
                if usingTouch() then
                    return
                end
                hovering = true
                local recent = os.clock() - (self._tipHiddenAt or 0) < 0.35 or self._tipOwner ~= nil
                begin(recent and 0 or 0.45, false)
            end),
            frame.MouseLeave:Connect(function()
                hovering = false
                token += 1
                self:_hideTooltip(element)
            end),
            frame.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch then
                    hovering = true
                    pressAt = pointerPosition()
                    begin(0.5, true)
                end
            end),
            frame.InputEnded:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.Touch then
                    hovering = false
                    token += 1
                    self:_hideTooltip(element)
                end
            end),
        }
        return function()
            for _, connection in ipairs(connections) do
                connection:Disconnect()
            end
        end
    end)())
end

-- While dragging, a stand-in follows the pointer while the window stays put,
-- and the window glides into its spot on release. The look is the player's
-- Drag Style; "Off" drags the window itself.
Library.DragStyles = { "Outline", "Brackets", "Ghost", "Frame", "Off" }

local function makeSkeleton(window)
    local root = window.Root
    local style = window.DragStyle or "Outline"
    local skeleton = create("Frame", {
        AnchorPoint = root.AnchorPoint,
        Position = root.Position,
        Size = UDim2.fromOffset(root.AbsoluteSize.X, root.AbsoluteSize.Y),
        BackgroundColor3 = style == "Ghost" and Theme.Background or Theme.Accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 40,
        Parent = window.Gui,
    })
    corner(skeleton, UDim.new(0, 10))
    -- Each part fades from hidden to its shown values, and back on release.
    local parts = {}
    local function part(object, shown)
        local hidden = {}
        for key in pairs(shown) do
            hidden[key] = 1
        end
        table.insert(parts, { Object = object, Shown = shown, Hidden = hidden })
    end
    local function brackets(length, inset)
        for _, spot in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
            local at = UDim2.new(spot.X, spot.X == 0 and inset or -inset, spot.Y, spot.Y == 0 and inset or -inset)
            for _, size in ipairs({ UDim2.fromOffset(length, 2), UDim2.fromOffset(2, length) }) do
                local bracket = create("Frame", {
                    AnchorPoint = spot,
                    Position = at,
                    Size = size,
                    BackgroundColor3 = Theme.Accent,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Parent = skeleton,
                })
                corner(bracket, UDim.new(1, 0))
                part(bracket, { BackgroundTransparency = 0 })
            end
        end
    end
    if style == "Brackets" then
        -- Just the four corners of the window, a little longer.
        brackets(22, 0)
    elseif style == "Ghost" then
        -- A see-through copy of the window's panel.
        part(skeleton, { BackgroundTransparency = 0.35 })
        part(stroke(skeleton, Theme.Stroke, 1, 1), { Transparency = 0 })
    elseif style == "Frame" then
        -- A single quiet line, nothing else.
        part(stroke(skeleton, Theme.StrokeHover, 1, 1), { Transparency = 0 })
    else
        -- Outline: a faint accent wash, an outline and corner brackets.
        part(skeleton, { BackgroundTransparency = 0.92 })
        part(stroke(skeleton, Theme.Accent, 1, 1.5), { Transparency = 0.2 })
        brackets(16, 6)
    end
    local scale = create("UIScale", { Scale = 1.02, Parent = skeleton })
    for _, item in ipairs(parts) do
        tween(item.Object, item.Shown, 0.15, Enum.EasingStyle.Quad)
    end
    tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Quint)
    local function fade()
        for _, item in ipairs(parts) do
            tween(item.Object, item.Hidden, 0.2, Enum.EasingStyle.Quad)
        end
        task.delay(0.22, function()
            skeleton:Destroy()
        end)
    end
    return skeleton, fade
end

function Window:_enableDrag()
    local dragging, moved = false, false
    local grabOffset, pressPoint = Vector2.zero, Vector2.zero
    local target = nil
    local skeleton, fadeSkeleton = nil, nil

    local function centre()
        local root = self.Root
        return root.AbsolutePosition + root.AbsoluteSize * root.AnchorPoint - self.Gui.AbsolutePosition
    end

    local function dropSkeleton()
        if not skeleton then
            return
        end
        local spot = Vector2.new(skeleton.Position.X.Offset, skeleton.Position.Y.Offset)
        if self.KeepOnScreen then
            spot = self:_clampedCentre(spot)
        end
        if self._clampTween then
            self._clampTween:Cancel()
        end
        self._clampTween = tween(self.Root, { Position = UDim2.fromOffset(spot.X, spot.Y) }, 0.3, Enum.EasingStyle.Quint)
        fadeSkeleton()
        skeleton, fadeSkeleton = nil, nil
    end

    table.insert(self._connections, UserInputService.InputBegan:Connect(function(input)
        if not isPress(input) then
            return
        end
        if not self.Open or not self.Root.Visible then
            return
        end
        local point = pointerPosition()
        if self._resizeActive or (self._grip and pointInside(point, self._grip)) then
            return
        end
        if not pointInside(point, self.Body) or self:_overControl(point) then
            return
        end
        if self._clampTween then
            self._clampTween:Cancel()
            self._clampTween = nil
        end
        dragging, moved = true, false
        pressPoint = point
        grabOffset = point - centre()
    end))

    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not dragging then
            return
        end
        if isPress(input) then
            dragging = false
            target = nil
            if skeleton then
                dropSkeleton()
            else
                self:_clampToScreen()
            end
        end
    end))

    table.insert(self._frameSteps, function(deltaTime)
        if not dragging then
            return
        end
        local point = pointerPosition()
        if not moved and (point - pressPoint).Magnitude > 3 then
            moved = true
            if self.DragSkeleton then
                skeleton, fadeSkeleton = makeSkeleton(self)
            end
        end
        if not moved then
            return
        end
        -- Hidden or minimized mid-drag: land it where the outline is.
        if skeleton and (not self.Open or not self.Root.Visible) then
            dragging = false
            dropSkeleton()
            return
        end
        target = point - grabOffset
        local alpha = 1 - math.exp(-deltaTime * 45)
        if skeleton then
            local current = Vector2.new(skeleton.Position.X.Offset, skeleton.Position.Y.Offset)
            local step = current:Lerp(target, alpha)
            skeleton.Position = UDim2.fromOffset(step.X, step.Y)
        else
            local step = centre():Lerp(target, alpha)
            self.Root.Position = UDim2.fromOffset(step.X, step.Y)
        end
    end)
end

-- One of Library.DragStyles; anything else falls back to "Outline".
-- Returns the style it settled on.
function Window:SetDragStyle(style)
    style = table.find(Library.DragStyles, style) and style or "Outline"
    self.DragStyle = style
    self.DragSkeleton = style ~= "Off"
    return style
end

function Window:GetDragStyle()
    return self.DragStyle
end

-- How the minimized island shows the session card: opening it while
-- hovered, or keeping it open the whole time it's minimized.
Library.IslandStyles = { "Show on Hover", "Always Show" }

-- One of Library.IslandStyles; anything else falls back to "Show on Hover".
-- Returns the style it settled on.
function Window:SetIslandStyle(style)
    style = table.find(Library.IslandStyles, style) and style or "Show on Hover"
    self.IslandStyle = style
    if self._islandSettle then
        self._islandSettle()
    end
    return style
end

function Window:GetIslandStyle()
    return self.IslandStyle
end

-- The older on/off switch: off is the "Off" style, on brings back the
-- default style if it was off.
function Window:SetDragSkeleton(enabled)
    if enabled == false then
        self:SetDragStyle("Off")
    elseif self.DragStyle == "Off" or not self.DragStyle then
        self:SetDragStyle("Outline")
    end
end

-- The sidebar's divider is a grab strip: dragging it sets the rail's width,
-- kept between a usable minimum and enough room for the content.
function Window:_sidebarResize(sidebar, width)
    local divider = sidebar:FindFirstChild("Divider")
    local want = width
    local function apply(value, remember)
        if remember ~= false then
            want = value
        end
        local room = self.Body.AbsoluteSize.X / self.Scale.Scale - 300
        value = math.floor(math.clamp(value, 150, math.max(math.min(300, room), 150)))
        self.SidebarWidth = value
        sidebar.Size = UDim2.new(0, value, 1, 0)
        self.Content.Position = UDim2.fromOffset(value + 1, 0)
        self.Content.Size = UDim2.new(1, -(value + 1), 1, 0)
    end
    self.SetSidebarWidth = function(_, value)
        apply(tonumber(value) or SIDEBAR_WIDTH)
    end
    apply(width)
    local grip = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.new(0, 6, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 6,
        Parent = sidebar,
    })
    grip:SetAttribute("NoDrag", true)
    local dragging, startX, startWidth = false, 0, width
    local function light(on)
        if divider then
            tween(divider, { BackgroundColor3 = on and Theme.Accent or Theme.Stroke }, 0.15)
        end
    end
    grip.MouseEnter:Connect(function()
        light(true)
    end)
    grip.MouseLeave:Connect(function()
        if not dragging then
            light(false)
        end
    end)
    grip.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, startX, startWidth = true, input.Position.X, self.SidebarWidth
            want = startWidth
            light(true)
        end
    end)
    self:_listen("Changed", function(input)
        if dragging and isMove(input) then
            apply(startWidth + (input.Position.X - startX) / self.Scale.Scale)
        end
    end)
    self:_listen("Ended", function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            light(false)
        end
    end)
    -- Shrinking the window pulls an over-wide rail back in.
    self.Body:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if not dragging then
            apply(want, false)
        end
    end)
end

-- See-through window: the body and sidebar let the game show through, and the
-- shadow lightens so it doesn't smudge behind them.
function Window:SetTransparent(enabled)
    self.Transparent = enabled == true
    local on = self.Transparent
    self._shadowRest = on and 0.85 or 0.6
    tween(self.Body, { BackgroundTransparency = on and 0.35 or 0 }, 0.25)
    -- See-through, the rail stays a touch more solid than the body so the
    -- tabs keep their contrast; over a background image it lets more through.
    local railAlpha = on and 0.5 or (self.Background and 0.45 or 0)
    tween(self.SidebarFill, { BackgroundTransparency = railAlpha }, 0.25)
    if self.Open and not self.Minimized and self.Root.Visible then
        tween(self.Shadow, { ImageTransparency = self._shadowRest }, 0.25)
    end
end

-- Renders the whole window above Roblox's core blur (the overlay behind the
-- Roblox menu). Executor-only hidden property; ignored where unsupported.
function Window:SetAlwaysOnTop(enabled)
    self.AlwaysOnTop = enabled == true
    Library._SetAlwaysOnTop(self.Gui, self.AlwaysOnTop)
end

local function orderedChildren(parent)
    local children = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child:IsA("GuiObject") then
            table.insert(children, child)
        end
    end
    table.sort(children, function(a, b)
        return a.LayoutOrder < b.LayoutOrder
    end)
    return children
end

local function popIn(object, delay, force)
    if not object.Visible and not force then
        return
    end
    object.Visible = false
    task.delay(delay, function()
        if not object.Parent then
            return
        end
        local scaleObject = create("UIScale", { Scale = 0.94, Parent = object })
        object.Visible = true
        tween(scaleObject, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
        task.delay(0.4, function()
            scaleObject:Destroy()
        end)
    end)
end

function Window:_revealCards(tab, baseDelay)
    local container = tab.CurrentSubTab or tab
    if container._revealed then
        return
    end
    container._revealed = true
    local index = 0
    local function reveal(object)
        popIn(object, (baseDelay or 0) + index * 0.035)
        index += 1
    end
    local columns = container._columnSet
    for _, child in ipairs(orderedChildren(container.List)) do
        if columns and child == columns.Holder then
            local left, right = orderedChildren(columns.Left), orderedChildren(columns.Right)
            for row = 1, math.max(#left, #right) do
                if left[row] then
                    reveal(left[row])
                end
                if right[row] then
                    reveal(right[row])
                end
            end
        else
            reveal(child)
        end
    end
end

function Window:_playIntro(morph)
    if self._introDone or self._destroyed then
        return
    end
    self._introDone = true
    self:_refreshModal()
    self:_refreshCursor()
    self:_refreshBackdrop(true)
    task.delay(0.4, function()
        self:_refreshToggleButton()
    end)
    -- Build the minimized bar ahead of time so the first minimize doesn't
    -- pay for it mid-click.
    task.delay(1.5, function()
        if not self._destroyed and not self.MiniBar then
            self:_buildMiniBar()
        end
    end)
    local root, shadow, scale = self.Root, self.Shadow, self.Scale
    if self.CurrentTab then
        self:_revealCards(self.CurrentTab, morph and 0.15 or 0.25)
    end
    root.Visible = true
    if morph then
        scale.Scale = self._fitScale or 1
        root.Position = UDim2.fromScale(0.5, 0.5)
        self:_fade(0, 0.3)
        tween(self.BodyStroke, { Transparency = 0 }, 0.3)
        tween(shadow, { ImageTransparency = 0.6 }, 0.3)
    else
        root.Position = UDim2.new(0.5, 0, 0.5, 24)
        tween(scale, { Scale = self._fitScale or 1 }, 0.5, Enum.EasingStyle.Back)
        tween(root, { Position = UDim2.fromScale(0.5, 0.5) }, 0.5, Enum.EasingStyle.Quint)
        self:_fade(0, 0.35)
        tween(self.BodyStroke, { Transparency = 0 }, 0.35)
    end
    if not morph then
        tween(shadow, { ImageTransparency = 0.6 }, 0.5)
    end

    for index, tab in ipairs(self.Tabs) do
        popIn(tab._button, 0.1 + index * 0.05, true)
    end
    self.Indicator.Visible = false
    task.delay(0.15 + #self.Tabs * 0.05, function()
        if self.CurrentTab then
            self:_placeIndicator(self.CurrentTab)
        end
    end)
end

function Window:_showLoader(opts)
    local duration = opts.LoadingDuration or 1.6
    local gui = self.Gui
    -- A compact card: logo, title and subtitle on top, a checklist of the
    -- loading steps under a hairline, and a thin progress line along the
    -- bottom edge. Everything but the prompt cards lives in one canvas group
    -- so it can fade as a unit.
    local steps = opts.LoadingSteps or { "Preparing interface", "Loading icons", "Almost there" }
    local WIDTH, PAD, STEP = 340, 22, 24
    local listTop = 80
    local height = listTop + #steps * STEP + 18
    local loader = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(WIDTH, height),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ZIndex = 10,
        Parent = gui,
    })
    local loaderCorner = corner(loader, UDim.new(0, 12))
    local loaderStroke = stroke(loader, Theme.Stroke, 1)
    local loaderScale = create("UIScale", { Scale = 0.97, Parent = loader })
    local loaderShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-25, -25),
        Size = UDim2.new(1, 50, 1, 50),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = loader,
    })
    local content = create("CanvasGroup", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Parent = loader,
    })

    if opts.Icon ~= false then
        local logo = create("ImageLabel", {
            Position = UDim2.fromOffset(PAD, PAD),
            Size = UDim2.fromOffset(30, 30),
            BackgroundTransparency = 1,
            ImageColor3 = Color3.new(1, 1, 1),
            ScaleType = Enum.ScaleType.Fit,
            Parent = content,
        })
        applyIcon(logo, opts.Icon or Assets.Logo, true)
    end
    local TEXT_X = opts.Icon ~= false and (PAD + 42) or PAD
    local titleLabel = label({
        Position = UDim2.fromOffset(TEXT_X, PAD - 2),
        Size = UDim2.new(1, -(TEXT_X + 70), 0, 18),
        Text = opts.LoadingTitle or opts.Title or "Aster UI",
        TextSize = 15,
        FontFace = Fonts.Bold,
        Parent = content,
    })
    local statusLabel = label({
        Position = UDim2.fromOffset(TEXT_X, PAD + 17),
        Size = UDim2.new(1, -(TEXT_X + 70), 0, 15),
        Text = opts.LoadingText or opts.Subtitle or "Loading",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = content,
    })
    local percentLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -PAD, 0, PAD + 6),
        Size = UDim2.fromOffset(56, 16),
        Text = "0%",
        TextSize = 13,
        FontFace = Fonts.Medium,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = content,
    })
    create("Frame", {
        Position = UDim2.fromOffset(PAD, listTop - 14),
        Size = UDim2.new(1, -PAD * 2, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = content,
    })

    -- Each step: a marker and its text. Pending is a dim dot, the running
    -- step a turning arc, and a finished one a check.
    local rows = {}
    for index, text in ipairs(steps) do
        local row = create("Frame", {
            Position = UDim2.fromOffset(PAD, listTop + (index - 1) * STEP),
            Size = UDim2.new(1, -PAD * 2, 0, STEP),
            BackgroundTransparency = 1,
            Parent = content,
        })
        local dot = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(6, 6),
            BackgroundColor3 = Theme.Surface3,
            BorderSizePixel = 0,
            Parent = row,
        })
        corner(dot, UDim.new(1, 0))
        local spinner = create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(12, 12),
            BackgroundTransparency = 1,
            Visible = false,
            Parent = row,
        })
        corner(spinner, UDim.new(1, 0))
        local spinnerStroke = create("UIStroke", {
            Color = Theme.Accent,
            Thickness = 2,
            Parent = spinner,
        })
        create("UIGradient", {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(0.501, 1),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = spinnerStroke,
        })
        local check = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 7, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Fit,
            Parent = row,
        })
        applyIcon(check, "check")
        local stepLabel = label({
            Position = UDim2.fromOffset(24, 0),
            Size = UDim2.new(1, -24, 1, 0),
            Text = tostring(text),
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTransparency = 1,
            Parent = row,
        })
        rows[index] = { Dot = dot, Spinner = spinner, Check = check, Label = stepLabel, State = "pending" }
        -- The rows fade in one after another once the card is up.
        task.delay(0.15 + index * 0.06, function()
            if loader.Parent and rows[index].State == "pending" then
                tween(stepLabel, { TextTransparency = 0.45 }, 0.3)
            end
        end)
    end
    local function setStep(index, state)
        local row = rows[index]
        if not row or row.State == state then
            return
        end
        row.State = state
        row.Dot.Visible = state == "pending"
        row.Spinner.Visible = state == "active"
        tween(row.Check, { ImageTransparency = state == "done" and 0 or 1 }, 0.2)
        tween(row.Label, {
            TextTransparency = state == "pending" and 0.45 or 0,
            TextColor3 = state == "active" and Theme.Text or Theme.Muted,
        }, 0.2)
    end

    local track = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 2),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = content,
    })
    local fill = create("Frame", {
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })

    tween(loader, { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.45, Enum.EasingStyle.Quint)
    tween(loaderScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Quint)
    tween(loaderShadow, { ImageTransparency = 0.55 }, 0.4)
    tween(fill, { Size = UDim2.fromScale(0.85, 1) }, duration * 0.8, Enum.EasingStyle.Quart)
    -- The percentage follows the bar and the running step's arc turns.
    local percentStep
    percentStep = RunService.RenderStepped:Connect(function(deltaTime)
        if not loader.Parent then
            percentStep:Disconnect()
            return
        end
        percentLabel.Text = math.floor(fill.Size.X.Scale * 100 + 0.5) .. "%"
        for _, row in ipairs(rows) do
            if row.State == "active" then
                row.Spinner.Rotation = (row.Spinner.Rotation + deltaTime * 360) % 360
            end
        end
    end)

    task.spawn(loadLucide)

    for index in ipairs(steps) do
        task.delay(duration * (index - 1) / #steps, function()
            if not loader.Parent then
                return
            end
            if index > 1 then
                setStep(index - 1, "done")
            end
            setStep(index, "active")
        end)
    end
    local function completeSteps()
        for index in ipairs(rows) do
            setStep(index, "done")
        end
    end

    local function finish()
        completeSteps()
        tween(content, { GroupTransparency = 1 }, 0.18)

        local fit = self._fitScale or 1
        local target = self.Root.Size
        tween(loader, {
            Size = UDim2.fromOffset(target.X.Offset * fit, target.Y.Offset * fit),
            Position = UDim2.fromScale(0.5, 0.5),
        }, 0.5, Enum.EasingStyle.Quint)
        tween(loaderCorner, { CornerRadius = UDim.new(0, Library._radius(10)) }, 0.5, Enum.EasingStyle.Quint)
        tween(loaderScale, { Scale = 1 }, 0.5, Enum.EasingStyle.Quint)

        task.delay(0.28, function()
            self:_playIntro(true)
            tween(loader, { GroupTransparency = 1 }, 0.25)
            tween(loaderStroke, { Transparency = 1 }, 0.2)
            tween(loaderShadow, { ImageTransparency = 1 }, 0.2)
        end)
        task.delay(0.6, function()
            loader:Destroy()
        end)
    end

    -- Prompt cards (unsupported executor, custom disclaimers): the checklist
    -- gives way to one card at a time, each with Exit and Continue, before
    -- the window opens.
    local function hideBar()
        completeSteps()
        tween(content, { GroupTransparency = 1 }, 0.18)
    end

    local function showCard(info, onContinue)
        local WIDTH, PAD, MAX_BODY = 360, 24, 220
        local tone = info.Color or Theme.Accent
        -- Fixed width from the start, so the body wraps at its final width
        -- while the loader is still resizing.
        local warnCard = create("CanvasGroup", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(0.5, 0),
            Size = UDim2.new(0, WIDTH, 1, 0),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            ZIndex = 5,
            Parent = loader,
        })
        local badge = create("Frame", {
            Position = UDim2.fromOffset(PAD, PAD),
            Size = UDim2.fromOffset(44, 44),
            BackgroundColor3 = tone,
            BackgroundTransparency = 0.86,
            BorderSizePixel = 0,
            Parent = warnCard,
        })
        corner(badge, UDim.new(0, 12))
        stroke(badge, tone, 1).Transparency = 0.6
        local badgeIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(22, 22),
            BackgroundTransparency = 1,
            ImageColor3 = tone,
            ScaleType = Enum.ScaleType.Fit,
            Parent = badge,
        })
        if info.Icon ~= false then
            applyIcon(badgeIcon, info.Icon or "info")
        else
            -- No icon: the badge collapses and the head text starts at the
            -- card's padding.
            badge.Visible = false
        end
        local headX = info.Icon ~= false and (PAD + 58) or PAD
        local headWidth = info.Icon ~= false and (PAD * 2 + 58) or (PAD * 2)
        label({
            Position = UDim2.fromOffset(headX, info.Subtitle and PAD + 3 or PAD + 12),
            Size = UDim2.new(1, -headWidth, 0, 20),
            Text = info.Title,
            TextSize = 17,
            Parent = warnCard,
        })
        if info.Subtitle then
            label({
                Position = UDim2.fromOffset(headX, PAD + 25),
                Size = UDim2.new(1, -headWidth, 0, 16),
                Text = tostring(info.Subtitle),
                TextSize = 13,
                TextColor3 = tone,
                Parent = warnCard,
            })
        end
        -- Long text scrolls past MAX_BODY instead of pushing the card off screen.
        local scroller = create("ScrollingFrame", {
            Position = UDim2.fromOffset(PAD, PAD + 60),
            Size = UDim2.new(1, -PAD * 2, 0, 16),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = TOUCH and 4 or 3,
            ScrollBarImageColor3 = Theme.Accent,
            ScrollBarImageTransparency = 0.4,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(),
            Parent = warnCard,
        })
        local body = label({
            Size = UDim2.new(1, -8, 0, 0),
            Text = tostring(info.Text),
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = scroller,
        })
        local row = create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, PAD, 1, -PAD + 4),
            Size = UDim2.new(1, -PAD * 2, 0, 34),
            BackgroundTransparency = 1,
            Parent = warnCard,
        })
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
            Parent = row,
        })

        -- Don't ask again: only offered when Continue is, and the executor
        -- can write the file that remembers it.
        local remember = false
        local rememberRow = nil
        if not info.Block and info.RememberText and UnsupportedSkip.Available() then
            local boxSize = TOUCH and 20 or 16
            rememberRow = create("TextButton", {
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, PAD, 1, -PAD + 4 - 34 - 12),
                Size = UDim2.new(1, -PAD * 2, 0, TOUCH and 28 or 22),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                Parent = warnCard,
            })
            local box = create("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.fromScale(0, 0.5),
                Size = UDim2.fromOffset(boxSize, boxSize),
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                Parent = rememberRow,
            })
            corner(box, UDim.new(0, 4))
            local boxStroke = stroke(box, Theme.Stroke, 1)
            local check = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(boxSize - 4, boxSize - 4),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.AccentDark,
                ImageTransparency = 1,
                ScaleType = Enum.ScaleType.Fit,
                Parent = box,
            })
            applyIcon(check, "check")
            local rememberLabel = label({
                Position = UDim2.fromOffset(boxSize + 8, 0),
                Size = UDim2.new(1, -(boxSize + 8), 1, 0),
                Text = info.RememberText,
                TextSize = 12,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = rememberRow,
            })
            rememberRow.MouseEnter:Connect(function()
                tween(boxStroke, { Color = remember and Theme.Accent or Theme.StrokeHover }, 0.12)
                tween(rememberLabel, { TextColor3 = Theme.Text }, 0.12)
            end)
            rememberRow.MouseLeave:Connect(function()
                tween(boxStroke, { Color = remember and Theme.Accent or Theme.Stroke }, 0.2)
                tween(rememberLabel, { TextColor3 = remember and Theme.Text or Theme.Muted }, 0.2)
            end)
            rememberRow.MouseButton1Click:Connect(function()
                remember = not remember
                tween(box, { BackgroundColor3 = remember and Theme.Accent or Theme.Surface2 }, 0.15)
                tween(boxStroke, { Color = remember and Theme.Accent or Theme.Stroke }, 0.15)
                tween(check, { ImageTransparency = remember and 0 or 1 }, 0.15)
                tween(rememberLabel, { TextColor3 = remember and Theme.Text or Theme.Muted }, 0.15)
            end)
        end

        local chosen = false
        local function button(text, primary, order, callback)
            local frame = create("TextButton", {
                Size = UDim2.fromOffset(0, 34),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundColor3 = primary and Theme.Accent or Theme.Surface2,
                BackgroundTransparency = primary and 0.12 or 0,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = order,
                Parent = row,
            })
            corner(frame, UDim.new(0, 7))
            local frameStroke = stroke(frame, primary and Theme.Accent or Theme.Stroke, 1)
            frameStroke.Transparency = primary and 0.4 or 0
            padding(frame, 14, 14)
            label({
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = text,
                TextSize = 13,
                TextColor3 = primary and Theme.AccentDark or Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Center,
                Parent = frame,
            })
            frame.MouseEnter:Connect(function()
                if primary then
                    tween(frame, { BackgroundTransparency = 0 }, 0.12)
                    tween(frameStroke, { Transparency = 0 }, 0.12)
                else
                    tween(frameStroke, { Color = Theme.StrokeHover }, 0.12)
                end
            end)
            frame.MouseLeave:Connect(function()
                if primary then
                    tween(frame, { BackgroundTransparency = 0.12 }, 0.2)
                    tween(frameStroke, { Transparency = 0.4 }, 0.2)
                else
                    tween(frameStroke, { Color = Theme.Stroke }, 0.2)
                end
            end)
            frame.MouseButton1Click:Connect(function()
                if chosen then
                    return
                end
                chosen = true
                callback()
            end)
        end
        if info.ExitText ~= false then
            button(info.ExitText or "Exit", info.Block, 1, function()
                if info.Callback then
                    task.spawn(info.Callback, false)
                end
                tween(loader, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 12) }, 0.25, Enum.EasingStyle.Quint)
                tween(loaderShadow, { ImageTransparency = 1 }, 0.2)
                task.delay(0.25, function()
                    self:Destroy()
                end)
            end)
        end
        if not info.Block then
            button(info.ContinueText or "Continue", true, 2, function()
                if remember and info.Remember then
                    info.Remember()
                end
                if info.Callback then
                    task.spawn(info.Callback, true)
                end
                tween(warnCard, { GroupTransparency = 1 }, 0.15)
                task.delay(0.15, function()
                    warnCard:Destroy()
                    onContinue()
                end)
            end)
        end

        -- The card grows to fit the message, then it fades in. The wrapped
        -- height can land a few frames late (font loading, the scroller's
        -- layout), so the card refits whenever it changes.
        local laidOut = false
        -- TextBounds of wrapped text stops at the label's current height, so
        -- the card would fit to its own clipped text; the full wrapped height
        -- is measured at the body's width instead.
        local function measure()
            local ok, size = pcall(function()
                local params = Instance.new("GetTextBoundsParams")
                params.Text = body.Text
                params.Font = body.FontFace
                params.Size = body.TextSize
                params.Width = WIDTH - PAD * 2 - 8
                return game:GetService("TextService"):GetTextBoundsAsync(params)
            end)
            return ok and size and math.ceil(size.Y) + 2 or body.TextBounds.Y
        end
        local function fit(duration)
            local textHeight = math.max(measure(), 16)
            local bodyHeight = math.min(textHeight, MAX_BODY)
            body.Size = UDim2.new(1, -8, 0, textHeight)
            scroller.Size = UDim2.new(1, -PAD * 2, 0, bodyHeight)
            scroller.CanvasSize = UDim2.fromOffset(0, textHeight)
            local height = PAD + 60 + bodyHeight + 18 + 34 + PAD - 4
            if rememberRow then
                height += rememberRow.Size.Y.Offset + 10
            end
            tween(loader, { Size = UDim2.fromOffset(WIDTH, height) }, duration, Enum.EasingStyle.Quint)
        end
        body:GetPropertyChangedSignal("TextBounds"):Connect(function()
            if laidOut and loader.Parent and warnCard.Parent then
                fit(0.2)
            end
        end)
        task.delay(0.15, function()
            if not loader.Parent then
                return
            end
            laidOut = true
            fit(0.35)
            task.delay(0.12, function()
                tween(warnCard, { GroupTransparency = 0 }, 0.3)
                badge.Size = UDim2.fromOffset(34, 34)
                badge.Position = UDim2.fromOffset(PAD + 5, PAD + 5)
                tween(badge, { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(PAD, PAD) }, 0.45, Enum.EasingStyle.Back)
            end)
        end)
    end

    local function runPrompts(queue, index)
        if not loader.Parent then
            return
        end
        local info = queue[index]
        if not info then
            finish()
            return
        end
        showCard(info, function()
            runPrompts(queue, index + 1)
        end)
    end

    task.delay(duration, function()
        tween(fill, { Size = UDim2.fromScale(1, 1) }, 0.25, Enum.EasingStyle.Quint)
        task.delay(0.25, function()
            if not loader.Parent then
                return
            end
            if opts._prompts then
                hideBar()
                runPrompts(opts._prompts, 1)
            else
                finish()
            end
        end)
    end)
end

function Window:_fitToScreen(instant)
    local viewport = self.Gui.AbsoluteSize
    if viewport.X == 0 or viewport.Y == 0 then
        return
    end
    local size = self.Root.Size
    -- The player's UI scale, times the adaptive factor for this screen, shrunk
    -- further when the window wouldn't fit.
    local wanted = (self._uiScale or 1) * (self._adaptive ~= false and Library._adaptiveFactor(viewport) or 1)
    local scale = math.min(wanted, (viewport.X - 24) / math.max(size.X.Offset, 1), (viewport.Y - 24) / math.max(size.Y.Offset, 1))
    self._fitScale = math.max(scale, 0.45)
    if self._introDone and self.Open then
        if instant then
            self.Scale.Scale = self._fitScale
        else
            tween(self.Scale, { Scale = self._fitScale }, 0.2)
        end
    end
end

-- Adaptive size: the window is drawn for a 1080p screen and grows on larger
-- ones (up to 1.75x on 4K) or shrinks a little on small laptops, so it covers
-- about the same share of any screen. 1080p-class screens, windowed or with
-- the topbar inset, stay at exactly 1. Touch screens only use the fit.
function Library._adaptiveFactor(viewport)
    if TOUCH then
        return 1
    end
    local factor = math.min(viewport.X / 1920, viewport.Y / 1020)
    if factor > 0.9 and factor < 1.15 then
        return 1
    end
    return math.clamp(math.floor(factor * 20 + 0.5) / 20, 0.85, 1.75)
end

function Window:SetAdaptiveSize(enabled)
    self._adaptive = enabled ~= false
    self:_fitToScreen()
    task.delay(0.22, function()
        if not self._destroyed then
            self:_clampToScreen()
        end
    end)
end

function Window:GetAdaptiveSize()
    return self._adaptive ~= false
end

-- UI scale: 0.6 to 1.5 on top of the automatic fit to small screens.
function Window:SetUIScale(value)
    value = math.clamp(tonumber(value) or 1, 0.6, 1.5)
    self.UIScale = value
    self._uiScale = value
    self:_fitToScreen()
    task.delay(0.22, function()
        if not self._destroyed then
            self:_clampToScreen()
        end
    end)
    Library._syncDraggableLabels()
end

function Window:GetUIScale()
    return self._uiScale or 1
end

-- Density: the spacing between cards, groupboxes and rows. Shared by every
-- window, like the theme. Anything built with Library._space follows it.
Library.DensityModes = { Compact = 0.55, Default = 1, Comfortable = 1.45 }
Library.Density = "Default"

-- Small gaps (a groupbox's 2px rows) still move visibly between modes.
function Library._spaced(base, factor)
    if base <= 0 then
        return 0
    end
    return math.max(math.floor(base * factor + (factor - 1) * 4 + 0.5), 0)
end

function Library._space(object, base)
    local factor = Library.DensityModes[Library.Density] or 1
    if object:IsA("UIListLayout") or object:IsA("UIGridLayout") then
        object:SetAttribute("Space", base)
        object.Padding = UDim.new(0, Library._spaced(base, factor))
    elseif object:IsA("UIPadding") then
        -- base is { left, right, top, bottom }
        object:SetAttribute("SpaceL", base[1])
        object:SetAttribute("SpaceR", base[2])
        object:SetAttribute("SpaceT", base[3])
        object:SetAttribute("SpaceB", base[4])
        object.PaddingLeft = UDim.new(0, math.floor(base[1] * math.sqrt(factor) + 0.5))
        object.PaddingRight = UDim.new(0, math.floor(base[2] * math.sqrt(factor) + 0.5))
        object.PaddingTop = UDim.new(0, Library._spaced(base[3], factor))
        object.PaddingBottom = UDim.new(0, Library._spaced(base[4], factor))
    end
    return object
end

function Library:SetDensity(mode)
    if type(mode) == "string" then
        for name in pairs(Library.DensityModes) do
            if name:lower() == mode:lower() then
                mode = name
                break
            end
        end
    end
    if not Library.DensityModes[mode] then
        mode = "Default"
    end
    Library.Density = mode
    for _, window in ipairs(Library.Windows) do
        if window.Gui and window.Gui.Parent then
            for _, object in ipairs(window.Gui:GetDescendants()) do
                local base = object:GetAttribute("Space")
                if base then
                    Library._space(object, base)
                elseif object:GetAttribute("SpaceL") then
                    Library._space(object, {
                        object:GetAttribute("SpaceL"), object:GetAttribute("SpaceR"),
                        object:GetAttribute("SpaceT"), object:GetAttribute("SpaceB"),
                    })
                end
            end
        end
    end
    return mode
end

function Window:SetDensity(mode)
    return Library:SetDensity(mode)
end

function Window:GetDensity()
    return Library.Density
end

-- Nearest centre that keeps the whole window inside the viewport.
function Window:_clampedCentre(centre)
    local viewport = self.Gui.AbsoluteSize
    local half = self.Root.AbsoluteSize / 2
    return Vector2.new(
        math.clamp(centre.X, math.min(half.X, viewport.X / 2), math.max(viewport.X - half.X, viewport.X / 2)),
        math.clamp(centre.Y, math.min(half.Y, viewport.Y / 2), math.max(viewport.Y - half.Y, viewport.Y / 2))
    )
end

function Window:_clampToScreen()
    if not self.KeepOnScreen or self._resizeActive then
        return
    end
    local root = self.Root
    local centre = root.AbsolutePosition + root.AbsoluteSize / 2 - self.Gui.AbsolutePosition
    local clamped = self:_clampedCentre(centre)
    if (clamped - centre).Magnitude > 0.5 then
        self._clampTween = tween(root, { Position = UDim2.fromOffset(clamped.X, clamped.Y) }, 0.25, Enum.EasingStyle.Quint)
    end
end

function Window:_createOpenButton(opts)
    local gui = self.Gui
    local pill = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(0, 40),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(pill, UDim.new(1, 0))
    stroke(pill, Theme.Stroke)
    padding(pill, 12, 16)
    local openIcon = cleanIcon(opts.Icon)
    if openIcon == nil then
        openIcon = Assets.Logo
    end
    if openIcon ~= false then
        local icon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.fromOffset(20, 20),
            BackgroundTransparency = 1,
            ImageColor3 = Color3.new(1, 1, 1),
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 31,
            Parent = pill,
        })
        applyIcon(icon, openIcon, true)
    end
    label({
        Position = UDim2.fromOffset(openIcon ~= false and 28 or 0, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = opts.Title or "Aster UI",
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.None,
        ZIndex = 31,
        Parent = pill,
    })
    self.OpenButton = pill

    local dragging, moved = false, false
    local grab = Vector2.zero
    pill.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            moved = false
            grab = pointerPosition() - pill.AbsolutePosition
        end
    end)
    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if isMove(input) then
            local point = pointerPosition() - grab - gui.AbsolutePosition
            if (point - (pill.AbsolutePosition - gui.AbsolutePosition)).Magnitude > 3 then
                moved = true
            end
            pill.AnchorPoint = Vector2.new(0, 0)
            pill.Position = UDim2.fromOffset(
                math.clamp(point.X, 0, math.max(gui.AbsoluteSize.X - pill.AbsoluteSize.X, 0)),
                math.clamp(point.Y, 0, math.max(gui.AbsoluteSize.Y - pill.AbsoluteSize.Y, 0))
            )
        end
    end))
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if dragging and isPress(input) then
            dragging = false
            if not moved then
                self:Toggle()
            end
        end
    end))
end

-- Square floating button that minimizes and restores the window. Shown on
-- touch devices only, or everywhere with Platform = "Both".
function Window:_toggleButtonAllowed()
    return self._toggleEnabled and (TOUCH or self._togglePlatform == "Both")
end

function Window:_refreshToggleButton()
    local button = self.ToggleButton
    if not button then
        return
    end
    local shown = self._introDone and not self._destroyed and self:_toggleButtonAllowed()
    if shown and not button.Visible then
        button.Visible = true
        button.Size = UDim2.fromOffset(0, 0)
        tween(button, { Size = UDim2.fromOffset(self._toggleSize, self._toggleSize) }, 0.45, Enum.EasingStyle.Quint)
    elseif not shown then
        button.Visible = false
    end
    -- Folded (window minimized or hidden): the outline takes the accent.
    local folded = self.Minimized or not self.Open
    tween(self._toggleStroke, { Color = folded and Theme.Accent or Theme.Stroke, Transparency = folded and 0.3 or 0 }, 0.35)
    local icon = self._toggleIcon
    tween(icon, { Rotation = folded and 180 or 0 }, 0.5, Enum.EasingStyle.Quint)
    if not icon:GetAttribute("CustomIcon") then
        tween(icon, { ImageColor3 = folded and Theme.Text or Theme.Accent }, 0.35)
    end
end

function Window:_createToggleButton(opts)
    local gui = self.Gui
    local size = tonumber(opts.Size) or (TOUCH and 56 or 50)
    local iconSize = math.floor(size * 0.46)
    self._toggleEnabled = opts.Enabled ~= false
    self._togglePlatform = opts.Platform == "Both" and "Both" or "Mobile"
    self._toggleSize = size
    local button = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = opts.Position or UDim2.new(0, 18 + size / 2, 0.5, 0),
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(button, UDim.new(0, 12))
    local buttonStroke = stroke(button, Theme.Stroke)
    local icon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(iconSize, iconSize),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 31,
        Parent = button,
    })
    local buttonScale = create("UIScale", { Parent = button })
    self.ToggleButton = button
    self._toggleStroke = buttonStroke
    self._toggleIcon = icon
    local toggleIcon = opts.Icon
    if toggleIcon == nil then
        toggleIcon = "layout-grid"
    end
    self:SetToggleButtonIcon(toggleIcon)

    local dragging, moved = false, false
    local grab = Vector2.zero
    button.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            moved = false
            grab = pointerPosition() - button.AbsolutePosition
            tween(buttonScale, { Scale = 0.94 }, 0.18, Enum.EasingStyle.Quint)
        end
    end)
    table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
        if not dragging or not isMove(input) then
            return
        end
        local point = pointerPosition() - grab - gui.AbsolutePosition
        if (point - (button.AbsolutePosition - gui.AbsolutePosition)).Magnitude > 3 then
            moved = true
        end
        if moved then
            button.AnchorPoint = Vector2.zero
            button.Position = UDim2.fromOffset(
                math.clamp(point.X, 0, math.max(gui.AbsoluteSize.X - button.AbsoluteSize.X, 0)),
                math.clamp(point.Y, 0, math.max(gui.AbsoluteSize.Y - button.AbsoluteSize.Y, 0))
            )
        end
    end))
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not dragging or not isPress(input) then
            return
        end
        dragging = false
        tween(buttonScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
        if moved then
            return
        end
        ripple(button)
        if not self.Open then
            self:Toggle(true)
        elseif self.Minimized then
            self:Restore()
        else
            self:Minimize()
        end
    end))
end

function Window:SetToggleButton(enabled)
    self._toggleEnabled = enabled ~= false
    self:_refreshToggleButton()
end

function Window:SetToggleButtonPlatform(platform)
    self._togglePlatform = platform == "Both" and "Both" or "Mobile"
    self:_refreshToggleButton()
end

function Window:SetToggleButtonIcon(icon)
    local image = self._toggleIcon
    if not image then
        return
    end
    icon = cleanIcon(icon)
    image.Image = ""
    if icon ~= false then
        applyIcon(image, icon)
        if image.Image == "" then
            applyIcon(image, Assets.Logo)
        end
    end
    if not image:GetAttribute("CustomIcon") then
        tween(image, { ImageColor3 = (self.Minimized or not self.Open) and Theme.Text or Theme.Accent }, 0)
    end
end

function Window:_enableResize(minSize)
    local maxSize = self.MaxSize or Vector2.new(math.huge, math.huge)
    self._minSize = minSize
    local root = self.Root
    local grip = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(1, 4, 1, 4),
        Size = UDim2.fromOffset(32, 32),
        BackgroundTransparency = 1,
        Active = true,
        ZIndex = 20,
        Parent = root,
    })
    self._grip = grip
    -- An arc that traces the window's own rounded corner: a rounded square
    -- laid over the corner whose outline fades out away from it, so only the
    -- curve and a short run of each edge show. Faint at rest, accent in use.
    local gripArc = create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.fromOffset(12, 12),
        Size = UDim2.fromOffset(26, 26),
        BackgroundTransparency = 1,
        ZIndex = 20,
        Parent = grip,
    })
    corner(gripArc, UDim.new(0, 10))
    local gripStroke = create("UIStroke", {
        Color = Theme.Muted,
        Thickness = 2,
        Transparency = 0.55,
        Parent = gripArc,
    })
    create("UIGradient", {
        Rotation = 45,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.55, 1),
            NumberSequenceKeypoint.new(0.85, 0),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = gripStroke,
    })
    local function lightGrip(on)
        tween(gripStroke, {
            Color = on and Theme.Accent or Theme.Muted,
            Transparency = on and 0 or 0.55,
        }, on and 0.15 or 0.3, Enum.EasingStyle.Quint)
    end

    -- The size follows the pointer through a critically damped spring, so it
    -- glides after the cursor and eases to rest when released instead of
    -- snapping. While resizing, the window is anchored at its top-left corner
    -- so only the right and bottom edges move and nothing jitters on half pixels.
    local STIFFNESS = 20
    local resizing = false
    local startSize = Vector2.zero
    local startPointer = Vector2.zero
    local current = Vector2.zero
    local velocity = Vector2.zero
    local target = Vector2.zero
    local applied = Vector2.zero

    local function readSize()
        return Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
    end

    local function pin()
        if root.AnchorPoint == Vector2.zero then
            return
        end
        -- A clamp tween still writing centre coordinates would fight the new anchor.
        if self._clampTween then
            self._clampTween:Cancel()
            self._clampTween = nil
        end
        local topLeft = root.AbsolutePosition - self.Gui.AbsolutePosition
        root.AnchorPoint = Vector2.zero
        root.Position = UDim2.fromOffset(topLeft.X, topLeft.Y)
    end

    local function unpin()
        local topLeft = root.AbsolutePosition - self.Gui.AbsolutePosition
        local half = root.AbsoluteSize / 2
        root.AnchorPoint = Vector2.new(0.5, 0.5)
        root.Position = UDim2.fromOffset(topLeft.X + half.X, topLeft.Y + half.Y)
    end

    local function clampSize(size)
        return Vector2.new(
            math.floor(math.clamp(size.X, minSize.X, maxSize.X) + 0.5),
            math.floor(math.clamp(size.Y, minSize.Y, maxSize.Y) + 0.5)
        )
    end

    grip.InputBegan:Connect(function(input)
        if not isPress(input) or not self.Open then
            return
        end
        if not self._resizeActive then
            pin()
            current = readSize()
            velocity = Vector2.zero
            applied = current
        end
        self._resizeActive = true
        resizing = true
        startSize = current
        startPointer = pointerPosition()
        target = clampSize(startSize)
        lightGrip(true)
    end)
    grip.MouseEnter:Connect(function()
        if not resizing then
            lightGrip(true)
        end
    end)
    grip.MouseLeave:Connect(function()
        if not resizing then
            lightGrip(false)
        end
    end)
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if resizing and isPress(input) then
            resizing = false
            lightGrip(false)
        end
    end))

    table.insert(self._frameSteps, function(deltaTime)
        if not self._resizeActive then
            return
        end
        if resizing then
            local delta = (pointerPosition() - startPointer) / self.Scale.Scale
            target = clampSize(startSize + delta)
        end
        local dt = math.min(deltaTime, 1 / 30)
        local decay = math.exp(-STIFFNESS * dt)
        local offset = current - target
        local drift = (velocity + offset * STIFFNESS) * dt
        velocity = (velocity - drift * STIFFNESS) * decay
        current = target + (offset + drift) * decay

        local rounded = Vector2.new(math.floor(current.X + 0.5), math.floor(current.Y + 0.5))
        if rounded ~= applied then
            applied = rounded
            root.Size = UDim2.fromOffset(rounded.X, rounded.Y)
        end

        if not resizing and (current - target).Magnitude < 0.3 and velocity.Magnitude < 3 then
            current = target
            velocity = Vector2.zero
            applied = target
            root.Size = UDim2.fromOffset(target.X, target.Y)
            unpin()
            self._resizeActive = false
            self:_fitToScreen()
            self:_clampToScreen()
        end
    end)
end

-- The window's own size in pixels, before the UI scale and screen fit.
function Window:GetSize()
    return Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset)
end

-- Resizes to an exact size, kept within MinSize and MaxSize. Ignored while the
-- player is dragging the grip.
function Window:SetSize(size, instant)
    if typeof(size) == "UDim2" then
        size = Vector2.new(size.X.Offset, size.Y.Offset)
    end
    if typeof(size) ~= "Vector2" or self._resizeActive then
        return
    end
    local minSize = self._minSize or Vector2.zero
    local maxSize = self.MaxSize or Vector2.new(math.huge, math.huge)
    size = Vector2.new(
        math.floor(math.clamp(size.X, minSize.X, maxSize.X) + 0.5),
        math.floor(math.clamp(size.Y, minSize.Y, maxSize.Y) + 0.5)
    )
    if size == self:GetSize() then
        return
    end
    local duration = (instant or not self.Root.Visible) and 0 or 0.3
    tween(self.Root, { Size = UDim2.fromOffset(size.X, size.Y) }, duration, Enum.EasingStyle.Quint)
    task.delay(duration + 0.02, function()
        if not self._destroyed then
            self:_fitToScreen()
            self:_clampToScreen()
        end
    end)
end

-- Configs are plain JSON, one file per config, in the same shape as a share code:
--   {"Folder":"MyHub","Name":"farm","Version":1,"Config":"{\"AutoFarm\":{\"Value\":true,\"Type\":\"Toggle\"}}"}
-- Config holds the flags as their own JSON string, each one {"Value":...,"Type":...}.
-- Colours are {"Hex":"ff5a5a"}, keybinds are key names, an empty dropdown has no Value.

local CONFIG_VERSION = 1
local LEGACY_SHARE_PREFIX = "airflow:"

local function configPath(self, name)
    return self.ConfigFolder .. "/" .. name .. ".json"
end

local function fileApiAvailable()
    return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
end

-- Makes every missing folder along the path, so FolderName can be "Hub/Game".
local function ensureFolder(folder)
    if type(isfolder) ~= "function" or type(makefolder) ~= "function" then
        return
    end
    local path = ""
    for segment in tostring(folder):gmatch("[^/\\]+") do
        path = path == "" and segment or path .. "/" .. segment
        if not isfolder(path) then
            makefolder(path)
        end
    end
end

local function colorToHex(color)
    return string.format("%02x%02x%02x",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5))
end

local function colorFromValue(value)
    if type(value) == "table" then
        if type(value.Hex) == "string" then
            value = value.Hex
        elseif type(value[1]) == "number" then
            -- Older configs stored { r, g, b } in 0-1.
            return Color3.new(value[1], value[2] or 0, value[3] or 0)
        end
    end
    if type(value) == "string" then
        local r, g, b = value:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
        end
    end
    return nil
end

local function serializeFlag(element)
    local kind = element._type
    local value = element:Get()
    if type(element._saveValue) == "function" then
        value = element:_saveValue()
    end
    if kind == "Keybind" then
        return { Type = kind, Value = value and value.Name or nil }
    elseif kind == "ColorPicker" then
        return { Type = kind, Value = typeof(value) == "Color3" and { Hex = colorToHex(value) } or nil }
    end
    return { Type = kind, Value = value }
end

local function deserializeFlag(element, entry, silent)
    local kind = element._type
    local value = entry.Value
    if kind == "Keybind" then
        element:Set(Keybinds.Resolve(value), silent)
    elseif kind == "ColorPicker" then
        local color = colorFromValue(value)
        if color then
            element:Set(color, silent)
        end
    elseif kind == "Dropdown" then
        -- A dropdown saved with nothing picked has no Value at all.
        element:Set(value, silent)
    elseif kind == "Toggle" then
        if type(value) == "boolean" then
            element:Set(value, silent)
        end
    elseif kind == "Slider" or kind == "Stepper" or kind == "Progress" then
        local number = tonumber(value)
        if number then
            element:Set(number, silent)
        end
    elseif value ~= nil then
        element:Set(value, silent)
    end
end

local function entryMatches(element, entry)
    return type(entry) == "table" and (entry.Type == nil or entry.Type == element._type)
end

-- Flags a config holds but no element has claimed yet are kept here. They are
-- applied when an element with that flag is created and written back on save,
-- so a config survives elements that only exist some of the time.
local function collectFlags(self)
    local data = {}
    if self and self._pendingFlags then
        for flag, pending in pairs(self._pendingFlags) do
            data[flag] = pending.Entry
        end
    end
    for flag, element in pairs(Library.Flags) do
        if element._type and type(element.Get) == "function" then
            local ok, entry = pcall(serializeFlag, element)
            if ok then
                data[flag] = entry
            end
        end
    end
    return data
end

function Window:_applyFlags(data, silent)
    silent = silent == true
    self._pendingFlags = {}
    for flag, entry in pairs(data) do
        local element = Library.Flags[flag]
        if element and type(element.Set) == "function" then
            if entryMatches(element, entry) then
                pcall(deserializeFlag, element, entry, silent)
            end
        elseif type(entry) == "table" then
            self._pendingFlags[flag] = { Entry = entry, Silent = silent }
        end
    end
end

-- Every flagged element reports here: its starting value becomes its default,
-- and a value waiting from an earlier load is applied once the constructor returns.
function Window:_flagCreated(flag, element)
    local ok, entry = pcall(serializeFlag, element)
    if ok then
        element._defaultEntry = entry
    end
    local pending = self._pendingFlags and self._pendingFlags[flag]
    if not pending then
        return
    end
    task.defer(function()
        if self._pendingFlags[flag] ~= pending or Library.Flags[flag] ~= element or element._destroyed then
            return
        end
        self._pendingFlags[flag] = nil
        if entryMatches(element, pending.Entry) then
            pcall(deserializeFlag, element, pending.Entry, pending.Silent)
        end
    end)
end

-- Anything listening for config changes (the config manager's status line).
function Window:_configChanged()
    for _, handler in ipairs(self._configListeners) do
        safeCall(handler)
    end
end

function Window:OnConfigChanged(handler)
    table.insert(self._configListeners, handler)
    return function()
        local index = table.find(self._configListeners, handler)
        if index then
            table.remove(self._configListeners, index)
        end
    end
end

local function validConfigName(name)
    return type(name) == "string" and name ~= "" and not name:find('[\\/:%*%?"<>|]')
end

local function encodeConfig(self, name, flags)
    return HttpService:JSONEncode({
        Folder = self.ConfigFolder,
        Name = name,
        Version = CONFIG_VERSION,
        Config = HttpService:JSONEncode(flags),
    })
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for index = 1, #B64 do
    B64_INDEX[B64:byte(index)] = index - 1
end

-- Only for reading the old "airflow:<base64>" share codes.
local function base64Decode(text)
    if #text % 4 ~= 0 then
        return nil
    end
    local out = {}
    for index = 1, #text, 4 do
        local n, pad = 0, 0
        for offset = 0, 3 do
            local byte = text:byte(index + offset)
            local value = B64_INDEX[byte]
            if byte == 61 and index + 3 >= #text then
                pad += 1
                value = 0
            elseif value == nil or pad > 0 then
                return nil
            end
            n = n * 64 + value
        end
        if pad > 2 then
            return nil
        end
        local chunk = string.char(bit32.extract(n, 16, 8), bit32.extract(n, 8, 8), bit32.extract(n, 0, 8))
        table.insert(out, chunk:sub(1, 3 - pad))
    end
    return table.concat(out)
end

-- Reads a config file or a pasted code: the JSON above (Config as a string or
-- a table), a bare flag table, or an old "airflow:" code. Returns flags, info.
local function decodeConfig(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text:sub(1, #LEGACY_SHARE_PREFIX) == LEGACY_SHARE_PREFIX then
        text = base64Decode((text:sub(#LEGACY_SHARE_PREFIX + 1):gsub("%s", "")))
        if not text then
            return nil, "invalid config code"
        end
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(text)
    end)
    if not ok or type(data) ~= "table" then
        return nil, "invalid config code"
    end
    local info = {}
    -- A bare flag table could have a flag named Config, but its entry carries a Type.
    if type(data.Config) == "string" or (type(data.Config) == "table" and data.Config.Type == nil) then
        info.Folder = type(data.Folder) == "string" and data.Folder or nil
        info.Name = type(data.Name) == "string" and data.Name or nil
        info.Version = tonumber(data.Version)
        local flags = data.Config
        if type(flags) == "string" then
            ok, flags = pcall(function()
                return HttpService:JSONDecode(data.Config)
            end)
            if not ok then
                return nil, "invalid config code"
            end
        end
        if type(flags) ~= "table" then
            return nil, "invalid config code"
        end
        data = flags
    end
    for flag, entry in pairs(data) do
        if type(flag) ~= "string" or type(entry) ~= "table" then
            return nil, "invalid config code"
        end
    end
    return data, info
end

local function writeConfig(self, name, data)
    if not validConfigName(name) then
        return false, "invalid config name"
    end
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    local encoded, text = pcall(encodeConfig, self, name, data)
    if not encoded then
        return false, "could not encode config"
    end
    ensureFolder(self.ConfigFolder)
    return pcall(writefile, configPath(self, name), text)
end

local function readConfig(self, name)
    if not fileApiAvailable() then
        return nil, "file API unavailable"
    end
    if not validConfigName(name) then
        return nil, "invalid config name"
    end
    local path = configPath(self, name)
    if not isfile(path) then
        return nil, "no config named " .. tostring(name)
    end
    local ok, text = pcall(readfile, path)
    if not ok or type(text) ~= "string" then
        return nil, "could not read " .. name
    end
    local data, info = decodeConfig(text)
    if not data then
        return nil, "config is not valid JSON"
    end
    return data, info
end

function Window:ConfigExists(name)
    return validConfigName(name) and fileApiAvailable() and isfile(configPath(self, name)) or false
end

function Window:SaveConfig(name)
    name = name or self.ConfigName
    if not name then
        return false, "no config name"
    end
    local ok, err = writeConfig(self, name, collectFlags(self))
    if ok then
        self.ConfigName = name
    end
    return ok, err
end

function Window:LoadConfig(name, silent)
    name = name or self.ConfigName
    if not name then
        return false, "no config name"
    end
    local data, err = readConfig(self, name)
    if not data then
        return false, err
    end
    self:_applyFlags(data, silent)
    self.ConfigName = name
    self.LoadedConfig = name
    self:_configChanged()
    return true
end

function Window:DeleteConfig(name)
    if not fileApiAvailable() or type(delfile) ~= "function" then
        return false, "file API unavailable"
    end
    if not validConfigName(name) then
        return false, "invalid config name"
    end
    local path = configPath(self, name)
    if not isfile(path) then
        return false, "no config named " .. name
    end
    local ok, err = pcall(delfile, path)
    if not ok then
        return false, err
    end
    if self.LoadedConfig == name then
        self.LoadedConfig = nil
    end
    self:_configChanged()
    return true
end

-- Moves the file and anything pointing at it: the loaded name and both autoloads.
function Window:RenameConfig(name, newName)
    if not validConfigName(newName) then
        return false, "invalid config name"
    end
    if name == newName then
        return true
    end
    if self:ConfigExists(newName) then
        return false, newName .. " already exists"
    end
    local data, err = readConfig(self, name)
    if not data then
        return false, err
    end
    local ok
    ok, err = writeConfig(self, newName, data)
    if not ok then
        return false, err
    end
    if type(delfile) == "function" then
        pcall(delfile, configPath(self, name))
    end
    if self.LoadedConfig == name then
        self.LoadedConfig = newName
    end
    if self.ConfigName == name then
        self.ConfigName = newName
    end
    for _, scope in ipairs({ "Global", "Account" }) do
        if self:GetAutoload(scope) == name then
            self:SetAutoload(newName, scope)
        end
    end
    self:_configChanged()
    return true
end

function Window:ListConfigs()
    local names = {}
    if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(self.ConfigFolder) then
        return names
    end
    local ok, paths = pcall(listfiles, self.ConfigFolder)
    if not ok or type(paths) ~= "table" then
        return names
    end
    for _, path in ipairs(paths) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)
    return names
end

-- Puts every flagged element back to the value it was created with.
function Window:ResetConfig(silent)
    self._pendingFlags = {}
    for _, element in pairs(Library.Flags) do
        if element._defaultEntry and type(element.Set) == "function" then
            pcall(deserializeFlag, element, element._defaultEntry, silent == true)
        end
    end
    self:_configChanged()
    return true
end

-- Empties a folder and removes it, one file at a time when the executor has
-- no delfolder or it refuses a folder that still has files in it.
local function wipeFolder(path)
    if type(isfolder) ~= "function" or not isfolder(path) then
        return true
    end
    if type(delfolder) == "function" and pcall(delfolder, path) and not isfolder(path) then
        return true
    end
    if type(listfiles) == "function" then
        local ok, entries = pcall(listfiles, path)
        for _, entry in ipairs(ok and entries or {}) do
            if isfolder(entry) then
                wipeFolder(entry)
            elseif type(delfile) == "function" then
                pcall(delfile, entry)
            end
        end
    end
    if type(delfolder) == "function" then
        pcall(delfolder, path)
    end
    return not isfolder(path)
end

-- Deletes the script's whole workspace folder: configs, themes, the default
-- theme, autoload, settings and the execution count.
function Window:ClearWorkspace()
    local ok = wipeFolder(self.ConfigFolder)
    self.LoadedConfig = nil
    for _, handler in ipairs(self._workspaceListeners or {}) do
        safeCall(handler)
    end
    self:_configChanged()
    return ok
end

-- Share codes are the same JSON a config file holds.

function Window:ExportConfig(name)
    local data, err
    if name then
        data, err = readConfig(self, name)
        if not data then
            return nil, err
        end
    else
        data = collectFlags(self)
        name = self.LoadedConfig or self.ConfigName
    end
    local ok, code = pcall(encodeConfig, self, name, data)
    if not ok then
        return nil, "could not encode config"
    end
    return code
end

-- Reads a code without applying it. Returns flags and { Folder, Name, Version }.
function Window:DecodeConfig(code)
    return decodeConfig(code)
end

-- saveAs: a name to save under, true for the name inside the code, or nil to
-- only apply it. Codes made for another folder are refused unless force is set.
function Window:ImportConfig(code, saveAs, force)
    local data, info = decodeConfig(code)
    if not data then
        return false, info
    end
    if not force and info.Folder and info.Folder ~= self.ConfigFolder then
        return false, "config is for " .. info.Folder
    end
    if saveAs == true then
        saveAs = info.Name
        if not validConfigName(saveAs) then
            return false, "config has no usable name"
        end
    end
    if saveAs then
        local ok, err = writeConfig(self, saveAs, data)
        if not ok then
            return false, err
        end
    end
    self:_applyFlags(data)
    if saveAs then
        self.ConfigName = saveAs
        self.LoadedConfig = saveAs
    end
    self:_configChanged()
    return true, nil, saveAs
end

local function readText(path)
    if not fileApiAvailable() or not isfile(path) then
        return nil
    end
    local ok, text = pcall(readfile, path)
    if ok and type(text) == "string" and text ~= "" then
        return text
    end
    return nil
end

local function removeFile(path)
    if fileApiAvailable() and type(delfile) == "function" and isfile(path) then
        pcall(delfile, path)
    end
end

-- Manager settings (autoload mode) live beside the configs, apart
-- from the flags, so loading a config never changes them.

local function settingsPath(self)
    return self.ConfigFolder .. "/configsettings.txt"
end

function Window:_readConfigSettings()
    local text = readText(settingsPath(self))
    if text then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(text)
        end)
        if ok and type(data) == "table" then
            return data
        end
    end
    return {}
end

function Window:_writeConfigSettings(changes)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    local data = self:_readConfigSettings()
    for key, value in pairs(changes) do
        data[key] = value
    end
    ensureFolder(self.ConfigFolder)
    return pcall(writefile, settingsPath(self), HttpService:JSONEncode(data))
end

-- Autoload: one config name kept next to the configs, either for every
-- account ("Global") or only the local player ("Account").

local function autoloadPath(self, scope)
    if scope == "Account" then
        return self.ConfigFolder .. "/autoload_" .. tostring(LocalPlayer and LocalPlayer.UserId or 0) .. ".txt"
    end
    return self.ConfigFolder .. "/autoload.txt"
end

function Window:GetAutoloadMode()
    return self:_readConfigSettings().AutoloadMode == "Account" and "Account" or "Global"
end

function Window:GetAutoload(scope)
    if scope then
        return readText(autoloadPath(self, scope))
    end
    return readText(autoloadPath(self, "Account")) or readText(autoloadPath(self, "Global"))
end

function Window:SetAutoload(name, scope)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    scope = scope or self:GetAutoloadMode()
    local ok, err = true, nil
    if name == nil or name == "" then
        removeFile(autoloadPath(self, scope))
        if scope == "Global" then
            removeFile(autoloadPath(self, "Account"))
        end
    else
        ensureFolder(self.ConfigFolder)
        ok, err = pcall(writefile, autoloadPath(self, scope), tostring(name))
        if ok and scope == "Global" then
            removeFile(autoloadPath(self, "Account"))
        end
    end
    self:_configChanged()
    return ok, err
end

-- Switching the mode moves the current autoload so only one stays active.
function Window:SetAutoloadMode(mode)
    mode = mode == "Account" and "Account" or "Global"
    if mode == self:GetAutoloadMode() then
        return true
    end
    local current = self:GetAutoload()
    local ok, err = self:_writeConfigSettings({ AutoloadMode = mode })
    if not ok then
        return false, err
    end
    removeFile(autoloadPath(self, mode == "Account" and "Global" or "Account"))
    if current then
        return self:SetAutoload(current, mode)
    end
    self:_configChanged()
    return true
end

function Window:LoadAutoload(silent)
    local name = self:GetAutoload()
    if not name then
        return false, "no autoload config"
    end
    return self:LoadConfig(name, silent)
end

-- Themes

Library._themeListeners = {}

local function toColor(value)
    if typeof(value) == "Color3" then
        return value
    elseif type(value) == "string" then
        local r, g, b = value:match("^%s*#?(%x%x)(%x%x)(%x%x)%s*$")
        if r then
            return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
        end
    elseif type(value) == "table" then
        local r, g, b = value[1] or value.R, value[2] or value.G, value[3] or value.B
        if tonumber(r) and tonumber(g) and tonumber(b) then
            return Color3.fromRGB(r, g, b)
        end
    end
    return nil
end

local function hexOf(color)
    return string.format("#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5))
end

-- Coloured text for statuses, metrics, table cells and labels. A theme key
-- used as a tag, <Success>online</Success>, follows theme changes; plain
-- rich text such as <font color="#ff5a5a"> works too. Library.Colorize wraps
-- text for you. Table fields, not locals: the chunk is at Luau's 200 limit.
Library._toneTags = {}
for _, name in ipairs(THEME_KEYS) do
    Library._toneTags[string.lower(name)] = name
end

-- A theme key, a Color3, "#rrggbb" or { r, g, b } as a Color3.
function Library._color(value)
    if type(value) == "string" then
        local key = Library._toneTags[string.lower(value)]
        if key then
            return Theme[key]
        end
    end
    return toColor(value)
end

function Library._rich(text)
    text = tostring(text == nil and "" or text)
    if not string.find(text, "<", 1, true) then
        return text
    end
    return (string.gsub(text, "<(/?)(%a+%d*)>", function(slash, name)
        local key = Library._toneTags[string.lower(name)]
        if not key then
            return nil
        end
        if slash == "/" then
            return "</font>"
        end
        return '<font color="' .. hexOf(Theme[key]) .. '">'
    end))
end

-- Library.Colorize("12 ms", "Success") or Library:Colorize(text, Color3).
function Library.Colorize(...)
    local args = { ... }
    if args[1] == Library then
        table.remove(args, 1)
    end
    local text, color = tostring(args[1] == nil and "" or args[1]), args[2]
    local key = type(color) == "string" and Library._toneTags[string.lower(color)]
    if key then
        return "<" .. key .. ">" .. text .. "</" .. key .. ">"
    end
    local resolved = toColor(color)
    if not resolved then
        return text
    end
    return '<font color="' .. hexOf(resolved) .. '">' .. text .. "</font>"
end

-- The window's corner radius in pixels, 0 (square) to 20; every other
-- rounded corner scales with it. The default is 10. Corners ease to the new
-- radius instead of jumping. Returns the radius it settled on.
function Library:SetCornerRadius(pixels, instant)
    pixels = math.clamp(math.floor((tonumber(pixels) or 10) + 0.5), 0, 20)
    Library.Roundness = pixels / 10
    for object, base in pairs(Library._cornerBases) do
        if not object.Parent then
            Library._cornerBases[object] = nil
        else
            local radius = UDim.new(0, math.floor(base * Library.Roundness + 0.5))
            if instant then
                object.CornerRadius = radius
            else
                tween(object, { CornerRadius = radius }, 0.25, Enum.EasingStyle.Quint)
            end
        end
    end
    return pixels
end

function Library:GetCornerRadius()
    return math.floor(Library.Roundness * 10 + 0.5)
end

function Library:SetTheme(theme, instant)
    if type(theme) == "string" then
        local found = Library.ThemePresets[theme]
        if not found then
            return false
        end
        Library.ThemeName = theme
        theme = found
    elseif type(theme) ~= "table" then
        return false
    end
    local changed = false
    for _, name in ipairs(THEME_KEYS) do
        local color = toColor(theme[name])
        if color and color ~= Theme[name] then
            Theme[name] = color
            changed = true
        end
    end
    if not changed then
        return true
    end
    rebuildThemeLookup()
    sweepBindings()
    driveTheme(instant and 0 or 0.3)
    for owner, fn in pairs(themeHooks) do
        if owner.Parent then
            pcall(fn)
        end
    end
    for _, fn in ipairs(Library._themeListeners) do
        pcall(fn)
    end
    return true
end

function Library:GetTheme()
    local copy = {}
    for _, name in ipairs(THEME_KEYS) do
        copy[name] = Theme[name]
    end
    return copy
end

-- The script's starting theme: a preset name or a colour table. A default the
-- player picked in the theme manager still wins over it.
function Library:SetDefaultTheme(theme)
    Library.DefaultTheme = theme
    if theme == nil then
        return true
    end
    local live = false
    for _, window in ipairs(Library.Windows) do
        if not window._destroyed then
            if window:GetDefaultTheme() then
                return true
            end
            live = true
        end
    end
    return Library:SetTheme(theme, not live)
end

function Library:GetDefaultTheme()
    return Library.DefaultTheme
end

local function themeFolder(self)
    return self.ConfigFolder .. "/themes"
end

function Window:SaveTheme(name)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    if type(name) ~= "string" or name == "" then
        return false, "theme needs a name"
    end
    ensureFolder(self.ConfigFolder)
    ensureFolder(themeFolder(self))
    local data = {}
    for _, key in ipairs(THEME_KEYS) do
        data[key] = hexOf(Theme[key])
    end
    return pcall(function()
        writefile(themeFolder(self) .. "/" .. name .. ".json", HttpService:JSONEncode(data))
    end)
end

function Window:LoadTheme(name, instant)
    if Library.ThemePresets[name] then
        return Library:SetTheme(name, instant)
    end
    local text = readText(themeFolder(self) .. "/" .. tostring(name) .. ".json")
    if not text then
        return false, "no theme named " .. tostring(name)
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(text)
    end)
    if not ok or type(data) ~= "table" then
        return false, "theme is not valid JSON"
    end
    Library.ThemeName = name
    return Library:SetTheme(data, instant)
end

function Window:DeleteTheme(name)
    if not fileApiAvailable() or type(delfile) ~= "function" then
        return false, "file API unavailable"
    end
    local path = themeFolder(self) .. "/" .. tostring(name) .. ".json"
    if not isfile(path) then
        return false, "no theme named " .. tostring(name)
    end
    delfile(path)
    if self:GetDefaultTheme() == name then
        self:SetDefaultTheme(nil)
    end
    return true
end

function Window:ListThemes()
    local names = {}
    if type(listfiles) ~= "function" or type(isfolder) ~= "function" or not isfolder(themeFolder(self)) then
        return names
    end
    for _, path in ipairs(listfiles(themeFolder(self))) do
        local name = path:match("([^/\\]+)%.json$")
        if name then
            table.insert(names, name)
        end
    end
    table.sort(names)
    return names
end

function Window:GetDefaultTheme()
    return readText(themeFolder(self) .. "/default.txt")
end

function Window:SetDefaultTheme(name)
    if not fileApiAvailable() then
        return false, "file API unavailable"
    end
    ensureFolder(self.ConfigFolder)
    ensureFolder(themeFolder(self))
    local path = themeFolder(self) .. "/default.txt"
    if name == nil or name == "" then
        if isfile(path) and type(delfile) == "function" then
            pcall(delfile, path)
        end
        return true
    end
    return pcall(writefile, path, tostring(name))
end

function Window:_applyDefaultTheme()
    local name = self:GetDefaultTheme()
    if name then
        local ok, loaded = pcall(self.LoadTheme, self, name, true)
        if ok and loaded then
            return
        end
    end
    if Library.DefaultTheme ~= nil then
        pcall(Library.SetTheme, Library, Library.DefaultTheme, true)
    end
end

-- Background images

-- Image assets anyone can use, from Fluent-modded's themes.
Library.BackgroundPresets = {
    ["Deep Violet"] = "rbxassetid://136310484943077",
    ["Blood Red"] = "rbxassetid://121343473918667",
    ["Cyanic"] = "rbxassetid://95656189244173",
    ["Amber Glow"] = "rbxassetid://107795771598485",
    ["Bloomings"] = "rbxassetid://133541508207801",
    ["Lavender Pink"] = "rbxassetid://126107479485287",
}
Library.BackgroundPresetOrder = { "Deep Violet", "Blood Red", "Cyanic", "Amber Glow", "Bloomings", "Lavender Pink" }

-- Table fields, not locals: the library chunk is at Luau's 200 local limit.
Library._imageExtensions = { png = true, jpg = true, jpeg = true, webp = true, gif = true, bmp = true }

function Window:_backgroundFolder()
    return self.ConfigFolder .. "/backgrounds"
end

function Window:_trimBackground(source)
    return (tostring(source or ""):match("^%s*(.-)%s*$"))
end

-- Turns a background source into something ImageLabel.Image takes. Web images
-- are downloaded once into backgrounds/cache and loaded with getcustomasset,
-- so this yields the first time a URL is used.
function Window:_resolveBackground(source)
    source = self:_trimBackground(source)
    local preset = Library.BackgroundPresets[source]
    if preset then
        return preset
    end
    if source:match("^%d+$") then
        return "rbxassetid://" .. source
    end
    if source:match("^rbxassetid://%d+") or source:match("^rbxasset://") or source:match("^rbxthumb://")
        or source:match("^https?://www%.roblox%.com/asset") then
        return source
    end
    local canLoad = fileApiAvailable() and typeof(getcustomasset) == "function"
    if source:match("^https?://") then
        if not canLoad then
            return nil, "web images need writefile and getcustomasset"
        end
        local clean = source:match("^[^?#]+") or source
        local ext = (clean:match("%.(%w+)$") or "png"):lower()
        if not Library._imageExtensions[ext] then
            ext = "png"
        end
        local key = (clean:gsub("^https?://", ""):gsub("[^%w]", "_")):sub(-60)
        local folder = self:_backgroundFolder() .. "/cache"
        local path = folder .. "/" .. key .. "_" .. #source .. "." .. ext
        if not isfile(path) then
            local ok, body = pcall(function()
                local request = (syn and syn.request) or http_request or request
                if request then
                    local response = request({ Url = source, Method = "GET" })
                    return response and response.Body
                end
                return game:HttpGet(source, true)
            end)
            if not ok or type(body) ~= "string" or #body < 128 then
                return nil, "could not download the image"
            end
            local head = body:sub(1, 64):lower()
            if head:find("<!doctype") or head:find("<html") then
                return nil, "that link is a web page, not an image"
            end
            ensureFolder(folder)
            if not pcall(writefile, path, body) then
                return nil, "could not save the image"
            end
        end
        local ok, asset = pcall(getcustomasset, path)
        if ok and type(asset) == "string" and asset ~= "" then
            return asset
        end
        pcall(delfile, path)
        return nil, "the downloaded file is not an image"
    end
    -- A file in the backgrounds folder, or any path in the workspace.
    if canLoad then
        for _, path in ipairs({ self:_backgroundFolder() .. "/" .. source, source }) do
            if isfile(path) then
                local ok, asset = pcall(getcustomasset, path)
                if ok and type(asset) == "string" and asset ~= "" then
                    return asset
                end
                return nil, "could not load " .. source
            end
        end
    end
    return nil, "no image called " .. source
end

-- source: a preset name, an image asset id, an rbxassetid:// link, an http(s)
-- image URL, or an image file in <ConfigFolder>/backgrounds. nil or "None"
-- removes it. May yield while a web image downloads.
function Window:SetBackground(source)
    self._backgroundGeneration += 1
    local generation = self._backgroundGeneration
    local image = self._backgroundImage
    source = source ~= false and self:_trimBackground(source) or ""
    if source == "" or source == "None" then
        self.Background = nil
        tween(image, { ImageTransparency = 1 }, 0.25)
        task.delay(0.25, function()
            if self._backgroundGeneration == generation then
                image.Visible = false
                image.Image = ""
            end
        end)
        self:SetTransparent(self.Transparent)
        return true
    end
    local asset, err = self:_resolveBackground(source)
    if self._backgroundGeneration ~= generation or self._destroyed then
        return false, "replaced by a newer background"
    end
    if not asset then
        return false, err
    end
    self.Background = source
    image.Image = asset
    image.Visible = true
    tween(image, { ImageTransparency = self.BackgroundTransparency }, 0.3)
    self:SetTransparent(self.Transparent)
    return true
end

function Window:GetBackground()
    return self.Background
end

-- 0 shows the image fully, 1 hides it behind the theme background colour.
function Window:SetBackgroundTransparency(value)
    self.BackgroundTransparency = math.clamp(tonumber(value) or 0.35, 0, 1)
    if self.Background then
        tween(self._backgroundImage, { ImageTransparency = self.BackgroundTransparency }, 0.15)
    end
end

-- Preset names, then the image files in <ConfigFolder>/backgrounds.
function Window:ListBackgrounds()
    local names = table.clone(Library.BackgroundPresetOrder)
    local folder = self:_backgroundFolder()
    if type(listfiles) == "function" and type(isfolder) == "function" and isfolder(folder) then
        local files = {}
        for _, path in ipairs(listfiles(folder)) do
            local name = path:match("([^/\]+)$")
            local ext = name and name:match("%.(%w+)$")
            if ext and Library._imageExtensions[ext:lower()] then
                table.insert(files, name)
            end
        end
        table.sort(files)
        for _, name in ipairs(files) do
            table.insert(names, name)
        end
    end
    return names
end

local function emptyState(parent, icon, text)
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, -10),
        Size = UDim2.fromOffset(200, 70),
        BackgroundTransparency = 1,
        Parent = parent,
    })
    local image
    if icon then
        image = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 0),
            Size = UDim2.fromOffset(26, 26),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ImageTransparency = 0.15,
            ScaleType = Enum.ScaleType.Fit,
            Parent = holder,
        })
        applyIcon(image, icon)
    end
    local caption = label({
        Position = UDim2.fromOffset(0, image and 36 or 27),
        Size = UDim2.new(1, 0, 0, 16),
        Text = text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = holder,
    })
    return holder, caption, image
end

local function fadeSlideIn(group, restY)
    restY = restY or 0
    group.GroupTransparency = 1
    group.Position = UDim2.fromOffset(0, restY + 14)
    group.Visible = true
    tween(group, { GroupTransparency = 0, Position = UDim2.fromOffset(0, restY) }, 0.32, Enum.EasingStyle.Quint)
end

local function formatDuration(seconds)
    seconds = math.max(math.floor(seconds), 0)
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds / 3600) % 24
    local minutes = math.floor(seconds / 60) % 60
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, seconds % 60)
    end
    return string.format("%ds", seconds)
end

local function shortId(id)
    if type(id) ~= "string" or id == "" then
        return "Studio"
    end
    if #id > 16 then
        return id:sub(1, 8) .. "..." .. id:sub(-4)
    end
    return id
end

local function copyToClipboard(text)
    local setter = setclipboard or toclipboard or (Clipboard and Clipboard.set)
    if type(setter) ~= "function" then
        return false
    end
    return (pcall(setter, tostring(text)))
end

local function fetchServers(order)
    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%s&limit=100&excludeFullGames=true",
        game.PlaceId,
        order
    )
    local ok, body = pcall(function()
        return game:HttpGet(url)
    end)
    if not ok or type(body) ~= "string" then
        return nil
    end
    local decoded, data = pcall(function()
        return HttpService:JSONDecode(body)
    end)
    if not decoded or type(data) ~= "table" or type(data.data) ~= "table" then
        return nil
    end
    return data.data
end

-- Small on/off pill used on the home card for the privacy switches.
local function miniSwitch(parent, initial, order, callback)
    local pill = create("TextButton", {
        Size = UDim2.fromOffset(30, 16),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(pill, UDim.new(1, 0))
    stroke(pill)
    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 2, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Theme.Muted,
        BorderSizePixel = 0,
        Parent = pill,
    })
    corner(knob, UDim.new(1, 0))
    local on = initial == true
    local function render(animate)
        local duration = animate and 0.22 or 0
        tween(pill, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3 }, duration)
        tween(knob, {
            Position = on and UDim2.new(0, 16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
            BackgroundColor3 = on and Theme.AccentDark or Theme.Muted,
        }, duration, Enum.EasingStyle.Back)
    end
    pill.MouseButton1Click:Connect(function()
        on = not on
        render(true)
        safeCall(callback, on)
    end)
    render(false)
    return pill
end

local function softButton(parent, text, props, callback)
    local button = create("TextButton", {
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        Parent = parent,
    })
    for key, value in pairs(props) do
        button[key] = value
    end
    corner(button, UDim.new(0, 6))
    local buttonStroke = stroke(button)
    local text_ = label({
        Size = UDim2.fromScale(1, 1),
        Text = text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = button,
    })
    if button.AutomaticSize == Enum.AutomaticSize.X then
        text_.Size = UDim2.new(0, 0, 1, 0)
        text_.AutomaticSize = Enum.AutomaticSize.X
        text_.TextTruncate = Enum.TextTruncate.None
        padding(button, 14, 14)
    end
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0.15 }, 0.12)
        tween(buttonStroke, { Color = Theme.StrokeHover }, 0.12)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0.45 }, 0.25)
        tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(callback)
    end)
    return button, text_
end

local function panelCard(parent, height, order)
    local frame = create("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = order,
        Parent = parent,
    })
    frame:SetAttribute("NoDrag", true)
    corner(frame, UDim.new(0, 10))
    stroke(frame)
    return frame
end

local STAT_TYPES = {
    Players = { "users", "Players" },
    Friends = { "user-check", "Friends" },
    Execs = { "zap", "Execs" },
    Session = { "timer", "Session" },
    Uptime = { "timer", "Session" },
    FPS = { "gauge", "FPS" },
    Ping = { "wifi", "Ping" },
    Executor = { "terminal", "Executor" },
    Game = { "gamepad-2", "Game" },
    Region = { "globe", "Region" },
    Time = { "clock", "Time" },
    ServerAge = { "server", "Server age" },
    Memory = { "cpu", "Memory" },
}

-- Health colour for a live metric: Success under good, Warning under bad,
-- Error past it. lowerIsBetter flips the scale (ping, memory).
function Library._healthColor(value, good, bad, lowerIsBetter)
    if type(value) ~= "number" then
        return Theme.Text
    end
    if lowerIsBetter then
        return value <= good and Theme.Success or value <= bad and Theme.Warning or Theme.Error
    end
    return value >= good and Theme.Success or value >= bad and Theme.Warning or Theme.Error
end

local function bumpExecutions(folder)
    if not fileApiAvailable() then
        return nil
    end
    local path = folder .. "/executions.txt"
    local count = 0
    pcall(function()
        ensureFolder(folder)
        if isfile(path) then
            count = tonumber(readfile(path)) or 0
        end
    end)
    count += 1
    pcall(writefile, path, tostring(count))
    return count
end

-- Containers: a tab or sub tab owns a scrolling list. Elements added straight
-- to it stack full width, groupboxes go into two columns underneath.

local function buildContainer(owner, parent, top, emptyIcon, emptyText)
    local list = create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, top),
        Size = UDim2.new(1, 0, 1, -top),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.5,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = parent,
    })
    Library._space(padding(list, 24, 24, 2, 24), { 24, 24, 2, 24 })
    Library._space(create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = list,
    }), 8)
    owner.List = list
    owner._items = {}
    owner._groupboxes = {}
    owner._childCount = 0
    owner._emptyText = emptyText
    owner._empty, owner._emptyCaption = emptyState(parent, emptyIcon, emptyText)
    list.ChildAdded:Connect(function(child)
        if child:IsA("GuiObject") then
            owner._childCount += 1
            owner:_refreshEmpty()
        end
    end)
    list.ChildRemoved:Connect(function(child)
        if child:IsA("GuiObject") then
            owner._childCount = math.max(owner._childCount - 1, 0)
            owner:_refreshEmpty()
        end
    end)
    owner:_refreshEmpty()
    return list
end

function Tab:_refreshEmpty()
    local empty = self._empty
    if not empty then
        return
    end
    if self._subTabs then
        empty.Visible = false
    else
        empty.Visible = self._childCount == 0
    end
end

function Tab:_columns()
    if self._columnSet then
        return self._columnSet
    end
    local holder = create("Frame", {
        Name = "Columns",
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 100000,
        Parent = self.List,
    })
    local layout = Library._space(create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = holder,
    }), 10)
    local function column(order)
        local frame = create("Frame", {
            Size = UDim2.new(0.5, -5, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = holder,
        })
        Library._space(create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 10),
            Parent = frame,
        }), 10)
        return frame
    end
    local set = { Holder = holder, Left = column(1), Right = column(2), Counts = { 0, 0 }, Stacked = false }
    local window = self.Window
    -- Narrow windows stack the right column under the left one.
    local function relayout()
        local width = holder.AbsoluteSize.X / window.Scale.Scale
        if width <= 0 then
            return
        end
        local stacked = width < STACK_BELOW
        local gap = layout.Padding.Offset
        if stacked == set.Stacked and gap == set.Gap then
            return
        end
        set.Stacked = stacked
        set.Gap = gap
        layout.FillDirection = stacked and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
        local size = stacked and UDim2.new(1, 0, 0, 0) or UDim2.new(0.5, -gap / 2, 0, 0)
        set.Left.Size = size
        set.Right.Size = size
    end
    holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
    layout:GetPropertyChangedSignal("Padding"):Connect(relayout)
    task.defer(relayout)
    self._columnSet = set
    return set
end

function Tab:Groupbox(opts, icon)
    if self._groupbox then
        return self.Parent:Groupbox(opts, icon)
    end
    opts = normalize(opts, { Title = "Name" })
    if icon ~= nil and opts.Icon == nil then
        opts.Icon = cleanIcon(icon)
    end
    local window = self.Window
    local set = self:_columns()
    local side = opts.Side
    if side == "Left" or side == 1 then
        side = 1
    elseif side == "Right" or side == 2 then
        side = 2
    else
        side = set.Counts[1] <= set.Counts[2] and 1 or 2
    end
    set.Counts[side] += 1

    local box = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        LayoutOrder = set.Counts[side],
        Parent = side == 1 and set.Left or set.Right,
    })
    box:SetAttribute("NoDrag", true)
    corner(box, UDim.new(0, 10))
    stroke(box)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = box,
    })

    -- The header is a filled strip: icon and bold title on the left, a
    -- chevron on the right. Pressing anywhere on it folds the box.
    local header = create("TextButton", {
        Size = UDim2.new(1, 0, 0, 40),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = 1,
        Parent = box,
    })
    corner(header, UDim.new(0, 10))
    -- Squares the strip's lower corners so it meets the body flat.
    local headerFill = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 10),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = header,
    })
    local titleX = 14
    if opts.Icon then
        local headerIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 14, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 2,
            Parent = header,
        })
        applyIcon(headerIcon, opts.Icon)
        titleX = 37
    end
    local collapseButton = create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 2,
        Parent = header,
    })
    applyIcon(collapseButton, "chevron-down")
    -- Beside the chevron, a button that pops the box out into a floating
    -- panel (and docks it back once it's out). PopOut = false leaves it off.
    local canPop = opts.PopOut ~= false
    local popButton, popIcon
    if canPop then
        popButton = create("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -34, 0.5, 0),
            Size = UDim2.fromOffset(24, 24),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3,
            Parent = header,
        })
        corner(popButton, UDim.new(0, 6))
        popIcon = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(13, 13),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ImageTransparency = TOUCH and 0 or 0.45,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 3,
            Parent = popButton,
        })
        applyIcon(popIcon, "picture-in-picture-2")
    end
    local title = label({
        Position = UDim2.fromOffset(titleX, 0),
        Size = UDim2.new(1, -(titleX + (canPop and 66 or 40)), 1, 0),
        Text = opts.Name or "Groupbox",
        TextSize = 13,
        FontFace = Fonts.Bold,
        ZIndex = 2,
        Parent = header,
    })

    local rule = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = box,
    })
    local body = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        LayoutOrder = 3,
        Parent = box,
    })
    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = body,
    })
    Library._space(padding(inner, 0, 0, 6, 8), { 0, 0, 6, 8 })
    Library._space(create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = inner,
    }), 2)

    local group = setmetatable({
        Name = opts.Name or "Groupbox",
        Window = window,
        Parent = self,
        List = inner,
        Frame = box,
        _frame = box,
        _order = 0,
        _groupbox = true,
        _metrics = METRICS.Row,
        _items = {},
    }, Tab)
    table.insert(self._groupboxes, group)

    local collapsed = false
    local generation = 0
    local function setCollapsed(value, instant)
        value = value == true
        if value == collapsed then
            return
        end
        collapsed = value
        generation += 1
        local current = generation
        local duration = instant and 0 or 0.32
        -- Anything open inside the box (a dropdown list, a picker, a focused
        -- box) closes with it, rather than floating over a folded header.
        if value then
            for _, element in ipairs(group._items) do
                if element._onHide then
                    element._onHide()
                end
                if element.Open and type(element.SetOpen) == "function" then
                    element:SetOpen(false)
                end
            end
        end
        window._controlsDirty = true
        local scale = window.Scale.Scale
        if value then
            body.AutomaticSize = Enum.AutomaticSize.None
            body.Size = UDim2.new(1, 0, 0, body.AbsoluteSize.Y / scale)
            tween(body, { Size = UDim2.new(1, 0, 0, 0) }, duration, Enum.EasingStyle.Quint)
        else
            tween(body, { Size = UDim2.new(1, 0, 0, inner.AbsoluteSize.Y / scale) }, duration, Enum.EasingStyle.Quint)
            local function settle()
                if generation == current and not collapsed then
                    body.AutomaticSize = Enum.AutomaticSize.Y
                    body.Size = UDim2.new(1, 0, 0, 0)
                end
            end
            if duration > 0 then
                task.delay(duration, settle)
            else
                settle()
            end
        end
        local motion = instant and 0 or 0.3
        -- Folded, the strip is the whole box: the hairline under it drops out
        -- of the layout once the body has closed, so the box ends exactly at
        -- the strip and both share the same rounded corners.
        if value then
            local function fold()
                if generation == current and collapsed then
                    rule.Visible = false
                    headerFill.Visible = false
                end
            end
            if duration > 0 then
                task.delay(duration, fold)
            else
                fold()
            end
        else
            rule.Visible = true
            headerFill.Visible = true
        end
        tween(collapseButton, { Rotation = value and -90 or 0 }, motion, Enum.EasingStyle.Quint)
    end

    local function hover(on)
        local duration = on and 0.15 or 0.25
        tween(collapseButton, { ImageColor3 = on and Theme.Text or Theme.Muted }, duration)
        if popIcon and not TOUCH then
            tween(popIcon, { ImageTransparency = on and 0 or 0.45 }, duration)
        end
    end
    header.MouseEnter:Connect(function()
        hover(true)
    end)
    header.MouseLeave:Connect(function()
        hover(false)
    end)
    local isTap = tapGuard(header, function()
        return box:FindFirstAncestorWhichIsA("ScrollingFrame")
    end)
    -- Popping out: the box itself is lifted out of its column into a panel
    -- on the window's pop-out layer, and a slot holds its place in the column
    -- (pressing the slot docks it back). The header drags the panel; a drop
    -- is clamped on screen and the spot is remembered for the next pop-out.
    local popped, popGeneration = false, 0
    local panel, panelScale, panelShadow, slot, stopPanel
    local dragStart, dragOrigin, dragMoved, suppressClick = nil, nil, false, false
    local animating = false

    local function layerScale()
        return math.max(window.Scale.Scale, 0.05)
    end
    local function toLayer(point)
        return (point - window._popLayer.AbsolutePosition) / layerScale()
    end
    -- Keeps a panel's top-centre spot on screen, header always reachable.
    local function clampSpot(spot, width, height)
        local view = window._popLayer.AbsoluteSize / layerScale()
        local margin = 8
        local x = math.clamp(spot.X, width / 2 + margin, math.max(view.X - width / 2 - margin, width / 2 + margin))
        local y = math.clamp(spot.Y, margin, math.max(view.Y - math.min(height, 120) - margin, margin))
        return Vector2.new(x, y)
    end
    local function closeInner()
        for _, element in ipairs(group._items) do
            if element._onHide then
                element._onHide()
            end
            if element.Open and type(element.SetOpen) == "function" then
                element:SetOpen(false)
            end
        end
    end
    local function setPopIcon(out)
        if popIcon then
            applyIcon(popIcon, out and "minimize-2" or "picture-in-picture-2")
        end
    end

    local function popOut()
        if popped or not canPop or not box.Parent or group._destroyed then
            return
        end
        -- A dock still in flight lands first, so the box is back in its column.
        if group._settleDock then
            group._settleDock()
        end
        local layer = window:_popoutLayer()
        popped = true
        group._popped = true
        popGeneration += 1
        local current = popGeneration
        closeInner()
        window:_closePopups()
        local scale = layerScale()
        local column = box.Parent
        local from = toLayer(box.AbsolutePosition)
        local width = box.AbsoluteSize.X / scale
        local height = box.AbsoluteSize.Y / scale

        -- The slot left behind: starts at the box's height so nothing below
        -- jumps, then eases down to a slim bar.
        slot = create("TextButton", {
            Size = UDim2.new(1, 0, 0, height),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = 0.6,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            LayoutOrder = box.LayoutOrder,
            Parent = column,
        })
        slot:SetAttribute("NoDrag", true)
        corner(slot, UDim.new(0, 10))
        stroke(slot, Theme.Stroke, 1).Transparency = 0.3
        local slotLabel = label({
            Size = UDim2.new(1, -24, 0, 40),
            Position = UDim2.fromOffset(12, 0),
            Text = Library._rich(group.Name) .. '<font transparency="0.4">  ·  popped out, click to dock</font>',
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            RichText = true,
            TextTransparency = 1,
            Parent = slot,
        })
        local thisSlot = slot
        slot.MouseEnter:Connect(function()
            tween(thisSlot, { BackgroundTransparency = 0.35 }, 0.15)
        end)
        slot.MouseLeave:Connect(function()
            tween(thisSlot, { BackgroundTransparency = 0.6 }, 0.25)
        end)
        slot.MouseButton1Click:Connect(function()
            if slot == thisSlot then
                group:Dock()
            end
        end)
        tween(slot, { Size = UDim2.new(1, 0, 0, 40) }, 0.42, Enum.EasingStyle.Quint)
        tween(slotLabel, { TextTransparency = 0 }, 0.3)
        slot.Visible = box.Visible

        panel = create("Frame", {
            Name = "PopOut",
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromOffset(from.X + width / 2, from.Y),
            Size = UDim2.fromOffset(width, height),
            BackgroundTransparency = 1,
            Parent = layer,
        })
        panel:SetAttribute("NoDrag", true)
        panelScale = create("UIScale", { Parent = panel })
        panelShadow = create("ImageLabel", {
            Position = UDim2.fromOffset(-24, -18),
            Size = UDim2.new(1, 48, 1, 44),
            BackgroundTransparency = 1,
            Image = Assets.Shadow,
            ImageColor3 = Color3.new(0, 0, 0),
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Slice,
            SliceCenter = Rect.new(49, 49, 450, 450),
            ZIndex = 0,
            Parent = panel,
        })
        table.insert(window._popPanels, panel)
        box.Parent = panel
        window._controlsDirty = true
        setPopIcon(true)

        -- Lifts off the column: a spring up and out to its float spot, with
        -- the shadow deepening under it.
        local spot = clampSpot(group._popSpot or Vector2.new(from.X + width / 2 + 22, from.Y - 14), width, height)
        animating = true
        panelScale.Scale = 0.97
        tween(panel, { Position = UDim2.fromOffset(spot.X, spot.Y) }, 0.5, Enum.EasingStyle.Quint)
        tween(panelScale, { Scale = 1 }, 0.55, Enum.EasingStyle.Back)
        tween(panelShadow, { ImageTransparency = 0.35 }, 0.4)
        task.delay(0.5, function()
            if popGeneration == current then
                animating = false
            end
        end)

        -- Each frame: the panel follows the box's height (folding, rows
        -- coming and going), mirrors its visibility, and stays on screen.
        local thisPanel = panel
        stopPanel = window:_listen("Render", function()
            if panel ~= thisPanel or not thisPanel.Parent then
                return
            end
            local boxHeight = box.AbsoluteSize.Y / layerScale()
            if math.abs(thisPanel.Size.Y.Offset - boxHeight) > 0.5 then
                thisPanel.Size = UDim2.fromOffset(thisPanel.Size.X.Offset, boxHeight)
            end
            thisPanel.Visible = box.Visible
            if slot then
                slot.Visible = box.Visible
            end
            if not animating and not dragStart then
                local position = Vector2.new(thisPanel.Position.X.Offset, thisPanel.Position.Y.Offset)
                local clamped = clampSpot(position, thisPanel.Size.X.Offset, boxHeight)
                if (clamped - position).Magnitude > 0.5 then
                    thisPanel.Position = UDim2.fromOffset(clamped.X, clamped.Y)
                end
            end
        end)
    end

    local function dock(instant)
        if not popped then
            return
        end
        popped = false
        group._popped = false
        popGeneration += 1
        dragStart, dragMoved, suppressClick = nil, false, false
        closeInner()
        window:_closePopups()
        local oldPanel, oldSlot, oldStop, oldScale, oldShadow = panel, slot, stopPanel, panelScale, panelShadow
        panel, slot, stopPanel = nil, nil, nil
        setPopIcon(false)
        group._popSpot = Vector2.new(oldPanel.Position.X.Offset, oldPanel.Position.Y.Offset)
        local settled = false
        local function settle()
            if settled then
                return
            end
            settled = true
            if group._settleDock == settle then
                group._settleDock = nil
            end
            if oldStop then
                oldStop()
            end
            local index = table.find(window._popPanels, oldPanel)
            if index then
                table.remove(window._popPanels, index)
            end
            -- Back into the column, unless it was popped again meanwhile.
            if box.Parent == oldPanel then
                if oldSlot and oldSlot.Parent and not group._destroyed then
                    box.Parent = oldSlot.Parent
                    box.LayoutOrder = oldSlot.LayoutOrder
                end
            end
            if oldSlot then
                oldSlot:Destroy()
            end
            if box.Parent ~= oldPanel then
                oldPanel:Destroy()
            end
            animating = false
            window._controlsDirty = true
        end
        group._settleDock = settle
        -- Flies home only when its slot is on screen; otherwise (another tab,
        -- the window hidden) it just drops back into place.
        local canFly = not instant and oldSlot and oldSlot.Parent and window.Root.Visible and box.Visible
            and oldSlot.AbsoluteSize.X > 0 and isShown(oldSlot, window.Body, oldSlot.AbsolutePosition + oldSlot.AbsoluteSize / 2)
        if not canFly then
            settle()
            return
        end
        animating = true
        local scale = layerScale()
        local height = box.AbsoluteSize.Y / scale
        local width = oldSlot.AbsoluteSize.X / scale
        tween(oldSlot, { Size = UDim2.new(1, 0, 0, height) }, 0.36, Enum.EasingStyle.Quint)
        local oldLabel = oldSlot:FindFirstChildWhichIsA("TextLabel")
        if oldLabel then
            tween(oldLabel, { TextTransparency = 1 }, 0.12)
        end
        -- The slot's top stays put as it grows, so its spot is the landing.
        local target = toLayer(oldSlot.AbsolutePosition)
        tween(oldPanel, {
            Position = UDim2.fromOffset(target.X + width / 2, target.Y),
            Size = UDim2.fromOffset(width, height),
        }, 0.36, Enum.EasingStyle.Quint)
        tween(oldScale, { Scale = 1 }, 0.2)
        tween(oldShadow, { ImageTransparency = 1 }, 0.3)
        task.delay(0.37, settle)
    end

    -- Dragging the floating panel by its header.
    header.InputBegan:Connect(function(input)
        if not popped or not isPress(input) or not panel then
            return
        end
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        dragOrigin = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
        dragMoved = false
        suppressClick = false
    end)
    window:_listen("Changed", function(input)
        if not dragStart or not panel or not isMove(input) then
            return
        end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
        if not dragMoved then
            if delta.Magnitude < (TOUCH and 8 or 5) then
                return
            end
            dragMoved, suppressClick = true, true
            animating = false
            closeInner()
            window:_closePopups()
            tween(panelScale, { Scale = 1.025 }, 0.18, Enum.EasingStyle.Quint)
            tween(panelShadow, { ImageTransparency = 0.15 }, 0.18)
        end
        local spot = clampSpot(dragOrigin + delta / layerScale(), panel.Size.X.Offset, panel.Size.Y.Offset)
        panel.Position = UDim2.fromOffset(spot.X, spot.Y)
    end, group)
    window:_listen("Ended", function(input)
        if not dragStart or not isPress(input) then
            return
        end
        dragStart = nil
        if dragMoved and panel then
            dragMoved = false
            tween(panelScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            tween(panelShadow, { ImageTransparency = 0.35 }, 0.3)
            group._popSpot = Vector2.new(panel.Position.X.Offset, panel.Position.Y.Offset)
        end
    end, group)
    if popButton then
        popButton.MouseEnter:Connect(function()
            tween(popButton, { BackgroundTransparency = 0 }, 0.15)
            tween(popIcon, { ImageColor3 = Theme.Text }, 0.15)
        end)
        popButton.MouseLeave:Connect(function()
            tween(popButton, { BackgroundTransparency = 1 }, 0.25)
            tween(popIcon, { ImageColor3 = Theme.Muted }, 0.25)
        end)
        popButton.MouseButton1Click:Connect(function()
            if popped then
                dock()
            else
                popOut()
            end
        end)
    end

    header.MouseButton1Click:Connect(function()
        if suppressClick then
            suppressClick = false
            return
        end
        if isTap() then
            setCollapsed(not collapsed)
        end
    end)

    function group:PopOut()
        popOut()
    end
    function group:Dock()
        dock()
    end
    function group:IsPoppedOut()
        return popped
    end
    function group:SetCollapsed(value)
        setCollapsed(value)
    end
    function group:Collapse()
        setCollapsed(true)
    end
    function group:Expand()
        setCollapsed(false)
    end
    function group:IsCollapsed()
        return collapsed
    end
    function group:SetTitle(text)
        group.Name = tostring(text)
        title.Text = group.Name
    end
    group._userVisible = opts.Visible ~= false
    function group:IsVisible()
        return group._userVisible
    end
    function group:SetVisible(visible)
        visible = visible and true or false
        if visible == group._userVisible then
            return
        end
        group._userVisible = visible
        if not visible then
            for _, element in ipairs(group._items) do
                if element._onHide then
                    element._onHide()
                end
                if element.Open and type(element.SetOpen) == "function" then
                    element:SetOpen(false)
                end
            end
        end
        box.Visible = visible
        window._controlsDirty = true
    end
    if not group._userVisible then
        box.Visible = false
    end
    function group:Destroy()
        for index = #group._items, 1, -1 do
            local element = group._items[index]
            if type(element.Destroy) == "function" then
                element:Destroy()
            end
        end
        local owner = group.Parent
        local index = table.find(owner._groupboxes, group)
        if index then
            table.remove(owner._groupboxes, index)
        end
        set.Counts[side] = math.max(set.Counts[side] - 1, 0)
        dock(true)
        group._destroyed = true
        window._controlsDirty = true
        box:Destroy()
    end

    if opts.Collapsed then
        setCollapsed(true, true)
    end
    if opts.PoppedOut then
        task.defer(popOut)
    end
    return group
end

local function sideGroupbox(side)
    return function(self, opts, icon)
        opts = normalize(opts, { Title = "Name" })
        opts.Side = side
        return self:Groupbox(opts, icon)
    end
end

Tab.CreateGroupbox = Tab.Groupbox
Tab.AddGroupbox = Tab.Groupbox
Tab.AddLeftGroupbox = sideGroupbox("Left")
Tab.AddRightGroupbox = sideGroupbox("Right")

-- Button rows: equal-width buttons side by side.

function Tab:ButtonRow(opts)
    local specs = type(opts) == "table" and (opts.Buttons or opts) or {}
    local compact = metricsOf(self).Compact
    local boxHeight = TOUCH and 34 or 30
    local frame = card(self, "Frame", boxHeight + (compact and 4 or 14), {})
    local inset = compact and 14 or 7
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, compact and 2 or 7),
        Size = UDim2.new(1, -inset * 2, 0, boxHeight),
        BackgroundTransparency = 1,
        Parent = frame,
    })
    local count = math.max(#specs, 1)
    local handle = { Buttons = {} }
    local names = {}
    for index, spec in ipairs(specs) do
        if type(spec) == "string" then
            spec = { Name = spec }
        end
        local text = spec.Name or spec.Title or "Button"
        table.insert(names, text)
        local button, text_ = softButton(holder, text, {
            Position = UDim2.new((index - 1) / count, (index - 1) * 6 / count, 0, 0),
            Size = UDim2.new(1 / count, -6 * (count - 1) / count, 1, 0),
        }, function()
            safeCall(spec.Callback)
        end)
        text_.TextSize = 13
        if spec.Style == "Primary" then
            tween(button, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.12 }, 0)
            tween(text_, { TextColor3 = Theme.AccentDark }, 0)
        elseif spec.Style == "Danger" then
            tween(text_, { TextColor3 = Theme.Error }, 0)
        end
        handle.Buttons[index] = { Button = button, Label = text_ }
    end
    function handle:SetText(index, text)
        local entry = handle.Buttons[index]
        if entry then
            entry.Label.Text = tostring(text)
        end
    end
    return finishElement(self, { Name = table.concat(names, " "), Visible = not (type(opts) == "table" and opts.Visible == false) }, handle, frame, "ButtonRow")
end

-- A text box with an action button beside it, for naming new configs and themes.
-- Without buttonText the box spans the row on its own.
local function actionInput(tab, placeholder, buttonText, callback)
    local boxHeight = TOUCH and 34 or 30
    local frame = card(tab, "Frame", boxHeight + 4, {})
    local inset = metricsOf(tab).Compact and 14 or 7
    local box
    local button = buttonText and softButton(frame, buttonText, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -inset, 0, 2),
        Size = UDim2.fromOffset(0, boxHeight),
        AutomaticSize = Enum.AutomaticSize.X,
    }, function()
        safeCall(callback, box.Text)
    end)
    local holder = create("Frame", {
        Position = UDim2.fromOffset(inset, 2),
        Size = UDim2.new(1, -(inset * 2 + (button and 70 or 0)), 0, boxHeight),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = frame,
    })
    corner(holder, UDim.new(0, 6))
    local holderStroke = stroke(holder)
    box = create("TextBox", {
        Position = UDim2.fromOffset(8, 0),
        Size = UDim2.new(1, -16, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = placeholder,
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = holder,
    })
    box.Focused:Connect(function()
        tween(holderStroke, { Color = Theme.StrokeHover }, 0.15)
    end)
    box.FocusLost:Connect(function(enterPressed)
        tween(holderStroke, { Color = Theme.Stroke }, 0.2)
        if enterPressed and box.Text ~= "" then
            safeCall(callback, box.Text)
        end
    end)
    if button then
        local function fit()
            local width = button.AbsoluteSize.X / tab.Window.Scale.Scale
            holder.Size = UDim2.new(1, -(inset * 2 + width + 6), 0, boxHeight)
        end
        button:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
        task.defer(fit)
    end
    return finishElement(tab, { Name = placeholder }, {
        Get = function()
            return box.Text
        end,
        Set = function(_, value)
            box.Text = tostring(value or "")
        end,
    }, frame, "ActionInput")
end

local function trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

-- Managers go in their own groupbox when added straight to a tab.
local function managerHost(tab, opts, name, icon)
    if tab._groupbox then
        return tab
    end
    local hostIcon = opts.Icon
    if hostIcon == nil then
        hostIcon = icon
    end
    local host = tab:Groupbox({ Name = opts.Name or name, Icon = hostIcon, Side = opts.Side })
    -- Library chrome, not a script feature: the feature list skips it.
    host._manager = true
    return host
end

function Tab:ConfigManager(opts)
    opts = normalize(opts, { Title = "Name" })
    local host = managerHost(self, opts, "Configs", "folder")
    local window = self.Window
    local manager = {}
    local list, status, modeList

    local function notify(ok, title, detail)
        window:Notify({ Title = title, Content = detail, Type = ok and "Success" or "Error", Duration = 3 })
    end

    local function refreshStatus()
        status:Set(("loaded: %s   |   autoload: %s"):format(window.LoadedConfig or "none", window:GetAutoload() or "none"))
    end

    local function pickedName()
        local name = list:Get()
        if not name then
            notify(false, "No config selected", "Pick one from the list first")
        end
        return name
    end

    local nameInput = actionInput(host, opts.Placeholder or "config name", nil, function(text)
        manager:Create(text)
    end)
    local names = window:ListConfigs()
    local initial = window.LoadedConfig or window:GetAutoload()
    list = host:Dropdown({
        Stacked = true,
        Options = names,
        Default = table.find(names, initial) and initial or nil,
        EmptyText = "--",
        NoneText = "--",
    })
    host:ButtonRow({
        { Name = "Create", Callback = function() manager:Create(nameInput:Get()) end },
        { Name = "Save", Callback = function() manager:Save() end },
    })
    host:ButtonRow({
        { Name = "Load", Callback = function() manager:Load() end },
        { Name = "Delete", Style = "Danger", Callback = function() manager:Delete() end },
    })
    host:ButtonRow({
        { Name = "Set autoload", Callback = function() manager:SetAutoload() end },
        { Name = "Clear autoload", Callback = function() manager:ClearAutoload() end },
    })
    host:ButtonRow({
        { Name = "Rename", Callback = function() manager:Rename(nil, nameInput:Get()) end },
        { Name = "Reset", Style = "Danger", Callback = function() manager:Reset() end },
    })
    status = host:Label("loaded: none   |   autoload: none")
    modeList = host:Dropdown({
        Name = "Autoload mode",
        Stacked = true,
        Options = { "All accounts", "This account" },
        Default = window:GetAutoloadMode() == "Account" and "This account" or "All accounts",
        AllowNone = false,
        Callback = function(choice)
            manager:SetAutoloadMode(choice == "This account" and "Account" or "Global")
        end,
    })
    host:Button({ Name = "Refresh list", Callback = function() manager:Refresh() end })
    host:Divider({ Text = "share" })
    host:Button({ Name = "Copy code", Callback = function() manager:Export() end })
    local codeInput = actionInput(host, "paste a config code...", nil, function(text)
        manager:Import(text)
    end)
    host:Button({ Name = "Import code", Callback = function() manager:Import(codeInput:Get()) end })

    function manager:Refresh()
        local names = window:ListConfigs()
        local keep = list:Get()
        list:Refresh(names, true)
        if keep and not table.find(names, keep) then
            list:Set(window.LoadedConfig and table.find(names, window.LoadedConfig) and window.LoadedConfig or nil, true)
        end
        refreshStatus()
    end

    local function select(name)
        manager:Refresh()
        list:Set(name, true)
    end

    function manager:Create(name)
        name = trim(name)
        if name == "" then
            notify(false, "Name the config", "Type a name before creating it")
            return
        end
        if not validConfigName(name) then
            notify(false, "Invalid name", 'Names cannot contain \\ / : * ? " < > |')
            return
        end
        local ok, err = window:SaveConfig(name)
        if ok then
            window.LoadedConfig = name
            nameInput:Set("")
            select(name)
        end
        notify(ok, ok and "Config created" or "Create failed", ok and name or tostring(err))
    end

    function manager:Save(name)
        name = name or list:Get()
        if not name then
            local typed = trim(nameInput:Get())
            if typed == "" then
                notify(false, "No config selected", "Pick one from the list or type a name")
                return
            end
            return manager:Create(typed)
        end
        local ok, err = window:SaveConfig(name)
        if ok then
            window.LoadedConfig = name
            refreshStatus()
        end
        notify(ok, ok and "Config saved" or "Save failed", ok and name or tostring(err))
    end

    function manager:Load(name)
        name = name or pickedName()
        if not name then
            return
        end
        local ok, err = window:LoadConfig(name)
        notify(ok, ok and "Config loaded" or "Load failed", ok and name or tostring(err))
    end

    function manager:Delete(name)
        name = name or pickedName()
        if not name then
            return
        end
        window:Confirm({
            Title = "Delete config",
            Content = "Remove " .. name .. "? This cannot be undone.",
            Icon = "trash-2",
            ConfirmText = "Delete",
            Callback = function()
                local ok, err = window:DeleteConfig(name)
                if ok then
                    if window:GetAutoload("Account") == name then
                        window:SetAutoload(nil, "Account")
                    end
                    if window:GetAutoload("Global") == name then
                        window:SetAutoload(nil, "Global")
                    end
                    list:Set(nil, true)
                end
                manager:Refresh()
                notify(ok, ok and "Config deleted" or "Delete failed", ok and name or tostring(err))
            end,
        })
    end

    function manager:Rename(name, newName)
        name = name or pickedName()
        if not name then
            return
        end
        newName = trim(newName)
        if newName == "" then
            notify(false, "Name the config", "Type the new name in the name box")
            return
        end
        if not validConfigName(newName) then
            notify(false, "Invalid name", 'Names cannot contain \\ / : * ? " < > |')
            return
        end
        local ok, err = window:RenameConfig(name, newName)
        if ok then
            nameInput:Set("")
            select(newName)
        end
        notify(ok, ok and "Config renamed" or "Rename failed", ok and (name .. " -> " .. newName) or tostring(err))
    end

    function manager:Reset()
        window:Confirm({
            Title = "Reset settings",
            Content = "Put every setting back to its default and delete this script's folder? Saved configs, themes and autoload are removed for good.",
            Icon = "rotate-ccw",
            ConfirmText = "Reset",
            Callback = function()
                window:ResetConfig()
                local wiped = window:ClearWorkspace()
                window:_applyDefaultTheme()
                list:Set(nil, true)
                manager:Refresh()
                modeList:Set("All accounts", true)
                notify(wiped, wiped and "Settings reset" or "Reset incomplete",
                    wiped and "Everything is back to its default" or "Some files in " .. window.ConfigFolder .. " could not be deleted")
            end,
        })
    end

    function manager:SetAutoload(name)
        name = name or pickedName()
        if not name then
            return
        end
        local ok, err = window:SetAutoload(name)
        notify(ok, ok and "Autoload set" or "Autoload failed", ok and name or tostring(err))
    end

    function manager:ClearAutoload()
        local current = window:GetAutoload()
        if not current then
            notify(false, "No autoload", "Nothing is set to autoload")
            return
        end
        local ok, err = window:SetAutoload(nil)
        notify(ok, ok and "Autoload cleared" or "Clear failed", ok and current or tostring(err))
    end

    function manager:ToggleAutoload(name)
        name = name or pickedName()
        if not name then
            return
        end
        if window:GetAutoload() == name then
            manager:ClearAutoload()
        else
            manager:SetAutoload(name)
        end
    end

    function manager:SetAutoloadMode(mode)
        local ok, err = window:SetAutoloadMode(mode)
        local label_ = mode == "Account" and "This account" or "All accounts"
        if modeList:Get() ~= label_ then
            modeList:Set(label_, true)
        end
        notify(ok ~= false, ok ~= false and "Autoload mode" or "Mode change failed", ok ~= false and label_ or tostring(err))
    end

    function manager:Export(name)
        local code, err = window:ExportConfig(name)
        if not code then
            notify(false, "Export failed", tostring(err))
            return nil
        end
        window:CopyToClipboard(code, "Config code")
        return code
    end

    function manager:Import(code)
        code = trim(code)
        if code == "" then
            notify(false, "Nothing to import", "Paste a config code first")
            return
        end
        local data, info = window:DecodeConfig(code)
        if not data then
            notify(false, "Import failed", "Invalid config code")
            return
        end
        -- The typed name wins; otherwise the code's own name, never overwriting a config.
        local saveAs = trim(nameInput:Get())
        if saveAs == "" then
            saveAs = nil
            if validConfigName(info.Name) then
                saveAs = info.Name
                local index = 2
                while window:ConfigExists(saveAs) do
                    saveAs = ("%s (%d)"):format(info.Name, index)
                    index += 1
                end
            end
        elseif not validConfigName(saveAs) then
            notify(false, "Invalid name", 'Names cannot contain \\ / : * ? " < > |')
            return
        end
        local function run()
            local ok, err = window:ImportConfig(code, saveAs, true)
            if ok then
                codeInput:Set("")
                if saveAs then
                    nameInput:Set("")
                    select(saveAs)
                end
            end
            notify(ok, ok and "Config imported" or "Import failed", ok and (saveAs or "Applied to current settings") or tostring(err))
        end
        if info.Folder and info.Folder ~= window.ConfigFolder then
            window:Confirm({
                Title = "Different script",
                Content = ("This config was made for %s. Import it anyway? Only matching settings are applied."):format(info.Folder),
                Icon = "triangle-alert",
                ConfirmText = "Import",
                Callback = run,
            })
            return
        end
        run()
    end

    local disconnect = window:OnConfigChanged(function()
        -- Configs can arrive from elsewhere (a cloud install), so the list is reread.
        manager:Refresh()
        if window.LoadedConfig and list:Get() == nil then
            list:Set(window.LoadedConfig, true)
        end
    end)
    status._listeners = status._listeners or {}
    table.insert(status._listeners, disconnect)

    refreshStatus()
    return manager
end

local PRESET_ORDER = {
    "Cybrion", "Midnight", "Nebula", "Synthwave", "Sakura", "Velvet", "Rose", "Crimson", "Sunset", "Amber", "Gold",
    "Cyber", "Toxic", "Matcha", "Emerald", "Aurora", "Ocean", "Frost", "Abyss", "Mono",
    "Halloween", "Haunted", "Christmas", "Valentine", "Lunar", "Tropical", "Dracula", "Coffee",
}

local function presetNames()
    local names, seen = {}, {}
    for _, name in ipairs(PRESET_ORDER) do
        if Library.ThemePresets[name] then
            table.insert(names, name)
            seen[name] = true
        end
    end
    local extra = {}
    for name in pairs(Library.ThemePresets) do
        if not seen[name] then
            table.insert(extra, name)
        end
    end
    table.sort(extra)
    for _, name in ipairs(extra) do
        table.insert(names, name)
    end
    return names
end

function Tab:ThemeManager(opts)
    opts = normalize(opts, { Title = "Name" })
    local host = managerHost(self, opts, "Themes", "palette")
    local window = self.Window
    local manager = {}
    local themes, status, defaultRow, presets
    local weather, weatherMode, dim, transparent, dragSkeleton, islandStyle
    local background, backgroundInput, backgroundOpacity, backgroundLabel
    local uiScale, density, adaptive, cornerRadius

    local function notify(ok, title, detail)
        window:Notify({ Title = title, Content = detail, Type = ok and "Success" or "Error", Duration = 3 })
    end

    local function refreshStatus()
        local current = window:GetDefaultTheme()
        status:Set("Default theme: " .. (current or "none"))
        local picked = themes:Get() or presets:Get()
        defaultRow:SetText(2, (picked and picked == current) and "Clear Default" or "Set Default")
    end

    local function pickedTheme()
        local name = themes:Get()
        if not name then
            notify(false, "No theme selected", "Pick one from the list first")
        end
        return name
    end

    presets = host:Dropdown({
        Name = "Preset",
        Options = presetNames(),
        Default = Library.ThemePresets[Library.ThemeName or ""] and Library.ThemeName or nil,
        NoneText = "custom",
        AllowNone = false,
        Callback = function(name)
            if name then
                Library:SetTheme(name)
                themes:Set(nil, true)
                refreshStatus()
            end
        end,
    })
    local labels = { None = "None", Snow = "Snow", Rain = "Rain", Ember = "Hell Fire", Sakura = "Sakura", Fireflies = "Fireflies", Matrix = "Matrix" }
    if window._backdrop and opts.Weather ~= false then
        weather = host:Dropdown({
            Name = "Weather",
            Options = { "Snow", "Rain", "Hell Fire", "Sakura", "Fireflies", "Matrix", "None" },
            Default = labels[window.Weather] or "Matrix",
            AllowNone = false,
            Callback = function(name)
                if name then
                    window:SetWeather(name)
                end
            end,
        })
    end
    if window._backdrop and opts.Weather ~= false then
        weatherMode = host:Dropdown({
            Name = "Weather Mode",
            Options = { "Screen", "UI" },
            Default = window.WeatherMode,
            AllowNone = false,
            Callback = function(mode)
                if mode then
                    window:SetWeatherMode(mode)
                end
            end,
        })
    end
    if window._backdrop and opts.Dim ~= false then
        dim = host:Toggle({
            Name = "Dim",
            Default = window._backdropDim,
            Callback = function(value)
                window:SetDim(value)
            end,
        })
    end
    if opts.Transparent ~= false then
        transparent = host:Toggle({
            Name = "Transparent",
            Default = window.Transparent == true,
            Callback = function(value)
                window:SetTransparent(value)
            end,
        })
    end
    if opts.DragSkeleton ~= false and opts.DragStyle ~= false then
        dragSkeleton = host:Dropdown({
            Name = "Drag Style",
            Options = Library.DragStyles,
            Default = window.DragStyle,
            AllowNone = false,
            Callback = function(style)
                if style then
                    window:SetDragStyle(style)
                end
            end,
        })
    end
    if opts.IslandStyle ~= false then
        islandStyle = host:Dropdown({
            Name = "Dynamic Island",
            Options = Library.IslandStyles,
            Default = window.IslandStyle,
            AllowNone = false,
            Callback = function(style)
                if style then
                    window:SetIslandStyle(style)
                end
            end,
        })
    end
    if opts.AdaptiveSize ~= false then
        adaptive = host:Toggle({
            Name = "Adaptive Size",
            Default = window:GetAdaptiveSize(),
            Callback = function(value)
                window:SetAdaptiveSize(value)
            end,
        })
    end
    if opts.Scale ~= false then
        uiScale = host:Slider({
            Name = "UI Scale",
            Min = 60,
            Max = 150,
            Increment = 5,
            Default = math.floor(window:GetUIScale() * 100 + 0.5),
            Suffix = "%",
            -- Rescaling mid-drag would move the slider out from under the
            -- pointer, so a drag applies on release.
            Callback = function(value)
                if not (uiScale and uiScale.Dragging) then
                    window:SetUIScale(value / 100)
                end
            end,
            OnRelease = function(value)
                window:SetUIScale(value / 100)
            end,
        })
    end
    if opts.Density ~= false then
        density = host:Dropdown({
            Name = "Density",
            Options = { "Compact", "Default", "Comfortable" },
            Default = Library.Density,
            AllowNone = false,
            Callback = function(mode)
                if mode then
                    Library:SetDensity(mode)
                end
            end,
        })
    end
    if opts.CornerRadius ~= false then
        cornerRadius = host:Slider({
            Name = "Corner Radius",
            Min = 0,
            Max = 20,
            Increment = 1,
            Default = Library:GetCornerRadius(),
            Suffix = "px",
            Callback = function(value)
                Library:SetCornerRadius(value)
            end,
        })
    end
    if opts.Background ~= false then
        -- The dropdown shows listed images by name, "custom" for ids and links.
        backgroundLabel = function(source)
            if source == nil or source == "" then
                return "None"
            end
            return table.find(window:ListBackgrounds(), source) and source or nil
        end
        local function applyBackground(source, fromList)
            task.spawn(function()
                local ok, err = window:SetBackground(source)
                if ok and not fromList then
                    background:Set(backgroundLabel(window.Background), true)
                elseif not ok and err ~= "replaced by a newer background" then
                    notify(false, "Background failed", tostring(err))
                end
            end)
        end
        local options = window:ListBackgrounds()
        table.insert(options, 1, "None")
        background = host:Dropdown({
            Name = "Background",
            Options = options,
            Default = backgroundLabel(window.Background),
            NoneText = "custom",
            AllowNone = false,
            Callback = function(name)
                if name then
                    applyBackground(name, true)
                end
            end,
        })
        backgroundInput = actionInput(host, "image id or url", "Set", function(text)
            text = trim(text)
            if text == "" then
                notify(false, "No image", "Paste an image id or link first")
                return
            end
            applyBackground(text)
        end)
        backgroundOpacity = host:Slider({
            Name = "Background Opacity",
            Min = 0,
            Max = 100,
            Default = math.floor((1 - window.BackgroundTransparency) * 100 + 0.5),
            Suffix = "%",
            Callback = function(value)
                window:SetBackgroundTransparency(1 - value / 100)
            end,
        })
    end
    local nameInput = actionInput(host, opts.Placeholder or "theme name", "Create", function(text)
        manager:Create(text)
    end)
    themes = host:Dropdown({
        Name = "Theme",
        Options = window:ListThemes(),
        Default = (function()
            local current = window:GetDefaultTheme()
            return current and not Library.ThemePresets[current] and current or nil
        end)(),
        EmptyText = "no themes",
        NoneText = "select",
        Callback = function()
            refreshStatus()
        end,
    })
    host:ButtonRow({
        { Name = "Save", Callback = function() manager:Save() end },
        { Name = "Load", Callback = function() manager:Load() end },
    })
    defaultRow = host:ButtonRow({
        { Name = "Delete", Callback = function() manager:Delete() end },
        { Name = "Set Default", Callback = function() manager:ToggleDefault() end },
    })
    status = host:Label("Default theme: none")

    function manager:Refresh()
        themes:Refresh(window:ListThemes(), true)
        if background then
            local options = window:ListBackgrounds()
            table.insert(options, 1, "None")
            background:Refresh(options, true, true)
        end
        refreshStatus()
    end

    function manager:Create(name)
        name = trim(name)
        if name == "" then
            notify(false, "Name the theme", "Type a name before creating it")
            return
        end
        if Library.ThemePresets[name] then
            notify(false, "Name taken", name .. " is a built-in preset")
            return
        end
        local ok, err = window:SaveTheme(name)
        manager:Refresh()
        if ok then
            themes:Set(name, true)
            nameInput:Set("")
            refreshStatus()
        end
        notify(ok, ok and "Theme created" or "Create failed", ok and name or tostring(err))
    end

    function manager:Save(name)
        name = name or pickedTheme()
        if not name then
            return
        end
        local ok, err = window:SaveTheme(name)
        notify(ok, ok and "Theme saved" or "Save failed", ok and name or tostring(err))
    end

    function manager:Load(name)
        name = name or pickedTheme()
        if not name then
            return
        end
        local ok, err = window:LoadTheme(name)
        if ok then
            presets:Set(nil, true)
        end
        notify(ok ~= false, ok and "Theme loaded" or "Load failed", ok and name or tostring(err))
    end

    function manager:Delete(name)
        name = name or pickedTheme()
        if not name then
            return
        end
        window:Confirm({
            Title = "Delete theme",
            Content = "Remove " .. name .. "? This cannot be undone.",
            Icon = "trash-2",
            ConfirmText = "Delete",
            Callback = function()
                local ok, err = window:DeleteTheme(name)
                manager:Refresh()
                notify(ok, ok and "Theme deleted" or "Delete failed", ok and name or tostring(err))
            end,
        })
    end

    function manager:ToggleDefault(name)
        name = name or themes:Get() or presets:Get()
        if not name then
            notify(false, "Nothing selected", "Pick a theme or a preset first")
            return
        end
        local clearing = window:GetDefaultTheme() == name
        local ok, err = window:SetDefaultTheme(not clearing and name or nil)
        refreshStatus()
        notify(ok ~= false, clearing and "Default cleared" or "Default theme set", ok ~= false and name or tostring(err))
    end

    if opts.Customize ~= false then
        host:Divider()
        local fields = opts.Colors or {
            { "Accent", "Accent" },
            { "Background", "Background" },
            { "Surface2", "Surface" },
            { "Text", "Text" },
            { "Muted", "Muted text" },
        }
        for _, field in ipairs(fields) do
            local key, title = field[1], field[2] or field[1]
            local pending, scheduled = nil, false
            local picker
            picker = host:ColorPicker({
                Name = title,
                Default = Theme[key],
                Callback = function(color)
                    -- Dragging the picker fires every frame; repaint at most
                    -- a dozen times a second.
                    pending = color
                    if scheduled then
                        return
                    end
                    scheduled = true
                    task.delay(0.08, function()
                        scheduled = false
                        Library:SetTheme({ [key] = pending }, true)
                        presets:Set(nil, true)
                    end)
                end,
            })
            table.insert(Library._themeListeners, function()
                if picker.Value ~= Theme[key] then
                    picker:Set(Theme[key], true)
                end
            end)
        end
    end

    -- One hidden flag carries the palette and the look settings above, so
    -- configs save and load the theme. Not a flag per toggle: flagged toggles
    -- would count as running features on the minimized island.
    if opts.Flag ~= false then
        local flag = type(opts.Flag) == "string" and opts.Flag or "__Theme"
        local look = { _type = "Theme", _searchName = "Theme", _searchKey = "theme", _listeners = {} }

        function look:Get()
            local colors = {}
            for _, key in ipairs(THEME_KEYS) do
                colors[key] = colorToHex(Theme[key])
            end
            return {
                Name = presets:Get() or themes:Get(),
                Colors = colors,
                Weather = weather and window.Weather or nil,
                WeatherMode = weatherMode and window.WeatherMode or nil,
                -- if-expressions, not and/or: a switched-off value is false, not nil.
                Dim = if dim then window._backdropDim == true else nil,
                Transparent = if transparent then window.Transparent == true else nil,
                DragStyle = dragSkeleton and window.DragStyle or nil,
                IslandStyle = islandStyle and window.IslandStyle or nil,
                CornerRadius = cornerRadius and Library:GetCornerRadius() or nil,
                UIScale = uiScale and window:GetUIScale() or nil,
                AdaptiveSize = if adaptive then window:GetAdaptiveSize() else nil,
                Density = density and Library.Density or nil,
                -- "" is no background; a missing field leaves it alone on load.
                Background = background and (window.Background or "") or nil,
                BackgroundTransparency = background and window.BackgroundTransparency or nil,
            }
        end

        function look:Set(value)
            if type(value) ~= "table" then
                return
            end
            if type(value.Colors) == "table" then
                Library:SetTheme(value.Colors)
            end
            local name = type(value.Name) == "string" and value.Name or nil
            if name and Library.ThemePresets[name] then
                Library.ThemeName = name
                presets:Set(name, true)
                themes:Set(nil, true)
            else
                if name then
                    Library.ThemeName = name
                end
                presets:Set(nil, true)
                themes:Set(name and table.find(window:ListThemes(), name) and name or nil, true)
            end
            if weather and type(value.Weather) == "string" then
                window:SetWeather(value.Weather)
                weather:Set(labels[window.Weather] or "None", true)
            end
            if weatherMode and type(value.WeatherMode) == "string" then
                window:SetWeatherMode(value.WeatherMode)
                weatherMode:Set(window.WeatherMode, true)
            end
            if dim and type(value.Dim) == "boolean" then
                window:SetDim(value.Dim)
                dim:Set(value.Dim, true)
            end
            if transparent and type(value.Transparent) == "boolean" then
                window:SetTransparent(value.Transparent)
                transparent:Set(value.Transparent, true)
            end
            if dragSkeleton and type(value.DragStyle) == "string" then
                dragSkeleton:Set(window:SetDragStyle(value.DragStyle), true)
            elseif dragSkeleton and type(value.DragSkeleton) == "boolean" then
                -- Configs saved before drag styles.
                window:SetDragSkeleton(value.DragSkeleton)
                dragSkeleton:Set(window.DragStyle, true)
            end
            if islandStyle and type(value.IslandStyle) == "string" then
                islandStyle:Set(window:SetIslandStyle(value.IslandStyle), true)
            end
            if cornerRadius and tonumber(value.CornerRadius) then
                cornerRadius:Set(Library:SetCornerRadius(value.CornerRadius), true)
            end
            if adaptive and type(value.AdaptiveSize) == "boolean" then
                window:SetAdaptiveSize(value.AdaptiveSize)
                adaptive:Set(value.AdaptiveSize, true)
            end
            if uiScale and tonumber(value.UIScale) then
                window:SetUIScale(tonumber(value.UIScale))
                uiScale:Set(math.floor(window:GetUIScale() * 100 + 0.5), true)
            end
            if density and type(value.Density) == "string" then
                density:Set(Library:SetDensity(value.Density), true)
            end
            -- Older theme configs carried these two settings. Their controls
            -- now live in the Interface Manager, but the saved values still
            -- apply so an old theme config keeps behaving the same.
            if value.ToggleStyle == "Toggle" or value.ToggleStyle == "Checkbox" then
                Library:SetForceCheckbox(value.ToggleStyle == "Checkbox")
                local style = window._interfaceToggleStyle
                if style and not style._destroyed then
                    style:Set(value.ToggleStyle, true)
                end
            end
            if type(value.KeybindMenu) == "boolean" then
                window:SetKeybindMenu(value.KeybindMenu)
            end
            if background and tonumber(value.BackgroundTransparency) then
                window:SetBackgroundTransparency(tonumber(value.BackgroundTransparency))
                backgroundOpacity:Set(math.floor((1 - window.BackgroundTransparency) * 100 + 0.5), true)
            end
            if background and type(value.Background) == "string" and value.Background ~= (window.Background or "") then
                local source = value.Background
                background:Set(backgroundLabel(source), true)
                -- A web image may download first; don't hold up the rest of the config.
                task.spawn(window.SetBackground, window, source)
            end
            refreshStatus()
        end

        Library.Flags[flag] = look
        window:_flagCreated(flag, look)
    end

    -- A reset wipes the themes folder, so drop the stale list.
    window._workspaceListeners = window._workspaceListeners or {}
    table.insert(window._workspaceListeners, function()
        themes:Set(nil, true)
        manager:Refresh()
    end)

    refreshStatus()
    return manager
end

-- The third ready-made manager: the settings that belong to the menu itself.
-- It always drives this window, and it can own the draggable FPS/ping
-- watermark so scripts do not have to build one by hand. Pass an existing
-- draggable label as Watermark to control that one instead.
function Tab:InterfaceManager(opts)
    opts = normalize(opts, { Title = "Name" })
    local host = managerHost(self, opts, "Interface", "monitor")
    local window = self.Window
    local manager = {}
    local keybind, backdropToggle, cursorToggle, watermarkToggle, toggleStyle, keybindMenuToggle
    local watermark = type(opts.Watermark) == "table" and type(opts.Watermark.SetVisible) == "function"
        and not opts.Watermark.Destroyed and opts.Watermark or nil
    local ownsWatermark = false
    local autoCreated = false

    if opts.Watermark ~= false and not watermark then
        watermark = window._interfaceWatermark
        if not watermark or watermark.Destroyed then
            watermark = Library:AddDraggableLabel({
                Window = window,
                Text = (opts.WatermarkName or window.Title or "Aster UI") .. " | -- FPS | -- ms",
                Position = opts.WatermarkPosition or Vector2.new(20, 70),
            })
            window._interfaceWatermark = watermark
            autoCreated = true
        end
        ownsWatermark = watermark ~= nil
    end

    -- Hidden by default, like the snippet this manager replaces. A watermark
    -- handed in by the script keeps whatever visibility it already had unless
    -- WatermarkVisible says otherwise.
    if watermark and not watermark.Destroyed then
        if autoCreated then
            watermark:SetVisible(opts.WatermarkVisible == true)
        elseif opts.WatermarkVisible ~= nil then
            watermark:SetVisible(opts.WatermarkVisible == true)
        end
    end

    -- The readout is the only part of the watermark this manager maintains.
    -- A label passed in by the script is left to the script's own updater.
    if ownsWatermark and watermark and window._interfaceWatermarkBound ~= watermark then
        window._interfaceWatermarkBound = watermark
        local frames, elapsed = 0, 0
        table.insert(window._connections, RunService.Heartbeat:Connect(function(deltaTime)
            if window._destroyed or not watermark or watermark.Destroyed then
                return
            end
            frames += 1
            elapsed += deltaTime
            if elapsed < 0.5 then
                return
            end
            local fps = math.floor(frames / elapsed + 0.5)
            frames, elapsed = 0, 0
            local ping = 0
            pcall(function()
                ping = math.floor(StatsService.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
            end)
            if ping <= 0 then
                pcall(function()
                    ping = math.floor(LocalPlayer:GetNetworkPing() * 1000 + 0.5)
                end)
            end
            watermark:SetText((opts.WatermarkName or window.Title or "Aster UI") .. " | " .. fps .. " FPS | " .. ping .. " ms")
        end))
    end
    manager.Watermark = watermark

    local function watermarkShown()
        local pill = watermark and watermark.Label
        return watermark ~= nil and not watermark.Destroyed and not (pill and pill.Visible == false)
    end

    if opts.MenuKeybind ~= false then
        keybind = host:Keybind({
            Name = "Menu Keybind",
            Default = window.Keybind or "LeftAlt",
            OnChanged = function(key)
                if key then
                    window:SetKeybind(key)
                end
            end,
        })
        window._interfaceKeybind = keybind
    end

    if window._backdrop and opts.Backdrop ~= false then
        backdropToggle = host:Toggle({
            Name = "Backdrop",
            Default = window._backdropEnabled ~= false,
            Callback = function(value)
                window:SetBackdrop(value)
            end,
        })
        window._interfaceBackdropToggle = backdropToggle
    end

    if opts.CustomCursor ~= false then
        cursorToggle = host:Toggle({
            Name = "Custom Cursor",
            Default = window.ShowCustomCursor == true,
            Callback = function(value)
                window:SetShowCustomCursor(value)
            end,
        })
        window._interfaceCursorToggle = cursorToggle
    end

    if watermark and not watermark.Destroyed and opts.Watermark ~= false then
        watermarkToggle = host:Toggle({
            Name = "Watermark",
            Default = watermarkShown(),
            Callback = function(value)
                if watermark and not watermark.Destroyed then
                    watermark:SetVisible(value)
                end
            end,
        })
        window._interfaceWatermarkToggle = watermarkToggle
    end

    -- Opens the floating Keybind Menu, the same list Obsidian hangs off its
    -- KeybindFrame. Stored on the window so the menu can keep this toggle in
    -- step when it is opened or closed through the API.
    if opts.KeybindMenu ~= false then
        keybindMenuToggle = host:Toggle({
            Name = "Keybind Menu",
            Default = window.KeybindFrame ~= nil and window.KeybindFrame.Visible == true,
            Callback = function(value)
                window:SetKeybindMenu(value)
            end,
        })
        window._keybindMenuToggle = keybindMenuToggle
    end

    if opts.ToggleStyle ~= false then
        toggleStyle = host:Dropdown({
            Name = "Toggle Style",
            Options = { "Toggle", "Checkbox" },
            -- The script's choice picks the starting option: ForceCheckbox in
            -- CreateWindow, or Aster.ForceCheckbox set before the window.
            Default = Library.ForceCheckbox and "Checkbox" or "Toggle",
            AllowNone = false,
            Callback = function(style)
                if style then
                    Library:SetForceCheckbox(style == "Checkbox")
                end
            end,
        })
        window._interfaceToggleStyle = toggleStyle
    end

    if opts.Unload ~= false then
        host:Button({
            Name = "Unload",
            Icon = "power",
            Style = "Danger",
            Callback = function()
                window:Confirm({
                    Title = "Unload " .. (window.Title or "Aster UI") .. "?",
                    Content = "Every feature is switched off and the menu closes.",
                    Icon = "power",
                    ConfirmText = "Unload",
                    Callback = function()
                        window:Destroy()
                    end,
                })
            end,
        })
    end

    -- Pull the widgets back in line with the window, for scripts that change
    -- these options through the API rather than through the manager.
    function manager:Refresh()
        if keybind and not keybind._destroyed then
            keybind:Set(window.Keybind, true)
        end
        if backdropToggle and not backdropToggle._destroyed then
            backdropToggle:Set(window._backdropEnabled ~= false, true)
        end
        if cursorToggle and not cursorToggle._destroyed then
            cursorToggle:Set(window.ShowCustomCursor == true, true)
        end
        if watermarkToggle and not watermarkToggle._destroyed then
            watermarkToggle:Set(watermarkShown(), true)
        end
        if toggleStyle and not toggleStyle._destroyed then
            toggleStyle:Set(Library.ForceCheckbox and "Checkbox" or "Toggle", true)
        end
        if keybindMenuToggle and not keybindMenuToggle._destroyed then
            keybindMenuToggle:Set(window.KeybindFrame ~= nil and window.KeybindFrame.Visible == true, true)
        end
    end

    -- One hidden flag carries the whole panel, so a config reloads the menu's
    -- own settings without each row counting as a running feature.
    if opts.Flag ~= false then
        local flag = type(opts.Flag) == "string" and opts.Flag or "__Interface"
        local interface = { _type = "Interface", _searchName = "Interface", _searchKey = "interface", _listeners = {} }

        function interface:Get()
            local bind = keybind and keybind:Get() or nil
            return {
                MenuKey = bind and bind.Name or nil,
                Backdrop = if backdropToggle then backdropToggle:Get() else nil,
                CustomCursor = if cursorToggle then cursorToggle:Get() else nil,
                Watermark = if watermarkToggle then watermarkToggle:Get() else nil,
                ToggleStyle = toggleStyle and toggleStyle:Get() or nil,
                KeybindMenu = if keybindMenuToggle then keybindMenuToggle:Get() else nil,
            }
        end

        function interface:Set(value)
            if type(value) ~= "table" then
                return
            end
            if keybind and not keybind._destroyed and value.MenuKey ~= nil then
                local bind = Keybinds.Resolve(value.MenuKey)
                if bind then
                    keybind:Set(bind, true)
                    window:SetKeybind(bind)
                end
            end
            if backdropToggle and not backdropToggle._destroyed and type(value.Backdrop) == "boolean" then
                backdropToggle:Set(value.Backdrop, true)
                window:SetBackdrop(value.Backdrop)
            end
            if cursorToggle and not cursorToggle._destroyed and type(value.CustomCursor) == "boolean" then
                cursorToggle:Set(value.CustomCursor, true)
                window:SetShowCustomCursor(value.CustomCursor)
            end
            if watermarkToggle and not watermarkToggle._destroyed and type(value.Watermark) == "boolean" then
                watermarkToggle:Set(value.Watermark, true)
                if watermark and not watermark.Destroyed then
                    watermark:SetVisible(value.Watermark)
                end
            end
            if toggleStyle and not toggleStyle._destroyed
                and (value.ToggleStyle == "Toggle" or value.ToggleStyle == "Checkbox") then
                Library:SetForceCheckbox(value.ToggleStyle == "Checkbox")
                toggleStyle:Set(value.ToggleStyle, true)
            end
            if keybindMenuToggle and not keybindMenuToggle._destroyed and type(value.KeybindMenu) == "boolean" then
                keybindMenuToggle:Set(value.KeybindMenu, true)
                window:SetKeybindMenu(value.KeybindMenu)
            end
        end

        Library.Flags[flag] = interface
        window:_flagCreated(flag, interface)
    end

    return manager
end

Tab.CreateButtonRow = Tab.ButtonRow
Tab.CreateConfigManager = Tab.ConfigManager
Tab.CreateThemeManager = Tab.ThemeManager
Tab.CreateInterfaceManager = Tab.InterfaceManager

-- Status: read-only key/value lines, mostly for groupboxes, in several styles.

local STATUS_HEIGHT = { Plain = 22, Row = 24, Badge = 28, Dot = 24, Bar = 38, Stat = 46 }

-- Tone: a theme key, a Color3 or "#rrggbb".
local function toneColor(tone)
    return Library._color(tone) or Theme.Accent
end

local function formatNumber(value)
    if value == math.floor(value) then
        return tostring(math.floor(value))
    end
    return string.format("%.1f", value)
end

local function parseFraction(value, max)
    if type(value) == "number" and type(max) == "number" then
        return value, max
    end
    if type(value) == "string" then
        local cleaned = (value:gsub(",", ""))
        local current, total = cleaned:match("^%s*(%-?[%d%.]+)%s*/%s*(%-?[%d%.]+)")
        if current then
            return tonumber(current), tonumber(total)
        end
    end
    return nil, nil
end

function Tab:Status(opts)
    opts = normalize(opts, { Title = "Name", Text = "Value", Content = "Value", CurrentValue = "Value", Default = "Value" })
    local style = STATUS_HEIGHT[opts.Style] and opts.Style or "Plain"
    local compact = metricsOf(self).Compact
    local window = self.Window
    local height = STATUS_HEIGHT[style]
    local pad = compact and 0 or 8
    local frame = card(self, "Frame", height + pad * 2, opts)
    local holder = create("Frame", {
        Position = UDim2.fromOffset(14, pad),
        Size = UDim2.new(1, -28, 0, height),
        BackgroundTransparency = 1,
        Parent = frame,
    })

    local handle = { Value = opts.Value, Max = opts.Max, Tone = opts.Tone or "Accent", Name = opts.Name or "", Color = opts.Color or opts.ValueColor }
    local keyLabel, valueLabel, chip, chipStroke, dot, pulse, fill
    local tinted = false

    local function keyText()
        return style == "Plain" and (handle.Name .. ":") or handle.Name
    end

    if style == "Plain" then
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 5),
            Parent = holder,
        })
        keyLabel = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 1,
            Parent = holder,
        })
        valueLabel = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = holder,
        })
    elseif style == "Stat" then
        keyLabel = label({
            Position = UDim2.fromOffset(0, 3),
            Size = UDim2.new(1, 0, 0, 14),
            TextSize = 11,
            TextColor3 = Theme.Muted,
            Parent = holder,
        })
        valueLabel = label({
            Position = UDim2.fromOffset(0, 18),
            Size = UDim2.new(1, 0, 0, 24),
            TextSize = 20,
            FontFace = Fonts.Bold,
            TextColor3 = Theme.Text,
            Parent = holder,
        })
    else
        local keyX = 0
        if style == "Dot" then
            keyX = 18
            pulse = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 5, 0.5, 0),
                Size = UDim2.fromOffset(8, 8),
                BackgroundColor3 = toneColor(handle.Tone),
                BackgroundTransparency = 0.4,
                BorderSizePixel = 0,
                Parent = holder,
            })
            corner(pulse, UDim.new(1, 0))
            dot = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 5, 0.5, 0),
                Size = UDim2.fromOffset(8, 8),
                BackgroundColor3 = toneColor(handle.Tone),
                BorderSizePixel = 0,
                Parent = holder,
            })
            corner(dot, UDim.new(1, 0))
            if opts.Pulse ~= false then
                TweenService:Create(pulse, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), {
                    Size = UDim2.fromOffset(20, 20),
                    BackgroundTransparency = 1,
                }):Play()
            else
                pulse.Visible = false
            end
        end
        local rowHeight = style == "Bar" and 18 or height
        keyLabel = label({
            Position = UDim2.fromOffset(keyX, 0),
            Size = UDim2.new(0.55, -keyX, 0, rowHeight),
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = holder,
        })
        if style == "Badge" then
            tinted = true
            chip = create("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(0, 22),
                AutomaticSize = Enum.AutomaticSize.X,
                BackgroundColor3 = toneColor(handle.Tone),
                BackgroundTransparency = 0.86,
                BorderSizePixel = 0,
                Parent = holder,
            })
            corner(chip, UDim.new(1, 0))
            chipStroke = stroke(chip, toneColor(handle.Tone), 0.6)
            padding(chip, 10, 10)
            valueLabel = label({
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                TextSize = 12,
                TextColor3 = toneColor(handle.Tone),
                TextTruncate = Enum.TextTruncate.None,
                Parent = chip,
            })
        else
            valueLabel = label({
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0.45, 0, 0, rowHeight),
                TextSize = 12,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Right,
                Parent = holder,
            })
        end
        if style == "Bar" then
            local track = create("Frame", {
                Position = UDim2.fromOffset(0, 25),
                Size = UDim2.new(1, 0, 0, 5),
                BackgroundColor3 = Theme.Surface3,
                BorderSizePixel = 0,
                ClipsDescendants = true,
                Parent = holder,
            })
            corner(track, UDim.new(1, 0))
            fill = create("Frame", {
                Size = UDim2.new(0, 0, 1, 0),
                BackgroundColor3 = toneColor(handle.Tone),
                BorderSizePixel = 0,
                Parent = track,
            })
            corner(fill, UDim.new(1, 0))
        end
    end

    local lastText = nil
    local function render(animate)
        keyLabel.Text = Library._rich(keyText())
        local value = handle.Value
        local text = value == nil and (opts.Placeholder or "-") or tostring(value)
        if style == "Bar" then
            local current, total = parseFraction(value, handle.Max)
            if current and total then
                handle.Max = total
                text = formatNumber(current) .. " / " .. formatNumber(total)
                local fraction = total > 0 and math.clamp(current / total, 0, 1) or 0
                tween(fill, { Size = UDim2.new(fraction, 0, 1, 0) }, animate and 0.4 or 0, Enum.EasingStyle.Quint)
            elseif type(value) == "number" and value <= 1 then
                text = string.format("%d%%", math.floor(value * 100 + 0.5))
                tween(fill, { Size = UDim2.new(math.clamp(value, 0, 1), 0, 1, 0) }, animate and 0.4 or 0, Enum.EasingStyle.Quint)
            end
        end
        text = Library._rich((opts.Prefix or "") .. text .. (opts.Suffix or ""))
        local changed = lastText ~= nil and text ~= lastText
        lastText = text
        valueLabel.Text = text
        local tone = toneColor(handle.Tone)
        local duration = animate and 0.25 or 0
        -- Color paints the whole value; inline tags still win over it.
        local valueColor = not tinted and Library._color(handle.Color) or Theme.Text
        if not tinted and not (changed and animate and opts.Flash ~= false) then
            tween(valueLabel, { TextColor3 = valueColor }, duration)
        end
        if chip then
            tween(chip, { BackgroundColor3 = tone }, duration)
            tween(chipStroke, { Color = tone }, duration)
            tween(valueLabel, { TextColor3 = tone }, duration)
        end
        if dot then
            tween(dot, { BackgroundColor3 = tone }, duration)
            tween(pulse, { BackgroundColor3 = tone }, 0)
        end
        if fill then
            tween(fill, { BackgroundColor3 = tone }, duration)
        end
        -- A brief accent flash marks a changed value.
        if changed and animate and not tinted and opts.Flash ~= false then
            tween(valueLabel, { TextColor3 = Theme.Accent }, 0.08)
            task.delay(0.1, function()
                if valueLabel.Parent then
                    tween(valueLabel, { TextColor3 = Library._color(handle.Color) or Theme.Text }, 0.45)
                end
            end)
        end
    end

    keyLabel.RichText = true
    valueLabel.RichText = true
    -- Theme tags in the text are baked to colours, so repaint on theme change.
    onTheme(holder, function()
        if lastText ~= nil then
            render(false)
        end
    end)

    function handle:Set(value, max)
        handle.Value = value
        if max ~= nil then
            handle.Max = max
        end
        render(true)
    end
    function handle:Get()
        return handle.Value
    end
    function handle:SetTone(tone)
        handle.Tone = tone
        render(true)
    end
    -- nil goes back to the normal text colour.
    function handle:SetColor(color)
        handle.Color = color
        render(true)
    end
    function handle:SetName(name)
        handle.Name = tostring(name)
        render(false)
    end
    function handle:Text()
        return valueLabel.Text
    end
    -- The value's resting colour, for the copy pinned on the minimized island.
    function handle._shownColor()
        if handle.Color ~= nil then
            return Library._color(handle.Color) or Theme.Text
        end
        if style == "Badge" or style == "Dot" or style == "Bar" then
            return toneColor(handle.Tone)
        end
        return Theme.Text
    end

    handle._listeners = {}
    if type(opts.Update) == "function" then
        local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
        local running = true
        table.insert(handle._listeners, function()
            running = false
        end)
        task.spawn(function()
            while running and frame.Parent do
                local ok, value, extra = isolatedCall(opts.Update)
                if ok then
                    if value ~= nil then
                        handle.Value = value
                    end
                    if type(extra) == "number" then
                        handle.Max = extra
                    elseif type(extra) == "string" or typeof(extra) == "Color3" then
                        handle.Tone = extra
                    end
                    render(true)
                else
                    warn("[Aster UI] status update error: " .. tostring(value))
                end
                task.wait(rate)
            end
        end)
        function handle:SetUpdateRate(seconds)
            rate = math.max(tonumber(seconds) or rate, 0.05)
        end
    end
    if opts.Pin then
        table.insert(window._pinned, handle)
        table.insert(handle._listeners, function()
            local index = table.find(window._pinned, handle)
            if index then
                table.remove(window._pinned, index)
            end
        end)
    end

    render(false)
    return finishElement(self, opts, handle, frame, "Status")
end

function Tab:Statuses(entries, shared)
    local handles = {}
    for index, entry in ipairs(entries or {}) do
        local entryOpts = type(entry) == "table" and table.clone(entry) or { Name = tostring(entry) }
        for key, value in pairs(shared or {}) do
            if entryOpts[key] == nil then
                entryOpts[key] = value
            end
        end
        local handle = self:Status(entryOpts)
        handles[entryOpts.Name or entryOpts.Title or index] = handle
    end
    return handles
end

-- Status list: a read-only block of rows that grows up to MaxRows, then
-- scrolls inside itself. Rows are reused between refreshes so nothing flickers.
function Tab:StatusList(opts)
    opts = normalize(opts, { Title = "Name" })
    local compact = metricsOf(self).Compact
    local window = self.Window
    local maxRows = math.max(math.floor(tonumber(opts.MaxRows) or 5), 1)
    local frame = card(self, "Frame", 0, opts)
    frame.AutomaticSize = Enum.AutomaticSize.Y
    if compact then
        padding(frame, 14, 14, 6, 8)
    else
        padding(frame, 14, 14, 11, 12)
    end
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = frame,
    })
    local heading = label({
        Size = UDim2.new(1, 0, 0, 16),
        Text = string.upper(tostring(opts.Name or "")),
        TextSize = 11,
        TextColor3 = Theme.Muted,
        Visible = tostring(opts.Name or "") ~= "",
        LayoutOrder = 1,
        Parent = frame,
    })
    local scroller = create("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        ScrollingEnabled = false,
        LayoutOrder = 2,
        Parent = frame,
    })
    scroller:SetAttribute("NoDrag", true)
    local content = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = scroller,
    })
    local contentPadding = padding(content, 0, 0, 0, 0)
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = content,
    })
    local empty = label({
        Size = UDim2.new(1, 0, 0, 24),
        AutomaticSize = Enum.AutomaticSize.Y,
        Text = tostring(opts.EmptyText or "Nothing yet"),
        TextSize = 13,
        LineHeight = 1.1,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 0,
        Parent = content,
    })

    local rowObjects, rows, signature, raw = {}, {}, nil, {}
    local handle = { _listeners = {} }

    -- Fits the list to its first MaxRows rows, measured, so wrapped rows count
    -- at their real height. Past MaxRows the list scrolls.
    local function fit()
        if handle._destroyed then
            return
        end
        local scale = window.Scale.Scale
        local count = #rows
        local height = 0
        if count == 0 then
            height = empty.AbsoluteSize.Y / scale
        else
            local shown = math.min(count, maxRows)
            for index = 1, shown do
                height += rowObjects[index].Frame.AbsoluteSize.Y / scale
            end
            height += (shown - 1) * 2
        end
        height = math.ceil(height)
        local scrolling = count > maxRows
        scroller.ScrollingEnabled = scrolling
        contentPadding.PaddingRight = UDim.new(0, scrolling and 8 or 0)
        if scroller.Size.Y.Offset ~= height then
            scroller.Size = UDim2.new(1, 0, 0, height)
        end
        local maxScroll = math.max(scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y, 0) / scale
        if scroller.CanvasPosition.Y > maxScroll then
            scroller.CanvasPosition = Vector2.new(0, maxScroll)
        end
    end

    local function fitText(row)
        if row.Value.Visible then
            row.Text.Size = UDim2.new(1, -(math.ceil(row.Value.AbsoluteSize.X / window.Scale.Scale) + 12), 0, 24)
        else
            row.Text.Size = UDim2.new(1, 0, 0, 24)
        end
    end

    local function newRow(order)
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = content,
        })
        local row = {
            Frame = holder,
            Text = label({
                Size = UDim2.new(1, 0, 0, 24),
                AutomaticSize = Enum.AutomaticSize.Y,
                Text = "",
                TextSize = 13,
                LineHeight = 1.1,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                TextWrapped = true,
                TextTruncate = Enum.TextTruncate.None,
                RichText = true,
                Parent = holder,
            }),
            Value = label({
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.new(0, 0, 0, 24),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = "",
                TextSize = 12,
                FontFace = Fonts.Medium,
                TextColor3 = Theme.Text,
                RichText = true,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextTruncate = Enum.TextTruncate.None,
                Visible = false,
                Parent = holder,
            }),
        }
        row.Connections = {
            holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit),
            row.Value:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
                fitText(row)
            end),
        }
        return row
    end

    local function normalizeRow(entry)
        if type(entry) == "table" then
            local text = entry.Text or entry.Name or entry[1]
            local tone = entry.Tone or entry.Color
            return {
                Text = tostring(text == nil and "" or text),
                Value = entry.Value ~= nil and tostring(entry.Value) or nil,
                Tone = (type(tone) == "string" or typeof(tone) == "Color3") and tone or nil,
            }
        end
        return { Text = tostring(entry) }
    end

    local function rowKey(entry)
        return entry.Text .. "\0" .. (entry.Value or "\1") .. "\0" .. tostring(entry.Tone or "")
    end

    -- Tone tints the value, or the text when there is no value.
    local function paint(row, entry)
        local key = rowKey(entry)
        if row.Key == key then
            return
        end
        row.Key = key
        row.Text.Text = Library._rich(entry.Text)
        local tone = entry.Tone and Library._color(entry.Tone) or nil
        if entry.Value then
            row.Value.Text = Library._rich(entry.Value)
            row.Value.Visible = true
            tween(row.Value, { TextColor3 = tone or Theme.Text }, 0)
            tween(row.Text, { TextColor3 = Theme.Muted }, 0)
        else
            row.Value.Visible = false
            tween(row.Text, { TextColor3 = tone or Theme.Muted }, 0)
        end
        fitText(row)
    end

    local function dropRow(row)
        for _, connection in ipairs(row.Connections) do
            connection:Disconnect()
        end
        row.Frame:Destroy()
    end

    function handle:Set(list)
        if type(list) ~= "table" or handle._destroyed then
            return
        end
        local nextRows, keys = {}, {}
        raw = {}
        for index, entry in ipairs(list) do
            raw[index] = type(entry) == "table" and table.clone(entry) or entry
            local row = normalizeRow(entry)
            nextRows[index] = row
            keys[index] = rowKey(row)
        end
        local nextSignature = table.concat(keys, "\2") .. "#" .. #nextRows
        if nextSignature == signature then
            return
        end
        signature = nextSignature
        rows = nextRows
        for index, entry in ipairs(rows) do
            local row = rowObjects[index]
            if not row then
                row = newRow(index)
                rowObjects[index] = row
            end
            paint(row, entry)
        end
        for index = #rowObjects, #rows + 1, -1 do
            dropRow(rowObjects[index])
            rowObjects[index] = nil
        end
        empty.Visible = #rows == 0
        fit()
    end
    function handle:Get()
        local copy = {}
        for index, entry in ipairs(raw) do
            copy[index] = type(entry) == "table" and table.clone(entry) or entry
        end
        return copy
    end
    function handle:Clear()
        handle:Set({})
    end
    function handle:SetName(text)
        text = tostring(text or "")
        heading.Text = string.upper(text)
        heading.Visible = text ~= ""
        handle._searchName = text
        handle._searchKey = string.lower(text)
    end
    local rate = math.max(tonumber(opts.UpdateRate) or 1, 0.05)
    function handle:SetUpdateRate(seconds)
        rate = math.max(tonumber(seconds) or rate, 0.05)
    end

    -- Theme tags are baked into the text, so a theme change repaints the rows.
    onTheme(content, function()
        for index, row in ipairs(rowObjects) do
            if rows[index] then
                row.Key = nil
                paint(row, rows[index])
            end
        end
    end)

    local emptyConnection = empty:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    table.insert(handle._listeners, function()
        handle._destroyed = true
        emptyConnection:Disconnect()
        for _, row in ipairs(rowObjects) do
            for _, connection in ipairs(row.Connections) do
                connection:Disconnect()
            end
        end
    end)

    -- Refreshes only while someone can see it: window open and not minimized,
    -- its tab and sub tab showing, and neither it nor its groupbox hidden.
    local function onScreen()
        if window._destroyed or not window.Open or window.Minimized or not handle._userVisible then
            return false
        end
        local page = self
        if page._groupbox then
            if page._userVisible == false then
                return false
            end
            page = page.Parent
        end
        if page._isSubTab then
            if page.Parent.CurrentSubTab ~= page then
                return false
            end
            page = page.Parent
        end
        return window.CurrentTab == page
    end

    if type(opts.Update) == "function" then
        local alive = true
        table.insert(handle._listeners, function()
            alive = false
        end)
        task.defer(function()
            local first = true
            while alive and frame.Parent do
                if first or onScreen() then
                    first = false
                    local ok, result = isolatedCall(opts.Update)
                    if ok then
                        if result ~= nil then
                            handle:Set(result)
                        end
                    else
                        warn("[Aster UI] status list update error: " .. tostring(result))
                    end
                end
                task.wait(rate)
            end
        end)
    end

    handle:Set(opts.Rows or {})
    return finishElement(self, opts, handle, frame, "StatusList")
end

Tab.CreateStatus = Tab.Status
Tab.AddStatus = Tab.Status
Tab.CreateStatuses = Tab.Statuses
Tab.CreateStatusList = Tab.StatusList
Tab.AddStatusList = Tab.StatusList

-- Image and Viewport: media cards. Image shows a picture from the same sources
-- as window backgrounds, plus "Avatar" for the player's headshot. Viewport
-- shows a 3D model or the player's avatar, turning slowly; drag it to spin it
-- by hand.

function Tab:_mediaCard(opts, defaultHeight)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local mediaHeight = math.clamp(tonumber(opts.Height) or defaultHeight, 40, 600)
    local inset = compact and 14 or 8
    local hasHead = type(opts.Name) == "string" and opts.Name ~= ""
    local titleTop = compact and 4 or 10
    local mediaTop = hasHead and (titleTop + (opts.Desc and 38 or 22)) or (compact and 4 or inset)
    local height = mediaTop + mediaHeight + (compact and 6 or inset)
    local frame, frameStroke = card(self, "Frame", height, opts)
    hoverStroke(frame, frameStroke)
    local title, descLabel
    if hasHead then
        title = label({
            Position = UDim2.fromOffset(14, titleTop),
            Size = UDim2.new(1, -28, 0, metrics.TitleHeight),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = frame,
        })
        if opts.Desc then
            descLabel = label({
                Position = UDim2.fromOffset(14, titleTop + metrics.TitleHeight + 1),
                Size = UDim2.new(1, -28, 0, metrics.DescLine),
                Text = opts.Desc,
                TextSize = metrics.DescSize,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = frame,
            })
        end
    end
    local media = create("Frame", {
        Position = UDim2.fromOffset(inset, mediaTop),
        Size = UDim2.new(1, -inset * 2, 0, mediaHeight),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(media, UDim.new(0, 6))
    stroke(media, Theme.Stroke)
    local placeholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 0.3,
        ScaleType = Enum.ScaleType.Fit,
        Parent = media,
    })
    -- A caption over the bottom of the picture, on a dark fade.
    local captionHolder = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 3,
        Parent = media,
    })
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new(1, 0),
        Parent = captionHolder,
    })
    local caption = label({
        Position = UDim2.fromOffset(10, 8),
        Size = UDim2.new(1, -20, 1, -10),
        TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1),
        ZIndex = 4,
        Parent = captionHolder,
    })
    local function setCaption(text)
        text = text ~= nil and tostring(text) or ""
        caption.Text = text
        captionHolder.Visible = text ~= ""
    end
    setCaption(opts.Caption)
    return opts, {
        Frame = frame,
        Stroke = frameStroke,
        Media = media,
        Placeholder = placeholder,
        Title = title,
        Desc = descLabel,
        SetCaption = setCaption,
    }
end

function Tab:Image(opts)
    local parts
    opts, parts = self:_mediaCard(opts, 160)
    local window = self.Window
    local media = parts.Media
    applyIcon(parts.Placeholder, "image")
    -- Enum lookups throw on unknown names.
    local function scaleType(name, fallback)
        local ok, value = pcall(function()
            return Enum.ScaleType[tostring(name)]
        end)
        return ok and value or fallback
    end
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageTransparency = 1,
        ScaleType = scaleType(opts.ScaleType or "Crop", Enum.ScaleType.Crop),
        ZIndex = 2,
        Parent = media,
    })
    corner(image, UDim.new(0, 6))
    if opts.Color then
        image.ImageColor3 = opts.Color
    end

    local handle = { Value = nil }
    local generation = 0

    -- Yields while a web image downloads. Returns ok, err like SetBackground.
    function handle:SetImage(source)
        generation += 1
        local current = generation
        handle.Value = source
        if source == nil or source == "" or source == "None" then
            tween(image, { ImageTransparency = 1 }, 0.2)
            tween(parts.Placeholder, { ImageTransparency = 0.3 }, 0.2)
            return true
        end
        local asset, err
        if type(source) == "number" then
            asset = "rbxassetid://" .. math.floor(source)
        elseif type(source) == "string" and ({ avatar = true, headshot = true })[source:lower()] then
            asset = "rbxthumb://type=AvatarHeadShot&id=" .. LocalPlayer.UserId .. "&w=420&h=420"
        else
            local ok, result, message = pcall(window._resolveBackground, window, tostring(source))
            if ok then
                asset, err = result, message
            else
                err = tostring(result)
            end
        end
        if generation ~= current then
            return false, "replaced by a newer image"
        end
        if not asset then
            warn("[Aster UI] image: " .. tostring(err))
            return false, err
        end
        image.ImageTransparency = 1
        image.Image = asset
        -- Fade in once it has loaded, or after a few seconds regardless.
        task.spawn(function()
            local waited = 0
            while not image.IsLoaded and waited < 4 and generation == current and image.Parent do
                waited += task.wait(0.05)
            end
            if generation == current and image.Parent then
                tween(image, { ImageTransparency = 0 }, 0.35)
                tween(parts.Placeholder, { ImageTransparency = 1 }, 0.2)
            end
        end)
        return true
    end
    handle.Set = handle.SetImage

    function handle:Get()
        return handle.Value
    end

    function handle:SetCaption(text)
        parts.SetCaption(text)
    end

    function handle:SetScaleType(name)
        image.ScaleType = scaleType(name, image.ScaleType)
    end

    function handle:SetColor(color)
        image.ImageColor3 = typeof(color) == "Color3" and color or Color3.new(1, 1, 1)
    end

    function handle:SetTitle(text)
        if parts.Title then
            parts.Title.Text = tostring(text)
        end
    end

    if opts.Image ~= nil then
        task.spawn(handle.SetImage, handle, opts.Image)
    end
    return finishElement(self, opts, handle, parts.Frame, "Image")
end

function Tab:Viewport(opts)
    local parts
    opts, parts = self:_mediaCard(opts, 180)
    local window = self.Window
    local media = parts.Media
    applyIcon(parts.Placeholder, "box")

    local viewport = create("ViewportFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ImageTransparency = 1,
        Ambient = opts.Ambient or Color3.fromRGB(165, 160, 175),
        LightColor = opts.LightColor or Color3.fromRGB(255, 250, 245),
        LightDirection = Vector3.new(-0.6, -1, -0.8),
        ZIndex = 2,
        Parent = media,
    })
    local camera = Instance.new("Camera")
    camera.FieldOfView = math.clamp(tonumber(opts.FieldOfView) or 35, 10, 90)
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    local world = Instance.new("WorldModel")
    world.Parent = viewport

    local handle = {
        Model = nil,
        Spin = opts.Spin ~= false,
        SpinSpeed = tonumber(opts.SpinSpeed) or 25,
    }
    local angle = math.rad(tonumber(opts.Angle) or 0)
    local pitch = math.rad(tonumber(opts.Pitch) or 10)
    local distanceScale = tonumber(opts.Distance) or 1
    local center, distance, basis = nil, 10, CFrame.new()
    local source = nil
    local generation = 0
    local dragging, lastX, resumeAt = false, 0, 0

    local function place()
        if not center then
            return
        end
        local direction = basis:VectorToWorldSpace(Vector3.new(
            math.sin(angle) * math.cos(pitch),
            math.sin(pitch),
            -math.cos(angle) * math.cos(pitch)
        ))
        camera.CFrame = CFrame.lookAt(center + direction * distance, center)
    end

    local function fit(model)
        local cf, size
        if model:IsA("Model") then
            cf, size = model:GetBoundingBox()
            basis = model:GetPivot().Rotation
        elseif model:IsA("BasePart") then
            cf, size = model.CFrame, model.Size
            basis = model.CFrame.Rotation
        else
            return false
        end
        center = cf.Position
        local radius = math.max(size.Magnitude / 2, 0.5)
        distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * distanceScale
        place()
        return true
    end

    -- A copy with its scripts and sounds stripped and every part anchored.
    local function prepare(instance)
        local copy = instance
        if opts.Clone ~= false then
            local archivable = instance.Archivable
            pcall(function()
                instance.Archivable = true
            end)
            local ok, result = pcall(instance.Clone, instance)
            pcall(function()
                instance.Archivable = archivable
            end)
            copy = ok and result or nil
        end
        if not copy then
            return nil
        end
        local function clean(object)
            if object:IsA("LuaSourceContainer") or object:IsA("Sound") or object:IsA("ForceField") then
                object:Destroy()
            elseif object:IsA("BasePart") then
                object.Anchored = true
                object.CanCollide = false
            end
        end
        for _, object in ipairs(copy:GetDescendants()) do
            pcall(clean, object)
        end
        if copy:IsA("BasePart") then
            copy.Anchored = true
        end
        local humanoid = copy:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
        end
        return copy
    end

    local function resolve(value)
        if type(value) == "function" then
            local ok, result = pcall(value)
            value = ok and result or nil
        end
        if type(value) == "string" and ({ avatar = true, player = true, character = true })[value:lower()] then
            value = LocalPlayer
        end
        if typeof(value) == "Instance" and value:IsA("Player") then
            local character = value.Character
            if not character then
                character = value.CharacterAdded:Wait()
                -- Let the body parts and accessories load in.
                task.wait(0.5)
            end
            value = character
        end
        return typeof(value) == "Instance" and value or nil
    end

    -- Yields while waiting for a character to spawn.
    function handle:SetModel(value)
        generation += 1
        local current = generation
        source = value
        if handle.Model then
            handle.Model:Destroy()
            handle.Model = nil
        end
        center = nil
        if value == nil then
            tween(viewport, { ImageTransparency = 1 }, 0.2)
            tween(parts.Placeholder, { ImageTransparency = 0.3 }, 0.2)
            return true
        end
        local instance = resolve(value)
        if generation ~= current then
            return false, "replaced by a newer model"
        end
        if not instance then
            return false, "no model to show"
        end
        local copy = prepare(instance)
        if not copy then
            return false, "could not copy the model"
        end
        copy.Parent = world
        handle.Model = copy
        if not fit(copy) then
            copy:Destroy()
            handle.Model = nil
            return false, "not a Model or a part"
        end
        viewport.ImageTransparency = 1
        tween(viewport, { ImageTransparency = 0 }, 0.35)
        tween(parts.Placeholder, { ImageTransparency = 1 }, 0.2)
        return true
    end
    handle.Set = handle.SetModel

    function handle:Get()
        return handle.Model
    end

    -- Copies the source again, e.g. after the character respawned or changed.
    function handle:Refresh()
        return handle:SetModel(source)
    end

    function handle:SetSpin(enabled)
        handle.Spin = enabled ~= false
    end

    function handle:SetSpinSpeed(degrees)
        handle.SpinSpeed = tonumber(degrees) or handle.SpinSpeed
    end

    function handle:SetAngle(degrees)
        angle = math.rad(tonumber(degrees) or 0)
        place()
    end

    function handle:SetCaption(text)
        parts.SetCaption(text)
    end

    function handle:SetTitle(text)
        if parts.Title then
            parts.Title.Text = tostring(text)
        end
    end

    media.InputBegan:Connect(function(input)
        if isPress(input) and handle.Model then
            dragging = true
            lastX = pointerPosition().X
        end
    end)
    window:_listen("Changed", function(input)
        if dragging and isMove(input) then
            local x = pointerPosition().X
            angle -= (x - lastX) * 0.012
            lastX = x
            place()
        end
    end, handle)
    window:_listen("Ended", function(input)
        if dragging and isPress(input) then
            dragging = false
            resumeAt = os.clock() + 1.5
        end
    end, handle)
    window:_listen("Render", function(deltaTime)
        if handle.Spin and center and not dragging and os.clock() >= resumeAt and window.Open and not window.Minimized
            and parts.Frame.Visible then
            angle += math.rad(handle.SpinSpeed) * deltaTime
            place()
        end
    end, handle)

    if opts.Model ~= nil then
        task.spawn(handle.SetModel, handle, opts.Model)
    end
    return finishElement(self, opts, handle, parts.Frame, "Viewport")
end

-- Table: rows under a header, sortable by clicking a column. Rank = true adds
-- a # column with medals for the top three, for leaderboards.

function Tab:Table(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc", Data = "Rows", OnRowClick = "Callback" })
    local window = self.Window
    local metrics = metricsOf(self)
    local compact = metrics.Compact
    local rowHeight = tonumber(opts.RowHeight) or (TOUCH and 32 or 26)
    local maxRows = math.max(math.floor(tonumber(opts.MaxRows) or 8), 1)
    local headerHeight = TOUCH and 28 or 24
    local textSize = compact and 12 or 13
    local inset = compact and 14 or 8
    local hasHead = type(opts.Name) == "string" and opts.Name ~= ""
    local titleTop = compact and 4 or 10
    local searchable = opts.Search ~= false
    local searchHeight = TOUCH and 30 or 26
    local searchTop = hasHead and (titleTop + (opts.Desc and 38 or 22)) or (compact and 4 or inset)
    local gridTop = searchTop + (searchable and searchHeight + 6 or 0)
    local bottom = compact and 6 or inset

    local frame, frameStroke = card(self, "Frame", gridTop + headerHeight + rowHeight + bottom, opts)
    hoverStroke(frame, frameStroke)
    local title
    if hasHead then
        title = label({
            Position = UDim2.fromOffset(14, titleTop),
            Size = UDim2.new(1, -28, 0, metrics.TitleHeight),
            Text = opts.Name,
            TextSize = metrics.TextSize,
            Parent = frame,
        })
        if opts.Desc then
            label({
                Position = UDim2.fromOffset(14, titleTop + metrics.TitleHeight + 1),
                Size = UDim2.new(1, -28, 0, metrics.DescLine),
                Text = opts.Desc,
                TextSize = metrics.DescSize,
                FontFace = Fonts.Regular,
                TextColor3 = Theme.Muted,
                Parent = frame,
            })
        end
    end
    -- Search: filters rows by any cell's text as you type. A count of what
    -- matches shows on the right while it filters.
    local query = ""
    local searchBox, searchCount
    if searchable then
        local holder = create("Frame", {
            Position = UDim2.fromOffset(inset, searchTop),
            Size = UDim2.new(1, -inset * 2, 0, searchHeight),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            Parent = frame,
        })
        holder:SetAttribute("NoDrag", true)
        corner(holder, UDim.new(0, 6))
        local searchStroke = stroke(holder)
        local iconHolder, searchIcon = glowIcon(holder, "search", Theme.Muted, UDim2.new(0, 9, 0.5, 0))
        iconHolder.Size = UDim2.fromOffset(13, 13)
        searchCount = label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -9, 0, 0),
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 11,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Visible = false,
            Parent = holder,
        })
        searchBox = create("TextBox", {
            Position = UDim2.fromOffset(29, 0),
            Size = UDim2.new(1, -90, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            PlaceholderText = opts.SearchPlaceholder or "Search",
            PlaceholderColor3 = Theme.Muted,
            TextColor3 = Theme.Text,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            ClearTextOnFocus = false,
            Parent = holder,
        })
        searchBox.Focused:Connect(function()
            tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
            tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
        end)
        searchBox.FocusLost:Connect(function()
            tween(searchStroke, { Color = Theme.Stroke }, 0.2)
            tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
        end)
    end

    local grid = create("Frame", {
        Position = UDim2.fromOffset(inset, gridTop),
        Size = UDim2.new(1, -inset * 2, 0, headerHeight + rowHeight),
        BackgroundColor3 = Theme.Surface,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = frame,
    })
    corner(grid, UDim.new(0, 6))
    stroke(grid, Theme.Stroke)
    local header = create("Frame", {
        Size = UDim2.new(1, 0, 0, headerHeight),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Parent = grid,
    })
    create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = header,
    })
    local body = create("ScrollingFrame", {
        Position = UDim2.fromOffset(0, headerHeight),
        Size = UDim2.new(1, 0, 1, -headerHeight),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.new(),
        Parent = grid,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = body,
    })
    local empty = label({
        Position = UDim2.fromOffset(0, headerHeight),
        Size = UDim2.new(1, 0, 0, rowHeight),
        Text = opts.EmptyText or "Nothing here yet",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = grid,
    })

    local handle = { Rows = {} }
    local shownCount = nil
    local columns, headerCells = {}, {}
    local pool = {}
    local sortKey, sortDescending = nil, false
    local shownHeight = nil
    local MEDALS = {
        Color3.fromRGB(245, 200, 90),
        Color3.fromRGB(200, 206, 218),
        Color3.fromRGB(214, 146, 96),
    }

    local function alignment(column)
        local align = type(column.Align) == "string" and column.Align:lower() or nil
        if align == "right" then
            return Enum.TextXAlignment.Right
        elseif align == "center" or align == "centre" then
            return Enum.TextXAlignment.Center
        end
        return Enum.TextXAlignment.Left
    end

    -- Widths: a number above 1 is pixels, up to 1 is a share of what the pixel
    -- columns leave, and the rest split whatever share is left.
    local function layoutColumns()
        local pixels, shares, autos = 0, 0, 0
        for _, column in ipairs(columns) do
            local width = tonumber(column.Width)
            if width and width > 1 then
                pixels += width
            elseif width and width > 0 then
                shares += width
            else
                autos += 1
            end
        end
        local left = math.max(1 - shares, 0)
        for _, column in ipairs(columns) do
            local width = tonumber(column.Width)
            local share
            if width and width > 1 then
                column.UDim = UDim.new(0, width)
            else
                share = (width and width > 0) and width or (autos > 0 and left / autos or 0)
                column.UDim = UDim.new(share, -pixels * share)
            end
        end
    end

    local function columnValue(row, column)
        if column.Rank then
            return nil
        end
        if row[1] ~= nil or column.Key == nil then
            return row[column.Index]
        end
        return row[column.Key]
    end

    local function display(value, column, row)
        if type(column.Format) == "function" then
            local ok, text = pcall(column.Format, value, row)
            if ok and text ~= nil then
                return tostring(text)
            end
        end
        if type(value) == "number" then
            local whole = value == math.floor(value)
            local text = whole and string.format("%d", value) or string.format("%.2f", value)
            -- Thousands separators on the whole part.
            local sign, int, rest = text:match("^(%-?)(%d+)(.*)$")
            if int then
                int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
                return sign .. int .. rest
            end
            return text
        end
        if value == nil then
            return ""
        end
        return tostring(value)
    end

    local function paintHeader()
        for _, cell in ipairs(headerCells) do
            local column = cell.Column
            local active = sortKey ~= nil and sortKey == column
            tween(cell.Label, { TextColor3 = active and Theme.Text or Theme.Muted }, 0.15)
            cell.Arrow.Visible = active
            if active then
                tween(cell.Arrow, { Rotation = sortDescending and 0 or 180 }, 0.2, Enum.EasingStyle.Quint)
            end
        end
    end

    local function sortedRows()
        local list = {}
        for index, row in ipairs(handle.Rows) do
            list[index] = { Row = row, Index = index }
        end
        if sortKey then
            local column = sortKey
            table.sort(list, function(a, b)
                local x, y = columnValue(a.Row, column), columnValue(b.Row, column)
                local nx, ny = tonumber(x), tonumber(y)
                if nx and ny then
                    if nx ~= ny then
                        if sortDescending then
                            return nx > ny
                        end
                        return nx < ny
                    end
                elseif x ~= nil and y ~= nil then
                    local sx, sy = string.lower(tostring(x)), string.lower(tostring(y))
                    if sx ~= sy then
                        if sortDescending then
                            return sx > sy
                        end
                        return sx < sy
                    end
                elseif x ~= y then
                    -- Empty cells sink to the bottom either way.
                    return x ~= nil
                end
                return a.Index < b.Index
            end)
        end
        -- Ranks come from the full order, so filtering never renumbers them.
        for position, item in ipairs(list) do
            item.Rank = position
        end
        if query == "" then
            return list
        end
        local shown = {}
        for _, item in ipairs(list) do
            for _, column in ipairs(columns) do
                if not column.Rank then
                    local text = display(columnValue(item.Row, column), column, item.Row)
                    text = string.lower((string.gsub(text, "<[^>]->", "")))
                    if string.find(text, query, 1, true) then
                        table.insert(shown, item)
                        break
                    end
                end
            end
        end
        return shown
    end

    local function newRow()
        local rowFrame = create("TextButton", {
            Size = UDim2.new(1, 0, 0, rowHeight),
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            Parent = body,
        })
        -- The accent bar on a highlighted row sits beside the cells, outside
        -- their layout.
        local marker = create("Frame", {
            Position = UDim2.new(0, 3, 0.5, 0),
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.new(0, 2, 1, -10),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Parent = rowFrame,
        })
        corner(marker, UDim.new(1, 0))
        local cellsFrame = create("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Parent = rowFrame,
        })
        padding(cellsFrame, 10, 10)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Parent = cellsFrame,
        })
        local entry = { Frame = rowFrame, Marker = marker, Cells = {}, Hover = false }
        for order, column in ipairs(columns) do
            local cell = create("Frame", {
                Size = UDim2.new(column.UDim.Scale, column.UDim.Offset, 1, 0),
                BackgroundTransparency = 1,
                LayoutOrder = order,
                Parent = cellsFrame,
            })
            local text = label({
                Size = UDim2.new(1, -6, 1, 0),
                TextSize = textSize,
                FontFace = column.Rank and Fonts.Bold or Fonts.Regular,
                TextColor3 = Theme.Text,
                TextXAlignment = alignment(column),
                RichText = not column.Rank,
                Parent = cell,
            })
            local badge
            if column.Rank then
                text.Size = UDim2.fromScale(1, 1)
                text.TextXAlignment = Enum.TextXAlignment.Center
                badge = create("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(rowHeight - 8, rowHeight - 8),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    ZIndex = 0,
                    Parent = cell,
                })
                corner(badge, UDim.new(1, 0))
            end
            entry.Cells[order] = { Label = text, Badge = badge }
        end
        local canTap = tapGuard(rowFrame, function()
            return body
        end)
        rowFrame.MouseEnter:Connect(function()
            entry.Hover = true
            tween(rowFrame, { BackgroundTransparency = 0.35 }, 0.1)
        end)
        rowFrame.MouseLeave:Connect(function()
            entry.Hover = false
            tween(rowFrame, {
                BackgroundColor3 = entry.Highlighted and Theme.Accent or Theme.Surface3,
                BackgroundTransparency = entry.Rest or 1,
            }, 0.2)
        end)
        rowFrame.MouseButton1Click:Connect(function()
            if entry.Data and canTap() then
                safeCall(opts.Callback, entry.Data, entry.Index)
            end
        end)
        return entry
    end

    local function fitHeight(instant)
        local count = shownCount or #handle.Rows
        local visible = math.clamp(count, 1, maxRows)
        local gridHeight = headerHeight + visible * rowHeight
        local total = gridTop + gridHeight + bottom
        if shownHeight == total then
            return
        end
        local duration = (instant or shownHeight == nil) and 0 or 0.25
        shownHeight = total
        tween(grid, { Size = UDim2.new(1, -inset * 2, 0, gridHeight) }, duration, Enum.EasingStyle.Quint)
        tween(frame, { Size = UDim2.new(1, 0, 0, total) }, duration, Enum.EasingStyle.Quint)
    end

    local function render()
        local list = sortedRows()
        for position, item in ipairs(list) do
            local entry = pool[position]
            if not entry then
                entry = newRow()
                pool[position] = entry
            end
            local row = item.Row
            entry.Data = row
            entry.Index = item.Index
            entry.Frame.LayoutOrder = position
            entry.Frame.Visible = true
            local highlighted = row.Highlight == true
            if not highlighted and type(opts.Highlight) == "function" then
                local ok, result = pcall(opts.Highlight, row, item.Index)
                highlighted = ok and result == true
            end
            entry.Highlighted = highlighted
            entry.Rest = highlighted and 0.86 or (position % 2 == 0 and 0.78 or 1)
            if not entry.Hover then
                entry.Frame.BackgroundColor3 = highlighted and Theme.Accent or Theme.Surface3
                entry.Frame.BackgroundTransparency = entry.Rest
                bindColors(entry.Frame, { BackgroundColor3 = entry.Frame.BackgroundColor3 })
            end
            entry.Marker.BackgroundTransparency = highlighted and 0 or 1
            for order, column in ipairs(columns) do
                local cell = entry.Cells[order]
                if column.Rank then
                    local medal = MEDALS[item.Rank]
                    cell.Label.Text = tostring(item.Rank)
                    cell.Label.TextColor3 = medal and Color3.fromRGB(28, 22, 18) or Theme.Muted
                    bindColors(cell.Label, { TextColor3 = cell.Label.TextColor3 })
                    cell.Badge.BackgroundColor3 = medal or Theme.Surface3
                    cell.Badge.BackgroundTransparency = medal and 0.05 or 1
                else
                    local value = columnValue(row, column)
                    cell.Label.Text = Library._rich(display(value, column, row))
                    -- Column Color: a colour, a theme key or a function(value, row)
                    -- returning either. A row's Colors[key or index] beats it.
                    local wanted = column.Color
                    if type(wanted) == "function" then
                        local ok, result = pcall(wanted, value, row)
                        wanted = ok and result or nil
                    end
                    if type(row.Colors) == "table" then
                        local own = row.Colors[column.Key or column.Index]
                        if own == nil then
                            own = row.Colors[column.Index]
                        end
                        if own ~= nil then
                            wanted = own
                        end
                    end
                    local color = Library._color(wanted) or (highlighted and Theme.Accent or Theme.Text)
                    cell.Label.TextColor3 = color
                    bindColors(cell.Label, { TextColor3 = color })
                end
            end
        end
        for position = #list + 1, #pool do
            pool[position].Frame.Visible = false
            pool[position].Data = nil
        end
        shownCount = #list
        empty.Visible = #list == 0
        empty.Text = (#list == 0 and query ~= "" and #handle.Rows > 0) and (opts.NoMatchText or "No rows match")
            or (opts.EmptyText or "Nothing here yet")
        if searchCount then
            searchCount.Visible = query ~= ""
            searchCount.Text = #list .. " / " .. #handle.Rows
        end
        fitHeight()
    end

    local function buildHeader()
        for _, cell in ipairs(headerCells) do
            cell.Frame:Destroy()
        end
        table.clear(headerCells)
        for _, entry in ipairs(pool) do
            entry.Frame:Destroy()
        end
        table.clear(pool)
        local row = header:FindFirstChild("Cells") or create("Frame", {
            Name = "Cells",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Parent = header,
        })
        if not row:FindFirstChildOfClass("UIListLayout") then
            padding(row, 10, 10)
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Parent = row,
            })
        end
        for order, column in ipairs(columns) do
            local cell = create("TextButton", {
                Size = UDim2.new(column.UDim.Scale, column.UDim.Offset, 1, 0),
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = "",
                LayoutOrder = order,
                Parent = row,
            })
            local align = column.Rank and Enum.TextXAlignment.Center or alignment(column)
            local right = align == Enum.TextXAlignment.Right
            local text = label({
                Size = UDim2.new(1, align == Enum.TextXAlignment.Center and 0 or -16, 1, 0),
                Position = UDim2.fromOffset(right and 16 or 0, 0),
                Text = string.upper(column.Name),
                TextSize = 11,
                FontFace = Fonts.Bold,
                TextColor3 = Theme.Muted,
                TextXAlignment = align,
                Parent = cell,
            })
            local arrow = create("ImageLabel", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.fromOffset(12, 12),
                BackgroundTransparency = 1,
                ImageColor3 = Theme.Accent,
                ScaleType = Enum.ScaleType.Fit,
                Visible = false,
                Parent = cell,
            })
            applyIcon(arrow, "chevron-down")
            -- The arrow sits just after the header text (before it when the
            -- column is right aligned).
            local function placeArrow()
                local width = text.TextBounds.X
                if right then
                    arrow.Position = UDim2.new(1, -(width + 15), 0.5, 0)
                elseif align == Enum.TextXAlignment.Center then
                    arrow.Position = UDim2.new(0.5, width / 2 + 3, 0.5, 0)
                else
                    local cellWidth = cell.AbsoluteSize.X / math.max(window.Scale.Scale, 0.01)
                    arrow.Position = UDim2.new(0, math.clamp(width + 4, 0, math.max(cellWidth - 12, 0)), 0.5, 0)
                end
            end
            text:GetPropertyChangedSignal("TextBounds"):Connect(placeArrow)
            cell:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeArrow)
            task.defer(placeArrow)
            local sortable = column.Sortable and not column.Rank
            if sortable then
                cell.MouseEnter:Connect(function()
                    if sortKey ~= column then
                        tween(text, { TextColor3 = Theme.Text }, 0.12)
                    end
                end)
                cell.MouseLeave:Connect(function()
                    if sortKey ~= column then
                        tween(text, { TextColor3 = Theme.Muted }, 0.2)
                    end
                end)
                cell.MouseButton1Click:Connect(function()
                    -- Numbers sort high to low first, text A to Z; the second
                    -- click flips it and the third goes back to the given order.
                    if sortKey ~= column then
                        local numeric = false
                        for _, data in ipairs(handle.Rows) do
                            local value = columnValue(data, column)
                            if value ~= nil then
                                numeric = tonumber(value) ~= nil
                                break
                            end
                        end
                        sortKey, sortDescending = column, numeric
                        column.FirstDescending = numeric
                    elseif sortDescending == column.FirstDescending then
                        sortDescending = not sortDescending
                    else
                        sortKey = nil
                    end
                    paintHeader()
                    render()
                end)
            end
            table.insert(headerCells, { Frame = cell, Label = text, Arrow = arrow, Column = column })
        end
        paintHeader()
    end

    function handle:SetColumns(list)
        table.clear(columns)
        if opts.Rank then
            table.insert(columns, { Name = "#", Rank = true, Width = TOUCH and 40 or 36, Sortable = false })
        end
        for index, column in ipairs(type(list) == "table" and list or {}) do
            if type(column) ~= "table" then
                column = { Name = tostring(column) }
            end
            local name = column.Name or column.Title or ("Column " .. index)
            table.insert(columns, {
                Name = name,
                Key = column.Key or name,
                Index = index,
                Width = column.Width,
                Align = column.Align,
                Format = column.Format,
                Color = column.Color,
                Sortable = column.Sortable ~= false and opts.Sortable ~= false,
            })
        end
        sortKey = nil
        layoutColumns()
        buildHeader()
        render()
    end

    local function findColumn(key)
        if type(key) == "number" then
            return columns[key + (opts.Rank and 1 or 0)]
        end
        for _, column in ipairs(columns) do
            if not column.Rank and (column.Key == key or column.Name == key) then
                return column
            end
        end
        return nil
    end

    function handle:SetRows(rows)
        handle.Rows = {}
        for index, row in ipairs(type(rows) == "table" and rows or {}) do
            handle.Rows[index] = type(row) == "table" and row or { row }
        end
        render()
    end
    handle.Set = handle.SetRows

    function handle:GetRows()
        return handle.Rows
    end
    handle.Get = handle.GetRows

    function handle:AddRow(row, position)
        row = type(row) == "table" and row or { row }
        if tonumber(position) then
            table.insert(handle.Rows, math.clamp(math.floor(position), 1, #handle.Rows + 1), row)
        else
            table.insert(handle.Rows, row)
        end
        render()
        return #handle.Rows
    end

    -- Replaces a row (by its index in the list you gave) and flashes it.
    function handle:UpdateRow(index, row)
        if not handle.Rows[index] then
            return false
        end
        handle.Rows[index] = type(row) == "table" and row or { row }
        render()
        for _, entry in ipairs(pool) do
            if entry.Index == index and entry.Frame.Visible then
                local restColor = entry.Highlighted and Theme.Accent or Theme.Surface3
                tween(entry.Frame, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.7 }, 0.08)
                task.delay(0.1, function()
                    if not entry.Hover then
                        tween(entry.Frame, { BackgroundColor3 = restColor, BackgroundTransparency = entry.Rest }, 0.5)
                    end
                end)
                break
            end
        end
        return true
    end

    function handle:RemoveRow(index)
        if not handle.Rows[index] then
            return false
        end
        table.remove(handle.Rows, index)
        render()
        return true
    end

    function handle:Clear()
        handle:SetRows({})
    end

    -- Sort(nil) goes back to the given order.
    function handle:Sort(key, descending)
        sortKey = key ~= nil and findColumn(key) or nil
        sortDescending = descending == true
        if sortKey then
            sortKey.FirstDescending = sortDescending
        end
        paintHeader()
        render()
    end

    function handle:SetTitle(text)
        if title then
            title.Text = tostring(text)
        end
    end

    function handle:SetMaxRows(count)
        maxRows = math.max(math.floor(tonumber(count) or maxRows), 1)
        fitHeight()
    end

    handle:SetColumns(opts.Columns or {})
    handle:SetRows(opts.Rows or {})
    if opts.SortBy ~= nil then
        handle:Sort(opts.SortBy, opts.SortDescending ~= false)
    end
    fitHeight(true)
    if searchBox then
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            local text = string.lower(trim(searchBox.Text))
            if text ~= query then
                query = text
                body.CanvasPosition = Vector2.zero
                render()
            end
        end)
    end
    function handle:SetSearch(text)
        if searchBox then
            searchBox.Text = tostring(text or "")
        end
    end
    -- Theme tags in cells are baked to colours; repaint them on theme change.
    onTheme(grid, render)
    return finishElement(self, opts, handle, frame, "Table")
end

Tab.CreateImage = Tab.Image
Tab.AddImage = Tab.Image
Tab.CreateViewport = Tab.Viewport
Tab.AddViewport = Tab.Viewport
Tab.CreateTable = Tab.Table
Tab.AddTable = Tab.Table
Tab.CreateLeaderboard = Tab.Table

local function settleSubOut(ui)
    if ui.OutFrame then
        ui.OutFrame.Parent = ui.Area
        ui.OutFrame.Visible = false
        ui.OutFrame = nil
    end
    ui.Out.Visible = false
end

local function settleSubIn(ui)
    if ui.InFrame then
        ui.InFrame.Parent = ui.Area
        ui.InFrame.Position = UDim2.fromOffset(0, 0)
        ui.InFrame = nil
    end
    ui.In.Visible = false
end

function Tab:_setupSubTabs()
    local top = self._headerBottom
    local page = self._page
    local strip = create("ScrollingFrame", {
        Name = "SubTabs",
        Position = UDim2.fromOffset(24, top - 4),
        Size = UDim2.new(1, -48, 0, 32),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(),
        Parent = page,
    })
    strip:SetAttribute("NoDrag", true)
    local highlight = create("Frame", {
        Size = UDim2.fromOffset(0, 32),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Visible = false,
        Parent = strip,
    })
    corner(highlight, UDim.new(0, 8))
    stroke(highlight, Theme.Stroke)
    local row = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        ZIndex = 2,
        Parent = strip,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        Parent = row,
    })
    self.Window:_overflowHint(page, strip, row, false, Theme.Background)
    local areaTop = top + 36
    local area = create("Frame", {
        Name = "SubPages",
        Position = UDim2.fromOffset(0, areaTop),
        Size = UDim2.new(1, 0, 1, -areaTop),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = page,
    })
    local ui = {
        Strip = strip,
        Row = row,
        Highlight = highlight,
        Area = area,
        Out = create("CanvasGroup", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 2,
            Parent = area,
        }),
        In = create("CanvasGroup", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 3,
            Parent = area,
        }),
        Generation = 0,
    }
    self._sub = ui
    self._subTabs = {}
    self.List.Visible = false
    self:_refreshEmpty()
    -- Keep the pill under the selected tab when widths change after layout.
    row:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if self.CurrentSubTab and not ui.Moving then
            self:_placeSubHighlight(self.CurrentSubTab, true)
        end
    end)
end

function Tab:_placeSubHighlight(sub, instant)
    local ui = self._sub
    local scale = self.Window.Scale.Scale
    local button = sub._button
    local width = button.AbsoluteSize.X / scale
    if width <= 0 then
        return
    end
    local x = (button.AbsolutePosition.X - ui.Row.AbsolutePosition.X) / scale
    local props = { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(width, 32) }
    if instant or not ui.Highlight.Visible then
        ui.Highlight.Visible = true
        ui.Highlight.Position = props.Position
        ui.Highlight.Size = props.Size
    else
        ui.Moving = true
        tween(ui.Highlight, props, 0.35, Enum.EasingStyle.Quint)
        task.delay(0.36, function()
            ui.Moving = false
        end)
    end
    local view = ui.Strip.AbsoluteSize.X / scale
    local canvasX = ui.Strip.CanvasPosition.X
    if x < canvasX then
        tween(ui.Strip, { CanvasPosition = Vector2.new(math.max(x - 8, 0), 0) }, 0.3, Enum.EasingStyle.Quint)
    elseif x + width > canvasX + view then
        tween(ui.Strip, { CanvasPosition = Vector2.new(x + width - view + 8, 0) }, 0.3, Enum.EasingStyle.Quint)
    end
end

function Tab:SubTab(opts, icon)
    if self._groupbox or self._isSubTab then
        return self.Parent:SubTab(opts, icon)
    end
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    if icon ~= nil and opts.Icon == nil then
        opts.Icon = cleanIcon(icon)
    end
    if not self._subTabs then
        self:_setupSubTabs()
    end
    local ui = self._sub
    local index = #self._subTabs + 1
    local sub = setmetatable({
        Name = opts.Name or ("Page " .. index),
        Window = self.Window,
        Parent = self,
        _order = 0,
        _isSubTab = true,
        _index = index,
        _iconName = opts.Icon,
    }, Tab)
    local frame = create("Frame", {
        Name = sub.Name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = ui.Area,
    })
    sub._frame = frame
    local emptyIcon = opts.Icon
    if emptyIcon == nil then
        emptyIcon = self._iconName
    end
    if emptyIcon == nil then
        emptyIcon = "layout-grid"
    end
    buildContainer(sub, frame, 0, emptyIcon, opts.EmptyText or "Nothing here yet")

    local button = create("TextButton", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = index,
        Parent = ui.Row,
    })
    padding(button, 14, 14)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = button,
    })
    if opts.Icon then
        local image = create("ImageLabel", {
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = button,
        })
        applyIcon(image, opts.Icon)
        if image:GetAttribute("CustomIcon") then
            image.ImageTransparency = 0.4
        end
        sub._iconImage = image
    end
    sub._label = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = sub.Name,
        TextSize = 13,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = button,
    })
    sub._button = button
    button.MouseEnter:Connect(function()
        if self.CurrentSubTab ~= sub then
            tween(sub._label, { TextColor3 = Theme.Text }, 0.12)
        end
    end)
    button.MouseLeave:Connect(function()
        if self.CurrentSubTab ~= sub then
            tween(sub._label, { TextColor3 = Theme.Muted }, 0.2)
        end
    end)
    button.MouseButton1Click:Connect(function()
        self:SelectSubTab(sub)
    end)

    table.insert(self._subTabs, sub)
    if index == 1 then
        self:SelectSubTab(sub, true)
    end
    return sub
end

Tab.CreateSubTab = Tab.SubTab
Tab.AddSubTab = Tab.SubTab

function Tab:SelectSubTab(sub, instant)
    if type(sub) ~= "table" then
        for index, entry in ipairs(self._subTabs or {}) do
            if entry.Name == sub or index == sub then
                sub = entry
                break
            end
        end
    end
    if type(sub) ~= "table" or not self._sub then
        return
    end
    local previous = self.CurrentSubTab
    if previous == sub then
        return
    end
    self.Window:_resetSearch()
    self.Window:_closePopups()
    self.CurrentSubTab = sub
    local ui = self._sub
    settleSubOut(ui)
    settleSubIn(ui)
    ui.Generation += 1
    local generation = ui.Generation

    local fade = instant and 0 or 0.2
    if previous then
        tween(previous._label, { TextColor3 = Theme.Muted }, fade)
        if previous._iconImage then
            tintIcon(previous._iconImage, Theme.Muted, false, fade)
        end
    end
    tween(sub._label, { TextColor3 = Theme.Text }, fade)
    if sub._iconImage then
        tintIcon(sub._iconImage, Theme.Accent, true, fade)
    end
    self:_placeSubHighlight(sub, instant)

    if instant or not previous then
        if previous then
            previous._frame.Visible = false
        end
        sub._frame.Visible = true
        return
    end

    local direction = sub._index > previous._index and 1 or -1
    ui.OutFrame = previous._frame
    previous._frame.Parent = ui.Out
    ui.Out.GroupTransparency = 0
    ui.Out.Position = UDim2.fromOffset(0, 0)
    ui.Out.Visible = true
    tween(ui.Out, { GroupTransparency = 1, Position = UDim2.fromOffset(-direction * 28, 0) }, 0.2)

    ui.InFrame = sub._frame
    sub._frame.Visible = true
    sub._frame.Parent = ui.In
    ui.In.GroupTransparency = 1
    ui.In.Position = UDim2.fromOffset(direction * 28, 0)
    ui.In.Visible = true
    tween(ui.In, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) }, 0.34, Enum.EasingStyle.Quint)

    task.delay(0.2, function()
        if ui.Generation == generation then
            settleSubOut(ui)
        end
    end)
    task.delay(0.34, function()
        if ui.Generation == generation then
            settleSubIn(ui)
        end
    end)
end

-- Search: one box over the whole window. Typing lists matching tabs, pages,
-- groupboxes and controls from every tab; picking one opens its tab and page,
-- scrolls it into view and flashes it.

Window._searchIcons = {
    Tab = "app-window",
    Page = "panels-top-left",
    Groupbox = "layout-grid",
    Button = "mouse-pointer-click",
    ButtonRow = "mouse-pointer-click",
    Toggle = "toggle-right",
    Slider = "sliders-horizontal",
    Dropdown = "list",
    Input = "text-cursor-input",
    Keybind = "keyboard",
    ColorPicker = "palette",
    Stepper = "chevrons-up-down",
    Progress = "activity",
    Status = "activity",
    StatusList = "activity",
    Label = "type",
    Paragraph = "type",
    OrderList = "list-ordered",
}

function Window:_searchResults(query)
    local results = {}
    local function consider(name, entry)
        if type(name) ~= "string" or name == "" then
            return
        end
        local at = string.find(string.lower(name), query, 1, true)
        if not at then
            return
        end
        entry.Name = name
        entry.At = at
        -- Name starts first, then word starts, then anywhere inside a word.
        entry.Rank = at == 1 and 0 or (string.find(string.sub(name, at - 1, at - 1), "[%s%p]") and 1 or 2)
        entry.Order = #results + 1
        table.insert(results, entry)
    end
    local function shown(element)
        return not element._destroyed
            and element._type ~= "Section" and element._type ~= "Divider"
            and (element._isShown == nil or element:_isShown())
    end
    for _, tab in ipairs(self.Tabs) do
        consider(tab.Name, { Kind = "Tab", Tab = tab, Icon = tab._iconName })
        for _, page in ipairs(tab._subTabs or { tab }) do
            local sub = page._isSubTab and page or nil
            local path = tab.Name
            if sub then
                consider(sub.Name, { Kind = "Page", Tab = tab, Sub = sub, Path = tab.Name })
                path = tab.Name .. "  ›  " .. sub.Name
            end
            if not page._noSearch then
                for _, element in ipairs(page._items or {}) do
                    if shown(element) then
                        consider(element._searchName, { Kind = element._type, Tab = tab, Sub = sub, Target = element, Path = path })
                    end
                end
                for _, group in ipairs(page._groupboxes or {}) do
                    if group._userVisible ~= false then
                        consider(group.Name, { Kind = "Groupbox", Tab = tab, Sub = sub, Target = group, Path = path })
                        local groupPath = path .. "  ›  " .. group.Name
                        for _, element in ipairs(group._items) do
                            if shown(element) then
                                consider(element._searchName, { Kind = element._type, Tab = tab, Sub = sub, Target = element, Group = group, Path = groupPath })
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(results, function(a, b)
        if a.Rank ~= b.Rank then
            return a.Rank < b.Rank
        end
        return a.Order < b.Order
    end)
    return results
end

-- Marks a found control: it pops, a soft accent glow blooms around it, a
-- sheen of light sweeps across it and a bright spot runs round its border,
-- then everything breathes once more and fades.
function Window:_flash(frame, radius)
    for _, name in ipairs({ "SearchFlash", "SearchGlow" }) do
        local old = frame:FindFirstChild(name)
        if old then
            old:Destroy()
        end
    end
    radius = radius or 8
    local accent = Theme.Accent
    local bright = accent:Lerp(Color3.new(1, 1, 1), 0.65)

    -- Outer glow: a wide, faint stroke around a second outline.
    local halo = create("Frame", {
        Name = "SearchGlow",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 10,
        Parent = frame,
    })
    corner(halo, UDim.new(0, radius))
    local haloStroke = create("UIStroke", {
        Color = accent,
        Thickness = 1,
        Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = halo,
    })

    -- Wash with a moving sheen: a brighter diagonal band crosses it once.
    local wash = create("Frame", {
        Name = "SearchFlash",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = accent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 10,
        Parent = frame,
    })
    corner(wash, UDim.new(0, radius))
    local sheen = create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.7),
            NumberSequenceKeypoint.new(0.4, 0.55),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(0.6, 0.55),
            NumberSequenceKeypoint.new(1, 0.7),
        }),
        Rotation = 18,
        Offset = Vector2.new(-1, 0),
        Parent = wash,
    })

    -- Border light: the ring's gradient turns, so a bright spot runs round it.
    local ring = create("UIStroke", {
        Color = Color3.new(1, 1, 1),
        Thickness = 1.6,
        Transparency = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = wash,
    })
    local runner = create("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, accent),
            ColorSequenceKeypoint.new(0.5, bright),
            ColorSequenceKeypoint.new(1, accent),
        }),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.45),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 0.45),
        }),
        Parent = ring,
    })

    -- Groupboxes clip their rows, so anything drawn outside a control is cut
    -- off at its corners. The strokes go on the inside of the control where
    -- the engine supports it; otherwise everything is inset by its width.
    local inside = pcall(function()
        haloStroke.BorderStrokePosition = Enum.BorderStrokePosition.Inner
        ring.BorderStrokePosition = Enum.BorderStrokePosition.Inner
    end)
    local glowWidth = inside and 6 or 3
    if not inside then
        halo.Position = UDim2.fromOffset(glowWidth + 1, glowWidth + 1)
        halo.Size = UDim2.new(1, -(glowWidth + 1) * 2, 1, -(glowWidth + 1) * 2)
        wash.Position = UDim2.fromOffset(2, 2)
        wash.Size = UDim2.new(1, -4, 1, -4)
    end

    -- A small pop, unless something else is scaling the control already. It
    -- never grows past full size, which would be clipped as well.
    local pop
    if not frame:FindFirstChildOfClass("UIScale") then
        pop = create("UIScale", { Scale = 0.975, Parent = frame })
        tween(pop, { Scale = 1 }, 0.4, Enum.EasingStyle.Quint)
    end

    tween(wash, { BackgroundTransparency = 0.8 }, 0.2, Enum.EasingStyle.Quad)
    tween(ring, { Transparency = 0 }, 0.2, Enum.EasingStyle.Quad)
    tween(haloStroke, { Thickness = glowWidth, Transparency = 0.72 }, 0.35, Enum.EasingStyle.Quint)
    tween(sheen, { Offset = Vector2.new(1, 0) }, 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    tween(runner, { Rotation = 540 }, 2.2, Enum.EasingStyle.Quad)
    task.spawn(function()
        task.wait(0.75)
        -- One softer breath, then fade out.
        tween(wash, { BackgroundTransparency = 0.9 }, 0.35, Enum.EasingStyle.Sine)
        tween(haloStroke, { Thickness = glowWidth / 2, Transparency = 0.85 }, 0.35, Enum.EasingStyle.Sine)
        task.wait(0.35)
        tween(wash, { BackgroundTransparency = 0.84 }, 0.3, Enum.EasingStyle.Sine)
        tween(haloStroke, { Thickness = glowWidth * 0.85, Transparency = 0.76 }, 0.3, Enum.EasingStyle.Sine)
        task.wait(0.4)
        tween(wash, { BackgroundTransparency = 1 }, 0.55, Enum.EasingStyle.Quad)
        tween(ring, { Transparency = 1 }, 0.65, Enum.EasingStyle.Quad)
        tween(haloStroke, { Thickness = glowWidth, Transparency = 1 }, 0.65, Enum.EasingStyle.Quad)
        task.wait(0.7)
        wash:Destroy()
        halo:Destroy()
        if pop then
            pop:Destroy()
        end
    end)
end

function Window:_revealResult(result)
    local tab, sub, target, group = result.Tab, result.Sub, result.Target, result.Group
    if self.CurrentTab ~= tab then
        self:SelectTab(tab)
    end
    if sub then
        tab:SelectSubTab(sub)
    end
    if not target then
        local button = sub and sub._button or tab._button
        task.delay(0.1, function()
            if button.Parent then
                self:_flash(button, sub and 8 or 10)
            end
        end)
        return
    end
    local expanding = group ~= nil and group:IsCollapsed()
    if expanding then
        group:Expand()
    end
    local list = (sub or tab).List
    task.spawn(function()
        -- Let the freshly shown page lay out before measuring it.
        task.wait()
        task.wait()
        if expanding then
            task.wait(0.3)
        end
        local frame = target._frame
        if self._destroyed or target._destroyed or not frame or not frame.Parent or not list then
            return
        end
        local scale = self.Scale.Scale
        local top = (frame.AbsolutePosition.Y - list.AbsolutePosition.Y) / scale + list.CanvasPosition.Y
        local height = frame.AbsoluteSize.Y / scale
        local view = list.AbsoluteWindowSize.Y / scale
        local limit = math.max(list.AbsoluteCanvasSize.Y / scale - view, 0)
        local y = math.clamp(top + height / 2 - view / 2, 0, limit)
        if math.abs(y - list.CanvasPosition.Y) > 2 then
            tween(list, { CanvasPosition = Vector2.new(0, y) }, 0.45, Enum.EasingStyle.Quint)
            task.wait(0.25)
        end
        if frame.Parent then
            self:_flash(frame, target._groupbox and 10 or 8)
        end
    end)
end

function Window:_resetSearch()
    if self.SearchBox and self.SearchBox.Text ~= "" then
        self.SearchBox.Text = ""
    end
end

-- Page titles stop short of the search box and close button.
function Window:_fitTitle(tab)
    local right = self.SearchBox and (self._searchWidth or SEARCH_WIDTH) + 72 or 56
    local reserve = tab._titleX + right
    tab._title.Size = UDim2.new(1, -reserve, 0, 24)
    if tab._desc then
        tab._desc.Size = UDim2.new(1, -reserve, 0, 16)
    end
end

function Window:_buildSearch(content)
    -- No box: the icon and text sit on a thin baseline. Focus draws an
    -- accent line out from the middle of it.
    local holder = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -56, 0, 14),
        Size = UDim2.fromOffset(SEARCH_WIDTH, 34),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 5,
        Parent = content,
    })
    holder:SetAttribute("NoDrag", true)
    local baseline = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, -2),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = holder,
    })
    local focusLine = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -1),
        Size = UDim2.new(0, 0, 0, 2),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = holder,
    })
    corner(focusLine, UDim.new(1, 0))
    -- Kept for the focus handlers below, which recolour it.
    local _, icon = glowIcon(holder, "search", Theme.Muted, UDim2.new(0, 2, 0.5, -1))
    icon.Parent.Size = UDim2.fromOffset(15, 15)
    local box = create("TextBox", {
        Position = UDim2.fromOffset(26, 0),
        Size = UDim2.new(1, -28, 1, -2),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Search",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = holder,
    })
    holder.MouseEnter:Connect(function()
        if not box:IsFocused() then
            tween(baseline, { BackgroundColor3 = Theme.StrokeHover }, 0.15)
        end
    end)
    holder.MouseLeave:Connect(function()
        tween(baseline, { BackgroundColor3 = Theme.Stroke }, 0.25)
    end)
    self.SearchBox = box

    -- Results float over the window under the box, like a dropdown popup.
    local rowHeight = TOUCH and 40 or 34
    local maxRows = 8
    local popup = create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        Size = UDim2.fromOffset(300, 0),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 45,
        Parent = self.Body,
    })
    popup:SetAttribute("NoDrag", true)
    local popupShadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-18, -12),
        Size = UDim2.new(1, 36, 1, 36),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        Parent = popup,
    })
    local panel = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Parent = popup,
    })
    corner(panel, UDim.new(0, 10))
    local panelStroke = stroke(panel, Theme.Stroke, 1)
    edgeHighlight(panel)
    local list = create("ScrollingFrame", {
        Position = UDim2.fromOffset(6, 6),
        Size = UDim2.new(1, -12, 1, -12),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(),
        Parent = panel,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = list,
    })
    local noResults = label({
        Size = UDim2.new(1, 0, 0, rowHeight),
        Text = "No results",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 0,
        Visible = false,
        Parent = list,
    })

    local rows = {}
    local results = {}
    local selected = 1
    local open = false
    local generation = 0
    local shownSize = Vector2.new(300, 0)
    local stopFollowing = nil
    local closeResults

    local function place()
        local scale = self.Scale.Scale
        local bodyPosition = self.Body.AbsolutePosition
        local bodyWidth = self.Body.AbsoluteSize.X / scale
        local right = (holder.AbsolutePosition.X + holder.AbsoluteSize.X - bodyPosition.X) / scale
        local top = (holder.AbsolutePosition.Y + holder.AbsoluteSize.Y - bodyPosition.Y) / scale + 6
        right = math.clamp(right, shownSize.X + 8, math.max(bodyWidth - 8, shownSize.X + 8))
        popup.Position = UDim2.fromOffset(right, top)
    end

    local function measure()
        local scale = self.Scale.Scale
        local bodySize = self.Body.AbsoluteSize / scale
        local below = (holder.AbsolutePosition.Y + holder.AbsoluteSize.Y - self.Body.AbsolutePosition.Y) / scale + 6
        local count = math.max(#rows, 1)
        local height = math.min(count, maxRows) * (rowHeight + 2) - 2 + 12
        height = math.max(math.min(height, bodySize.Y - below - 12), rowHeight + 12)
        local width = math.min(math.max(holder.AbsoluteSize.X / scale, 300), math.max(bodySize.X - 16, 160))
        shownSize = Vector2.new(width, height)
    end

    local function paintSelection()
        for index, row in ipairs(rows) do
            local on = index == selected
            tween(row.Button, { BackgroundTransparency = on and 0.35 or 1 }, 0.12)
            tintIcon(row.Icon, on and Theme.Accent or Theme.Muted, on, 0.12)
        end
    end

    local function keepSelectionInView()
        local rowTop = (selected - 1) * (rowHeight + 2)
        local view = list.AbsoluteWindowSize.Y / self.Scale.Scale
        local y = list.CanvasPosition.Y
        if rowTop < y then
            y = rowTop
        elseif rowTop + rowHeight > y + view then
            y = rowTop + rowHeight - view
        else
            return
        end
        list.CanvasPosition = Vector2.new(0, math.max(y, 0))
    end

    local function setOpen(value)
        if value == open then
            return
        end
        open = value
        generation += 1
        local current = generation
        if value then
            if self._closePopup and self._closePopup ~= closeResults then
                self._closePopup()
            end
            self._closePopup = closeResults
            place()
            popup.Size = UDim2.fromOffset(shownSize.X, 0)
            popup.Visible = true
            tween(popup, { Size = UDim2.fromOffset(shownSize.X, shownSize.Y) }, 0.26, Enum.EasingStyle.Quint)
            tween(panelStroke, { Transparency = 0 }, 0.12)
            tween(popupShadow, { ImageTransparency = 0.55 }, 0.26)
            if not stopFollowing then
                stopFollowing = self:_listen("Render", place)
            end
        else
            if self._closePopup == closeResults then
                self._closePopup = nil
            end
            tween(popup, { Size = UDim2.fromOffset(shownSize.X, 0) }, 0.18, Enum.EasingStyle.Quint)
            tween(popupShadow, { ImageTransparency = 1 }, 0.14)
            task.delay(0.19, function()
                if generation == current and not open then
                    popup.Visible = false
                    panelStroke.Transparency = 1
                    if stopFollowing then
                        stopFollowing()
                        stopFollowing = nil
                    end
                end
            end)
        end
    end
    closeResults = function()
        setOpen(false)
    end

    local function choose(result)
        if not result then
            return
        end
        setOpen(false)
        box.Text = ""
        if box:IsFocused() then
            box:ReleaseFocus()
        end
        self:_revealResult(result)
    end

    local function escape(text)
        return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
    end

    local function render(query)
        for _, row in ipairs(rows) do
            row.Button:Destroy()
        end
        table.clear(rows)
        results = self:_searchResults(query)
        selected = 1
        local accent = colorToHex(Theme.Accent)
        for index, result in ipairs(results) do
            if index > 50 then
                break
            end
            local button = create("TextButton", {
                Size = UDim2.new(1, 0, 0, rowHeight),
                BackgroundColor3 = Theme.Surface3,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = list,
            })
            corner(button, UDim.new(0, 7))
            -- One line of breadcrumbs: tab, sub tab and groupbox in muted
            -- text, each split by a chevron, ending on the match in accent.
            local crumbs = create("Frame", {
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -20, 1, 0),
                BackgroundTransparency = 1,
                ClipsDescendants = true,
                Parent = button,
            })
            create("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 5),
                Parent = crumbs,
            })
            local part = 0
            local firstIcon = nil
            local function crumbIcon(icon)
                if not icon then
                    return
                end
                part += 1
                local image = create("ImageLabel", {
                    Size = UDim2.fromOffset(14, 14),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Muted,
                    ScaleType = Enum.ScaleType.Fit,
                    LayoutOrder = part,
                    Parent = crumbs,
                })
                applyIcon(image, icon)
                firstIcon = firstIcon or image
            end
            local function crumbText(text, color, rich)
                part += 1
                return label({
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = text,
                    RichText = rich == true,
                    TextSize = 13,
                    FontFace = color and Fonts.Medium or Fonts.Regular,
                    TextColor3 = color or Theme.Muted,
                    TextTruncate = Enum.TextTruncate.None,
                    LayoutOrder = part,
                    Parent = crumbs,
                })
            end
            local function chevron()
                crumbText(">")
            end
            local tab, sub, group = result.Tab, result.Sub, result.Group
            local onTab = result.Kind == "Tab"
            local onSub = result.Kind == "Page"
            local onGroup = result.Kind == "Groupbox"
            local tabIcon = tab._iconName
            if tabIcon == nil then
                tabIcon = "layout-grid"
            end
            crumbIcon(tabIcon)
            if not onTab then
                crumbText(tab.Name)
                if sub then
                    chevron()
                    local subIcon = sub._iconName
                    if subIcon == nil then
                        subIcon = "layers"
                    end
                    crumbIcon(subIcon)
                    if not onSub then
                        crumbText(sub.Name)
                    end
                end
                if group and not onGroup then
                    chevron()
                    crumbText(group.Name)
                end
                if not onSub then
                    chevron()
                end
            end
            -- The match itself: accent, with the typed part in bold.
            local name = result.Name
            local stop = result.At + #query
            local marked = escape(string.sub(name, 1, result.At - 1))
                .. "<b>" .. escape(string.sub(name, result.At, stop - 1)) .. "</b>"
                .. escape(string.sub(name, stop))
            crumbText(marked, Theme.Accent, true)
            local image = firstIcon
            local isTap = tapGuard(button, function()
                return list
            end)
            button.MouseEnter:Connect(function()
                if not usingTouch() then
                    selected = index
                    paintSelection()
                end
            end)
            button.MouseButton1Click:Connect(function()
                if isTap() then
                    choose(result)
                end
            end)
            table.insert(rows, { Button = button, Icon = image })
        end
        noResults.Visible = #rows == 0
        list.CanvasSize = UDim2.fromOffset(0, math.max(#rows, 1) * (rowHeight + 2) - 2)
        list.CanvasPosition = Vector2.zero
        paintSelection()
        measure()
        if open then
            place()
            tween(popup, { Size = UDim2.fromOffset(shownSize.X, shownSize.Y) }, 0.2, Enum.EasingStyle.Quint)
        end
    end

    local function update()
        local query = string.match(string.lower(box.Text), "^%s*(.-)%s*$")
        if query == "" then
            setOpen(false)
            return
        end
        render(query)
        setOpen(true)
    end

    box.Focused:Connect(function()
        tween(focusLine, { Size = UDim2.new(1, 0, 0, 2) }, 0.35, Enum.EasingStyle.Quint)
        tween(icon, { ImageColor3 = Theme.Accent }, 0.15)
        if box.Text ~= "" then
            update()
        end
    end)
    box.FocusLost:Connect(function(enterPressed)
        tween(focusLine, { Size = UDim2.new(0, 0, 0, 2) }, 0.3, Enum.EasingStyle.Quint)
        tween(icon, { ImageColor3 = Theme.Muted }, 0.2)
        if enterPressed and open then
            choose(results[selected])
        end
    end)
    box:GetPropertyChangedSignal("Text"):Connect(update)
    self:_listen("Began", function(input)
        if not open then
            return
        end
        if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
            if #rows > 0 then
                local step = input.KeyCode == Enum.KeyCode.Up and -1 or 1
                selected = math.clamp(selected + step, 1, #rows)
                paintSelection()
                keepSelectionInView()
            end
        elseif input.KeyCode == Enum.KeyCode.Escape then
            setOpen(false)
        elseif isPress(input) then
            local point = pointerPosition()
            if not pointInside(point, popup) and not pointInside(point, holder) then
                setOpen(false)
            end
        end
    end)

    local function fit()
        local width = content.AbsoluteSize.X / self.Scale.Scale
        local searchWidth = math.clamp(math.floor(width * 0.32), 110, SEARCH_WIDTH)
        holder.Size = UDim2.fromOffset(searchWidth, 34)
        if searchWidth ~= self._searchWidth then
            self._searchWidth = searchWidth
            for _, tab in ipairs(self.Tabs) do
                self:_fitTitle(tab)
            end
        end
    end
    content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
    task.defer(fit)
end

-- Identity: the player's name and headshot shown in the sidebar and on the
-- home tab. The privacy switches hide them everywhere at once.

function Window:_trackName(textLabel, kind)
    table.insert(self._identity.Names, { Label = textLabel, Kind = kind })
    self:_renderIdentity()
end

function Window:_trackAvatar(image, placeholder)
    table.insert(self._identity.Avatars, { Image = image, Placeholder = placeholder })
    self:_renderIdentity(true)
end

function Window:_renderIdentity(instant)
    for _, entry in ipairs(self._identity.Names) do
        if entry.Kind == "User" then
            entry.Label.Text = self._hideName and "@hidden" or ("@" .. LocalPlayer.Name)
        else
            entry.Label.Text = self._hideName and "Hidden" or LocalPlayer.DisplayName
        end
    end
    local duration = instant and 0 or 0.2
    for _, entry in ipairs(self._identity.Avatars) do
        tween(entry.Image, { ImageTransparency = self._hideAvatar and 1 or 0 }, duration)
        tween(entry.Placeholder, { ImageTransparency = self._hideAvatar and 0.2 or 1 }, duration)
    end
end

function Window:SetHideName(hidden)
    self._hideName = hidden == true
    self:_renderIdentity()
end

function Window:SetHideAvatar(hidden)
    self._hideAvatar = hidden == true
    self:_renderIdentity()
end

local function avatar(window, parent, props, ringColor, ringTransparency, ringThickness)
    local holder = create("Frame", {
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = parent,
    })
    for key, value in pairs(props) do
        holder[key] = value
    end
    corner(holder, UDim.new(1, 0))
    stroke(holder, ringColor or Theme.Stroke, ringTransparency or 0, ringThickness or 1)
    local image = create("ImageLabel", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        Parent = holder,
    })
    corner(image, UDim.new(1, 0))
    local placeholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(0.45, 0.45),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = holder,
    })
    applyIcon(placeholder, "user")
    window:_trackAvatar(image, placeholder)
    return holder
end

function Window:_buildProfile(sidebar)
    create("Frame", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -PROFILE_HEIGHT),
        Size = UDim2.new(1, -20, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = sidebar,
    })
    local card = create("TextButton", {
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -8),
        Size = UDim2.new(1, -16, 0, PROFILE_HEIGHT - 16),
        BackgroundColor3 = Theme.Surface2,
        BackgroundTransparency = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = sidebar,
    })
    corner(card, UDim.new(0, 8))
    local cardStroke = stroke(card, Theme.Stroke, 0)
    local head = avatar(self, card, {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 8, 0.5, 0),
        Size = UDim2.fromOffset(32, 32),
    })
    local online = create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 1, 1, 1),
        Size = UDim2.fromOffset(9, 9),
        BackgroundColor3 = Theme.Success,
        BorderSizePixel = 0,
        ZIndex = 2,
        Parent = head,
    })
    corner(online, UDim.new(1, 0))
    stroke(online, Theme.Surface2, 0, 2)
    local name = label({
        Position = UDim2.new(0, 48, 0.5, -15),
        Size = UDim2.new(1, -74, 0, 15),
        TextSize = 12,
        FontFace = Fonts.Bold,
        Parent = card,
    })
    self:_trackName(name, "Display")
    local gameLabel = label({
        Position = UDim2.new(0, 48, 0.5, 1),
        Size = UDim2.new(1, -74, 0, 13),
        Text = "…",
        TextSize = 11,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = card,
    })
    local chevron = create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = card,
    })
    applyIcon(chevron, "chevron-right")
    task.spawn(function()
        gameLabel.Text = detectGameName()
    end)
    card.MouseEnter:Connect(function()
        if usingTouch() then
            return
        end
        tween(cardStroke, { Color = Theme.StrokeHover }, 0.12)
        tween(chevron, { ImageColor3 = Theme.Text, Position = UDim2.new(1, -6, 0.5, 0) }, 0.15)
    end)
    card.MouseLeave:Connect(function()
        tween(cardStroke, { Color = Theme.Stroke }, 0.2)
        tween(chevron, { ImageColor3 = Theme.Muted, Position = UDim2.new(1, -8, 0.5, 0) }, 0.2)
    end)
    card.MouseButton1Click:Connect(function()
        if self.Home then
            self:SelectTab(self.Home)
        end
    end)
    self.Profile = card
end

-- Server actions

function Window:Rejoin()
    self:Notify({ Title = "Rejoining", Content = "Teleporting back into this server", Icon = "refresh-cw", Duration = 3 })
    task.spawn(function()
        local ok, err = pcall(function()
            if #Players:GetPlayers() <= 1 or game.JobId == "" then
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            else
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end)
        if not ok then
            self:Notify({ Title = "Rejoin failed", Content = tostring(err), Type = "Error", Duration = 4 })
        end
    end)
end

local function hopServers(window, order, pick, title)
    task.spawn(function()
        local servers = fetchServers(order)
        if not servers then
            window:Notify({ Title = title .. " failed", Content = "Could not load the server list", Type = "Error", Duration = 4 })
            return
        end
        local candidates = {}
        for _, server in ipairs(servers) do
            if type(server) == "table" and server.id ~= game.JobId then
                local playing, capacity = tonumber(server.playing), tonumber(server.maxPlayers)
                if playing and capacity and playing < capacity then
                    table.insert(candidates, server)
                end
            end
        end
        local target = #candidates > 0 and pick(candidates) or nil
        if not target then
            window:Notify({ Title = title .. " failed", Content = "No other open server found", Type = "Warning", Duration = 4 })
            return
        end
        window:Notify({
            Title = title,
            Content = string.format("Joining a server with %d/%d players", target.playing, target.maxPlayers),
            Icon = "server",
            Duration = 3,
        })
        local ok, err = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, target.id, LocalPlayer)
        end)
        if not ok then
            window:Notify({ Title = title .. " failed", Content = tostring(err), Type = "Error", Duration = 4 })
        end
    end)
end

function Window:ServerHop()
    hopServers(self, "Desc", function(list)
        return list[math.random(1, #list)]
    end, "Server hop")
end

function Window:JoinLowestServer()
    hopServers(self, "Asc", function(list)
        table.sort(list, function(a, b)
            return a.playing < b.playing
        end)
        return list[1]
    end, "Lowest server")
end

function Window:CopyToClipboard(text, what)
    local ok = copyToClipboard(text)
    self:Notify({
        Title = ok and "Copied" or "Clipboard unavailable",
        Content = ok and (what or tostring(text)) or "Your executor has no setclipboard",
        Type = ok and "Success" or "Error",
        Icon = ok and "clipboard-check" or nil,
        Duration = 2.5,
    })
    return ok
end

-- Home

-- Home reads top to bottom: a banner greeting the player, a performance card
-- with live graphs, the server and links side by side, and a status line.

-- A Home card that grows with its stacked contents.
function Window:_homeCard(parent, order)
    local card = panelCard(parent, 0, order)
    card.AutomaticSize = Enum.AutomaticSize.Y
    padding(card, 16, 16, 14, 14)
    create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = card })
    return card
end

-- A small caps heading at the top of a Home card.
function Window:_homeCaption(parent, text, order)
    return label({
        Size = UDim2.new(1, 0, 0, 22),
        Text = string.upper(text),
        TextSize = 10,
        TextColor3 = Theme.Muted,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = order,
        Parent = parent,
    })
end

-- A rounded chip of an icon and short text. Returns the chip, its label and
-- its icon so callers can recolour them.
function Window:_homeChip(parent, order, icon, text, color)
    icon = cleanIcon(icon)
    local chip = create("TextButton", {
        Size = UDim2.fromOffset(0, 24),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(chip, UDim.new(0, 6))
    local chipStroke = stroke(chip)
    padding(chip, 8, 9)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = chip,
    })
    local image
    if icon ~= false then
        image = create("ImageLabel", {
            Size = UDim2.fromOffset(12, 12),
            BackgroundTransparency = 1,
            ImageColor3 = color or Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            Parent = chip,
        })
        applyIcon(image, icon)
    end
    local text_ = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = text,
        TextSize = 12,
        TextColor3 = color or Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = chip,
    })
    return chip, text_, image, chipStroke
end

-- A chip that flips on press: on, it takes the accent; off, it sits muted.
function Window:_homeToggleChip(parent, order, icon, text, initial, callback)
    local chip, text_, image, chipStroke = self:_homeChip(parent, order, icon, text)
    local on = initial == true
    local function paint(duration)
        tween(chip, { BackgroundColor3 = on and Theme.Accent or Theme.Surface3, BackgroundTransparency = on and 0.85 or 0.2 }, duration)
        tween(chipStroke, { Color = on and Theme.Accent or Theme.Stroke, Transparency = on and 0.6 or 0 }, duration)
        tween(text_, { TextColor3 = on and Theme.Accent or Theme.Muted }, duration)
        if image then
            tween(image, { ImageColor3 = on and Theme.Accent or Theme.Muted }, duration)
        end
    end
    paint(0)
    chip.MouseButton1Click:Connect(function()
        on = not on
        paint(0.2)
        safeCall(callback, on)
    end)
    return chip
end

function Window:_homeProfile(list, opts, order)
    local banner = panelCard(list, 140, order)
    banner.ClipsDescendants = true

    -- The avatar bust stands on the banner's right edge and fades in from
    -- the left, so it reads as part of the card rather than a framed photo.
    local bust = create("ImageLabel", {
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -16, 1, 0),
        Size = UDim2.fromOffset(140, 140),
        BackgroundTransparency = 1,
        Image = "rbxthumb://type=AvatarBust&id=" .. tostring(LocalPlayer.UserId) .. "&w=420&h=420",
        ScaleType = Enum.ScaleType.Fit,
        Parent = banner,
    })
    create("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.45, 0),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = bust,
    })
    local bustPlaceholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.6, 0.55),
        Size = UDim2.fromOffset(40, 40),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = bust,
    })
    applyIcon(bustPlaceholder, "user")
    self:_trackAvatar(bust, bustPlaceholder)

    local textWidth = UDim2.new(1, -190, 0, 0)
    label({
        Position = UDim2.fromOffset(22, 20),
        Size = textWidth + UDim2.fromOffset(0, 14),
        Text = string.upper(opts.Welcome or "Welcome back"),
        TextSize = 10,
        TextColor3 = Theme.Muted,
        Parent = banner,
    })
    local nameLabel = label({
        Position = UDim2.fromOffset(22, 35),
        Size = textWidth + UDim2.fromOffset(0, 32),
        TextSize = 26,
        FontFace = Fonts.Bold,
        Parent = banner,
    })
    self:_trackName(nameLabel, "Display")
    local userLabel = label({
        Position = UDim2.fromOffset(22, 67),
        Size = textWidth + UDim2.fromOffset(0, 16),
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = banner,
    })
    self:_trackName(userLabel, "User")

    -- Chips along the bottom: tier, time left, then the privacy toggles.
    local chips = create("Frame", {
        Position = UDim2.new(0, 22, 1, -40),
        Size = UDim2.new(1, -44, 0, 24),
        BackgroundTransparency = 1,
        Parent = banner,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = chips,
    })
    local tier = opts.Tier
    if tier == nil then
        tier = "Free"
    end
    if tier then
        local tierIconValue = opts.TierIcon
        if tierIconValue == nil then
            tierIconValue = self._logoIcon
        end
        local tierChip, tierText, tierIcon = self:_homeChip(chips, 1, tierIconValue, tostring(tier), Theme.Accent)
        tierChip.Active = false
        tierText.FontFace = Fonts.Bold
        if tierIcon then
            tierIcon.Size = UDim2.fromOffset(13, 13)
        end
        self.TierLabel = tierText
    end
    local expiryChip, expiryText = self:_homeChip(chips, 2, "clock", "")
    expiryChip.Active = false
    expiryChip.Visible = false
    self:_homeToggleChip(chips, 3, "eye-off", "Name", self._hideName, function(on)
        self:SetHideName(on)
    end)
    self:_homeToggleChip(chips, 4, "user-x", "Avatar", self._hideAvatar, function(on)
        self:SetHideAvatar(on)
    end)

    return function()
        local value = opts.Expiry
        if type(value) == "function" then
            local ok, result = pcall(value)
            value = ok and result or nil
        end
        if type(value) == "number" then
            local left = value - os.time()
            expiryText.Text = left > 0 and (formatDuration(left) .. " left") or "Expired"
        elseif value ~= nil then
            expiryText.Text = tostring(value)
        end
        expiryChip.Visible = expiryText.Text ~= ""
    end
end

-- A large live readout with a short bar history under it. Returns the value
-- label and a push(value, color) that adds a sample.
function Window:_homeGraph(parent, order, icon, title, ceiling)
    local cell = create("Frame", {
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = parent,
    })
    local holder = glowIcon(cell, icon, Theme.Muted, UDim2.new(0, 0, 0, 7))
    holder.Size = UDim2.fromOffset(12, 12)
    label({
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -18, 0, 14),
        Text = string.upper(title),
        TextSize = 10,
        TextColor3 = Theme.Muted,
        Parent = cell,
    })
    local value = label({
        Position = UDim2.fromOffset(0, 16),
        Size = UDim2.new(1, 0, 0, 28),
        Text = "…",
        TextSize = 24,
        FontFace = Fonts.Bold,
        RichText = true,
        Parent = cell,
    })
    local track = create("Frame", {
        Position = UDim2.fromOffset(0, 50),
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        Parent = cell,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = track,
    })
    local COUNT = 24
    local bars, samples = {}, {}
    for index = 1, COUNT do
        local bar = create("Frame", {
            Size = UDim2.new(1 / COUNT, -2, 0, 2),
            BackgroundColor3 = Theme.Surface3,
            BorderSizePixel = 0,
            LayoutOrder = index,
            Parent = track,
        })
        corner(bar, UDim.new(0, 2))
        bars[index] = bar
    end
    local function push(sample, color)
        table.insert(samples, sample)
        if #samples > COUNT then
            table.remove(samples, 1)
        end
        local top = ceiling or 1
        for _, s in ipairs(samples) do
            top = math.max(top, s)
        end
        local offset = COUNT - #samples
        for index, bar in ipairs(bars) do
            local s = samples[index - offset]
            local latest = index == COUNT
            local height = s and math.max(s / top, 0.08) or 0
            tween(bar, {
                Size = UDim2.new(1 / COUNT, -2, height, s and 0 or 2),
                BackgroundColor3 = (latest and color) or (s and Theme.Muted or Theme.Surface3),
                BackgroundTransparency = latest and 0 or (s and 0.6 or 0),
            }, 0.35, Enum.EasingStyle.Quint)
        end
    end
    return value, push
end

-- A small figure: value over a caps caption.
function Window:_homeFigure(parent, order, title)
    local cell = create("Frame", {
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = parent,
    })
    local value = label({
        Size = UDim2.new(1, -8, 0, 20),
        Text = "…",
        TextSize = 15,
        FontFace = Fonts.Bold,
        RichText = true,
        Parent = cell,
    })
    label({
        Position = UDim2.fromOffset(0, 21),
        Size = UDim2.new(1, -8, 0, 14),
        Text = string.upper(title),
        TextSize = 10,
        TextColor3 = Theme.Muted,
        Parent = cell,
    })
    return value
end

-- A square tile button: an icon over a short label.
function Window:_homeAction(parent, order, icon, text, callback)
    local button = create("TextButton", {
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ClipsDescendants = true,
        LayoutOrder = order,
        Parent = parent,
    })
    corner(button, UDim.new(0, 8))
    local buttonStroke = stroke(button)
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 11),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Text,
        ScaleType = Enum.ScaleType.Fit,
        Parent = button,
    })
    applyIcon(image, icon)
    label({
        Position = UDim2.new(0, 4, 0, 32),
        Size = UDim2.new(1, -8, 0, 14),
        Text = text,
        TextSize = 11,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        Parent = button,
    })
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0 }, 0.15, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(image, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0.5 }, 0.25, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
        tween(image, { ImageColor3 = Theme.Text }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        ripple(button)
        safeCall(callback)
    end)
    return button
end

function Window:_homeGame(parent, order)
    local card = self:_homeCard(parent, order)
    local head = create("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = card,
    })
    local icon = create("ImageLabel", {
        Size = UDim2.fromOffset(44, 44),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Image = "rbxthumb://type=GameIcon&id=" .. tostring(game.GameId) .. "&w=150&h=150",
        Parent = head,
    })
    corner(icon, UDim.new(0, 10))
    stroke(icon)
    local gameName = label({
        Position = UDim2.fromOffset(56, 3),
        Size = UDim2.new(1, -56, 0, 20),
        Text = "Loading",
        TextSize = 15,
        FontFace = Fonts.Bold,
        Parent = head,
    })
    local detail = label({
        Position = UDim2.fromOffset(56, 24),
        Size = UDim2.new(1, -56, 0, 16),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = head,
    })
    local owner = nil
    task.spawn(function()
        local info = fetchGameInfo()
        gameName.Text = info and info.Name or detectGameName()
        owner = info and type(info.Creator) == "table" and info.Creator.Name or nil
    end)

    local actions = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        Parent = card,
    })
    padding(actions, 0, 0, 12, 0)
    create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(6, 6),
        CellSize = UDim2.new(0.25, -5, 0, 54),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = actions,
    })
    self:_homeAction(actions, 1, "refresh-cw", "Rejoin", function()
        self:Rejoin()
    end)
    self:_homeAction(actions, 2, "shuffle", "Hop", function()
        self:ServerHop()
    end)
    self:_homeAction(actions, 3, "users", "Lowest", function()
        self:JoinLowestServer()
    end)
    self:_homeAction(actions, 4, "copy", "Job ID", function()
        self:CopyToClipboard(game.JobId, "Job ID")
    end)

    label({
        Size = UDim2.new(1, 0, 0, 26),
        Text = "Job " .. shortId(game.JobId) .. "  ·  Place " .. tostring(game.PlaceId),
        TextSize = 11,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextYAlignment = Enum.TextYAlignment.Bottom,
        LayoutOrder = 3,
        Parent = card,
    })

    -- The detail line keeps the player count live.
    return function()
        local count = #Players:GetPlayers() .. "/" .. Players.MaxPlayers .. " players"
        detail.Text = owner and ("by " .. owner .. "  ·  " .. count) or count
    end
end

-- One row of the links card: icon, title and text, and a round icon button.
function Window:_homeLink(card, order, icon, title, text, buttonIcon, callback)
    local row = create("Frame", {
        Size = UDim2.new(1, 0, 0, 46),
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = card,
    })
    create("Frame", {
        Name = "Rule",
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        Parent = row,
    })
    icon = cleanIcon(icon)
    local textX = 28
    if icon ~= false then
        local holder = glowIcon(row, icon, Theme.Accent, UDim2.new(0, 0, 0.5, 0))
        holder.Size = UDim2.fromOffset(16, 16)
    else
        textX = 0
    end
    local titleLabel = label({
        Position = UDim2.fromOffset(textX, 6),
        Size = UDim2.new(1, -(textX + 40), 0, 18),
        Text = title,
        TextSize = 13,
        Parent = row,
    })
    local textLabel = label({
        Position = UDim2.fromOffset(textX, 24),
        Size = UDim2.new(1, -(textX + 40), 0, 15),
        Text = text,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = row,
    })
    local button = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = row,
    })
    corner(button, UDim.new(0, 8))
    local buttonStroke = stroke(button)
    local image = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(14, 14),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = button,
    })
    applyIcon(image, buttonIcon)
    button.MouseEnter:Connect(function()
        tween(button, { BackgroundTransparency = 0 }, 0.15, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(image, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    button.MouseLeave:Connect(function()
        tween(button, { BackgroundTransparency = 0.5 }, 0.25, Enum.EasingStyle.Quint)
        tween(buttonStroke, { Color = Theme.Stroke }, 0.25)
        tween(image, { ImageColor3 = Theme.Muted }, 0.25)
    end)
    button.MouseButton1Click:Connect(function()
        safeCall(callback)
    end)
    return row, titleLabel, textLabel
end

-- Builds the links card into parent, or nothing when there are no links and
-- the feature list is off. Returns the card (or nil) and the feature refresh.
function Window:_homeLinks(parent, opts, order)
    local links = {}
    if opts.Discord then
        local discordIcon = opts.DiscordIcon
        if discordIcon == nil then
            discordIcon = "message-circle"
        end
        table.insert(links, {
            Icon = discordIcon,
            Title = opts.DiscordTitle or "Community",
            Text = opts.Discord,
        })
    end
    if opts.Website then
        local websiteIcon = opts.WebsiteIcon
        if websiteIcon == nil then
            websiteIcon = "globe"
        end
        table.insert(links, {
            Icon = websiteIcon,
            Title = opts.WebsiteTitle or "Website",
            Text = opts.Website,
        })
    end
    for _, link in ipairs(opts.Links or {}) do
        table.insert(links, link)
    end
    local features = opts.Features
    if #links == 0 and features == false then
        return nil, function() end
    end
    local card = self:_homeCard(parent, order)
    self:_homeCaption(card, "Links", 0)
    for index, link in ipairs(links) do
        local action = type(link.Callback) == "function"
        local linkIcon = link.Icon
        if linkIcon == nil then
            linkIcon = "link"
        end
        self:_homeLink(card, index, linkIcon, link.Title or "", link.Text or "", action and "arrow-up-right" or "copy", function()
            if action then
                safeCall(link.Callback)
            else
                self:CopyToClipboard(link.Copy or link.Text, link.Title)
            end
        end)
    end
    local refresh = function() end
    if features ~= false then
        if type(features) == "table" then
            self._featuresTitle = features.Title
            self._features = features.List or (#features > 0 and features or nil)
        end
        local featuresIcon
        if type(features) == "table" then
            featuresIcon = features.Icon
        end
        if featuresIcon == nil then
            featuresIcon = "list-checks"
        end
        local _, _, text_ = self:_homeLink(card, 100,
            featuresIcon,
            type(features) == "table" and features.Title or "Feature list",
            "", "chevron-right", function()
                self:ShowFeatures()
            end)
        refresh = function()
            local desc = type(features) == "table" and features.Desc
            text_.Text = desc or (self:_featureSummary())
        end
        task.defer(refresh)
    end
    -- The first row needs no rule above it.
    local first = nil
    for _, child in ipairs(card:GetChildren()) do
        if child:IsA("Frame") and child:FindFirstChild("Rule") and (not first or child.LayoutOrder < first.LayoutOrder) then
            first = child
        end
    end
    if first then
        first.Rule.Visible = false
    end
    return card, refresh
end

-- A quiet status line under the cards: executor support on the left, the
-- hide key on the right.
function Window:_homeExecutor(list, opts, order)
    local line = create("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        LayoutOrder = order,
        Parent = list,
    })
    local executor, supported, message = executorReport(opts)
    local dot = create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 4, 0.5, 0),
        Size = UDim2.fromOffset(7, 7),
        BackgroundColor3 = supported and Theme.Success or Theme.Warning,
        BorderSizePixel = 0,
        Parent = line,
    })
    corner(dot, UDim.new(1, 0))
    local left = create("Frame", {
        Position = UDim2.fromOffset(18, 0),
        Size = UDim2.new(1, -170, 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = line,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = left,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = executor,
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 1,
        Parent = left,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = message,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = supported and Theme.Muted or Theme.Warning,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = left,
    })

    local hint = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -2, 0.5, 0),
        Size = UDim2.fromOffset(0, 22),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = line,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
        Parent = hint,
    })
    label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = TOUCH and "Tap the pill or" or "Hide with",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 1,
        Parent = hint,
    })
    local chip = create("Frame", {
        Size = UDim2.fromOffset(0, 20),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = hint,
    })
    corner(chip, UDim.new(0, 5))
    stroke(chip)
    padding(chip, 6, 6)
    self._keyChipLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = keyName(self.Keybind),
        TextSize = 11,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        Parent = chip,
    })
end

-- Feature list: every control the script adds, grouped by tab, or a list the
-- script writes itself. Items that match a control jump to it when picked.

Window._featureKinds = {
    Toggle = true,
    Slider = true,
    Dropdown = true,
    Input = true,
    Keybind = true,
    ColorPicker = true,
    Stepper = true,
    Button = true,
    ButtonRow = true,
    OrderList = true,
}

function Window:_featureGroups()
    local found, byName = {}, {}
    for _, tab in ipairs(self.Tabs) do
        if tab ~= self.Home and tab._userVisible ~= false then
            local group = { Name = tab.Name, Icon = tab._iconName, Items = {} }
            for _, page in ipairs(tab._subTabs or { tab }) do
                local sub = page._isSubTab and page or nil
                local function add(name, element, box, path)
                    if type(name) ~= "string" or name == "" then
                        return
                    end
                    local item = {
                        Name = name,
                        Kind = element._type == "ButtonRow" and "Button" or element._type,
                        Path = path,
                        Result = { Tab = tab, Sub = sub, Target = element, Group = box },
                    }
                    table.insert(group.Items, item)
                    byName[string.lower(name)] = byName[string.lower(name)] or item
                end
                local function addElement(element, box, path)
                    if element._destroyed or not self._featureKinds[element._type] or (element._isShown and not element:_isShown()) then
                        return
                    end
                    if element._type == "ButtonRow" and element.Buttons then
                        for _, button in ipairs(element.Buttons) do
                            add(button.Label.Text, element, box, path)
                        end
                    else
                        add(element._searchName, element, box, path)
                    end
                end
                if not page._noSearch then
                    for _, element in ipairs(page._items or {}) do
                        addElement(element, nil, sub and sub.Name or nil)
                    end
                    for _, box in ipairs(page._groupboxes or {}) do
                        if box._userVisible ~= false and not box._manager then
                            for _, element in ipairs(box._items) do
                                addElement(element, box, sub and (sub.Name .. "  ›  " .. box.Name) or box.Name)
                            end
                        end
                    end
                end
            end
            if #group.Items > 0 then
                table.insert(found, group)
            end
        end
    end
    local custom = self._features
    if type(custom) ~= "table" then
        return found
    end
    -- A written list: groups of items, or bare items, which gather into one
    -- group where the first one appears.
    local function customItem(entry)
        if type(entry) ~= "table" then
            entry = { Name = entry }
        end
        local name = tostring(entry.Name or entry.Title or entry[1] or "")
        local link = byName[string.lower(name)]
        return {
            Name = name,
            Desc = entry.Desc or entry.Description,
            Tag = entry.Tag,
            Icon = entry.Icon,
            Kind = link and link.Kind,
            Path = link and link.Path,
            Result = link and link.Result,
            Callback = entry.Callback,
        }
    end
    local groups, loose = {}, nil
    for _, entry in ipairs(custom) do
        if type(entry) == "table" and type(entry.Items) == "table" then
            local group = { Name = tostring(entry.Name or entry.Title or "Features"), Icon = entry.Icon, Items = {} }
            for _, item in ipairs(entry.Items) do
                table.insert(group.Items, customItem(item))
            end
            table.insert(groups, group)
        else
            if not loose then
                loose = { Name = self._featuresTitle or "Features", Items = {} }
                table.insert(groups, loose)
            end
            table.insert(loose.Items, customItem(entry))
        end
    end
    return groups
end

function Window:_featureSummary()
    local groups = self:_featureGroups()
    local count = 0
    for _, group in ipairs(groups) do
        count += #group.Items
    end
    local text = count .. (count == 1 and " feature" or " features")
    if type(self._features) ~= "table" and #groups > 0 then
        text ..= " across " .. #groups .. (#groups == 1 and " tab" or " tabs")
    end
    return text, groups, count
end

-- Opens the feature list over the window. Search filters it; picking an item
-- linked to a control closes the list and jumps to that control.
function Window:ShowFeatures()
    if self._dialog then
        self._dialog.Close()
    end
    local summary, groups, total = self:_featureSummary()
    local PAD = 16
    local ROW = TOUCH and 44 or 38
    local body = self.Body

    local overlay = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 40,
        Parent = body,
    })
    -- A canvas group so the whole list fades as one on open and close.
    local card_ = create("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(420, 460),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Active = true,
        Parent = overlay,
    })
    corner(card_, UDim.new(0, 12))
    local cardStroke = stroke(card_, Theme.Stroke, 1)
    local cardScale = create("UIScale", { Scale = 0.94, Parent = card_ })
    local function fit()
        local scale = self.Scale.Scale
        local size = body.AbsoluteSize / scale
        card_.Size = UDim2.fromOffset(math.min(440, size.X - 24), math.min(480, size.Y - 24))
    end
    fit()
    local fitConnection = body:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

    local iconHolder = glowIcon(card_, "list-checks", Theme.Accent, UDim2.new(0, PAD, 0, PAD + 10))
    iconHolder.Size = UDim2.fromOffset(18, 18)
    label({
        Position = UDim2.fromOffset(PAD + 28, PAD),
        Size = UDim2.new(1, -(PAD * 2 + 28 + 36), 0, 18),
        Text = self._featuresTitle or "Features",
        TextSize = 15,
        Parent = card_,
    })
    label({
        Position = UDim2.fromOffset(PAD + 28, PAD + 19),
        Size = UDim2.new(1, -(PAD * 2 + 28 + 36), 0, 14),
        Text = summary,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = card_,
    })
    local closeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -(PAD - 6), 0, PAD - 6),
        Size = TOUCH and UDim2.fromOffset(40, 40) or UDim2.fromOffset(32, 32),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Parent = card_,
    })
    corner(closeButton, UDim.new(0, 8))
    local closeIcon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(16, 16),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ScaleType = Enum.ScaleType.Fit,
        Parent = closeButton,
    })
    applyIcon(closeIcon, "x")
    if closeIcon.Image == "" then
        closeIcon:Destroy()
        label({ Size = UDim2.fromScale(1, 1), Text = "×", TextSize = 20, TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Center, Parent = closeButton })
    end
    closeButton.MouseEnter:Connect(function()
        tween(closeButton, { BackgroundTransparency = 0.5 }, 0.12)
    end)
    closeButton.MouseLeave:Connect(function()
        tween(closeButton, { BackgroundTransparency = 1 }, 0.2)
    end)

    local top = PAD + 44
    local searchHolder = create("Frame", {
        Position = UDim2.fromOffset(PAD, top),
        Size = UDim2.new(1, -PAD * 2, 0, TOUCH and 36 or 32),
        BackgroundColor3 = Theme.Surface,
        BorderSizePixel = 0,
        Parent = card_,
    })
    corner(searchHolder, UDim.new(0, 7))
    local searchStroke = stroke(searchHolder)
    local _, searchIcon = glowIcon(searchHolder, "search", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
    searchIcon.Parent.Size = UDim2.fromOffset(14, 14)
    local searchBox = create("TextBox", {
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -40, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Search features",
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ClearTextOnFocus = false,
        Parent = searchHolder,
    })
    searchBox.Focused:Connect(function()
        tween(searchStroke, { Color = Theme.StrokeHover }, 0.15)
        tween(searchIcon, { ImageColor3 = Theme.Accent }, 0.15)
    end)
    searchBox.FocusLost:Connect(function()
        tween(searchStroke, { Color = Theme.Stroke }, 0.2)
        tween(searchIcon, { ImageColor3 = Theme.Muted }, 0.2)
    end)
    top += (TOUCH and 36 or 32) + 10

    local scroller = create("ScrollingFrame", {
        Position = UDim2.fromOffset(PAD, top),
        Size = UDim2.new(1, -PAD * 2 + 6, 1, -(top + PAD - 4)),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = TOUCH and 4 or 3,
        ScrollBarImageColor3 = Theme.Accent,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(),
        Parent = card_,
    })
    local content = create("Frame", {
        Size = UDim2.new(1, -10, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = scroller,
    })
    local layout = create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = content,
    })
    -- Canvas sized by hand, as elsewhere, so it scrolls under UIScale.
    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroller.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y / self.Scale.Scale + 4)
    end)
    local noResults = label({
        Size = UDim2.new(1, 0, 0, 60),
        Text = total == 0 and "No features yet" or "No matches",
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        LayoutOrder = 0,
        Visible = total == 0,
        Parent = content,
    })

    local dialog = {}
    local closed = false
    local stopEscape = nil
    function dialog.Close()
        if closed then
            return
        end
        closed = true
        if self._dialog == dialog then
            self._dialog = nil
        end
        fitConnection:Disconnect()
        if stopEscape then
            -- Deferred: Close can run from inside the input dispatch loop.
            task.defer(stopEscape)
        end
        if searchBox:IsFocused() then
            searchBox:ReleaseFocus()
        end
        tween(overlay, { BackgroundTransparency = 1 }, 0.18)
        tween(card_, { Position = UDim2.new(0.5, 0, 0.5, 8), GroupTransparency = 1 }, 0.18, Enum.EasingStyle.Quint)
        tween(cardScale, { Scale = 0.96 }, 0.18, Enum.EasingStyle.Quint)
        tween(cardStroke, { Transparency = 1 }, 0.12)
        task.delay(0.2, function()
            overlay:Destroy()
        end)
    end

    local sections = {}
    local order = 0
    for _, group in ipairs(groups) do
        order += 1
        local header = create("Frame", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            LayoutOrder = order,
            Parent = content,
        })
        local groupIcon = group.Icon
        if groupIcon == nil then
            groupIcon = "layout-grid"
        end
        local headX = 24
        if groupIcon ~= false then
            local headIcon = glowIcon(header, groupIcon, Theme.Accent, UDim2.new(0, 2, 0, 18))
            headIcon.Size = UDim2.fromOffset(14, 14)
        else
            headX = 2
        end
        label({
            Position = UDim2.fromOffset(headX, 10),
            Size = UDim2.new(1, -70, 0, 16),
            Text = string.upper(group.Name),
            TextSize = 11,
            TextColor3 = Theme.Muted,
            Parent = header,
        })
        local countLabel = label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -4, 0, 10),
            Size = UDim2.new(0, 40, 0, 16),
            Text = tostring(#group.Items),
            TextSize = 11,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = header,
        })
        local section = { Header = header, Count = countLabel, Rows = {} }
        for _, item in ipairs(group.Items) do
            order += 1
            local sub = item.Desc or item.Path
            local clickable = item.Result ~= nil or type(item.Callback) == "function"
            local row = create("TextButton", {
                Size = UDim2.new(1, 0, 0, sub and ROW + 4 or ROW - 4),
                BackgroundColor3 = Theme.Surface2,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = order,
                Parent = content,
            })
            corner(row, UDim.new(0, 8))
            local rowIconValue = item.Icon
            if rowIconValue == nil then
                rowIconValue = self._searchIcons[item.Kind] or "check"
            end
            local rowIcon
            if rowIconValue ~= false then
                rowIcon = glowIcon(row, rowIconValue, Theme.Muted, UDim2.new(0, 10, 0.5, 0))
                rowIcon.Size = UDim2.fromOffset(14, 14)
            end
            local textX = rowIcon and 34 or 10
            local right = 12 + (clickable and 22 or 0)
            local tag
            if item.Tag then
                tag = create("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -(clickable and 30 or 10), 0.5, 0),
                    Size = UDim2.fromOffset(0, 20),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Theme.Accent,
                    BackgroundTransparency = 0.85,
                    BorderSizePixel = 0,
                    Parent = row,
                })
                corner(tag, UDim.new(0, 5))
                padding(tag, 7, 7)
                label({
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = tostring(item.Tag),
                    TextSize = 11,
                    TextColor3 = Theme.Accent,
                    TextTruncate = Enum.TextTruncate.None,
                    Parent = tag,
                })
            end
            local nameLabel = label({
                Position = UDim2.fromOffset(textX, sub and 5 or 0),
                Size = UDim2.new(1, -(textX + right), 0, sub and 18 or ROW - 4),
                Text = item.Name,
                TextSize = 13,
                Parent = row,
            })
            local subLabel
            if sub then
                subLabel = label({
                    Position = UDim2.fromOffset(textX, 23),
                    Size = UDim2.new(1, -(textX + right), 0, 14),
                    Text = sub,
                    TextSize = 11,
                    FontFace = Fonts.Regular,
                    TextColor3 = Theme.Muted,
                    Parent = row,
                })
            end
            if tag then
                local function reserveTag()
                    local width = textX + right + tag.AbsoluteSize.X / self.Scale.Scale + 8
                    nameLabel.Size = UDim2.new(1, -width, 0, nameLabel.Size.Y.Offset)
                    if subLabel then
                        subLabel.Size = UDim2.new(1, -width, 0, 14)
                    end
                end
                tag:GetPropertyChangedSignal("AbsoluteSize"):Connect(reserveTag)
                task.defer(reserveTag)
            end
            if clickable then
                local go = create("ImageLabel", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -10, 0.5, 0),
                    Size = UDim2.fromOffset(14, 14),
                    BackgroundTransparency = 1,
                    ImageColor3 = Theme.Muted,
                    ImageTransparency = 0.4,
                    ScaleType = Enum.ScaleType.Fit,
                    Parent = row,
                })
                applyIcon(go, "arrow-up-right")
            end
            local isTap = tapGuard(row, function()
                return scroller
            end)
            row.MouseEnter:Connect(function()
                if not usingTouch() then
                    tween(row, { BackgroundTransparency = 0.3 }, 0.12)
                end
            end)
            row.MouseLeave:Connect(function()
                tween(row, { BackgroundTransparency = 1 }, 0.2)
            end)
            row.MouseButton1Click:Connect(function()
                if not clickable or not isTap() then
                    return
                end
                dialog.Close()
                if item.Result then
                    self:_revealResult(item.Result)
                end
                safeCall(item.Callback)
            end)
            table.insert(section.Rows, { Frame = row, Key = string.lower(item.Name .. " " .. (sub or "")) })
        end
        table.insert(sections, section)
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        local query = string.lower(searchBox.Text)
        local any = false
        for _, section in ipairs(sections) do
            local shown = 0
            for _, row in ipairs(section.Rows) do
                local match = query == "" or string.find(row.Key, query, 1, true) ~= nil
                row.Frame.Visible = match
                if match then
                    shown += 1
                end
            end
            section.Header.Visible = shown > 0
            section.Count.Text = tostring(shown)
            any = any or shown > 0
        end
        noResults.Visible = not any
        scroller.CanvasPosition = Vector2.zero
    end)
    closeButton.MouseButton1Click:Connect(dialog.Close)
    overlay.MouseButton1Click:Connect(dialog.Close)
    stopEscape = self:_listen("Began", function(input)
        if input.KeyCode == Enum.KeyCode.Escape then
            dialog.Close()
        end
    end)

    self._dialog = dialog
    tween(overlay, { BackgroundTransparency = 0.45 }, 0.25)
    tween(card_, { Position = UDim2.fromScale(0.5, 0.5), GroupTransparency = 0 }, 0.3, Enum.EasingStyle.Quint)
    tween(cardScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
    return dialog
end

function Window:_homeStats(list, opts, order, tab)
    local show = opts.Stats or { "Players", "Execs", "Session", "FPS", "Ping" }
    -- FPS and ping get large readouts with a bar history; every other stat
    -- is a small figure in the row under them.
    local card = self:_homeCard(list, order)
    local graphs = create("Frame", {
        Size = UDim2.new(1, 0, 0, 76),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = card,
    })
    create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(24, 0),
        CellSize = UDim2.new(0.5, -12, 0, 76),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = graphs,
    })
    local rule = create("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Stroke,
        BorderSizePixel = 0,
        LayoutOrder = 2,
        Parent = card,
    })
    local figures = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = card,
    })
    padding(figures, 0, 0, 12, 0)
    local figureGrid = create("UIGridLayout", {
        CellPadding = UDim2.fromOffset(0, 8),
        CellSize = UDim2.new(0.25, 0, 0, 36),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = figures,
    })
    local values, sparks = {}, {}
    local graphCount, figureCount = 0, 0
    for index, name in ipairs(show) do
        local kind = STAT_TYPES[name]
        if kind and not values[name] then
            if name == "FPS" or name == "Ping" then
                graphCount += 1
                values[name], sparks[name] = self:_homeGraph(graphs, index, kind[1], kind[2], name == "FPS" and 60 or 100)
            else
                figureCount += 1
                values[name] = self:_homeFigure(figures, index, kind[2])
            end
        end
    end
    graphs.Visible = graphCount > 0
    figures.Visible = figureCount > 0
    rule.Visible = graphCount > 0 and figureCount > 0
    if graphCount == 0 then
        padding(figures, 0, 0, 0, 0)
    end
    local function fitFigures()
        local width = figures.AbsoluteSize.X / self.Scale.Scale
        local columns = math.clamp(figureCount, 1, width >= 440 and 5 or 3)
        figureGrid.CellSize = UDim2.new(1 / columns, 0, 0, 36)
    end
    figures:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitFigures)
    task.defer(fitFigures)

    if values.Executor then
        values.Executor.Text = detectExecutor()
    end
    if values.Game then
        values.Game.Text = "Loading"
        task.spawn(function()
            values.Game.Text = detectGameName()
        end)
    end
    if values.Region then
        values.Region.Text = "Loading"
        detectRegion(function(region)
            values.Region.Text = region
        end)
    end
    if values.Execs then
        local executions = bumpExecutions(opts.StatsFolder or self.ConfigFolder)
        values.Execs.Text = executions and tostring(executions) or "—"
    end
    if values.Friends then
        local friends = {}
        local function recount()
            local total = 0
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    local known = friends[player.UserId]
                    if known == nil then
                        local ok, result = pcall(function()
                            return LocalPlayer:IsFriendsWith(player.UserId)
                        end)
                        known = ok and result == true
                        friends[player.UserId] = known
                    end
                    if known then
                        total += 1
                    end
                end
            end
            values.Friends.Text = tostring(total)
        end
        task.spawn(recount)
        table.insert(self._connections, Players.PlayerAdded:Connect(function()
            task.spawn(recount)
        end))
        table.insert(self._connections, Players.PlayerRemoving:Connect(function()
            task.defer(recount)
        end))
    end

    local session = values.Session or values.Uptime
    local started = os.clock()
    local frames = 0
    self:_listen("Render", function()
        frames += 1
    end)
    -- FPS, ping and memory are tinted by how healthy they are, unless the
    -- script turns that off with StatColors = false.
    local tinted = opts.StatColors ~= false
    local function tint(valueLabel, color)
        if tinted and valueLabel.TextColor3 ~= color then
            tween(valueLabel, { TextColor3 = color }, 0.3)
        end
    end
    return function()
        if values.FPS then
            values.FPS.Text = tostring(frames)
            tint(values.FPS, Library._healthColor(frames, 50, 30))
            sparks.FPS(frames, Library._healthColor(frames, 50, 30))
        end
        frames = 0
        if values.Ping then
            local ok, ping = pcall(function()
                return math.floor(LocalPlayer:GetNetworkPing() * 1000)
            end)
            ping = ok and ping or 0
            values.Ping.Text = ping .. "ms"
            tint(values.Ping, Library._healthColor(ping, 90, 180, true))
            sparks.Ping(ping, Library._healthColor(ping, 90, 180, true))
        end
        if values.Players then
            values.Players.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
        end
        if session then
            session.Text = formatDuration(os.clock() - started)
        end
        if values.Time then
            values.Time.Text = os.date(opts.TimeFormat or "%H:%M")
        end
        if values.ServerAge then
            values.ServerAge.Text = formatDuration(workspace.DistributedGameTime)
        end
        if values.Memory then
            local ok, memory = pcall(function()
                return StatsService:GetTotalMemoryUsageMb()
            end)
            values.Memory.Text = ok and string.format("%d MB", memory) or "—"
            tint(values.Memory, ok and Library._healthColor(memory, 1500, 3000, true) or Theme.Text)
        end
    end, function()
        frames = 0
    end
end

local function homePage(sub, page)
    local list = sub.List
    if type(page.Content) == "string" then
        local card_ = panelCard(list, 0, 1)
        card_.AutomaticSize = Enum.AutomaticSize.Y
        padding(card_, 16, 16, 14, 16)
        label({
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = page.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = card_,
        })
    end
    if type(page.Entries) == "table" then
        for index, entry in ipairs(page.Entries) do
            local card_ = panelCard(list, 0, index + 1)
            card_.AutomaticSize = Enum.AutomaticSize.Y
            padding(card_, 16, 16, 14, 16)
            create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 6),
                Parent = card_,
            })
            local head = create("Frame", {
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
                LayoutOrder = 1,
                Parent = card_,
            })
            label({
                Size = UDim2.new(1, -90, 1, 0),
                Text = entry.Title or entry.Version or "Update",
                TextSize = 15,
                Parent = head,
            })
            if entry.Date or entry.Tag then
                local chip = create("Frame", {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, 0, 0.5, 0),
                    Size = UDim2.fromOffset(0, 20),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundColor3 = Theme.Surface,
                    BorderSizePixel = 0,
                    Parent = head,
                })
                corner(chip, UDim.new(0, 5))
                stroke(chip)
                padding(chip, 8, 8)
                label({
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = entry.Tag or entry.Date,
                    TextSize = 11,
                    TextColor3 = Theme.Muted,
                    TextTruncate = Enum.TextTruncate.None,
                    Parent = chip,
                })
            end
            local body = entry.Content or entry.Body
            if type(entry.Changes) == "table" then
                body = "• " .. table.concat(entry.Changes, "\n• ")
            end
            if body then
                label({
                    Size = UDim2.new(1, 0, 0, 0),
                    AutomaticSize = Enum.AutomaticSize.Y,
                    Text = body,
                    TextSize = 13,
                    FontFace = Fonts.Regular,
                    TextColor3 = Theme.Muted,
                    TextWrapped = true,
                    TextTruncate = Enum.TextTruncate.None,
                    TextYAlignment = Enum.TextYAlignment.Top,
                    LayoutOrder = 2,
                    Parent = card_,
                })
            end
        end
    end
    if type(page.Build) == "function" then
        safeCall(page.Build, sub, list)
    else
        sub._noSearch = true
    end
end

function Window:_buildHome(opts)
    self._hideName = opts.HideName == true
    self._hideAvatar = opts.HideAvatar == true
    self:_renderIdentity(true)
    local homeIcon = opts.Icon
    if homeIcon == nil then
        homeIcon = "house"
    end
    local tab = self:Tab({
        Name = opts.Name or "Home",
        Desc = opts.Desc,
        Icon = homeIcon,
        PageTitle = opts.Title or "Home",
    })
    tab._order = 100
    self.Home = tab

    local pages = opts.Pages or opts.Tabs
    local overview = tab
    if type(pages) == "table" and #pages > 0 then
        local overviewIcon = opts.TabIcon
        if overviewIcon == nil then
            overviewIcon = "layout-grid"
        end
        overview = tab:SubTab({ Name = opts.OverviewName or "Overview", Icon = overviewIcon })
    end
    overview._noSearch = true
    overview._order = 100
    local list = overview.List

    local refreshExpiry = self:_homeProfile(list, opts, 1)
    local refreshStats, resetStats = self:_homeStats(list, opts, 2, tab)

    -- Server and links side by side, stacked when narrow.
    local split = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = list,
    })
    local splitLayout = create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 10),
        Parent = split,
    })
    local function column(order_)
        local frame = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = order_,
            Parent = split,
        })
        create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = frame })
        return frame
    end
    local leftColumn, rightColumn = column(1), column(2)
    local refreshGame = self:_homeGame(leftColumn, 1)
    local linksCard, refreshFeatures = self:_homeLinks(rightColumn, opts, 1)
    if not linksCard then
        rightColumn:Destroy()
    end
    local function fitSplit()
        local wide = linksCard ~= nil and split.AbsoluteSize.X / self.Scale.Scale >= 540
        splitLayout.FillDirection = wide and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
        local size = wide and UDim2.new(0.5, -5, 0, 0) or UDim2.new(1, 0, 0, 0)
        leftColumn.Size = size
        if linksCard then
            rightColumn.Size = size
        end
    end
    split:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitSplit)
    task.defer(fitSplit)

    self:_homeExecutor(list, opts, 4)

    if type(pages) == "table" then
        for _, page in ipairs(pages) do
            homePage(tab:SubTab({ Name = page.Name or page.Title or "Page", Icon = page.Icon }), page)
        end
    end

    refreshExpiry()
    refreshStats()
    refreshGame()
    task.spawn(function()
        while not self._destroyed and tab._page.Parent do
            task.wait(1)
            if self.Open and self.CurrentTab == tab then
                refreshStats()
                refreshExpiry()
                refreshGame()
                refreshFeatures()
            else
                resetStats()
            end
        end
    end)
    return tab
end

function Window:Tab(opts, icon)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    if icon ~= nil and opts.Icon == nil then
        opts.Icon = cleanIcon(icon)
    end
    local tab = setmetatable({
        Name = opts.Name or "Tab",
        Window = self,
        _order = 0,
    }, Tab)

    local button = create("TextButton", {
        Size = UDim2.new(1, 0, 0, TAB_TILE_HEIGHT),
        BackgroundColor3 = Theme.Surface3,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        LayoutOrder = #self.Tabs + 1,
        Parent = self._tabStack,
    })
    corner(button, UDim.new(0, 7))
    local buttonStroke = stroke(button, Theme.Stroke, 1)
    buttonStroke.Enabled = false
    tab._button = button

    local hasIcon = opts.Icon ~= nil and opts.Icon ~= false
    if hasIcon then
        local iconImage = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0, 20, 0.5, 0),
            Size = UDim2.fromOffset(16, 16),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = button,
        })
        applyIcon(iconImage, opts.Icon)
        if iconImage:GetAttribute("CustomIcon") then
            iconImage.ImageTransparency = 0.4
        end
        tab._icon = iconImage
    end
    tab._label = label({
        Position = UDim2.fromOffset(hasIcon and 38 or 14, 0),
        Size = UDim2.new(1, hasIcon and -46 or -22, 1, 0),
        Text = tab.Name,
        TextSize = 13,
        TextColor3 = Theme.Muted,
        Parent = button,
    })

    local page = create("Frame", {
        Name = tab.Name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        Parent = self.Content,
    })
    tab._page = page
    local titleX = 24
    if hasIcon then
        local holder = glowIcon(page, opts.Icon, Theme.Accent, UDim2.new(0, 24, 0, 32))
        holder.Size = UDim2.fromOffset(20, 20)
        titleX = 54
    end
    tab._titleX = titleX
    tab._title = label({
        Position = UDim2.fromOffset(titleX, 20),
        Size = UDim2.new(1, -titleX, 0, 24),
        Text = opts.PageTitle or tab.Name,
        TextSize = 22,
        Parent = page,
    })
    if opts.Desc then
        tab._desc = label({
            Position = UDim2.fromOffset(titleX, 44),
            Size = UDim2.new(1, -titleX, 0, 16),
            Text = opts.Desc,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = page,
        })
    end
    local listTop = opts.Desc and 70 or 58
    tab._headerBottom = listTop
    tab._iconName = opts.Icon
    local emptyIcon = opts.Icon
    if emptyIcon == nil then
        emptyIcon = "layout-grid"
    end
    buildContainer(tab, page, listTop, emptyIcon, opts.EmptyText or "Nothing here yet")

    local pressScale = create("UIScale", { Parent = button })
    local function release()
        tween(pressScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint)
    end
    button.MouseEnter:Connect(function()
        if self.CurrentTab ~= tab and not usingTouch() then
            tween(button, { BackgroundTransparency = 0.75 }, 0.2, Enum.EasingStyle.Quint)
            tween(tab._label, { TextColor3 = Theme.Text }, 0.2)
            if tab._icon then
                tintIcon(tab._icon, Theme.Text, true, 0.2)
            end
        end
    end)
    button.MouseLeave:Connect(function()
        release()
        if self.CurrentTab ~= tab then
            tween(button, { BackgroundTransparency = 1 }, 0.3, Enum.EasingStyle.Quint)
            tween(tab._label, { TextColor3 = Theme.Muted }, 0.3)
            if tab._icon then
                tintIcon(tab._icon, Theme.Muted, false, 0.3)
            end
        end
    end)
    button.MouseButton1Down:Connect(function()
        tween(pressScale, { Scale = 0.97 }, 0.15, Enum.EasingStyle.Quint)
    end)
    button.MouseButton1Up:Connect(release)
    local isTap = tapGuard(button, function()
        return self.TabList
    end)
    button.MouseButton1Click:Connect(function()
        release()
        if isTap() then
            self:SelectTab(tab)
        end
    end)
    tab._stroke = buttonStroke
    self:_fitTitle(tab)

    if not self._introDone then
        button.Visible = false
    end
    table.insert(self.Tabs, tab)
    if #self.Tabs == 1 then
        task.defer(function()
            if not self.CurrentTab then
                self:SelectTab(tab)
            end
        end)
    end
    return tab
end

Window.CreateTab = Window.Tab

-- Cloud configs: a tab for browsing, previewing, installing and publishing
-- configs other players shared. The library draws it; OnFetch, OnPublish and
-- the other callbacks are the script's backend. Favorites, installs and the
-- sort order are remembered in the script's settings file.
function Window:CloudConfigs(opts)
    opts = normalize(opts, { Title = "Name", Description = "Desc" })
    local window = self
    local tabIcon = opts.Icon
    if tabIcon == nil then
        tabIcon = "cloud"
    end
    local tab = self:Tab({
        Name = opts.Name or "Cloud",
        Desc = opts.Desc,
        Icon = tabIcon,
        PageTitle = opts.PageTitle,
    })
    tab._noSearch = true
    tab.List.Visible = false
    if tab._empty then
        tab._empty:Destroy()
        tab._empty = nil
    end

    local CARD = 116
    local ROW = TOUCH and 36 or 32
    local CHIP = TOUCH and 30 or 26
    local SORTS = { "Popular", "New", "Top", "Installs" }
    local SORT_NAMES = { Popular = "Popular", New = "Newest", Top = "Top rated", Installs = "Most installed" }
    local FILTERS = { "All", "Favorites", "Mine", "Installed" }
    local NAME_LIMIT = 40
    local DESC_LIMIT = math.max(math.floor(tonumber(opts.DescriptionLimit) or 300), 20)
    local pageSize = math.max(math.floor(tonumber(opts.PageSize) or 20), 1)
    local tagList = type(opts.Tags) == "table" and opts.Tags or {}
    local maxTags = math.max(math.floor(tonumber(opts.MaxTags) or 3), 0)
    local anonName = tostring(opts.StreamerName or "Ouroboros User")

    local cloud = { Tab = tab }
    local records, byId = {}, {}
    local cards = {}
    local hasMore, page, token = false, 0, 0
    local loading = false
    local query = { Search = "", Sort = "Popular", Filter = "All", Tag = nil }
    local views, currentView = {}, nil
    local detail, detailRecord, detailToken = {}, nil, 0

    local stored = window:_readConfigSettings()
    local favorites = type(stored.CloudFavorites) == "table" and stored.CloudFavorites or {}
    local installed = type(stored.CloudInstalled) == "table" and stored.CloudInstalled or {}
    if table.find(SORTS, stored.CloudSort) then
        query.Sort = stored.CloudSort
    elseif table.find(SORTS, opts.Sort) then
        query.Sort = opts.Sort
    end
    local function persist(key, value)
        window:_writeConfigSettings({ [key] = value })
    end

    local function notify(ok, title, detail_)
        window:Notify({ Title = title, Content = detail_, Type = ok and "Success" or "Error", Duration = 3 })
    end

    -- The Home tab's hide-name switch doubles as streamer mode.
    local function streamerOn()
        return window._hideName == true
    end

    -- Records

    local function countFlags(code)
        local data = type(code) == "string" and window:DecodeConfig(code)
        if not data then
            return nil
        end
        local count = 0
        for _ in pairs(data) do
            count += 1
        end
        return count
    end

    local function compact(number)
        number = math.max(math.floor(tonumber(number) or 0), 0)
        if number >= 1e6 then
            return (("%.1f"):format(number / 1e6):gsub("%.0$", "")) .. "m"
        elseif number >= 1e3 then
            return (("%.1f"):format(number / 1e3):gsub("%.0$", "")) .. "k"
        end
        return tostring(number)
    end

    local function ago(stamp)
        stamp = tonumber(stamp)
        if not stamp then
            return nil
        end
        local delta = os.time() - stamp
        if delta < 60 then
            return "just now"
        elseif delta < 3600 then
            return math.floor(delta / 60) .. "m ago"
        elseif delta < 86400 then
            return math.floor(delta / 3600) .. "h ago"
        elseif delta < 604800 then
            return math.floor(delta / 86400) .. "d ago"
        elseif delta < 2592000 then
            return math.floor(delta / 604800) .. "w ago"
        end
        return os.date("%d %b %Y", stamp)
    end

    local function escape(text)
        return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
    end

    -- Rich text with every match of the search drawn in the accent.
    local function highlight(text)
        local needle = string.lower(query.Search)
        if needle == "" then
            return escape(text)
        end
        local lower = string.lower(text)
        local hex = colorToHex(Theme.Accent)
        local out, from = {}, 1
        while true do
            local first, last = string.find(lower, needle, from, true)
            if not first then
                break
            end
            table.insert(out, escape(text:sub(from, first - 1)))
            table.insert(out, ('<font color="#%s"><b>%s</b></font>'):format(hex, escape(text:sub(first, last))))
            from = last + 1
        end
        table.insert(out, escape(text:sub(from)))
        return table.concat(out)
    end

    local function normalizeRecord(raw)
        if type(raw) ~= "table" then
            return nil
        end
        local id = raw.Id ~= nil and tostring(raw.Id) or HttpService:GenerateGUID(false)
        local record = byId[id] or { Id = id }
        for key, value in pairs(raw) do
            if key ~= "Id" then
                record[key] = value
            end
        end
        record.Name = tostring(record.Name or "Untitled")
        record.Author = tostring(record.Author or "Unknown")
        record.Description = record.Description ~= nil and tostring(record.Description) or ""
        local tags = {}
        for _, tag in ipairs(type(record.Tags) == "table" and record.Tags or {}) do
            table.insert(tags, tostring(tag))
        end
        record.Tags = tags
        record.Installs = tonumber(record.Installs) or 0
        record.Likes = tonumber(record.Likes) or 0
        record.Updated = tonumber(record.Updated or record.Created)
        record.Liked = record.Liked == true
        if type(record.Code) ~= "string" or record.Code == "" then
            record.Code = nil
        end
        record.Count = tonumber(record.Count) or countFlags(record.Code)
        record.Mine = record.Mine == true or tonumber(record.AuthorId) == LocalPlayer.UserId or tonumber(record.OwnerId) == LocalPlayer.UserId
        byId[id] = record
        return record
    end

    local function publicRecord(record)
        return {
            Id = record.Id,
            Name = record.Name,
            Description = record.Description,
            Author = record.Author,
            AuthorId = record.AuthorId,
            Tags = table.clone(record.Tags),
            Installs = record.Installs,
            Likes = record.Likes,
            Liked = record.Liked,
            Updated = record.Updated,
            Code = record.Code,
            Count = record.Count,
            Folder = record.Folder,
            Mine = record.Mine,
        }
    end

    -- What is kept locally for favorites and installs: no code, it is refetched.
    local function summary(record)
        local kept = publicRecord(record)
        kept.Code = nil
        kept.Liked = nil
        return kept
    end

    local function installState(record)
        local mark = installed[record.Id]
        if type(mark) ~= "table" then
            return nil
        end
        if record.Updated and tonumber(mark.Updated) and record.Updated > tonumber(mark.Updated) then
            return "Update"
        end
        return "Installed"
    end

    local function otherScript(record)
        return type(record.Folder) == "string" and record.Folder ~= window.ConfigFolder
    end

    -- Small pieces

    local function iconButton(parent, icon, glyph, size, plain)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(size, size),
            BackgroundColor3 = Theme.Surface2,
            BackgroundTransparency = plain and 1 or 0,
            Text = "",
            AutoButtonColor = false,
            Parent = parent,
        })
        corner(button, UDim.new(0, 8))
        if not plain then
            hoverStroke(button, stroke(button))
        end
        local image = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(15, 15),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Muted,
            ScaleType = Enum.ScaleType.Fit,
            Parent = button,
        })
        applyIcon(image, icon)
        if image.Image == "" then
            image:Destroy()
            image = label({
                Size = UDim2.fromScale(1, 1),
                Text = glyph,
                TextSize = 15,
                TextColor3 = Theme.Muted,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.None,
                Parent = button,
            })
        end
        return button, image
    end

    local function primary(button, text_)
        tween(button, { BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.12 }, 0)
        tween(text_, { TextColor3 = Theme.AccentDark }, 0)
        text_.FontFace = Fonts.Bold
    end

    local function clear(parent)
        for _, child in ipairs(parent:GetChildren()) do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
    end

    local function chip(parent, text, order, onClick)
        local button = create("TextButton", {
            Size = UDim2.fromOffset(0, CHIP),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Surface2,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = parent,
        })
        button:SetAttribute("NoDrag", true)
        corner(button, UDim.new(1, 0))
        local chipStroke = stroke(button)
        padding(button, 12, 12)
        local text_ = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = text,
            TextSize = 12,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Parent = button,
        })
        local object = { Button = button, Label = text_ }
        function object.Set(on, instant)
            local duration = instant and 0 or 0.15
            tween(button, { BackgroundColor3 = on and Theme.Accent or Theme.Surface2 }, duration)
            tween(text_, { TextColor3 = on and Theme.AccentDark or Theme.Muted }, duration)
            tween(chipStroke, { Transparency = on and 1 or 0 }, duration)
        end
        if onClick then
            button.MouseButton1Click:Connect(onClick)
        else
            button.Active = false
        end
        return object
    end

    local function tagPill(parent, text, order)
        local pill = label({
            Size = UDim2.fromOffset(0, 18),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 0.2,
            Text = text,
            TextSize = 11,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = order,
            Parent = parent,
        })
        corner(pill, UDim.new(0, 5))
        padding(pill, 7, 7)
        return pill
    end

    local function hlist(parent, gap, wraps)
        return create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, gap),
            Wraps = wraps == true,
            Parent = parent,
        })
    end

    local function vlist(parent, gap)
        return create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, gap),
            Parent = parent,
        })
    end

    local function wrapped(parent, text, size, color, order, font)
        return label({
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = text,
            TextSize = size,
            FontFace = font or Fonts.Regular,
            TextColor3 = color or Theme.Text,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            LayoutOrder = order,
            Parent = parent,
        })
    end

    local function scroller(parent, visible)
        local frame = create("ScrollingFrame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Theme.Accent,
            ScrollBarImageTransparency = 0.4,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            CanvasSize = UDim2.new(),
            Visible = visible ~= false,
            Parent = parent,
        })
        frame:SetAttribute("NoDrag", true)
        return frame
    end

    -- A text box on the surface colour. Multi-line boxes show a counter.
    local function field(parent, order, placeholder, height, limit)
        local multi = height > ROW
        local holder = create("Frame", {
            Size = UDim2.new(1, 0, 0, height),
            BackgroundColor3 = Theme.Surface,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            LayoutOrder = order,
            Parent = parent,
        })
        corner(holder, UDim.new(0, 8))
        local holderStroke = stroke(holder)
        local box = create("TextBox", {
            Position = UDim2.fromOffset(10, multi and 8 or 0),
            Size = UDim2.new(1, -20, 1, multi and -24 or 0),
            BackgroundTransparency = 1,
            Text = "",
            PlaceholderText = placeholder,
            PlaceholderColor3 = Theme.Muted,
            TextColor3 = Theme.Text,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
            MultiLine = multi,
            TextWrapped = multi,
            ClearTextOnFocus = false,
            Parent = holder,
        })
        local counter = multi and label({
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -10, 1, -4),
            Size = UDim2.fromOffset(0, 14),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 11,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            Parent = holder,
        })
        box.Focused:Connect(function()
            tween(holderStroke, { Color = Theme.StrokeHover }, 0.15)
        end)
        box.FocusLost:Connect(function()
            tween(holderStroke, { Color = Theme.Stroke }, 0.2)
        end)
        box:GetPropertyChangedSignal("Text"):Connect(function()
            local text = box.Text
            local length = utf8.len(text) or #text
            if limit and length > limit then
                local cut = utf8.offset(text, limit + 1)
                box.Text = cut and text:sub(1, cut - 1) or text:sub(1, limit)
                return
            end
            if counter then
                counter.Text = limit and (length .. "/" .. limit) or ""
            end
        end)
        if counter and limit then
            counter.Text = "0/" .. limit
        end
        return box, holderStroke
    end

    local function uniqueName(base)
        base = trim((tostring(base or ""):gsub('[\\/:%*%?"<>|]', "")))
        if base == "" then
            base = "Cloud config"
        end
        local name, index = base, 2
        while window:ConfigExists(name) do
            name = ("%s (%d)"):format(base, index)
            index += 1
        end
        return name
    end

    -- Layout: the page holds three views that slide over each other.

    local top = tab._headerBottom
    -- One pixel wider than the content on every side: root clips the slide,
    -- and the strokes along its edges would be clipped with it.
    local root = create("Frame", {
        Position = UDim2.fromOffset(23, top - 1),
        Size = UDim2.new(1, -46, 1, -(top + 14)),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Parent = tab._page,
    })
    for _, name in ipairs({ "Browse", "Detail", "Publish" }) do
        views[name] = create("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            Parent = root,
        })
        padding(views[name], 1, 1, 1, 1)
    end

    local function showView(view)
        if currentView == view then
            return
        end
        local previous = currentView
        currentView = view
        if previous then
            previous.Visible = false
        end
        local fromX = view == views.Browse and -24 or 24
        view.Position = UDim2.fromOffset(fromX, 0)
        view.Visible = true
        tween(view, { Position = UDim2.fromOffset(0, 0) }, 0.3, Enum.EasingStyle.Quint)
    end

    -- Browse: search, publish and refresh, the filter strip, then results.

    local browse = views.Browse
    local toolbar = create("Frame", {
        Size = UDim2.new(1, 0, 0, ROW),
        BackgroundTransparency = 1,
        Parent = browse,
    })
    local publishButton, publishText = softButton(toolbar, "Publish", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
    }, function()
        cloud:OpenPublish()
    end)
    primary(publishButton, publishText)
    publishButton.Visible = type(opts.OnPublish) == "function"
    local refreshButton, refreshIcon = iconButton(toolbar, "refresh-cw", "R", ROW)
    refreshButton.AnchorPoint = Vector2.new(1, 0)
    local searchHolder = create("Frame", {
        Size = UDim2.new(1, -(ROW + 8), 1, 0),
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Parent = toolbar,
    })
    corner(searchHolder, UDim.new(0, 8))
    local searchStroke = stroke(searchHolder)
    local searchIcon, searchImage = glowIcon(searchHolder, "search", Theme.Muted, UDim2.new(0, 10, 0.5, 0))
    searchIcon.Size = UDim2.fromOffset(14, 14)
    local searchBox = create("TextBox", {
        Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -62, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = opts.SearchPlaceholder or (TOUCH and "Search configs..." or "Search configs...   ( / )"),
        PlaceholderColor3 = Theme.Muted,
        TextColor3 = Theme.Text,
        TextSize = 13,
        FontFace = Fonts.Regular,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        ClipsDescendants = true,
        Parent = searchHolder,
    })
    local searchClear = iconButton(searchHolder, "x", "x", 24, true)
    searchClear.AnchorPoint = Vector2.new(1, 0.5)
    searchClear.Position = UDim2.new(1, -4, 0.5, 0)
    searchClear.Visible = false

    local fetch
    local searchToken = 0
    local recent = type(stored.CloudRecent) == "table" and stored.CloudRecent or {}
    local recentFrame = create("Frame", {
        Position = UDim2.fromOffset(0, ROW + 4),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Surface2,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 5,
        Parent = browse,
    })
    corner(recentFrame, UDim.new(0, 8))
    stroke(recentFrame)
    padding(recentFrame, 6, 6, 6, 6)
    vlist(recentFrame, 2)

    local function rememberSearch(text)
        text = trim(text)
        if #text < 2 then
            return
        end
        for index = #recent, 1, -1 do
            if string.lower(recent[index]) == string.lower(text) then
                table.remove(recent, index)
            end
        end
        table.insert(recent, 1, text)
        while #recent > 6 do
            table.remove(recent)
        end
        persist("CloudRecent", recent)
    end

    local function showRecent(show)
        show = show and #recent > 0 and searchBox.Text == ""
        if show == recentFrame.Visible then
            return
        end
        recentFrame.Visible = show
        if not show then
            return
        end
        clear(recentFrame)
        local header = create("Frame", {
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            LayoutOrder = 0,
            Parent = recentFrame,
        })
        label({
            Position = UDim2.fromOffset(8, 0),
            Size = UDim2.new(1, -60, 1, 0),
            Text = "Recent searches",
            TextSize = 11,
            TextColor3 = Theme.Muted,
            Parent = header,
        })
        local wipe = create("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -6, 0, 0),
            Size = UDim2.fromOffset(0, 20),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Text = "Clear",
            TextSize = 11,
            FontFace = Fonts.Medium,
            TextColor3 = Theme.Accent,
            AutoButtonColor = false,
            Parent = header,
        })
        wipe.MouseButton1Down:Connect(function()
            recent = {}
            persist("CloudRecent", recent)
            showRecent(false)
        end)
        for index, text in ipairs(recent) do
            local row = create("TextButton", {
                Size = UDim2.new(1, 0, 0, TOUCH and 32 or 28),
                BackgroundColor3 = Theme.Surface3,
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
                LayoutOrder = index,
                Parent = recentFrame,
            })
            corner(row, UDim.new(0, 6))
            local icon = glowIcon(row, "history", Theme.Muted, UDim2.new(0, 8, 0.5, 0))
            icon.Size = UDim2.fromOffset(13, 13)
            label({
                Position = UDim2.fromOffset(28, 0),
                Size = UDim2.new(1, -34, 1, 0),
                Text = text,
                TextSize = 13,
                FontFace = Fonts.Regular,
                Parent = row,
            })
            row.MouseEnter:Connect(function()
                tween(row, { BackgroundTransparency = 0.5 }, 0.1)
            end)
            row.MouseLeave:Connect(function()
                tween(row, { BackgroundTransparency = 1 }, 0.15)
            end)
            row.MouseButton1Down:Connect(function()
                searchToken += 1
                searchBox.Text = text
                query.Search = text
                rememberSearch(text)
                showRecent(false)
                searchBox:ReleaseFocus()
                fetch(false)
            end)
        end
    end

    local function fitToolbar()
        local scale = window.Scale.Scale
        local publishWidth = publishButton.Visible and (publishButton.AbsoluteSize.X / scale + 8) or 0
        refreshButton.Position = UDim2.new(1, -publishWidth, 0, 0)
        searchHolder.Size = UDim2.new(1, -(publishWidth + ROW + 8), 1, 0)
        recentFrame.Size = UDim2.new(1, -(publishWidth + ROW + 8), 0, 0)
    end
    publishButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitToolbar)
    task.defer(fitToolbar)

    -- A pixel taller than the chips on each side, so their strokes aren't clipped.
    local filterRow = create("Frame", {
        Position = UDim2.fromOffset(0, ROW + 7),
        Size = UDim2.new(1, 0, 0, CHIP + 2),
        BackgroundTransparency = 1,
        Parent = browse,
    })
    local sortButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -1, 0, 1),
        Size = UDim2.fromOffset(0, CHIP),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = Theme.Surface2,
        Text = "",
        AutoButtonColor = false,
        Parent = filterRow,
    })
    corner(sortButton, UDim.new(1, 0))
    hoverStroke(sortButton, stroke(sortButton))
    padding(sortButton, 10, 12)
    hlist(sortButton, 6)
    local sortIcon = glowIcon(sortButton, "arrow-down-up", Theme.Accent, UDim2.new())
    sortIcon.Size = UDim2.fromOffset(13, 13)
    local sortLabel = label({
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = SORT_NAMES[query.Sort],
        TextSize = 12,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        Parent = sortButton,
    })
    local filterStrip = create("ScrollingFrame", {
        Size = UDim2.new(1, -120, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.X,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.new(),
        Parent = filterRow,
    })
    filterStrip:SetAttribute("NoDrag", true)
    hlist(filterStrip, 6)
    padding(filterStrip, 1, 1, 1, 1)
    local function fitFilters()
        local width = sortButton.AbsoluteSize.X / window.Scale.Scale
        filterStrip.Size = UDim2.new(1, -(width + 8), 1, 0)
    end
    sortButton:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitFilters)
    task.defer(fitFilters)

    local resultsTop = ROW + 8 + CHIP + 10
    local results = scroller(browse)
    results.Position = UDim2.fromOffset(0, resultsTop)
    results.Size = UDim2.new(1, 0, 1, -resultsTop)
    padding(results, 1, 6, 1, 12)
    vlist(results, 10)
    local summaryRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 16),
        BackgroundTransparency = 1,
        LayoutOrder = 0,
        Parent = results,
    })
    local summaryLabel = label({
        Size = UDim2.new(1, -100, 1, 0),
        Text = "",
        RichText = true,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = summaryRow,
    })
    local resetButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Text = "Clear filters",
        TextSize = 12,
        FontFace = Fonts.Medium,
        TextColor3 = Theme.Accent,
        AutoButtonColor = false,
        Visible = false,
        Parent = summaryRow,
    })
    local resetFilters

    local function filtered()
        return query.Search ~= "" or query.Tag ~= nil or query.Filter ~= "All"
    end

    -- "12 configs in Favorites, tagged PvP, matching "boss"", or "Searching..."
    local function renderSummary(pending)
        local parts = {}
        if query.Filter ~= "All" then
            table.insert(parts, "in " .. query.Filter)
        end
        if query.Tag then
            table.insert(parts, "tagged " .. escape(query.Tag))
        end
        if query.Search ~= "" then
            table.insert(parts, ('matching <font color="#%s">"%s"</font>'):format(colorToHex(Theme.Accent), escape(query.Search)))
        end
        local context = #parts > 0 and (" " .. table.concat(parts, ", ")) or ""
        if pending or (loading and #records == 0) then
            summaryLabel.Text = "Searching" .. context .. "..."
        else
            local count = #records
            summaryLabel.Text = ("%d%s config%s%s"):format(count, hasMore and "+" or "", (count == 1 and not hasMore) and "" or "s", context)
        end
        resetButton.Visible = filtered()
    end

    local spin = nil
    local function busy(on)
        loading = on
        if on and not spin then
            refreshIcon.Rotation = 0
            spin = TweenService:Create(refreshIcon, TweenInfo.new(0.9, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 360 })
            spin:Play()
        elseif not on and spin then
            spin:Cancel()
            spin = nil
            tween(refreshIcon, { Rotation = 360 }, 0.35, Enum.EasingStyle.Quint)
        end
        renderSummary()
    end
    local grid = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = results,
    })
    local gridLayout = create("UIGridLayout", {
        CellSize = UDim2.new(1, 0, 0, CARD),
        CellPadding = UDim2.fromOffset(8, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = grid,
    })
    local function fitGrid()
        local width = results.AbsoluteSize.X / window.Scale.Scale
        local columns = width >= 620 and 2 or 1
        gridLayout.CellSize = UDim2.new(1 / columns, -(columns - 1) * 8 / columns, 0, CARD)
    end
    results:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitGrid)
    task.defer(fitGrid)
    local moreButton = softButton(results, "Load more", {
        Size = UDim2.new(1, 0, 0, 32),
        LayoutOrder = 2,
        Visible = false,
    }, function()
        cloud:LoadMore()
    end)
    local stateFrame = create("Frame", {
        Size = UDim2.new(1, 0, 0, 180),
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = 3,
        Parent = results,
    })

    -- Loading placeholders that pulse where cards will land.
    local skeletons = {}
    local function addSkeletons(count)
        for _ = 1, count do
            local cell = create("Frame", {
                BackgroundColor3 = Theme.Surface2,
                BorderSizePixel = 0,
                LayoutOrder = 100000 + #skeletons,
                Parent = grid,
            })
            corner(cell, UDim.new(0, 10))
            stroke(cell)
            for index, spec in ipairs({ { 14, 0.45 }, { 36, 0.3 }, { 58, 0.8 }, { 76, 0.6 } }) do
                local bar = create("Frame", {
                    Position = UDim2.fromOffset(14, spec[1]),
                    Size = UDim2.new(spec[2], -14, 0, index == 1 and 14 or 10),
                    BackgroundColor3 = Theme.Surface3,
                    BorderSizePixel = 0,
                    Parent = cell,
                })
                corner(bar, UDim.new(0, 4))
                TweenService:Create(bar, TweenInfo.new(0.75, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
                    BackgroundTransparency = 0.65,
                }):Play()
            end
            table.insert(skeletons, cell)
        end
    end
    local function clearSkeletons()
        for _, cell in ipairs(skeletons) do
            cell:Destroy()
        end
        skeletons = {}
    end

    -- kind: nil hides it, or "empty" / "error" with a message.
    local function setState(kind, text)
        clear(stateFrame)
        stateFrame.Visible = kind ~= nil
        if not kind then
            return
        end
        local holder, caption = emptyState(stateFrame, kind == "error" and "cloud-off" or "search-x", text)
        holder.Size = UDim2.fromOffset(280, 70)
        holder.Position = UDim2.new(0.5, 0, 0, 60)
        caption.TextWrapped = true
        caption.TextTruncate = Enum.TextTruncate.None
        caption.Size = UDim2.new(1, 0, 0, 32)
        if kind == "error" or filtered() then
            softButton(stateFrame, kind == "error" and "Try again" or "Clear filters", {
                AnchorPoint = Vector2.new(0.5, 0),
                Position = UDim2.new(0.5, 0, 0, 132),
                Size = UDim2.fromOffset(0, 30),
                AutomaticSize = Enum.AutomaticSize.X,
            }, function()
                if kind == "error" then
                    cloud:Refresh()
                else
                    resetFilters()
                end
            end)
        end
        renderSummary()
    end

    -- Cards

    local openDetail, installRecord, refreshRecord

    local function renderCard(card)
        local record = card.Record
        card.Title.Text = highlight(record.Name)
        local meta = { "by " .. record.Author }
        local when = ago(record.Updated)
        if when then
            table.insert(meta, when)
        end
        if record.Count then
            table.insert(meta, record.Count .. (record.Count == 1 and " setting" or " settings"))
        end
        card.Meta.Text = table.concat(meta, "  ·  ")
        card.Desc.Text = record.Description ~= "" and highlight(record.Description) or "No description"
        card.Desc.TextTransparency = record.Description ~= "" and 0.2 or 0.55
        card.Likes.Text = compact(record.Likes)
        card.Installs.Text = compact(record.Installs)
        tween(card.Heart, { ImageColor3 = record.Liked and Theme.Accent or Theme.Muted }, 0.15)
        local state = installState(record)
        local badge, color
        if state == "Update" then
            badge, color = "UPDATE", Theme.Accent
        elseif state == "Installed" then
            badge, color = "INSTALLED", Theme.Success
        elseif record.Mine then
            badge, color = "YOURS", Theme.Accent
        elseif otherScript(record) then
            badge, color = "OTHER SCRIPT", Theme.Warning
        end
        card.Badge.Visible = badge ~= nil
        if badge then
            card.Badge.Text = badge
            tween(card.Badge, { TextColor3 = color, BackgroundColor3 = color }, 0)
        end
        card.Star.Visible = favorites[record.Id] ~= nil
        card.InstallText.Text = state == "Update" and "Update" or (state == "Installed" and "Reinstall" or "Install")
        clear(card.TagRow)
        for index, tag in ipairs(record.Tags) do
            if index > 3 then
                tagPill(card.TagRow, "+" .. (#record.Tags - 3), index)
                break
            end
            tagPill(card.TagRow, tag, index)
        end
    end

    local function buildCard(record, order)
        local frame = create("TextButton", {
            BackgroundColor3 = Theme.Surface2,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = order,
            Parent = grid,
        })
        frame:SetAttribute("NoDrag", true)
        corner(frame, UDim.new(0, 10))
        hoverStroke(frame, stroke(frame))
        padding(frame, 14, 14, 12, 12)
        local card = { Record = record, Frame = frame }
        card.Title = label({
            Size = UDim2.new(1, -110, 0, 18),
            RichText = true,
            TextSize = 14,
            FontFace = Fonts.Bold,
            Parent = frame,
        })
        local corner_ = create("Frame", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.fromScale(1, 0),
            Size = UDim2.fromOffset(0, 18),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Parent = frame,
        })
        local cornerLayout = hlist(corner_, 6)
        cornerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
        card.Star = label({
            Size = UDim2.fromOffset(14, 18),
            Text = "★",
            TextSize = 13,
            TextColor3 = Theme.Accent,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 1,
            Parent = corner_,
        })
        card.Badge = label({
            Size = UDim2.fromOffset(0, 17),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 0.85,
            TextSize = 10,
            FontFace = Fonts.Bold,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = corner_,
        })
        corner(card.Badge, UDim.new(0, 5))
        padding(card.Badge, 6, 6)
        card.Meta = label({
            Position = UDim2.fromOffset(0, 20),
            Size = UDim2.new(1, 0, 0, 16),
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            Parent = frame,
        })
        card.Desc = label({
            Position = UDim2.fromOffset(0, 41),
            RichText = true,
            Size = UDim2.new(1, 0, 0, 30),
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextWrapped = true,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = frame,
        })
        local bottom = create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1,
            Parent = frame,
        })
        card.TagRow = create("Frame", {
            Size = UDim2.new(1, -190, 1, 0),
            BackgroundTransparency = 1,
            ClipsDescendants = true,
            Parent = bottom,
        })
        hlist(card.TagRow, 4)
        local install, installText = softButton(bottom, "Install", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(76, 26),
        }, function()
            installRecord(record)
        end)
        primary(install, installText)
        card.InstallText = installText
        local stats = create("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -86, 0.5, 0),
            Size = UDim2.fromOffset(0, 20),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Parent = bottom,
        })
        hlist(stats, 4)
        local function stat(icon, order_)
            local holder, image = glowIcon(stats, icon, Theme.Muted, UDim2.new())
            holder.Size = UDim2.fromOffset(12, 12)
            holder.LayoutOrder = order_
            local text_ = label({
                Size = UDim2.fromOffset(0, 20),
                AutomaticSize = Enum.AutomaticSize.X,
                TextSize = 12,
                TextColor3 = Theme.Muted,
                TextTruncate = Enum.TextTruncate.None,
                LayoutOrder = order_ + 1,
                Parent = stats,
            })
            return text_, image
        end
        card.Likes, card.Heart = stat("heart", 1)
        create("Frame", { Size = UDim2.fromOffset(4, 1), BackgroundTransparency = 1, LayoutOrder = 3, Parent = stats })
        card.Installs = stat("download", 4)
        local isTap = tapGuard(frame, function()
            return results
        end)
        frame.MouseButton1Click:Connect(function()
            if isTap() then
                if query.Search ~= "" then
                    rememberSearch(query.Search)
                end
                openDetail(record)
            end
        end)
        cards[record.Id] = card
        renderCard(card)
        return card
    end

    local function renderList()
        for _, card in pairs(cards) do
            card.Frame:Destroy()
        end
        cards = {}
        for index, record in ipairs(records) do
            buildCard(record, index)
        end
    end

    -- Favorites and Installed are kept on this device, so they filter locally.
    local function localRecords()
        local source = query.Filter == "Favorites" and favorites or installed
        local search = string.lower(query.Search)
        local list = {}
        for id, entry in pairs(source) do
            local kept = query.Filter == "Favorites" and entry or (type(entry) == "table" and entry.Record)
            if type(kept) == "table" then
                kept = table.clone(kept)
                kept.Id = id
                local record = normalizeRecord(kept)
                local matches = search == "" or string.find(string.lower(record.Name), search, 1, true)
                    or string.find(string.lower(record.Description), search, 1, true)
                if matches and query.Tag then
                    matches = table.find(record.Tags, query.Tag) ~= nil
                end
                if matches then
                    table.insert(list, record)
                end
            end
        end
        table.sort(list, function(a, b)
            if query.Sort == "New" then
                return (a.Updated or 0) > (b.Updated or 0)
            elseif query.Sort == "Installs" then
                return a.Installs > b.Installs
            end
            return a.Likes > b.Likes
        end)
        return list
    end

    local function emptyText()
        if query.Filter == "Favorites" then
            return "No favorites yet. Open a config and press Favorite to keep it here."
        elseif query.Filter == "Installed" then
            return "Nothing installed from the cloud yet"
        elseif query.Filter == "Mine" then
            return "You haven't published anything yet"
        elseif query.Search ~= "" or query.Tag then
            return "No configs match your search"
        end
        return tostring(opts.EmptyText or "No configs shared yet. Be the first!")
    end

    function fetch(more)
        token += 1
        local myToken = token
        if query.Filter == "Favorites" or query.Filter == "Installed" then
            busy(false)
            clearSkeletons()
            records = localRecords()
            hasMore = false
            renderList()
            moreButton.Visible = false
            setState(#records == 0 and "empty" or nil, emptyText())
            return
        end
        if type(opts.OnFetch) ~= "function" then
            renderList()
            setState(#records == 0 and "empty" or nil, emptyText())
            return
        end
        if more then
            if not hasMore then
                return
            end
            page += 1
        else
            page = 1
            records = {}
            renderList()
            results.CanvasPosition = Vector2.zero
        end
        busy(true)
        clearSkeletons()
        addSkeletons(more and 2 or 4)
        moreButton.Visible = false
        setState(nil)
        local fetchQuery = {
            Search = query.Search,
            Sort = query.Sort,
            Filter = query.Filter,
            Tag = query.Tag,
            Page = page,
            PageSize = pageSize,
            Folder = window.ConfigFolder,
            UserId = LocalPlayer.UserId,
        }
        task.spawn(function()
            local ok, list, extra = isolatedCall(function()
                return opts.OnFetch(fetchQuery)
            end)
            if myToken ~= token then
                return
            end
            busy(false)
            clearSkeletons()
            if not ok or type(list) ~= "table" then
                if more then
                    page -= 1
                end
                if not ok then
                    warn("[Aster UI] cloud OnFetch error: " .. tostring(list))
                end
                hasMore = more and hasMore or false
                moreButton.Visible = false
                setState("error", not ok and "Could not load configs" or tostring(extra or "Could not load configs"))
                return
            end
            hasMore = extra == true
            local seen = {}
            for _, record in ipairs(records) do
                seen[record] = true
            end
            for _, raw in ipairs(list) do
                local record = normalizeRecord(raw)
                if record and not seen[record] then
                    seen[record] = true
                    table.insert(records, record)
                    buildCard(record, #records)
                end
            end
            moreButton.Visible = hasMore
            setState(#records == 0 and "empty" or nil, emptyText())
        end)
    end

    -- Near the bottom, the next page loads by itself.
    results:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
        if not hasMore or loading then
            return
        end
        local scale = window.Scale.Scale
        local remaining = results.AbsoluteCanvasSize.Y / scale - results.AbsoluteWindowSize.Y / scale - results.CanvasPosition.Y
        if remaining < 160 then
            fetch(true)
        end
    end)

    -- Filters and sorting

    local filterChips, tagChips = {}, {}
    local function renderFilters(instant)
        for name, object in pairs(filterChips) do
            object.Set(query.Filter == name, instant)
        end
        for name, object in pairs(tagChips) do
            object.Set(query.Tag == name, instant)
        end
        sortLabel.Text = SORT_NAMES[query.Sort]
    end
    for index, name in ipairs(FILTERS) do
        if not (name == "Mine" and opts.MineFilter == false) then
            filterChips[name] = chip(filterStrip, name, index, function()
                if query.Filter ~= name then
                    query.Filter = name
                    renderFilters()
                    fetch(false)
                end
            end)
        end
    end
    if #tagList > 0 then
        create("Frame", {
            Size = UDim2.fromOffset(1, 16),
            BackgroundColor3 = Theme.Stroke,
            BorderSizePixel = 0,
            LayoutOrder = 10,
            Parent = filterStrip,
        })
    end
    for index, tag in ipairs(tagList) do
        tag = tostring(tag)
        tagChips[tag] = chip(filterStrip, tag, 10 + index, function()
            query.Tag = query.Tag ~= tag and tag or nil
            renderFilters()
            fetch(false)
        end)
    end
    sortButton.MouseButton1Click:Connect(function()
        local index = table.find(SORTS, query.Sort) or 1
        query.Sort = SORTS[index % #SORTS + 1]
        persist("CloudSort", query.Sort)
        renderFilters()
        fetch(false)
    end)

    function resetFilters()
        searchToken += 1
        searchBox.Text = ""
        query.Search, query.Tag, query.Filter = "", nil, "All"
        renderFilters()
        fetch(false)
    end
    resetButton.MouseButton1Click:Connect(resetFilters)

    -- Typing searches after a short pause; Enter searches now.
    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        searchClear.Visible = searchBox.Text ~= ""
        showRecent(searchBox:IsFocused())
        searchToken += 1
        local mine = searchToken
        local text = trim(searchBox.Text)
        if text ~= query.Search then
            renderSummary(true)
        end
        task.delay(0.35, function()
            text = trim(searchBox.Text)
            if mine == searchToken and text ~= query.Search then
                query.Search = text
                fetch(false)
            end
        end)
    end)
    searchBox.Focused:Connect(function()
        tween(searchStroke, { Color = Theme.Accent }, 0.15)
        tween(searchImage, { ImageColor3 = Theme.Accent }, 0.15)
        showRecent(true)
    end)
    searchBox.FocusLost:Connect(function(enterPressed)
        tween(searchStroke, { Color = Theme.Stroke }, 0.2)
        tween(searchImage, { ImageColor3 = Theme.Muted }, 0.2)
        rememberSearch(searchBox.Text)
        -- Late enough for a press on a recent search to land first.
        task.delay(0.15, function()
            if not searchBox:IsFocused() then
                showRecent(false)
            end
        end)
        if enterPressed then
            searchToken += 1
            local text = trim(searchBox.Text)
            if text ~= query.Search then
                query.Search = text
                fetch(false)
            end
        end
    end)
    searchClear.MouseButton1Click:Connect(function()
        searchToken += 1
        searchBox.Text = ""
        if query.Search ~= "" then
            query.Search = ""
            fetch(false)
        end
    end)
    -- "/" jumps to the search box while the list is showing.
    window:_listen("Began", function(input, processed)
        if processed or input.KeyCode ~= Enum.KeyCode.Slash then
            return
        end
        if window.Open and window.CurrentTab == tab and currentView == views.Browse and not UserInputService:GetFocusedTextBox() then
            task.defer(function()
                searchBox:CaptureFocus()
                searchBox.Text = searchBox.Text:gsub("/$", "")
            end)
        end
    end, cloud)
    refreshButton.MouseButton1Click:Connect(function()
        cloud:Refresh()
    end)

    -- Actions on a record

    -- Runs callback with the record's code, asking the backend for it first
    -- when the list came without codes.
    local function withCode(record, callback, onFail)
        if record.Code then
            callback(record.Code)
            return
        end
        local function fail(reason)
            if onFail then
                onFail(reason)
            else
                notify(false, "Could not load config", reason)
            end
        end
        if type(opts.OnFetchCode) ~= "function" then
            fail("This config has no code")
            return
        end
        task.spawn(function()
            local ok, code, reason = isolatedCall(function()
                return opts.OnFetchCode(publicRecord(record))
            end)
            if ok and type(code) == "string" and code ~= "" then
                record.Code = code
                record.Count = record.Count or countFlags(code)
                callback(code)
            else
                fail(tostring(reason or (not ok and "the request failed") or "no code came back"))
            end
        end)
    end

    function installRecord(record)
        if record._busy then
            return
        end
        record._busy = true
        withCode(record, function(code)
            record._busy = nil
            local data, info = window:DecodeConfig(code)
            if not data then
                notify(false, "Install failed", "The config code is invalid")
                return
            end
            local count = 0
            for _ in pairs(data) do
                count += 1
            end
            local mark = installed[record.Id]
            local saveAs = nil
            if fileApiAvailable() then
                -- An update overwrites the config it installed last time.
                saveAs = type(mark) == "table" and type(mark.Name) == "string" and window:ConfigExists(mark.Name) and mark.Name
                    or uniqueName(record.Name)
            end
            local other = info.Folder and info.Folder ~= window.ConfigFolder
            local function apply(save)
                local name = save and saveAs or nil
                local ok, err = window:ImportConfig(code, name, true)
                if not ok then
                    notify(false, "Install failed", tostring(err))
                    return
                end
                installed[record.Id] = { Updated = record.Updated or os.time(), Name = name, At = os.time(), Record = summary(record) }
                persist("CloudInstalled", installed)
                record.Installs += 1
                refreshRecord(record)
                notify(true, "Config installed", name and ("Saved as " .. name) or "Applied to your current settings")
                if opts.OnInstall then
                    task.spawn(safeCall, opts.OnInstall, publicRecord(record), name)
                end
            end
            local content = ("%s by %s changes %d setting%s."):format(record.Name, record.Author, count, count == 1 and "" or "s")
            if other then
                content ..= (" It was made for %s, so only matching settings apply."):format(info.Folder)
            end
            if saveAs then
                content ..= (" Install also saves it as %s; Apply only doesn't."):format(saveAs)
            end
            local buttons = { { Title = "Cancel" } }
            table.insert(buttons, { Title = "Apply only", Variant = not saveAs and "Primary" or nil, Callback = function()
                apply(false)
            end })
            if saveAs then
                table.insert(buttons, { Title = "Install", Variant = "Primary", Callback = function()
                    apply(true)
                end })
            end
            window:Dialog({
                Title = installState(record) == "Update" and "Update config" or "Install config",
                Content = content,
                Icon = other and "triangle-alert" or "download",
                Buttons = buttons,
            })
        end, function(reason)
            record._busy = nil
            notify(false, "Could not load config", reason)
        end)
    end

    local function toggleLike(record)
        if type(opts.OnLike) ~= "function" or record._liking then
            return
        end
        local liked = not record.Liked
        record.Liked = liked
        record.Likes = math.max(record.Likes + (liked and 1 or -1), 0)
        record._liking = true
        refreshRecord(record)
        task.spawn(function()
            local ok, result, reason = isolatedCall(function()
                return opts.OnLike(publicRecord(record), liked)
            end)
            record._liking = nil
            if not ok or result == false then
                record.Liked = not liked
                record.Likes = math.max(record.Likes + (liked and -1 or 1), 0)
                refreshRecord(record)
                notify(false, "Like not saved", tostring(reason or "Try again in a moment"))
            end
        end)
    end

    local function toggleFavorite(record)
        local on = favorites[record.Id] == nil
        favorites[record.Id] = on and summary(record) or nil
        persist("CloudFavorites", favorites)
        refreshRecord(record)
        window:Notify({
            Title = on and "Added to favorites" or "Removed from favorites",
            Content = record.Name,
            Icon = "star",
            Duration = 2,
        })
    end

    local function removeRecord(record)
        local index = table.find(records, record)
        if index then
            table.remove(records, index)
        end
        byId[record.Id] = nil
        local card = cards[record.Id]
        if card then
            card.Frame:Destroy()
            cards[record.Id] = nil
        end
        if #records == 0 and not loading then
            setState("empty", emptyText())
        end
    end

    local function deleteRecord(record)
        window:Confirm({
            Title = "Delete config",
            Content = ("Remove %s from the cloud? People who installed it keep their copy."):format(record.Name),
            Icon = "trash-2",
            ConfirmText = "Delete",
            Callback = function()
                task.spawn(function()
                    local ok, result, reason = isolatedCall(function()
                        return opts.OnDelete(publicRecord(record))
                    end)
                    if not ok or result == false then
                        notify(false, "Delete failed", tostring(reason or "Try again in a moment"))
                        return
                    end
                    favorites[record.Id] = nil
                    persist("CloudFavorites", favorites)
                    removeRecord(record)
                    showView(views.Browse)
                    notify(true, "Config deleted", record.Name)
                end)
            end,
        })
    end

    local function reportRecord(record)
        local reasons = type(opts.ReportReasons) == "table" and opts.ReportReasons or { "Broken", "Spam", "Inappropriate" }
        local buttons = { { Title = "Cancel" } }
        for _, reason in ipairs(reasons) do
            table.insert(buttons, { Title = tostring(reason), Callback = function()
                task.spawn(function()
                    local ok, result = isolatedCall(function()
                        return opts.OnReport(publicRecord(record), tostring(reason))
                    end)
                    local sent = ok and result ~= false
                    notify(sent, sent and "Report sent" or "Report failed", sent and "Thanks for letting us know" or "Try again in a moment")
                end)
            end })
        end
        window:Dialog({
            Title = "Report config",
            Content = ("What's wrong with %s?"):format(record.Name),
            Icon = "flag",
            Buttons = buttons,
        })
    end

    -- Detail view

    local detailList = scroller(views.Detail)
    padding(detailList, 1, 8, 1, 16)
    vlist(detailList, 10)

    local function valueText(entry)
        local value = type(entry) == "table" and entry.Value or nil
        if value == nil then
            return "None"
        elseif type(value) == "boolean" then
            return value and "On" or "Off"
        elseif type(value) == "number" then
            return (("%.2f"):format(value):gsub("%.?0+$", ""))
        elseif type(value) == "table" then
            if type(value.Hex) == "string" then
                return "#" .. string.upper(value.Hex)
            elseif type(value.Colors) == "table" then
                local text = type(value.Name) == "string" and value.Name or "Custom"
                if type(value.Background) == "string" and value.Background ~= "" then
                    text ..= ", image"
                end
                return text
            end
            local parts = {}
            for index, item in ipairs(value) do
                parts[index] = tostring(item)
            end
            return #parts > 0 and table.concat(parts, ", ") or "None"
        end
        return tostring(value)
    end

    local function encoded(entry)
        local ok, text = pcall(HttpService.JSONEncode, HttpService, type(entry) == "table" and entry.Value or nil)
        return ok and text or tostring(entry)
    end

    local function renderDetail()
        local record = detailRecord
        if not record or not detail.Meta then
            return
        end
        detail.Title.Text = record.Name
        local meta = { "by " .. record.Author }
        local when = ago(record.Updated)
        if when then
            table.insert(meta, "updated " .. when)
        end
        if otherScript(record) then
            table.insert(meta, "made for " .. record.Folder)
        end
        detail.Meta.Text = table.concat(meta, "  ·  ")
        detail.Stats.Text = ("%s like%s  ·  %s install%s"):format(
            compact(record.Likes), record.Likes == 1 and "" or "s",
            compact(record.Installs), record.Installs == 1 and "" or "s")
        if detail.BuiltFor ~= record or detail.BuiltMine ~= record.Mine then
            detail.BuiltFor, detail.BuiltMine = record, record.Mine
            local row = detail.Actions
            clear(row)
            local order = 0
            local function action(text, style, callback)
                order += 1
                local button, text_ = softButton(row, text, {
                    Size = UDim2.new(0, 0, 0, 30),
                    AutomaticSize = Enum.AutomaticSize.X,
                    LayoutOrder = order,
                }, callback)
                text_.TextSize = 13
                if style == "Primary" then
                    primary(button, text_)
                elseif style == "Danger" then
                    tween(text_, { TextColor3 = Theme.Error }, 0)
                end
                return text_
            end
            detail.InstallLabel = action("Install", "Primary", function()
                installRecord(record)
            end)
            if type(opts.OnLike) == "function" then
                detail.LikeLabel = action("Like", nil, function()
                    toggleLike(record)
                end)
            end
            detail.FavoriteLabel = action("Favorite", nil, function()
                toggleFavorite(record)
            end)
            action("Copy code", nil, function()
                withCode(record, function(code)
                    window:CopyToClipboard(code, "Config code")
                end)
            end)
            if record.Mine then
                if type(opts.OnUpdate) == "function" then
                    action("Edit", nil, function()
                        cloud:OpenPublish(record)
                    end)
                end
                if type(opts.OnDelete) == "function" then
                    action("Delete", "Danger", function()
                        deleteRecord(record)
                    end)
                end
            elseif type(opts.OnReport) == "function" then
                action("Report", "Danger", function()
                    reportRecord(record)
                end)
            end
        end
        local state = installState(record)
        detail.InstallLabel.Text = state == "Update" and "Update" or (state == "Installed" and "Reinstall" or "Install")
        if detail.LikeLabel then
            detail.LikeLabel.Text = (record.Liked and "Liked" or "Like") .. "  ·  " .. compact(record.Likes)
        end
        detail.FavoriteLabel.Text = favorites[record.Id] and "Favorited" or "Favorite"
    end

    -- Every setting in the config next to the player's own: changed ones
    -- first, then the same ones, then flags this script doesn't have.
    local function fillPreview(record, myToken)
        local function mismatch(text)
            if detailToken == myToken then
                detail.Summary.Text = text
            end
        end
        withCode(record, function(code)
            if detailToken ~= myToken then
                return
            end
            local data = window:DecodeConfig(code)
            if not data then
                mismatch("The config code is invalid")
                return
            end
            local current = collectFlags(window)
            local rows = {}
            local changed = 0
            for flag, entry in pairs(data) do
                local element = Library.Flags[flag]
                local known = element ~= nil
                local differs = known and encoded(entry) ~= encoded(current[flag])
                if differs then
                    changed += 1
                end
                table.insert(rows, {
                    Name = element and element._searchName ~= "" and element._searchName or flag,
                    Value = valueText(entry),
                    Known = known,
                    Changed = differs,
                    Rank = differs and 0 or (known and 1 or 2),
                })
            end
            table.sort(rows, function(a, b)
                if a.Rank ~= b.Rank then
                    return a.Rank < b.Rank
                end
                return string.lower(a.Name) < string.lower(b.Name)
            end)
            record.Count = #rows
            detail.Summary.Text = changed == 0 and ("%d settings, all the same as yours"):format(#rows)
                or ("%d settings, %d different from yours"):format(#rows, changed)
            clear(detail.Rows)
            for index, item in ipairs(rows) do
                if index > 150 then
                    wrapped(detail.Rows, ("and %d more"):format(#rows - 150), 12, Theme.Muted, index)
                    break
                end
                local rowFrame = create("Frame", {
                    Size = UDim2.new(1, 0, 0, 30),
                    BackgroundColor3 = Theme.Surface2,
                    BackgroundTransparency = item.Changed and 0 or 0.5,
                    BorderSizePixel = 0,
                    LayoutOrder = index,
                    Parent = detail.Rows,
                })
                corner(rowFrame, UDim.new(0, 7))
                if item.Changed then
                    local dot = create("Frame", {
                        AnchorPoint = Vector2.new(0, 0.5),
                        Position = UDim2.new(0, 10, 0.5, 0),
                        Size = UDim2.fromOffset(6, 6),
                        BackgroundColor3 = Theme.Accent,
                        BorderSizePixel = 0,
                        Parent = rowFrame,
                    })
                    corner(dot, UDim.new(1, 0))
                end
                label({
                    Position = UDim2.fromOffset(24, 0),
                    Size = UDim2.new(0.55, -24, 1, 0),
                    Text = item.Known and item.Name or (item.Name .. "  (not in this script)"),
                    TextSize = 12,
                    TextColor3 = item.Known and Theme.Text or Theme.Muted,
                    Parent = rowFrame,
                })
                label({
                    AnchorPoint = Vector2.new(1, 0),
                    Position = UDim2.new(1, -10, 0, 0),
                    Size = UDim2.new(0.45, -10, 1, 0),
                    Text = item.Value,
                    TextSize = 12,
                    FontFace = Fonts.Regular,
                    TextColor3 = item.Changed and Theme.Accent or Theme.Muted,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = rowFrame,
                })
            end
            if cards[record.Id] then
                renderCard(cards[record.Id])
            end
        end, mismatch)
    end

    function openDetail(record)
        detailRecord = record
        detailToken += 1
        local myToken = detailToken
        clear(detailList)
        detail = {}
        detailList.CanvasPosition = Vector2.zero
        softButton(detailList, "Back", {
            Size = UDim2.new(0, 0, 0, 28),
            AutomaticSize = Enum.AutomaticSize.X,
            LayoutOrder = 1,
        }, function()
            showView(views.Browse)
        end)
        detail.Title = wrapped(detailList, record.Name, 20, Theme.Text, 2, Fonts.Bold)
        detail.Meta = wrapped(detailList, "", 12, Theme.Muted, 3)
        if record.Description ~= "" then
            wrapped(detailList, record.Description, 13, Theme.Text, 4)
        end
        if #record.Tags > 0 then
            local tagsRow = create("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                LayoutOrder = 5,
                Parent = detailList,
            })
            hlist(tagsRow, 4, true)
            for index, tag in ipairs(record.Tags) do
                tagPill(tagsRow, tag, index)
            end
        end
        detail.Stats = wrapped(detailList, "", 12, Theme.Muted, 6)
        detail.Actions = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = 7,
            Parent = detailList,
        })
        hlist(detail.Actions, 6, true)
        create("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Stroke,
            BorderSizePixel = 0,
            LayoutOrder = 8,
            Parent = detailList,
        })
        wrapped(detailList, "Settings", 14, Theme.Text, 9, Fonts.Bold)
        detail.Summary = wrapped(detailList, "Loading settings...", 12, Theme.Muted, 10)
        detail.Rows = create("Frame", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            LayoutOrder = 11,
            Parent = detailList,
        })
        vlist(detail.Rows, 4)
        renderDetail()
        showView(views.Detail)
        fillPreview(record, myToken)
    end

    function refreshRecord(record)
        local card = cards[record.Id]
        if card then
            renderCard(card)
        end
        if detailRecord == record and currentView == views.Detail then
            renderDetail()
        end
    end

    -- Publish view: also the edit form for the player's own configs.

    local form = { Mode = "Publish", Record = nil, Source = false, Tags = {}, Busy = false }
    local publishList = scroller(views.Publish)
    padding(publishList, 1, 8, 1, 16)
    vlist(publishList, 8)
    softButton(publishList, "Back", {
        Size = UDim2.new(0, 0, 0, 28),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 1,
    }, function()
        showView(form.Mode == "Edit" and form.Record and views.Detail or views.Browse)
    end)
    local formTitle = wrapped(publishList, "Publish a config", 20, Theme.Text, 2, Fonts.Bold)
    wrapped(publishList, "Name", 12, Theme.Muted, 3)
    local nameBox = field(publishList, 4, "What is it for?", ROW, NAME_LIMIT)
    wrapped(publishList, "Description", 12, Theme.Muted, 5)
    local descBox = field(publishList, 6, "What does it do, and how should people use it?", 90, DESC_LIMIT)
    local tagsTitle = wrapped(publishList, "Tags", 12, Theme.Muted, 7)
    local tagsRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 8,
        Parent = publishList,
    })
    hlist(tagsRow, 6, true)
    tagsTitle.Visible = #tagList > 0 and maxTags > 0
    tagsRow.Visible = tagsTitle.Visible
    wrapped(publishList, "Settings to share", 12, Theme.Muted, 9)
    local sourceRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 10,
        Parent = publishList,
    })
    hlist(sourceRow, 6, true)
    local sourceSummary = wrapped(publishList, "", 12, Theme.Muted, 11)
    local identityNote = wrapped(publishList, "", 12, Theme.Muted, 12)
    local formError = wrapped(publishList, "", 12, Theme.Error, 13)
    formError.Visible = false
    local submitRow = create("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        LayoutOrder = 14,
        Parent = publishList,
    })
    hlist(submitRow, 6)
    local submitButton, submitText = softButton(submitRow, "Publish", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 1,
    }, function()
        cloud:_submit()
    end)
    primary(submitButton, submitText)
    softButton(submitRow, "Cancel", {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        LayoutOrder = 2,
    }, function()
        showView(form.Mode == "Edit" and form.Record and views.Detail or views.Browse)
    end)

    local formTagChips = {}
    local function renderFormTags()
        for tag, object in pairs(formTagChips) do
            object.Set(table.find(form.Tags, tag) ~= nil)
        end
        tagsTitle.Text = maxTags > 0 and ("Tags  (%d/%d)"):format(#form.Tags, maxTags) or "Tags"
    end
    for index, tag in ipairs(tagList) do
        tag = tostring(tag)
        formTagChips[tag] = chip(tagsRow, tag, index, function()
            local at = table.find(form.Tags, tag)
            if at then
                table.remove(form.Tags, at)
            elseif #form.Tags < maxTags then
                table.insert(form.Tags, tag)
            else
                notify(false, "Too many tags", ("Pick up to %d"):format(maxTags))
            end
            renderFormTags()
        end)
    end

    -- The code and setting count for the picked source, or nil and why not.
    local function sourceCode(name)
        if form.Source == "Keep" then
            return nil, form.Record and form.Record.Count
        elseif form.Source then
            local code, err = window:ExportConfig(form.Source)
            if not code then
                return nil, nil, err
            end
            return code, countFlags(code)
        end
        local ok, code = pcall(encodeConfig, window, name ~= "" and name or "Cloud config", collectFlags(window))
        if not ok then
            return nil, nil, "could not encode your settings"
        end
        return code, countFlags(code)
    end

    local sourceChips = {}
    local function renderSource()
        for key, object in pairs(sourceChips) do
            object.Set(key == (form.Source or "*current"))
        end
        local _, count, err = sourceCode(trim(nameBox.Text))
        if err then
            sourceSummary.Text = tostring(err)
        elseif form.Source == "Keep" then
            sourceSummary.Text = "Keeps the settings already published" .. (count and (" (" .. count .. ")") or "")
        else
            sourceSummary.Text = ("%d setting%s from %s"):format(count or 0, count == 1 and "" or "s", form.Source or "your current settings")
        end
    end

    local function buildSources()
        clear(sourceRow)
        sourceChips = {}
        local order = 0
        local function add(key, text)
            order += 1
            sourceChips[key] = chip(sourceRow, text, order, function()
                form.Source = key ~= "*current" and key or false
                renderSource()
            end)
        end
        if form.Mode == "Edit" then
            add("Keep", "Keep published settings")
        end
        add("*current", "Current settings")
        for _, name in ipairs(window:ListConfigs()) do
            add(name, name)
        end
        renderSource()
    end

    local function showError(text)
        formError.Text = tostring(text)
        formError.Visible = true
    end

    function cloud:OpenPublish(record)
        local editing = type(record) == "table" and record.Id and byId[record.Id] or nil
        if editing then
            form.Mode, form.Record = "Edit", editing
            form.Source = "Keep"
            form.Tags = table.clone(editing.Tags)
            nameBox.Text = editing.Name
            descBox.Text = editing.Description
        elseif form.Mode == "Edit" then
            -- Leaving an edit starts a fresh draft; a publish draft is kept.
            form.Mode, form.Record, form.Source, form.Tags = "Publish", nil, false, {}
            nameBox.Text = ""
            descBox.Text = ""
        end
        formTitle.Text = editing and "Edit config" or "Publish a config"
        submitText.Text = editing and "Save changes" or "Publish"
        formError.Visible = false
        local streamer = streamerOn()
        identityNote.Text = streamer and ("Your name is hidden, so you publish as " .. anonName)
            or ("You publish as " .. LocalPlayer.DisplayName)
        renderFormTags()
        buildSources()
        publishList.CanvasPosition = Vector2.zero
        showView(views.Publish)
    end

    nameBox:GetPropertyChangedSignal("Text"):Connect(function()
        formError.Visible = false
    end)

    function cloud:_submit()
        if form.Busy then
            return
        end
        local name = trim(nameBox.Text)
        if name == "" then
            showError("Give your config a name")
            return
        end
        local code, count, err = sourceCode(name)
        if err then
            showError(err)
            return
        end
        if form.Source ~= "Keep" and (count or 0) == 0 then
            showError("There are no settings to share")
            return
        end
        local editing = form.Mode == "Edit" and form.Record or nil
        local callback = editing and opts.OnUpdate or opts.OnPublish
        if type(callback) ~= "function" then
            showError(editing and "Editing isn't available" or "Publishing isn't available")
            return
        end
        local streamer = streamerOn()
        local payload = {
            Name = name,
            Description = trim(descBox.Text),
            Tags = table.clone(form.Tags),
            Code = code,
            Count = count,
            Folder = window.ConfigFolder,
            Author = streamer and anonName or LocalPlayer.DisplayName,
            AuthorId = not streamer and LocalPlayer.UserId or nil,
            OwnerId = LocalPlayer.UserId,
            Streamer = streamer,
        }
        form.Busy = true
        submitText.Text = editing and "Saving..." or "Publishing..."
        formError.Visible = false
        task.spawn(function()
            local ok, result, reason = isolatedCall(function()
                if editing then
                    return callback(publicRecord(editing), payload)
                end
                return callback(payload)
            end)
            form.Busy = false
            submitText.Text = editing and "Save changes" or "Publish"
            if not ok or result == false then
                if not ok then
                    warn("[Aster UI] cloud publish error: " .. tostring(result))
                end
                showError(ok and reason and tostring(reason) or "Something went wrong, try again")
                return
            end
            local merged = table.clone(payload)
            merged.Code = code or (editing and editing.Code)
            merged.Updated = os.time()
            if type(result) == "table" then
                for key, value in pairs(result) do
                    merged[key] = value
                end
            end
            if editing then
                merged.Id = editing.Id
                normalizeRecord(merged)
                if favorites[editing.Id] then
                    favorites[editing.Id] = summary(editing)
                    persist("CloudFavorites", favorites)
                end
                refreshRecord(editing)
                notify(true, "Config updated", name)
                openDetail(editing)
            else
                nameBox.Text = ""
                descBox.Text = ""
                form.Tags = {}
                form.Source = false
                if type(result) == "table" then
                    merged.Mine = true
                    local record = normalizeRecord(merged)
                    if query.Filter == "All" or query.Filter == "Mine" then
                        table.insert(records, 1, record)
                        renderList()
                        setState(nil)
                    end
                    notify(true, "Config published", name)
                    openDetail(record)
                else
                    notify(true, "Config published", name)
                    showView(views.Browse)
                    fetch(false)
                end
            end
        end)
    end

    -- Handle

    function cloud:Refresh()
        fetch(false)
    end

    function cloud:LoadMore()
        if not loading then
            fetch(true)
        end
    end

    -- For backends that push results instead of answering OnFetch.
    function cloud:SetConfigs(list, more)
        token += 1
        busy(false)
        clearSkeletons()
        records = {}
        for _, raw in ipairs(type(list) == "table" and list or {}) do
            local record = normalizeRecord(raw)
            if record then
                table.insert(records, record)
            end
        end
        hasMore = more == true
        renderList()
        moreButton.Visible = hasMore
        setState(#records == 0 and "empty" or nil, emptyText())
    end

    function cloud:AddConfigs(list, more)
        token += 1
        busy(false)
        clearSkeletons()
        for _, raw in ipairs(type(list) == "table" and list or {}) do
            local record = normalizeRecord(raw)
            if record and not table.find(records, record) then
                table.insert(records, record)
                buildCard(record, #records)
            end
        end
        hasMore = more == true
        moreButton.Visible = hasMore
        setState(#records == 0 and "empty" or nil, emptyText())
    end

    function cloud:UpdateConfig(id, changes)
        local record = byId[tostring(id)]
        if record and type(changes) == "table" then
            local merged = table.clone(changes)
            merged.Id = record.Id
            normalizeRecord(merged)
            refreshRecord(record)
        end
    end

    function cloud:RemoveConfig(id)
        local record = byId[tostring(id)]
        if record then
            removeRecord(record)
            if detailRecord == record and currentView == views.Detail then
                showView(views.Browse)
            end
        end
    end

    function cloud:SetLoading(on)
        token += 1
        busy(on == true)
        clearSkeletons()
        if loading then
            addSkeletons(4)
            setState(nil)
        end
    end

    function cloud:SetError(text)
        token += 1
        busy(false)
        clearSkeletons()
        setState(text and "error" or nil, tostring(text or ""))
    end

    function cloud:Open(id)
        local record = byId[tostring(id)]
        if record then
            window:SelectTab(tab)
            openDetail(record)
        end
    end

    function cloud:Back()
        showView(views.Browse)
    end

    function cloud:GetQuery()
        return table.clone(query)
    end

    function cloud:GetFavorites()
        local list = {}
        for id, kept in pairs(favorites) do
            local copy = table.clone(kept)
            copy.Id = id
            table.insert(list, copy)
        end
        return list
    end

    function cloud:GetInstalled()
        local list = {}
        for id, mark in pairs(installed) do
            table.insert(list, { Id = id, Name = mark.Name, Updated = mark.Updated, Record = mark.Record })
        end
        return list
    end

    renderFilters(true)
    showView(views.Browse)
    -- The first fetch waits until the tab is opened, so a hidden tab costs nothing.
    local fetched = false
    local function firstFetch()
        if not fetched and tab._page.Visible then
            fetched = true
            fetch(false)
        end
    end
    tab._page:GetPropertyChangedSignal("Visible"):Connect(firstFetch)
    if type(opts.OnFetch) ~= "function" then
        fetched = true
        setState("empty", emptyText())
    else
        task.defer(firstFetch)
    end
    return cloud
end

Window.CreateCloudConfigs = Window.CloudConfigs
Window.CloudConfig = Window.CloudConfigs
Window.CreateCloudConfig = Window.CloudConfigs

-- Tab badges were removed. These stay as no-ops so older scripts that call
-- them keep running.
function Tab:SetBadge() end

function Tab:GetBadge()
    return nil
end

function Window:Dialog(opts)
    opts = normalize(opts, { Text = "Content", Message = "Content" })
    if self._dialog then
        self._dialog.Close()
    end
    local WIDTH = 300
    local PAD = 18

    local overlay = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 40,
        Parent = self.Body,
    })
    local card = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 10),
        Size = UDim2.fromOffset(WIDTH, 120),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 41,
        Parent = overlay,
    })
    corner(card, UDim.new(0, 10))
    local cardStroke = stroke(card, Theme.Stroke, 1)
    local cardScale = create("UIScale", { Scale = 0.94, Parent = card })
    local fading = {}

    local titleOffset = 0
    if opts.Icon then
        local holder, image = glowIcon(card, opts.Icon, Theme.Accent, UDim2.new(0, PAD, 0, PAD + 9))
        image.ImageTransparency = 1
        holder.ZIndex = 42
        image.ZIndex = 42
        table.insert(fading, { image, "ImageTransparency", 0 })
        titleOffset = 24
    end
    local title = label({
        Position = UDim2.fromOffset(PAD + titleOffset, PAD),
        Size = UDim2.new(1, -(PAD * 2 + titleOffset), 0, 18),
        Text = opts.Title or "Are you sure?",
        TextSize = 15,
        TextTransparency = 1,
        ZIndex = 42,
        Parent = card,
    })
    table.insert(fading, { title, "TextTransparency", 0 })

    local contentHeight = 0
    if opts.Content then
        local content = label({
            Position = UDim2.fromOffset(PAD, PAD + 24),
            Size = UDim2.new(1, -PAD * 2, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = opts.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTransparency = 1,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 42,
            Parent = card,
        })
        table.insert(fading, { content, "TextTransparency", 0 })
        contentHeight = math.max(content.TextBounds.Y, 16) + 6
        content:GetPropertyChangedSignal("TextBounds"):Connect(function()
            local newHeight = math.max(content.TextBounds.Y, 16) + 6
            if newHeight ~= contentHeight then
                contentHeight = newHeight
                card.Size = UDim2.fromOffset(WIDTH, PAD + 24 + contentHeight + 12 + 34 + PAD)
                local rowFrame = card:FindFirstChild("ButtonRow")
                if rowFrame then
                    rowFrame.Position = UDim2.fromOffset(PAD, PAD + 24 + contentHeight + 12)
                end
            end
        end)
    end

    local row = create("Frame", {
        Name = "ButtonRow",
        Position = UDim2.fromOffset(PAD, PAD + 24 + contentHeight + 12),
        Size = UDim2.new(1, -PAD * 2, 0, 34),
        BackgroundTransparency = 1,
        ZIndex = 42,
        Parent = card,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = row,
    })
    card.Size = UDim2.fromOffset(WIDTH, PAD + 24 + contentHeight + 12 + 34 + PAD)

    local dialog = {}
    local closed = false
    function dialog.Close()
        if closed then
            return
        end
        closed = true
        if self._dialog == dialog then
            self._dialog = nil
        end
        tween(overlay, { BackgroundTransparency = 1 }, 0.18)
        tween(card, { BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 0.5, 8) }, 0.18, Enum.EasingStyle.Quint)
        tween(cardScale, { Scale = 0.96 }, 0.18, Enum.EasingStyle.Quint)
        tween(cardStroke, { Transparency = 1 }, 0.12)
        for _, entry in ipairs(fading) do
            tween(entry[1], { [entry[2]] = 1 }, 0.12)
        end
        task.delay(0.2, function()
            overlay:Destroy()
        end)
    end

    for index, spec in ipairs(opts.Buttons or {}) do
        local primary = spec.Variant == "Primary"
        local buttonFrame = create("TextButton", {
            Size = UDim2.fromOffset(0, 34),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = primary and Theme.Accent or Theme.Surface2,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            ClipsDescendants = true,
            LayoutOrder = index,
            ZIndex = 43,
            Parent = row,
        })
        corner(buttonFrame, UDim.new(0, 7))
        local buttonStroke = stroke(buttonFrame, primary and Theme.Accent or Theme.Stroke, 1)
        padding(buttonFrame, 14, 14)
        local text = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = spec.Title or spec.Name or "OK",
            TextSize = 13,
            TextColor3 = primary and Theme.AccentDark or Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTransparency = 1,
            ZIndex = 44,
            Parent = buttonFrame,
        })
        local restBg = primary and 0.12 or 0
        local restStroke = primary and 0.4 or 0
        table.insert(fading, { buttonFrame, "BackgroundTransparency", restBg })
        table.insert(fading, { buttonStroke, "Transparency", restStroke })
        table.insert(fading, { text, "TextTransparency", 0 })
        buttonFrame.MouseEnter:Connect(function()
            if closed then
                return
            end
            if primary then
                tween(buttonFrame, { BackgroundTransparency = 0 }, 0.12)
                tween(buttonStroke, { Transparency = 0 }, 0.12)
            else
                tween(buttonStroke, { Color = Theme.StrokeHover }, 0.12)
            end
        end)
        buttonFrame.MouseLeave:Connect(function()
            if closed then
                return
            end
            if primary then
                tween(buttonFrame, { BackgroundTransparency = restBg }, 0.2)
                tween(buttonStroke, { Transparency = restStroke }, 0.2)
            else
                tween(buttonStroke, { Color = Theme.Stroke }, 0.2)
            end
        end)
        buttonFrame.MouseButton1Click:Connect(function()
            dialog.Close()
            safeCall(spec.Callback)
        end)
    end

    if opts.CloseOnBackdrop ~= false then
        overlay.MouseButton1Click:Connect(function()
            dialog.Close()
            safeCall(opts.OnCancel)
        end)
    end

    self._dialog = dialog
    tween(overlay, { BackgroundTransparency = 0.45 }, 0.25)
    tween(card, { BackgroundTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }, 0.3, Enum.EasingStyle.Quint)
    tween(cardStroke, { Transparency = 0 }, 0.25)
    tween(cardScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
    for _, entry in ipairs(fading) do
        tween(entry[1], { [entry[2]] = entry[3] }, 0.25)
    end
    return dialog
end

function Window:Confirm(opts)
    opts = normalize(opts, { Text = "Content", Message = "Content" })
    return self:Dialog({
        Title = opts.Title or "Are you sure?",
        Content = opts.Content,
        Icon = opts.Icon,
        OnCancel = opts.OnCancel,
        Buttons = {
            { Title = opts.CancelText or "Cancel", Callback = opts.OnCancel },
            { Title = opts.ConfirmText or "Confirm", Variant = "Primary", Callback = opts.Callback },
        },
    })
end

function Window:_listen(kind, handler, owner)
    local list = self._inputListeners[kind]
    table.insert(list, handler)
    local function disconnect()
        for index, entry in ipairs(list) do
            if entry == handler then
                table.remove(list, index)
                break
            end
        end
    end
    if owner then
        owner._listeners = owner._listeners or {}
        table.insert(owner._listeners, disconnect)
    end
    return disconnect
end

function Window:_indicatorY(tab)
    local stack = self._tabStack
    return (tab._button.AbsolutePosition.Y - stack.AbsolutePosition.Y) / self.Scale.Scale + stack.Position.Y.Offset
end

function Window:_placeIndicator(tab)
    local indicator = self.Indicator
    local targetY = self:_indicatorY(tab)
    if not indicator.Visible then
        indicator.Visible = true
        indicator.Position = UDim2.fromOffset(8, targetY)
        indicator.BackgroundTransparency = 1
        tween(indicator, { BackgroundTransparency = 0.35 }, 0.3)
    end
    tween(indicator, { Position = UDim2.fromOffset(8, targetY) }, 0.45, Enum.EasingStyle.Quint)
end

-- While a tab list or sub tab strip runs past an end, that end gets a fade
-- and a small chip with a chevron and how many tabs are out of sight there.
-- Pressing the chip scrolls most of a view toward them.
function Window:_overflowHint(host, scroller, items, vertical, fadeColor)
    local overlay = create("Frame", {
        AnchorPoint = scroller.AnchorPoint,
        Position = scroller.Position,
        Size = scroller.Size,
        BackgroundTransparency = 1,
        ZIndex = 3,
        Parent = host,
    })
    local function mirror()
        overlay.Position = scroller.Position
        overlay.Size = scroller.Size
        overlay.Visible = scroller.Visible
    end
    for _, property in ipairs({ "Position", "Size", "Visible" }) do
        scroller:GetPropertyChangedSignal(property):Connect(mirror)
    end

    local function axis(vector)
        return vertical and vector.Y or vector.X
    end
    local function scale()
        return self.Scale and self.Scale.Scale or 1
    end
    local function scrollBy(direction)
        local view = axis(scroller.AbsoluteWindowSize) / scale()
        local limit = math.max(axis(scroller.AbsoluteCanvasSize) / scale() - view, 0)
        local target = math.clamp(axis(scroller.CanvasPosition) + direction * view * 0.75, 0, limit)
        tween(scroller, { CanvasPosition = vertical and Vector2.new(0, target) or Vector2.new(target, 0) }, 0.35, Enum.EasingStyle.Quint)
    end

    local hints = {}
    for _, direction in ipairs({ -1, 1 }) do
        local far = direction > 0
        local fade = create("Frame", {
            AnchorPoint = vertical and Vector2.new(0, far and 1 or 0) or Vector2.new(far and 1 or 0, 0),
            Position = vertical and UDim2.fromScale(0, far and 1 or 0) or UDim2.fromScale(far and 1 or 0, 0),
            Size = vertical and UDim2.new(1, 0, 0, 34) or UDim2.new(0, 48, 1, 0),
            BackgroundColor3 = fadeColor,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
            Parent = overlay,
        })
        create("UIGradient", {
            Rotation = vertical and (far and 270 or 90) or (far and 180 or 0),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(0.4, 0.2),
                NumberSequenceKeypoint.new(1, 1),
            }),
            Parent = fade,
        })
        local home = vertical and UDim2.new(0.5, 0, far and 1 or 0, far and -5 or 5) or UDim2.new(far and 1 or 0, far and -2 or 2, 0.5, 0)
        local chip = create("TextButton", {
            AnchorPoint = vertical and Vector2.new(0.5, far and 1 or 0) or Vector2.new(far and 1 or 0, 0.5),
            Position = home,
            Size = UDim2.fromOffset(0, 20),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Surface3,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Visible = false,
            ZIndex = 2,
            Parent = overlay,
        })
        corner(chip, UDim.new(1, 0))
        local chipStroke = stroke(chip, Theme.Stroke, 1)
        padding(chip, 7, 7)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 3),
            Parent = chip,
        })
        local arrow = create("ImageLabel", {
            Size = UDim2.fromOffset(12, 12),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Fit,
            LayoutOrder = 1,
            ZIndex = 2,
            Parent = chip,
        })
        applyIcon(arrow, vertical and (far and "chevron-down" or "chevron-up") or (far and "chevron-right" or "chevron-left"))
        local arrowFade = "ImageTransparency"
        if arrow.Image == "" then
            arrow:Destroy()
            arrow = label({
                Size = UDim2.fromOffset(10, 20),
                Text = "›",
                TextSize = 16,
                TextColor3 = Theme.Accent,
                TextTransparency = 1,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.None,
                Rotation = vertical and (far and 90 or -90) or (far and 0 or 180),
                LayoutOrder = 1,
                ZIndex = 2,
                Parent = chip,
            })
            arrowFade = "TextTransparency"
        end
        local count = label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 11,
            TextColor3 = Theme.Text,
            TextTransparency = 1,
            TextTruncate = Enum.TextTruncate.None,
            Visible = false,
            LayoutOrder = 2,
            ZIndex = 2,
            Parent = chip,
        })
        chip.MouseEnter:Connect(function()
            if not usingTouch() then
                tween(chipStroke, { Color = Theme.StrokeHover }, 0.12)
            end
        end)
        chip.MouseLeave:Connect(function()
            tween(chipStroke, { Color = Theme.Stroke }, 0.2)
        end)
        chip.MouseButton1Click:Connect(function()
            scrollBy(direction)
        end)
        hints[direction] = {
            Direction = direction,
            Fade = fade,
            Chip = chip,
            Stroke = chipStroke,
            Arrow = arrow,
            ArrowFade = arrowFade,
            Count = count,
            Home = home,
            Shown = false,
            Generation = 0,
        }
    end

    local function show(hint, on)
        if hint.Shown == on then
            return
        end
        hint.Shown = on
        hint.Generation += 1
        local away = hint.Home + (vertical and UDim2.fromOffset(0, hint.Direction * 6) or UDim2.fromOffset(hint.Direction * 6, 0))
        local value = on and 0 or 1
        if on then
            hint.Fade.Visible = true
            hint.Chip.Visible = true
            hint.Chip.Position = away
            tween(hint.Chip, { Position = hint.Home, BackgroundTransparency = 0.08 }, 0.3, Enum.EasingStyle.Quint)
        else
            tween(hint.Chip, { Position = away, BackgroundTransparency = 1 }, 0.2, Enum.EasingStyle.Quint)
            local generation = hint.Generation
            task.delay(0.21, function()
                if hint.Generation == generation then
                    hint.Fade.Visible = false
                    hint.Chip.Visible = false
                end
            end)
        end
        tween(hint.Fade, { BackgroundTransparency = value }, 0.2)
        tween(hint.Stroke, { Transparency = value }, 0.2)
        tween(hint.Arrow, { [hint.ArrowFade] = value }, 0.2)
        tween(hint.Count, { TextTransparency = value }, 0.2)
    end

    local function refresh()
        local view = axis(scroller.AbsoluteWindowSize)
        local overflow = (axis(scroller.AbsoluteCanvasSize) - view) / scale()
        local position = axis(scroller.CanvasPosition)
        local start = axis(scroller.AbsolutePosition)
        local before, after = 0, 0
        for _, item in ipairs(items:GetChildren()) do
            if item:IsA("GuiObject") and item.Visible and axis(item.AbsoluteSize) > 0 then
                local centre = axis(item.AbsolutePosition) + axis(item.AbsoluteSize) / 2 - start
                if centre < 0 then
                    before += 1
                elseif centre > view then
                    after += 1
                end
            end
        end
        for direction, hint in pairs(hints) do
            local hidden = direction < 0 and before or after
            hint.Count.Text = tostring(hidden)
            hint.Count.Visible = hidden > 0
            show(hint, overflow > 1 and (direction < 0 and position > 1 or direction > 0 and position < overflow - 1))
        end
    end
    for _, property in ipairs({ "CanvasPosition", "AbsoluteCanvasSize", "AbsoluteWindowSize" }) do
        scroller:GetPropertyChangedSignal(property):Connect(refresh)
    end
    task.defer(refresh)
end

function Window:_scrollTabIntoView(tab)
    local list = self.TabList
    local scale = self.Scale.Scale
    local top = (tab._button.AbsolutePosition.Y - list.AbsolutePosition.Y) / scale + list.CanvasPosition.Y
    local bottom = top + tab._button.AbsoluteSize.Y / scale
    local view = list.AbsoluteWindowSize.Y / scale
    local y = list.CanvasPosition.Y
    if top - 8 < y then
        y = top - 8
    elseif bottom + 8 > y + view then
        y = bottom + 8 - view
    else
        return
    end
    tween(list, { CanvasPosition = Vector2.new(0, math.max(0, y)) }, 0.35, Enum.EasingStyle.Quint)
end

function Window:_closePopups()
    if self._closePopup then
        self._closePopup()
    end
end

-- Popped-out groupboxes float on one screen-wide layer above the window. It
-- carries the window's scale, so a panel keeps the size it had in its column,
-- and it shows while the window is open (minimized included).
function Window:_popoutLayer()
    if self._popLayer then
        return self._popLayer
    end
    local layer = create("Frame", {
        Name = "PopOuts",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 20,
        Parent = self.Gui,
    })
    local layerScale = create("UIScale", { Parent = layer })
    self._popLayer = layer
    self._popPanels = {}
    self:_listen("Render", function()
        local scale = math.max(self.Scale.Scale, 0.05)
        if math.abs(layerScale.Scale - scale) > 1e-4 then
            layerScale.Scale = scale
            layer.Size = UDim2.fromScale(1 / scale, 1 / scale)
        end
        layer.Visible = self.Open == true and not self._destroyed
    end)
    return layer
end

-- Where a control's popup is drawn: the pop-out layer for one inside a
-- floating panel, otherwise the window body.
function Window:_popupHost(object)
    local layer = self._popLayer
    if layer and object and object:IsDescendantOf(layer) then
        return layer
    end
    return self.Body
end

-- A floating panel under the point counts as a control, so pressing it never
-- starts a window drag.
function Window:_overPopout(point)
    local layer = self._popLayer
    if not layer or not layer.Visible then
        return false
    end
    for _, panel in ipairs(self._popPanels) do
        if panel.Parent and panel.Visible and pointInside(point, panel) then
            return true
        end
    end
    return false
end

-- Fades the whole body by lending it to the fader CanvasGroup, then hands it
-- back to the root once fully shown so it renders directly again.
function Window:_fade(target, duration)
    local fader, body = self._fader, self.Body
    self._fadeGeneration = (self._fadeGeneration or 0) + 1
    local generation = self._fadeGeneration
    if body.Parent ~= fader then
        fader.GroupTransparency = self._bodyAlpha
        body.Parent = fader
    end
    fader.Visible = true
    self._bodyAlpha = target
    tween(fader, { GroupTransparency = target }, duration)
    task.delay(duration + 0.03, function()
        if self._fadeGeneration == generation and target <= 0 and not self._destroyed then
            body.Parent = self.Root
            fader.Visible = false
        end
    end)
end

function Window:SelectTab(tab)
    if self.CurrentTab == tab then
        return
    end
    local previous = self.CurrentTab
    self:_resetSearch()
    self:_closePopups()
    self.CurrentTab = tab

    self:_settleTransition()
    local generation = (self._transitionGeneration or 0) + 1
    self._transitionGeneration = generation

    if previous then
        tween(previous._label, { TextColor3 = Theme.Muted }, 0.3)
        if previous._icon then
            tintIcon(previous._icon, Theme.Muted, false, 0.3)
        end
        local outLayer = self._outLayer
        previous._page.Parent = outLayer
        self._outPage = previous._page
        outLayer.GroupTransparency = 0
        outLayer.Position = UDim2.fromOffset(0, 0)
        outLayer.Visible = true
        tween(outLayer, { GroupTransparency = 1, Position = UDim2.fromOffset(0, -6) }, 0.2, Enum.EasingStyle.Quint)
        task.delay(0.18, function()
            if self._transitionGeneration == generation then
                self:_settleOut()
            end
        end)
    end

    tween(tab._button, { BackgroundTransparency = 1 }, 0.2)
    tween(tab._stroke, { Transparency = 1 }, 0.2)
    tween(tab._label, { TextColor3 = Theme.Text }, 0.3)
    if tab._icon then
        tintIcon(tab._icon, Theme.Text, true, 0.3)
    end

    self:_placeIndicator(tab)
    self:_scrollTabIntoView(tab)

    local page = tab._page
    page.Position = UDim2.fromOffset(0, 0)
    page.Visible = true
    page.Parent = self._inLayer
    self._inPage = page
    fadeSlideIn(self._inLayer)
    task.delay(0.32, function()
        if self._transitionGeneration == generation then
            self:_settleIn()
        end
    end)
end

function Window:_settleOut()
    local page = self._outPage
    if page then
        page.Parent = self.Content
        page.Visible = false
        self._outPage = nil
    end
    self._outLayer.Visible = false
end

function Window:_settleIn()
    local page = self._inPage
    if page then
        page.Parent = self.Content
        page.Position = UDim2.fromOffset(0, 0)
        self._inPage = nil
    end
    self._inLayer.Visible = false
end

function Window:_settleTransition()
    self:_settleOut()
    self:_settleIn()
end

-- Backdrop: a black tint over the game while the window is up, with an
-- optional weather layer (rain, snow or hell fire embers) drifting through it.
-- It fades out when the window is minimized or hidden and sweeps back in with
-- a gust when it comes back.

local WEATHER = {
    -- The rain texture is a wide sheet with one faint streak down the middle
    -- (about 1/60 of its width, 57% of its height), so it is stretched much
    -- wider than the drop it draws. See RAIN_STREAK.
    Rain = { Image = "rbxassetid://241868005", Count = 90, Stretch = true },
    Snow = { Image = "rbxassetid://99851851", Count = 60 },
    Ember = { Image = "rbxassetid://242205518", Count = 55 },
    -- Drawn with plain frames and text, no images: petals are tinted pills
    -- that flip as they fall, matrix columns are text strips.
    Sakura = { Petal = true, Count = 46, Glow = Color3.fromRGB(255, 150, 190), GlowAmount = 0.1 },
    Fireflies = { Image = Assets.Glow, Count = 34, Glow = Color3.fromRGB(70, 150, 60), GlowAmount = 0.16 },
    Matrix = {
        Text = true,
        Count = 38,
        Glow = Color3.fromRGB(30, 200, 90),
        GlowAmount = 0.07,
        Glyphs = "01234567890123456789アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン+-*=<>:",
    },
}
local WEATHER_NAMES = {
    rain = "Rain",
    snow = "Snow",
    ember = "Ember",
    embers = "Ember",
    fire = "Ember",
    hellfire = "Ember",
    sakura = "Sakura",
    petals = "Sakura",
    cherryblossom = "Sakura",
    firefly = "Fireflies",
    fireflies = "Fireflies",
    matrix = "Matrix",
    matrixrain = "Matrix",
    code = "Matrix",
}
local RAIN_STREAK = Vector2.new(7 / 420, 151 / 263)
local weatherRandom = Random.new()

-- "UI" keeps the weather inside the window, behind its content; anything
-- else drifts it across the whole screen.
local function weatherMode(mode)
    if type(mode) == "string" and ({ ui = true, window = true, inside = true })[mode:lower()] then
        return "UI"
    end
    return "Screen"
end

local function weatherName(name)
    if type(name) ~= "string" then
        return "None"
    end
    return WEATHER_NAMES[(name:lower():gsub("[%s_%-]", ""))] or "None"
end

local function roll(min, max)
    return weatherRandom:NextNumber(min, max)
end

-- Places a particle. `anywhere` scatters it over the whole screen (first
-- frame after the backdrop appears), otherwise it enters from its edge.
local function seedParticle(kind, particle, width, height, anywhere)
    particle.Time = roll(0, 10)
    particle.Phase = roll(0, math.pi * 2)
    if kind == "Rain" then
        local w = roll(2, 3.5)
        particle.Size = Vector2.new(w, roll(26, 52))
        particle.VY = roll(950, 1400)
        particle.VX = particle.VY * 0.12
        particle.Sway, particle.Spin = 0, 0
        particle.Rotation = -math.deg(math.atan2(particle.VX, particle.VY))
        particle.Alpha = roll(0, 0.35)
        particle.X = roll(-0.15 * width, width)
        particle.Y = anywhere and roll(-40, height) or roll(-120, -particle.Size.Y)
    elseif kind == "Snow" then
        local s = roll(6, 17)
        particle.Size = Vector2.new(s, s)
        particle.VY = roll(30, 55) * (0.6 + s / 17)
        particle.VX = roll(-8, 14)
        particle.Sway = roll(12, 38)
        particle.Frequency = roll(0.5, 1.3)
        particle.Spin = roll(-60, 60)
        particle.Rotation = roll(0, 360)
        particle.Alpha = roll(0.05, 0.45)
        particle.X = roll(0, width)
        particle.Y = anywhere and roll(-20, height) or roll(-60, -s)
    elseif kind == "Sakura" then
        local s = roll(7, 14)
        particle.Size = Vector2.new(s, s * roll(0.55, 0.75))
        particle.VY = roll(35, 70)
        particle.VX = roll(18, 45)
        particle.Sway = roll(14, 34)
        particle.Frequency = roll(0.6, 1.4)
        particle.Flutter = roll(1.2, 2.6)
        particle.Spin = roll(-90, 90)
        particle.Rotation = roll(0, 360)
        particle.Alpha = roll(0.05, 0.35)
        particle.Color = Color3.fromRGB(255, 205, 220):Lerp(Color3.fromRGB(255, 140, 180), roll(0, 1))
        particle.X = roll(-0.25 * width, width)
        particle.Y = anywhere and roll(-20, height) or roll(-60, -s)
    elseif kind == "Fireflies" then
        -- They wander instead of crossing the screen, and live a few seconds:
        -- fade in, pulse, fade out, then turn up somewhere else.
        local s = roll(14, 28)
        particle.Size = Vector2.new(s, s)
        particle.VY = roll(-14, 8)
        particle.VX = roll(-12, 12)
        particle.Sway = roll(10, 30)
        particle.SwayY = roll(8, 22)
        particle.Frequency = roll(0.3, 0.8)
        particle.Spin, particle.Rotation = 0, 0
        particle.Alpha = roll(0, 0.25)
        particle.Life = roll(5, 11)
        particle.Age = anywhere and roll(0, particle.Life) or 0
        particle.Pulse = roll(1.5, 3.5)
        particle.Color = Color3.fromRGB(200, 255, 120):Lerp(Color3.fromRGB(255, 230, 120), roll(0, 1))
        particle.X = roll(0, width)
        particle.Y = roll(height * 0.15, height)
    elseif kind == "Matrix" then
        local definition = WEATHER.Matrix
        if not definition.List then
            definition.List = {}
            for _, code in utf8.codes(definition.Glyphs) do
                table.insert(definition.List, utf8.char(code))
            end
        end
        local list = definition.List
        local s = math.floor(roll(12, 19))
        local length = math.floor(roll(8, 20))
        particle.TextSize = s
        particle.Size = Vector2.new(s + 6, s * length)
        particle.VY = roll(160, 360) * (s / 15)
        particle.VX, particle.Sway, particle.Spin, particle.Rotation = 0, 0, 0, 0
        -- Smaller columns read as further away: dimmer.
        particle.Alpha = roll(0, 0.25) + (19 - s) * 0.04
        particle.X = math.floor(roll(0, width) / 18) * 18 + 9
        particle.Y = anywhere and roll(-particle.Size.Y / 2, height) or -particle.Size.Y / 2 - roll(0, 240)
        particle.Chars = {}
        for index = 1, length do
            particle.Chars[index] = list[math.random(#list)]
        end
        particle.Shuffle = roll(0.05, 0.2)
    else
        local s = roll(4, 12)
        particle.Size = Vector2.new(s, s)
        particle.VY = -roll(60, 170)
        particle.VX = roll(-12, 12)
        particle.Sway = roll(8, 28)
        particle.Frequency = roll(1, 2.4)
        particle.Spin = roll(-140, 140)
        particle.Rotation = roll(0, 360)
        particle.Alpha = roll(0, 0.3)
        particle.Color = Color3.fromRGB(255, 70, 20):Lerp(Color3.fromRGB(255, 190, 70), roll(0, 1))
        particle.X = roll(0, width)
        particle.Y = anywhere and roll(height * 0.2, height + 10) or height + roll(10, 80)
    end
    local label = particle.Label
    if kind == "Rain" then
        label.Size = UDim2.fromOffset(particle.Size.X / RAIN_STREAK.X, particle.Size.Y / RAIN_STREAK.Y)
    else
        label.Size = UDim2.fromOffset(particle.Size.X, particle.Size.Y)
    end
    if kind == "Matrix" then
        label.TextSize = particle.TextSize
        label.Text = table.concat(particle.Chars, "\n")
    elseif kind == "Sakura" then
        label.BackgroundColor3 = particle.Color
    else
        label.ImageColor3 = particle.Color
            or (kind == "Rain" and Color3.fromRGB(190, 210, 245) or Color3.new(1, 1, 1))
    end
end

function Window:_buildBackdrop(opts)
    local layer = create("Frame", {
        Name = "Backdrop",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
        ZIndex = 0,
        Parent = self.Gui,
    })
    local tint = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 0,
        Parent = layer,
    })
    -- Darker towards the top and bottom edges.
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.5, 0.3),
            NumberSequenceKeypoint.new(1, 0),
        }),
        Parent = tint,
    })
    -- Heat rising from the bottom of the screen, hell fire only.
    local heat = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.fromScale(0, 1),
        Size = UDim2.fromScale(1, 0.5),
        BackgroundColor3 = Color3.fromRGB(255, 60, 15),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 1,
        Parent = layer,
    })
    create("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new(1, 0),
        Parent = heat,
    })
    -- Holds the heat and the particles so both move together between the
    -- screen and the window.
    local field = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = layer,
    })
    heat.Parent = field
    self._backdrop = layer
    self._backdropTintFrame = tint
    self._backdropHeat = heat
    self._weatherField = field
    self._weatherParticles = {}
    self._backdropFade = 0
    self._weatherKick = 0
    self._backdropShown = false
    self._backdropEnabled = opts.Enabled ~= false
    self._backdropTint = math.clamp(tonumber(opts.Tint) or 0.45, 0, 1)
    self._backdropDim = opts.Dim ~= false
    self._dimLevel = self._backdropDim and 1 or 0
    self._weatherDensity = math.clamp(tonumber(opts.Density) or 1, 0, 3)
    self._weatherSpeed = math.clamp(tonumber(opts.Speed) or 1, 0.1, 3)
    self.Weather = weatherName(opts.Weather == nil and "Matrix" or opts.Weather)
    self.WeatherMode = "Screen"
    self:SetWeatherMode(opts.Mode)
    self:_rebuildWeather()
    table.insert(self._frameSteps, function(deltaTime)
        self:_stepBackdrop(deltaTime)
    end)
end

-- The area the particles cover, in the field's own (unscaled) units.
function Window:_weatherSize()
    if self.WeatherMode == "UI" then
        return Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset)
    end
    return self.Gui.AbsoluteSize
end

function Window:_rebuildWeather()
    for _, particle in ipairs(self._weatherParticles) do
        particle.Label:Destroy()
    end
    self._weatherParticles = {}
    local definition = WEATHER[self.Weather]
    if not definition then
        return
    end
    -- The glow along the bottom: red heat for hell fire, a soft tint for the
    -- others that ask for one.
    self._backdropHeat.BackgroundColor3 = definition.Glow or Color3.fromRGB(255, 60, 15)
    local size = self:_weatherSize()
    -- The window is a fraction of the screen, so it gets fewer particles.
    local count = definition.Count * self._weatherDensity * (self.WeatherMode == "UI" and 0.45 or 1)
    for _ = 1, math.floor(count + 0.5) do
        local instance, property
        if definition.Text then
            property = "TextTransparency"
            instance = create("TextLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1,
                Text = "",
                TextColor3 = Color3.fromRGB(90, 255, 140),
                TextTransparency = 1,
                FontFace = Font.fromEnum(Enum.Font.Code),
                TextXAlignment = Enum.TextXAlignment.Center,
                TextYAlignment = Enum.TextYAlignment.Top,
                LineHeight = 1,
                ZIndex = 2,
                Parent = self._weatherField,
            })
            -- A fading tail and a pale leading glyph.
            create("UIGradient", {
                Rotation = 90,
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                    ColorSequenceKeypoint.new(0.88, Color3.new(1, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 255, 240)),
                }),
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1),
                    NumberSequenceKeypoint.new(0.6, 0.45),
                    NumberSequenceKeypoint.new(1, 0),
                }),
                Parent = instance,
            })
        elseif definition.Petal then
            property = "BackgroundTransparency"
            instance = create("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundColor3 = Color3.fromRGB(255, 190, 210),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = 2,
                Parent = self._weatherField,
            })
            corner(instance, UDim.new(1, 0))
            create("UIGradient", {
                Rotation = 35,
                Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(235, 200, 215)),
                Parent = instance,
            })
        else
            property = "ImageTransparency"
            instance = create("ImageLabel", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1,
                Image = definition.Image,
                ImageTransparency = 1,
                ScaleType = definition.Stretch and Enum.ScaleType.Stretch or Enum.ScaleType.Fit,
                ZIndex = 2,
                Parent = self._weatherField,
            })
        end
        local particle = { Label = instance, Property = property }
        seedParticle(self.Weather, particle, size.X, size.Y, true)
        table.insert(self._weatherParticles, particle)
    end
end

function Window:_stepBackdrop(deltaTime)
    local target = self._backdropShown and 1 or 0
    local fade = self._backdropFade
    if fade == target and target == 0 then
        return
    end
    if fade < target then
        fade = math.min(fade + deltaTime / 0.45, target)
    elseif fade > target then
        fade = math.max(fade - deltaTime / 0.25, target)
    end
    self._backdropFade = fade
    if fade <= 0 then
        self._backdrop.Visible = false
        self._weatherField.Visible = false
        return
    end
    local eased = 1 - (1 - fade) ^ 3
    local kind = self.Weather
    -- The dim eases on its own so turning it off doesn't touch the weather.
    local dim = self._dimLevel
    if self._backdropDim then
        dim = math.min(dim + deltaTime / 0.3, 1)
    else
        dim = math.max(dim - deltaTime / 0.3, 0)
    end
    self._dimLevel = dim
    self._backdropTintFrame.BackgroundTransparency = 1 - self._backdropTint * eased * dim
    local definition = WEATHER[kind]
    self._backdropHeat.BackgroundTransparency = kind == "Ember"
        and 1 - (0.22 + math.sin(os.clock() * 2.1) * 0.05) * eased
        or definition and definition.GlowAmount and 1 - (definition.GlowAmount + math.sin(os.clock() * 0.8) * definition.GlowAmount * 0.25) * eased
        or 1

    -- The gust on restore: particles rush in fast and settle back.
    local kick = self._weatherKick
    self._weatherKick = math.max(kick - deltaTime * 1.3, 0)
    local speed = self._weatherSpeed * (1 + kick * kick * 2.5)
    local size = self:_weatherSize()
    local width, height = size.X, size.Y
    for _, particle in ipairs(self._weatherParticles) do
        particle.Time += deltaTime
        particle.X += particle.VX * deltaTime * speed
        particle.Y += particle.VY * deltaTime * speed
        particle.Rotation += particle.Spin * deltaTime * speed
        local margin = math.max(particle.Size.X, particle.Size.Y)
        if particle.Life then
            particle.Age += deltaTime
        end
        if (particle.Life and particle.Age > particle.Life)
            or (not particle.Life and ((particle.VY > 0 and particle.Y > height + margin) or (particle.VY < 0 and particle.Y < -margin))) then
            seedParticle(kind, particle, width, height, false)
        elseif particle.X > width + margin * 4 then
            particle.X -= width + margin * 6
        elseif particle.X < -margin * 4 then
            particle.X += width + margin * 6
        end
        local x = particle.X
        local alpha = 1 - particle.Alpha
        if particle.Sway ~= 0 then
            x += math.sin(particle.Time * particle.Frequency + particle.Phase) * particle.Sway
        end
        local y = particle.Y
        local label = particle.Label
        if kind == "Ember" then
            -- Flicker, and burn out on the way up.
            alpha *= math.clamp(particle.Y / (height * 0.85), 0, 1) ^ 0.6
            alpha *= 0.75 + math.sin(particle.Time * 9 + particle.Phase) * 0.25
        elseif kind == "Sakura" then
            -- Flip: the petal narrows and widens as it turns over.
            local turn = math.abs(math.cos(particle.Time * particle.Flutter + particle.Phase))
            label.Size = UDim2.fromOffset(particle.Size.X * (0.3 + turn * 0.7), particle.Size.Y)
        elseif kind == "Fireflies" then
            y += math.cos(particle.Time * particle.Frequency * 1.3 + particle.Phase) * particle.SwayY
            local age, life = particle.Age, particle.Life
            alpha *= math.clamp(math.min(age / 1.2, (life - age) / 1.2), 0, 1)
            alpha *= 0.5 + math.sin(particle.Time * particle.Pulse + particle.Phase) * 0.5
        elseif kind == "Matrix" then
            particle.Shuffle -= deltaTime * speed
            if particle.Shuffle <= 0 then
                particle.Shuffle = roll(0.05, 0.2)
                local list = WEATHER.Matrix.List
                local chars = particle.Chars
                chars[math.random(#chars)] = list[math.random(#list)]
                chars[#chars] = list[math.random(#list)]
                label.Text = table.concat(chars, "\n")
            end
        end
        label.Position = UDim2.fromOffset(x, y)
        label.Rotation = particle.Rotation
        label[particle.Property or "ImageTransparency"] = 1 - alpha * eased
    end
end

function Window:_refreshBackdrop(gust)
    if not self._backdrop then
        return
    end
    local shown = self._backdropEnabled and self._introDone and self.Open and not self.Minimized and not self._destroyed
    if shown and not self._backdropShown then
        self._backdrop.Visible = true
        self._weatherField.Visible = true
        if self._backdropFade <= 0 then
            local size = self:_weatherSize()
            for _, particle in ipairs(self._weatherParticles) do
                seedParticle(self.Weather, particle, size.X, size.Y, true)
            end
        end
        if gust then
            self._weatherKick = 1
        end
    end
    self._backdropShown = shown == true
end

function Window:SetBackdrop(enabled)
    if not self._backdrop then
        return
    end
    self._backdropEnabled = enabled ~= false
    local toggle = self._interfaceBackdropToggle
    if toggle and not toggle._destroyed then
        toggle:Set(self._backdropEnabled, true)
    end
    self:_refreshBackdrop(true)
end

function Window:SetBackdropTint(amount)
    if not self._backdrop then
        return
    end
    self._backdropTint = math.clamp(tonumber(amount) or 0.45, 0, 1)
end

-- Turns the black tint on or off, leaving the weather running.
function Window:SetDim(enabled)
    if not self._backdrop then
        return
    end
    self._backdropDim = enabled ~= false
end

function Window:SetWeatherMode(mode)
    if not self._backdrop then
        return
    end
    mode = weatherMode(mode)
    local field = self._weatherField
    if mode == "UI" then
        -- Under everything else in the body: sidebar, content and glows.
        field.ZIndex = 0
        field.Parent = self.Body
    else
        field.ZIndex = 2
        field.Parent = self._backdrop
    end
    if mode == self.WeatherMode then
        return
    end
    self.WeatherMode = mode
    self:_rebuildWeather()
    if self._backdropShown then
        self._weatherKick = 1
    end
end

function Window:SetWeather(name)
    if not self._backdrop then
        return
    end
    local kind = weatherName(name)
    if kind == self.Weather then
        return
    end
    self.Weather = kind
    self:_rebuildWeather()
    if self._backdropShown then
        self._weatherKick = 1
    end
end

function Window:SetWeatherDensity(density)
    if not self._backdrop then
        return
    end
    self._weatherDensity = math.clamp(tonumber(density) or 1, 0, 3)
    self:_rebuildWeather()
end

function Window:SetWeatherSpeed(speed)
    if not self._backdrop then
        return
    end
    self._weatherSpeed = math.clamp(tonumber(speed) or 1, 0.1, 3)
end

-- Minimize: the window folds into a Dynamic Island style pill hanging from
-- the top of the screen. Compact, it shows the logo and a live meter of
-- running toggles. Hovering springs it open into a session card: the
-- player, the game and session time, frame rate and ping meters, the server
-- and running counts, and the key that reopens the window. A
-- notification while minimized opens it briefly to show it. Click or tap
-- restores.

-- One table, not separate locals: the main chunk is at Luau's 200 local limit.
local Mini = {
    -- Sized after the iPhone 18 island: a slimmer, shorter pill sitting close
    -- to the top edge, opening into a wide card with deep rounded corners.
    Top = 8, -- gap from the top of the screen
    Width = TOUCH and 176 or 168, -- compact
    Height = TOUCH and 36 or 32,
    Wide = 340, -- expanded and activity
    Radius = 34, -- corner of the expanded and activity cards
    Bars = 4,
    Pinned = 6,
}

-- The morph is carried by a plain "ghost" panel drawn over the window. The
-- window body itself never moves or fades, so nothing has to be laid out
-- again mid-animation: the ghost covers it, the window is hidden underneath,
-- and on the way back the window is shown under the ghost before it clears.
local function makeGhost(window, position, size, radius)
    if window._ghost then
        window._ghost:Destroy()
    end
    local ghost = create("Frame", {
        Position = UDim2.fromOffset(position.X, position.Y),
        Size = UDim2.fromOffset(size.X, size.Y),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 29,
        Parent = window.Gui,
    })
    local ghostCorner = Library._fixedCorner(ghost, UDim.new(0, radius))
    local ghostStroke = stroke(ghost, Theme.Stroke, 1)
    window._ghost = ghost
    return ghost, ghostStroke, ghostCorner
end

local function morphGhost(ghost, ghostCorner, position, size, radius, duration)
    tween(ghost, {
        Position = UDim2.fromOffset(position.X, position.Y),
        Size = UDim2.fromOffset(size.X, size.Y),
    }, duration, Enum.EasingStyle.Quint)
    tween(ghostCorner, { CornerRadius = UDim.new(0, radius) }, duration, Enum.EasingStyle.Quint)
end

local function dissolve(window, ghost, ghostStroke, duration)
    tween(ghost, { BackgroundTransparency = 1 }, duration, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 1 }, duration, Enum.EasingStyle.Quad)
    task.delay(duration + 0.02, function()
        if window._ghost == ghost then
            window._ghost = nil
        end
        ghost:Destroy()
    end)
end

function Window:_buildMiniBar()
    if self.MiniBar then
        return self.MiniBar
    end
    local gui = self.Gui

    -- The island itself: a black pill hanging from the top of the screen. It
    -- is a canvas so its rounded shape clips whatever layer is showing.
    local island = create("CanvasGroup", {
        Name = "Island",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, Mini.Top),
        Size = UDim2.fromOffset(Mini.Width, Mini.Height),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    local islandCorner = Library._fixedCorner(island, UDim.new(0, Mini.Height / 2))
    local islandScale = create("UIScale", { Parent = island })
    self._miniScale = islandScale
    -- How far the split bubble is out of the pill: drawn back in while the
    -- island is open, budded off again once it settles to the pill.
    local merge = create("NumberValue", { Value = 1 })
    local mergeTween
    self._miniOrb = island

    -- The wide layers keep a fixed width, so nothing reflows while the island
    -- grows around them.
    local function layer(name)
        return create("CanvasGroup", {
            Name = name,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(0.5, 0),
            Size = UDim2.new(0, Mini.Wide, 0, 400),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            Parent = island,
        })
    end

    -- Compact: the logo leading, a live meter of running toggles trailing.
    -- A graphite surface, lit from the top, so the pill isn't a flat black
    -- slab; it fades with the layer, leaving the open card black.
    local compact = create("CanvasGroup", {
        Name = "Compact",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.fromRGB(30, 30, 34),
        BorderSizePixel = 0,
        Parent = island,
    })
    create("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 120, 120)),
        Parent = compact,
    })
    -- The logo sits in a soft accent disc, like an app glyph. Without one the
    -- title starts at the pill's edge instead.
    local miniLogo = self._logoIcon
    if miniLogo ~= false then
        local logoDisc = create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 5, 0.5, 0),
            Size = UDim2.fromOffset(Mini.Height - 10, Mini.Height - 10),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.82,
            BorderSizePixel = 0,
            Parent = compact,
        })
        corner(logoDisc, UDim.new(1, 0))
        local logo = create("ImageLabel", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(16, 16),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            ScaleType = Enum.ScaleType.Fit,
            Parent = logoDisc,
        })
        applyIcon(logo, miniLogo, true)
    end
    -- The script's name beside the logo, so the pill reads at a glance.
    local titleX = miniLogo ~= false and (Mini.Height + 2) or 14
    local miniTitle = label({
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, titleX, 0.5, 0),
        Size = UDim2.new(1, -titleX - 72, 0, 18),
        Text = self.Title,
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextColor3 = Color3.fromRGB(244, 244, 246),
        Parent = compact,
    })
    local meter = create("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        Parent = compact,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
        Parent = meter,
    })
    local barsHolder = create("Frame", {
        Size = UDim2.fromOffset(Mini.Bars * 3 + (Mini.Bars - 1) * 2, 16),
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = 1,
        Parent = meter,
    })
    local bars = {}
    for index = 1, Mini.Bars do
        local bar = create("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, (index - 1) * 5, 0.5, 0),
            Size = UDim2.fromOffset(3, 3),
            BackgroundColor3 = Theme.Muted,
            BorderSizePixel = 0,
            Parent = barsHolder,
        })
        corner(bar, UDim.new(1, 0))
        bars[index] = bar
    end
    local countLabel = label({
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "",
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextTruncate = Enum.TextTruncate.None,
        Visible = false,
        LayoutOrder = 2,
        Parent = meter,
    })
    -- Idle (nothing running): a health dot tinted by frame rate and the
    -- session clock, so the pill never sits empty.
    local idleDot = create("Frame", {
        Size = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        LayoutOrder = -1,
        Parent = meter,
    })
    corner(idleDot, UDim.new(1, 0))
    local idleLabel = label({
        Size = UDim2.fromOffset(0, 18),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "0s",
        TextSize = 12,
        FontFace = Fonts.Bold,
        TextColor3 = Color3.fromRGB(220, 220, 224),
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 0,
        Parent = meter,
    })

    -- Expanded, on hover: the player's session.
    local expanded = layer("Expanded")
    local expandedList = create("Frame", {
        Position = UDim2.fromOffset(16, 14),
        Size = UDim2.new(1, -32, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = expanded,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = expandedList,
    })
    -- The open card is the player's session, like a now-playing card: who
    -- and where on top with the session clock, two wide meters for frame
    -- rate and ping, then chips for the server and what's running.
    local top = create("Frame", {
        Size = UDim2.new(1, 0, 0, 48),
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        Parent = expandedList,
    })
    local face = create("ImageLabel", {
        Size = UDim2.fromOffset(48, 48),
        BackgroundColor3 = Color3.fromRGB(38, 38, 41),
        BorderSizePixel = 0,
        Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150",
        Parent = top,
    })
    corner(face, UDim.new(0, 12))
    local facePlaceholder = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Muted,
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Parent = face,
    })
    applyIcon(facePlaceholder, "user")
    self:_trackAvatar(face, facePlaceholder)
    local nameLabel = label({
        Position = UDim2.fromOffset(60, 5),
        Size = UDim2.new(1, -150, 0, 20),
        TextSize = 15,
        FontFace = Fonts.Bold,
        TextColor3 = Color3.fromRGB(244, 244, 246),
        Parent = top,
    })
    self:_trackName(nameLabel, "Display")
    local tabLabel = label({
        Position = UDim2.fromOffset(60, 26),
        Size = UDim2.new(1, -150, 0, 15),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        Parent = top,
    })
    task.spawn(function()
        tabLabel.Text = detectGameName()
    end)
    local sessionLabel = label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 3),
        Size = UDim2.fromOffset(90, 24),
        Text = "0s",
        TextSize = 20,
        FontFace = Fonts.Bold,
        TextColor3 = Color3.fromRGB(244, 244, 246),
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = top,
    })
    label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 27),
        Size = UDim2.fromOffset(90, 14),
        Text = "session",
        TextSize = 11,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = top,
    })

    -- Two readouts: a large number with its unit, a caption, and a thin
    -- line under them that fills and tints with how healthy it is.
    local meters = create("Frame", {
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        Parent = expandedList,
    })
    local function meterPill(position, caption)
        local cell = create("Frame", {
            Position = position,
            Size = UDim2.new(0.5, -10, 1, 0),
            BackgroundTransparency = 1,
            Parent = meters,
        })
        local value = label({
            Size = UDim2.new(1, -70, 0, 24),
            Text = "",
            TextSize = 20,
            FontFace = Fonts.Bold,
            TextColor3 = Color3.fromRGB(244, 244, 246),
            RichText = true,
            Parent = cell,
        })
        label({
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 6),
            Size = UDim2.fromOffset(70, 14),
            Text = caption,
            TextSize = 10,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = cell,
        })
        local track = create("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 0, 1, -4),
            Size = UDim2.new(1, 0, 0, 3),
            BackgroundColor3 = Color3.fromRGB(38, 38, 42),
            BorderSizePixel = 0,
            Parent = cell,
        })
        corner(track, UDim.new(1, 0))
        local fill = create("Frame", {
            Size = UDim2.fromScale(0, 1),
            BackgroundColor3 = Theme.Success,
            BorderSizePixel = 0,
            Parent = track,
        })
        corner(fill, UDim.new(1, 0))
        return fill, value
    end
    local fpsFill, fpsValue = meterPill(UDim2.fromScale(0, 0), "FRAME RATE")
    local pingFill, pingValue = meterPill(UDim2.new(0.5, 10, 0, 0), "PING")

    -- Chips: a muted name and a bold value, the running count in accent.
    local chips = create("Frame", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        Parent = expandedList,
    })
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        Parent = chips,
    })
    local function chipOf(order, name, color)
        local chipFrame = create("Frame", {
            Size = UDim2.fromOffset(0, 30),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Color3.fromRGB(32, 32, 35),
            BorderSizePixel = 0,
            LayoutOrder = order,
            Parent = chips,
        })
        corner(chipFrame, UDim.new(1, 0))
        padding(chipFrame, 14, 14)
        create("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 7),
            Parent = chipFrame,
        })
        label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = name,
            TextSize = 12,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 1,
            Parent = chipFrame,
        })
        return label({
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 12,
            FontFace = Fonts.Bold,
            TextColor3 = color or Color3.fromRGB(244, 244, 246),
            TextTruncate = Enum.TextTruncate.None,
            LayoutOrder = 2,
            Parent = chipFrame,
        })
    end
    local playersValue = chipOf(1, "Players")
    local bigCount = chipOf(2, "Running", Theme.Accent)
    local tabValue = chipOf(3, "Tab")

    -- Pinned statuses are no longer shown here; the holder stays so the
    -- refresh below has somewhere to keep its rows.
    local rowsHolder = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        Visible = false,
        LayoutOrder = 4,
        Parent = expandedList,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 2),
        Parent = rowsHolder,
    })
    -- What's running, by name, so the count above has something behind it.
    local runningNames = label({
        Size = UDim2.new(1, 0, 0, 15),
        Text = "",
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Color3.fromRGB(200, 200, 206),
        RichText = true,
        Visible = false,
        LayoutOrder = 4,
        Parent = expandedList,
    })
    local hint = label({
        Size = UDim2.new(1, 0, 0, 14),
        TextSize = 11,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        LayoutOrder = 5,
        Parent = expandedList,
    })

    -- Frame rate is counted every frame; the card's values refresh twice a
    -- second while it's open.
    local sessionStart = self._sessionStart or os.clock()
    local frames, frameClock, fps = 0, os.clock(), 60
    self:_listen("Render", function()
        frames += 1
        local now = os.clock()
        if now - frameClock >= 0.5 then
            fps = math.floor(frames / (now - frameClock) + 0.5)
            frames, frameClock = 0, now
        end
    end)
    local function refreshSession()
        sessionLabel.Text = formatDuration(os.clock() - sessionStart)
        idleLabel.Text = sessionLabel.Text
        tween(idleDot, { BackgroundColor3 = Library._healthColor(fps, 50, 30) }, 0.4)
        local unit = '<font size="12" color="#8A8A93"> %s</font>'
        fpsValue.Text = fps .. string.format(unit, "fps")
        tween(fpsFill, {
            Size = UDim2.fromScale(math.clamp(fps / 60, 0.05, 1), 1),
            BackgroundColor3 = Library._healthColor(fps, 50, 30),
        }, 0.4, Enum.EasingStyle.Quint)
        local okPing, ping = pcall(function()
            return math.floor(LocalPlayer:GetNetworkPing() * 1000)
        end)
        ping = okPing and ping or 0
        pingValue.Text = ping .. string.format(unit, "ms")
        -- Lower ping fills more: 40ms or less is full, 400ms and up is low.
        tween(pingFill, {
            Size = UDim2.fromScale(math.clamp(1 - (ping - 40) / 360, 0.05, 1), 1),
            BackgroundColor3 = Library._healthColor(ping, 90, 180, true),
        }, 0.4, Enum.EasingStyle.Quint)
        playersValue.Text = #Players:GetPlayers() .. "/" .. Players.MaxPlayers
        local tab = self.CurrentTab
        tabValue.Text = tab and tab.Name or "-"
    end
    task.spawn(function()
        while island.Parent do
            if island.Visible and self.Minimized then
                refreshSession()
            end
            task.wait(0.5)
        end
    end)

    -- Activity: a notification that arrives while minimized drops in here.
    local activity = layer("Activity")
    local activityList = create("Frame", {
        Position = UDim2.fromOffset(16, 13),
        Size = UDim2.new(1, -32, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = activity,
    })
    local activityChip = create("Frame", {
        Size = UDim2.fromOffset(34, 34),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.85,
        BorderSizePixel = 0,
        Parent = activityList,
    })
    corner(activityChip, UDim.new(1, 0))
    local activityIcon = create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(17, 17),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        ScaleType = Enum.ScaleType.Fit,
        Parent = activityChip,
    })
    local activityText = create("Frame", {
        Position = UDim2.fromOffset(46, 0),
        Size = UDim2.new(1, -46, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = activityList,
    })
    create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 1),
        Parent = activityText,
    })
    local activityTitle = label({
        Size = UDim2.new(1, 0, 0, 18),
        TextSize = 14,
        FontFace = Fonts.Bold,
        LayoutOrder = 1,
        Parent = activityText,
    })
    local activityBody = label({
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextSize = 12,
        FontFace = Fonts.Regular,
        TextColor3 = Theme.Muted,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        MaxVisibleGraphemes = 140,
        LayoutOrder = 2,
        Parent = activityText,
    })

    local hit = create("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 10,
        Parent = island,
    })

    -- Morphing between shapes: the island springs to its new size while the
    -- old layer fades out and the new one fades in just behind it.
    local layers = { Compact = compact, Expanded = expanded, Activity = activity }
    local mode = "Compact"
    local modeToken = 0
    local sizeTween, cornerTween
    local hovered, pressed = false, false
    local hoverToken = 0
    local dragFrom, dragAnchor, dragging, dragged = nil, nil, false, false
    local activityToken = 0
    local activityLive = false

    local function shapeFor(name)
        if name == "Expanded" then
            return Vector2.new(Mini.Wide, math.floor(expandedList.AbsoluteSize.Y + 28 + 0.5)), Mini.Radius
        elseif name == "Activity" then
            return Vector2.new(Mini.Wide, math.floor(math.max(activityList.AbsoluteSize.Y, 34) + 26 + 0.5)), Mini.Radius
        end
        return Vector2.new(Mini.Width, Mini.Height), Mini.Height / 2
    end

    -- Where the island hangs: the top centre of its shape, as fractions of
    -- the screen so it keeps its spot across resolutions. Dragging moves it;
    -- each shape is clamped on screen, so the wide card slides in from an edge
    -- and the pill goes back to its spot when it folds.
    local saved = self:_readConfigSettings().IslandPosition
    if type(saved) == "table" and tonumber(saved.X) and tonumber(saved.Y) then
        self._islandAnchor = Vector2.new(math.clamp(tonumber(saved.X), 0, 1), math.clamp(tonumber(saved.Y), 0, 1))
    end
    local positionTween
    local function anchorPixels()
        local view = gui.AbsoluteSize
        local anchor = self._islandAnchor
        if not anchor then
            return Vector2.new(view.X / 2, Mini.Top)
        end
        return Vector2.new(anchor.X * view.X, anchor.Y * view.Y)
    end
    local function islandSpot(size, from)
        local view = gui.AbsoluteSize
        local spot = from or anchorPixels()
        local margin = 6
        local x = math.clamp(spot.X, size.X / 2 + margin, math.max(view.X - size.X / 2 - margin, size.X / 2 + margin))
        local y = math.clamp(spot.Y, margin, math.max(view.Y - size.Y - margin, margin))
        return Vector2.new(x, y)
    end
    local function placeIsland(size, duration, style)
        local spot = islandSpot(size)
        if positionTween then
            positionTween:Cancel()
            positionTween = nil
        end
        if duration and duration > 0 then
            positionTween = tween(island, { Position = UDim2.fromOffset(spot.X, spot.Y) }, duration, style or Enum.EasingStyle.Quint)
        else
            island.Position = UDim2.fromOffset(spot.X, spot.Y)
        end
    end
    self._islandReset = function()
        self._islandAnchor = nil
        if island.Visible then
            placeIsland(Vector2.new(island.Size.X.Offset, island.Size.Y.Offset), 0.35)
        end
    end

    local function setMode(name, instant)
        local size, radius = shapeFor(name)
        local changed = name ~= mode
        mode = name
        modeToken += 1
        local token = modeToken
        local current = Vector2.new(island.Size.X.Offset, island.Size.Y.Offset)
        local growing = size.X > current.X + 1 or size.Y > current.Y + 1
        local duration = instant and 0 or (growing and 0.5 or 0.38)
        -- A snap must stop a morph still in flight, or it keeps writing the
        -- old shape over the new one.
        if sizeTween then
            sizeTween:Cancel()
        end
        if cornerTween then
            cornerTween:Cancel()
        end
        placeIsland(size, duration)
        sizeTween = tween(island, { Size = UDim2.fromOffset(size.X, size.Y) }, duration, growing and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
        cornerTween = tween(islandCorner, { CornerRadius = UDim.new(0, radius) }, duration, Enum.EasingStyle.Quint)
        -- The iOS island gives a soft squeeze as it swells open, then springs
        -- back, so the morph reads as one elastic body rather than a resize.
        if changed and not instant and not pressed and not dragging then
            islandScale.Scale = growing and 0.96 or 1.03
            tween(islandScale, { Scale = 1 }, growing and 0.55 or 0.4, Enum.EasingStyle.Back)
        end
        if changed or instant then
            if mergeTween then
                mergeTween:Cancel()
                mergeTween = nil
            end
            if instant then
                merge.Value = name == "Compact" and 1 or 0
            elseif name == "Compact" then
                -- Wait for the pill to shrink most of the way, then bud off.
                task.delay(duration * 0.55, function()
                    if modeToken == token then
                        mergeTween = tween(merge, { Value = 1 }, 0.6, Enum.EasingStyle.Back)
                    end
                end)
            else
                mergeTween = tween(merge, { Value = 0 }, 0.2, Enum.EasingStyle.Quint)
            end
        end
        if not changed and not instant then
            -- A refit (same shape, new height) bumps the token, which cancels
            -- a fade-in still waiting from the morph; finish it here or the
            -- card stays black until the next hover.
            local target = layers[name]
            if target.GroupTransparency > 0 then
                tween(target, { GroupTransparency = 0 }, 0.22, Enum.EasingStyle.Quad)
            end
            if target ~= compact and target.Position ~= UDim2.fromScale(0.5, 0) then
                tween(target, { Position = UDim2.fromScale(0.5, 0) }, 0.32, Enum.EasingStyle.Quint)
            end
            return
        end
        for key, group in pairs(layers) do
            if key ~= name then
                tween(group, { GroupTransparency = 1 }, instant and 0 or 0.14, Enum.EasingStyle.Quad)
            end
        end
        local target = layers[name]
        if instant then
            target.GroupTransparency = 0
            -- Compact fills the island from its corner; only the wide
            -- layers hang from the centre.
            if target ~= compact then
                target.Position = UDim2.fromScale(0.5, 0)
            end
        else
            -- The new layer rises a few pixels into place as it fades in, so
            -- the content reads as arriving with the shape, not popping in.
            if target ~= compact then
                target.Position = UDim2.new(0.5, 0, 0, 6)
            end
            task.delay(0.1, function()
                if modeToken == token then
                    tween(target, { GroupTransparency = 0 }, 0.22, Enum.EasingStyle.Quad)
                    if target ~= compact then
                        tween(target, { Position = UDim2.fromScale(0.5, 0) }, 0.32, Enum.EasingStyle.Quint)
                    end
                end
            end)
        end
    end

    local function settleMode()
        if hovered and not TOUCH and not dragging then
            setMode("Expanded")
        elseif activityLive then
            setMode("Activity")
        elseif self.IslandStyle == "Always Show" and not dragging then
            self:_refreshMini()
            refreshSession()
            setMode("Expanded")
        else
            setMode("Compact")
        end
    end

    self._islandSettle = function()
        if self.Minimized and island.Visible and not dragging then
            settleMode()
        end
    end

    -- Called by Minimize once the window is out of the way: the island is
    -- reset to its compact pill and its spot handed back for the ghost.
    function self:_miniLand()
        hovered, activityLive = false, false
        activityToken += 1
        islandScale.Scale = 1
        setMode("Compact", true)
        local size = Vector2.new(Mini.Width, Mini.Height)
        local spot = islandSpot(size)
        return Vector2.new(spot.X - size.X / 2, spot.Y), size
    end

    hit.MouseEnter:Connect(function()
        if usingTouch() or dragging then
            return
        end
        hovered = true
        hoverToken += 1
        local token = hoverToken
        -- Already open (the pointer left and came back within the grace):
        -- just stay. Otherwise lean in a touch, and only open once the
        -- pointer rests, so sweeping past the island doesn't burst it open.
        if mode == "Expanded" then
            return
        end
        if not pressed then
            tween(islandScale, { Scale = 1.04 }, 0.18, Enum.EasingStyle.Quint)
        end
        task.delay(0.12, function()
            if hoverToken == token and hovered and self.Minimized and not dragging then
                self:_refreshMini()
                refreshSession()
                setMode("Expanded")
            end
        end)
    end)
    hit.MouseLeave:Connect(function()
        hovered = false
        hoverToken += 1
        local token = hoverToken
        if not pressed then
            tween(islandScale, { Scale = 1 }, 0.25, Enum.EasingStyle.Quint)
        end
        -- A grace period: the card shifts while it morphs and clamps on
        -- screen, so a pointer grazing its edge shouldn't snap it shut.
        task.delay(mode == "Expanded" and 0.28 or 0.1, function()
            if hoverToken == token and not hovered and self.Minimized then
                settleMode()
            end
        end)
    end)
    -- Press and pull to move the island anywhere on screen. It folds to the
    -- pill while carried, lifts a little, and a drop near its home at the top
    -- centre snaps back there. A drag never counts as the click that restores.
    hit.InputBegan:Connect(function(input)
        if not isPress(input) then
            return
        end
        pressed = true
        dragged = false
        tween(islandScale, { Scale = 0.95 }, 0.12, Enum.EasingStyle.Quad)
        if not self._islandLocked then
            dragFrom = Vector2.new(input.Position.X, input.Position.Y)
            dragAnchor = islandSpot(Vector2.new(Mini.Width, Mini.Height))
        end
    end)
    self:_listen("Changed", function(input)
        if not dragFrom or not isMove(input) or not self.Minimized then
            return
        end
        local delta = Vector2.new(input.Position.X, input.Position.Y) - dragFrom
        if not dragging then
            if delta.Magnitude < (TOUCH and 10 or 6) then
                return
            end
            dragging, dragged = true, true
            hovered = false
            setMode("Compact")
            tween(islandScale, { Scale = 1.06 }, 0.2, Enum.EasingStyle.Quint)
        end
        local spot = islandSpot(Vector2.new(Mini.Width, Mini.Height), dragAnchor + delta)
        local view = gui.AbsoluteSize
        self._islandAnchor = Vector2.new(spot.X / math.max(view.X, 1), spot.Y / math.max(view.Y, 1))
        if positionTween then
            positionTween:Cancel()
            positionTween = nil
        end
        island.Position = UDim2.fromOffset(spot.X, spot.Y)
    end)
    table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
        if not isPress(input) then
            return
        end
        dragFrom = nil
        if pressed then
            pressed = false
            tween(islandScale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
        end
        if dragging then
            dragging = false
            local home = Vector2.new(gui.AbsoluteSize.X / 2, Mini.Top)
            local spot = islandSpot(Vector2.new(Mini.Width, Mini.Height))
            if (spot - home).Magnitude < 28 then
                self._islandAnchor = nil
                placeIsland(Vector2.new(Mini.Width, Mini.Height), 0.35, Enum.EasingStyle.Back)
            end
            local anchor = self._islandAnchor
            self:_writeConfigSettings({ IslandPosition = anchor and { X = anchor.X, Y = anchor.Y } or false })
            hovered = not usingTouch() and pointInside(pointerPosition(), island)
            task.delay(0.1, function()
                if self.Minimized and not dragging then
                    settleMode()
                end
            end)
        end
    end))
    -- Keeps the island on screen when the viewport changes size.
    table.insert(self._connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if island.Visible and not dragging then
            placeIsland(Vector2.new(island.Size.X.Offset, island.Size.Y.Offset), 0)
        end
    end))
    hit.MouseButton1Click:Connect(function()
        if dragged then
            dragged = false
            return
        end
        if self.Minimized then
            self:Restore()
        end
    end)
    -- Restore hides the island under the pointer, so MouseLeave never fires.
    self._miniUnhover = function()
        hovered, pressed, activityLive = false, false, false
        dragFrom, dragging = nil, false
        activityToken += 1
        islandScale.Scale = 1
        -- Clicked open while expanded: once the island has faded out, fold it
        -- back to the pill so the next minimize starts from it.
        task.delay(0.15, function()
            if not self.Minimized then
                setMode("Compact", true)
            end
        end)
    end

    -- A notification while minimized: the island opens to show it for a few
    -- seconds, then folds back.
    self._islandActivity = function(opts)
        if not self.Minimized or not island.Visible then
            return
        end
        local color = NOTIFY_COLORS[opts.Type] or Theme.Accent
        activityTitle.Text = tostring(opts.Title or "Notification")
        activityTitle.TextColor3 = NOTIFY_COLORS[opts.Type] or Theme.Text
        activityBody.Text = tostring(opts.Content or "")
        activityBody.Visible = activityBody.Text ~= ""
        local icon = opts.Icon
        if icon == nil then
            icon = ({ Success = "circle-check", Warning = "triangle-alert", Error = "circle-x" })[opts.Type] or "bell"
        end
        local showIcon = icon ~= false
        activityChip.Visible = showIcon
        activityText.Position = UDim2.fromOffset(showIcon and 46 or 0, 0)
        applyIcon(activityIcon, icon)
        if not activityIcon:GetAttribute("CustomIcon") then
            activityIcon.ImageColor3 = color
        end
        activityChip.BackgroundColor3 = color
        activityLive = true
        activityToken += 1
        local token = activityToken
        task.defer(function()
            if activityToken == token and not hovered and not dragging then
                setMode("Activity")
                islandScale.Scale = 0.96
                tween(islandScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            end
        end)
        task.delay(math.clamp(tonumber(opts.Duration) or 3, 1.5, 5), function()
            if activityToken == token then
                activityLive = false
                if self.Minimized and not hovered then
                    settleMode()
                end
            end
        end)
    end

    -- The meter dances while anything runs and lies flat when nothing does.
    local running = 0
    self:_listen("Render", function()
        if island.Visible and running > 0 and mode == "Compact" then
            local now = os.clock()
            for index, bar in ipairs(bars) do
                local wave = 0.5 + 0.5 * math.sin(now * (6 + index * 1.4) + index * 1.9)
                bar.Size = UDim2.fromOffset(3, math.floor(4 + wave * 11 + 0.5))
            end
        end
    end)

    -- Split, like iOS with two Live Activities: when toggles are running and
    -- a status is pinned, the pill keeps the status (logo leading, value
    -- trailing) and the running meter buds off into its own little circle
    -- beside it. One activity alone stays in the single pill.
    local pinValue = label({
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        Size = UDim2.new(1, -52, 0, 18),
        TextSize = 13,
        FontFace = Fonts.Bold,
        TextXAlignment = Enum.TextXAlignment.Right,
        RichText = true,
        TextTransparency = 1,
        Parent = compact,
    })
    local bubble = create("TextButton", {
        Name = "IslandBubble",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Color3.fromRGB(26, 26, 30),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Visible = false,
        ZIndex = 30,
        Parent = gui,
    })
    corner(bubble, UDim.new(1, 0))
    local split = create("NumberValue", { Value = 0 })
    local splitOn = false
    local pinnedLead = nil
    local function setSplit(on)
        if on == splitOn then
            return
        end
        splitOn = on
        barsHolder.Parent = on and bubble or meter
        barsHolder.AnchorPoint = on and Vector2.new(0.5, 0.5) or Vector2.new(0, 0)
        barsHolder.Position = on and UDim2.fromScale(0.5, 0.5) or UDim2.new()
        meter.Visible = not on
        tween(pinValue, { TextTransparency = on and 0 or 1 }, 0.2, Enum.EasingStyle.Quad)
        -- Buds off with a spring, and is drawn back in quicker.
        tween(split, { Value = on and 1 or 0 }, on and 0.55 or 0.3, on and Enum.EasingStyle.Back or Enum.EasingStyle.Quint)
        if on then
            islandScale.Scale = 0.96
            tween(islandScale, { Scale = 1 }, 0.45, Enum.EasingStyle.Back)
        end
    end
    self:_listen("Render", function()
        local t = split.Value * merge.Value
        local shown = island.Visible and t > 0.02 and island.GroupTransparency < 0.5
        bubble.Visible = shown
        if not shown then
            return
        end
        local origin = gui.AbsolutePosition
        local pos, size = island.AbsolutePosition - origin, island.AbsoluteSize
        local d = math.min(size.Y, Mini.Height)
        local gap = 6
        -- Buds off the side with room to spare: the right, or the left near
        -- the right edge of the screen.
        local right = pos.X + size.X + gap + d <= gui.AbsoluteSize.X
        local edge = right and pos.X + size.X or pos.X
        local dir = right and 1 or -1
        local inner = edge - dir * d * 0.6
        local outer = edge + dir * (gap + d / 2)
        local x = inner + (outer - inner) * t
        local scale = math.clamp(0.35 + 0.65 * t, 0, 1.2)
        -- Liquid: mid-flight the drop stretches along its path and thins,
        -- then rounds back into a circle as it settles.
        local stretch = math.sin(math.clamp(t, 0, 1) * math.pi)
        bubble.Position = UDim2.fromOffset(x, pos.Y + d / 2)
        bubble.Size = UDim2.fromOffset(d * scale * (1 + 0.4 * stretch), d * scale * (1 - 0.18 * stretch))
        bubble.BackgroundTransparency = island.GroupTransparency
    end)
    bubble.MouseButton1Click:Connect(function()
        if self.Minimized then
            self:Restore()
        end
    end)

    local cardRows = {}
    function self:_refreshMini()
        local count = 0
        for _, element in pairs(Library.Flags) do
            if element._type == "Toggle" and element.Value == true then
                count += 1
            end
        end
        if count ~= running then
            local rising = count > running
            running = count
            countLabel.Text = tostring(count)
            for _, bar in ipairs(bars) do
                tween(bar, { BackgroundColor3 = count > 0 and Theme.Accent or Theme.Muted }, 0.25)
                if count == 0 then
                    tween(bar, { Size = UDim2.fromOffset(3, 3) }, 0.25)
                end
            end
            -- A small bump, like a live activity updating.
            if rising and mode == "Compact" and island.Visible then
                islandScale.Scale = 1.06
                tween(islandScale, { Scale = 1 }, 0.4, Enum.EasingStyle.Back)
            end
        end
        bigCount.Text = tostring(count)
        local names = {}
        for _, element in pairs(Library.Flags) do
            if element._type == "Toggle" and element.Value == true and element._searchName ~= "" then
                table.insert(names, element._searchName)
            end
        end
        table.sort(names)
        local shownNames = {}
        for index = 1, math.min(#names, 3) do
            shownNames[index] = Library._rich(names[index])
        end
        local extra = #names - #shownNames
        runningNames.Text = '<font color="#8A8A93">Running </font>' .. table.concat(shownNames, '<font color="#8A8A93"> · </font>')
            .. (extra > 0 and string.format('<font color="#8A8A93">  +%d</font>', extra) or "")
        runningNames.Visible = #names > 0
        pinnedLead = nil
        for _, handle in ipairs(self._pinned) do
            if not handle._isShown or handle:_isShown() then
                pinnedLead = handle
                break
            end
        end
        if pinnedLead then
            local text = tostring(pinnedLead:Text() or "")
            -- A status with nothing to show yet doesn't take the pill.
            if text:gsub("<[^>]*>", ""):match("%S") then
                pinValue.Text = text
                local color = pinnedLead._shownColor and pinnedLead._shownColor() or Theme.Text
                -- Too dark to read on the black pill: fall back to text colour.
                local _, _, value = color:ToHSV()
                pinValue.TextColor3 = value < 0.35 and Theme.Text or color
            else
                pinnedLead = nil
            end
        end
        setSplit(running > 0 and pinnedLead ~= nil)
        -- The pill's own meter: the clock when idle or when the bars budded
        -- off without a status to keep, the bars and count otherwise.
        local barsHere = running > 0 and not splitOn
        idleDot.Visible = not barsHere
        idleLabel.Visible = not barsHere
        countLabel.Visible = barsHere
        barsHolder.Visible = running > 0
        meter.Visible = not splitOn
        miniTitle.Visible = not splitOn
        local key = typeof(self.Keybind) == "EnumItem" and keyName(self.Keybind)
        hint.Text = TOUCH and "Tap to open" or (key and ("Click or press " .. key .. " to open") or "Click to open")

        local list = {}
        for _, handle in ipairs(self._pinned) do
            if (not handle._isShown or handle:_isShown()) and #list < Mini.Pinned then
                table.insert(list, handle)
            end
        end
        rowsHolder.Visible = false
        for index = 1, math.max(#list, #cardRows) do
            local handle = list[index]
            local row = cardRows[index]
            if handle then
                if not row then
                    local frame = create("Frame", {
                        Size = UDim2.new(1, 0, 0, 18),
                        BackgroundTransparency = 1,
                        LayoutOrder = index,
                        Parent = rowsHolder,
                    })
                    row = {
                        Frame = frame,
                        Key = label({
                            Size = UDim2.new(0.5, -4, 1, 0),
                            TextSize = 12,
                            FontFace = Fonts.Regular,
                            TextColor3 = Theme.Muted,
                            RichText = true,
                            Parent = frame,
                        }),
                        Value = label({
                            AnchorPoint = Vector2.new(1, 0),
                            Position = UDim2.fromScale(1, 0),
                            Size = UDim2.new(0.5, -4, 1, 0),
                            TextSize = 12,
                            TextXAlignment = Enum.TextXAlignment.Right,
                            RichText = true,
                            Parent = frame,
                        }),
                    }
                    cardRows[index] = row
                end
                row.Frame.Visible = true
                row.Key.Text = Library._rich(handle.Name)
                row.Value.Text = handle:Text()
                -- Carries the status's own colour: its Color, or its tone
                -- for the tinted styles (badge, dot, bar).
                local color = handle._shownColor and handle._shownColor() or Theme.Text
                if row.Value.TextColor3 ~= color then
                    tween(row.Value, { TextColor3 = color }, 0.2)
                end
            elseif row then
                row.Frame.Visible = false
            end
        end
        -- Rows coming and going change the expanded height.
        if mode == "Expanded" and (hovered or self.IslandStyle == "Always Show") then
            task.defer(function()
                if mode == "Expanded" and (hovered or self.IslandStyle == "Always Show") and self.Minimized then
                    local size = shapeFor("Expanded")
                    if math.abs(size.Y - island.Size.Y.Offset) > 1 then
                        setMode("Expanded")
                    end
                end
            end)
        end
    end

    self.MiniBar = island
    self.Island = island
    return island
end

function Window:Minimize()
    if self.Minimized or not self._introDone or not self.Open or self._destroyed then
        return
    end
    self.Minimized = true
    self:_refreshModal()
    self:_refreshCursor()
    self._minimizeGeneration = (self._minimizeGeneration or 0) + 1
    local generation = self._minimizeGeneration
    self:_closePopups()
    self:_refreshToggleButton()
    self:_refreshBackdrop()
    local bar = self:_buildMiniBar()
    self:_refreshMini()
    local gui = self.Gui

    -- Starts from whatever is on screen: the window, or a ghost still
    -- mid-flight if a restore was interrupted.
    local fromPosition = self.Root.AbsolutePosition - gui.AbsolutePosition
    local fromSize = self.Root.AbsoluteSize
    local fromAlpha = 1
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    end

    -- 1. The ghost fades in over the window while it eases back a touch.
    local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition, fromSize, Library._radius(10))
    ghost.BackgroundTransparency = fromAlpha
    ghostStroke.Transparency = fromAlpha
    tween(ghost, { BackgroundTransparency = 0 }, 0.11, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 0 }, 0.11, Enum.EasingStyle.Quad)
    tween(self.Scale, { Scale = (self._fitScale or 1) * 0.985 }, 0.11, Enum.EasingStyle.Quad)
    tween(self.Shadow, { ImageTransparency = 1 }, 0.2)
    bar.Visible = true
    bar.GroupTransparency = 1

    task.delay(0.11, function()
        if self._minimizeGeneration ~= generation or self._destroyed then
            return
        end
        -- 2. Covered by the ghost, the window is hidden and the ghost folds
        -- down into the island.
        self.Root.Visible = false
        self.Scale.Scale = self._fitScale or 1
        local target, size = self:_miniLand(fromPosition + fromSize / 2)
        morphGhost(ghost, ghostCorner, target, size, math.floor(size.Y / 2), 0.36)
        task.delay(0.3, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            -- 3. The island fades in on top as the ghost lands.
            self._miniScale.Scale = 0.9
            tween(self._miniScale, { Scale = 1 }, 0.3, Enum.EasingStyle.Quint)
            tween(bar, { GroupTransparency = 0 }, 0.18, Enum.EasingStyle.Quad)
            dissolve(self, ghost, ghostStroke, 0.2)
            -- Always Show: once landed as the pill, swell open into the card.
            if self.IslandStyle == "Always Show" then
                task.delay(0.22, function()
                    if self._minimizeGeneration == generation and self._islandSettle then
                        self._islandSettle()
                    end
                end)
            end
        end)
    end)

    task.spawn(function()
        while self.Minimized and self._minimizeGeneration == generation and not self._destroyed do
            self:_refreshMini()
            task.wait(0.5)
        end
    end)
end

function Window:Restore()
    if not self.Minimized or self._destroyed then
        return
    end
    self.Minimized = false
    self:_refreshModal()
    self:_refreshCursor()
    self._minimizeGeneration = (self._minimizeGeneration or 0) + 1
    local generation = self._minimizeGeneration
    self:_refreshToggleButton()
    self:_refreshBackdrop(true)
    local gui = self.Gui
    local bar = self.MiniBar
    local fit = self._fitScale or 1
    local size = Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset) * fit
    local centre = self.Root.AbsolutePosition + self.Root.AbsoluteSize / 2 - gui.AbsolutePosition
    local target = centre - size / 2

    -- Picks up from whatever is on screen: a ghost still mid-flight if
    -- minimize was interrupted, otherwise the island.
    local fromPosition, fromSize = target, size
    local fromAlpha = 1
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    elseif bar and bar.Visible then
        fromPosition = self._miniOrb.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._miniOrb.AbsoluteSize
    end
    if bar and bar.Visible then
        if self._miniUnhover then
            self._miniUnhover()
        end
        tween(bar, { GroupTransparency = 1 }, 0.12, Enum.EasingStyle.Quad)
        task.delay(0.12, function()
            if self._minimizeGeneration == generation then
                bar.Visible = false
            end
        end)
    end

    local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition, fromSize, math.floor(math.min(fromSize.X, fromSize.Y) / 2))
    ghost.BackgroundTransparency = fromAlpha
    ghostStroke.Transparency = fromAlpha
    tween(ghost, { BackgroundTransparency = 0 }, 0.1, Enum.EasingStyle.Quad)
    tween(ghostStroke, { Transparency = 0 }, 0.1, Enum.EasingStyle.Quad)
    morphGhost(ghost, ghostCorner, target, size, Library._radius(10), 0.4)
    tween(self.Shadow, { ImageTransparency = self._shadowRest }, 0.45)

    -- Shown under the ghost a little early so its first frames are drawn
    -- while still covered, then the ghost clears to reveal it.
    task.delay(0.3, function()
        if self._minimizeGeneration ~= generation or self._destroyed then
            return
        end
        self.Scale.Scale = fit
        self.BodyStroke.Transparency = 0
        self.Root.Visible = true
    end)
    task.delay(0.4, function()
        if self._ghost == ghost and self._minimizeGeneration == generation then
            dissolve(self, ghost, ghostStroke, 0.22)
        end
    end)
end

-- The minimized island can be dragged anywhere; its spot is remembered in
-- the config folder. These lock it in place or send it back to the top.
function Window:SetIslandDraggable(enabled)
    self._islandLocked = enabled == false
end

function Window:ResetIslandPosition()
    self._islandAnchor = nil
    if self._islandReset then
        self._islandReset()
    end
    self:_writeConfigSettings({ IslandPosition = false })
end

function Window:SetMinimized(minimized)
    if minimized then
        self:Minimize()
    else
        self:Restore()
    end
end

function Window:Toggle(open)
    if not self._introDone then
        return
    end
    if self.Minimized then
        if open ~= false then
            self:Restore()
        end
        return
    end
    if open == nil then
        open = not self.Open
    end
    if open == self.Open then
        return
    end
    self.Open = open
    self:_refreshModal()
    self:_refreshCursor()
    self:_refreshToggleButton()
    self:_refreshBackdrop(open)
    -- Like minimize, a plain ghost panel carries the scale and fade. The body
    -- is never reparented into the fader or rescaled, which relaid out the
    -- whole window and stuttered on the keypress frame.
    self._minimizeGeneration = (self._minimizeGeneration or 0) + 1
    local generation = self._minimizeGeneration
    local gui = self.Gui
    local fit = self._fitScale or 1
    local size = Vector2.new(self.Root.Size.X.Offset, self.Root.Size.Y.Offset) * fit
    local centre = self.Root.AbsolutePosition + self.Root.AbsoluteSize / 2 - gui.AbsolutePosition
    local shrunk = size * 0.94
    local fromPosition, fromSize, fromAlpha
    if self._ghost then
        fromPosition = self._ghost.AbsolutePosition - gui.AbsolutePosition
        fromSize = self._ghost.AbsoluteSize
        fromAlpha = self._ghost.BackgroundTransparency
    end
    if open then
        local ghost, ghostStroke, ghostCorner = makeGhost(self, fromPosition or centre - shrunk / 2, fromSize or shrunk, Library._radius(10))
        ghost.BackgroundTransparency = fromAlpha or 1
        ghostStroke.Transparency = fromAlpha or 1
        tween(ghost, { BackgroundTransparency = 0 }, 0.12, Enum.EasingStyle.Quad)
        tween(ghostStroke, { Transparency = 0 }, 0.12, Enum.EasingStyle.Quad)
        morphGhost(ghost, ghostCorner, centre - size / 2, size, Library._radius(10), 0.3)
        tween(self.Shadow, { ImageTransparency = self._shadowRest }, 0.3)
        -- Shown under the ghost once it covers the spot, then revealed.
        task.delay(0.2, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            self.Scale.Scale = fit
            self.BodyStroke.Transparency = 0
            self.Root.Visible = true
        end)
        task.delay(0.3, function()
            if self._ghost == ghost and self._minimizeGeneration == generation then
                dissolve(self, ghost, ghostStroke, 0.18)
            end
        end)
    else
        self:_closePopups()
        local position = fromPosition or self.Root.AbsolutePosition - gui.AbsolutePosition
        local current = fromSize or self.Root.AbsoluteSize
        local ghost, ghostStroke, ghostCorner = makeGhost(self, position, current, Library._radius(10))
        ghost.BackgroundTransparency = fromAlpha or 1
        ghostStroke.Transparency = fromAlpha or 1
        tween(ghost, { BackgroundTransparency = 0 }, 0.08, Enum.EasingStyle.Quad)
        tween(ghostStroke, { Transparency = 0 }, 0.08, Enum.EasingStyle.Quad)
        tween(self.Shadow, { ImageTransparency = 1 }, 0.16)
        task.delay(0.08, function()
            if self._minimizeGeneration ~= generation or self._destroyed then
                return
            end
            self.Root.Visible = false
            morphGhost(ghost, ghostCorner, centre - shrunk / 2, shrunk, Library._radius(10), 0.2)
            dissolve(self, ghost, ghostStroke, 0.16)
        end)
    end
end

function Window:SetKeepOnScreen(enabled)
    self.KeepOnScreen = enabled ~= false
    if self.KeepOnScreen then
        self:_clampToScreen()
    end
end

-- The modal element only ever carries the Modal flag (see its creation
-- note). Refreshed from every path that changes what is on screen.
function Window:_refreshModal()
    if not self._modal then
        return
    end
    self._modal.Modal = self.UnlockMouseWhileOpen == true
        and self.Open == true
        and self._introDone == true
        and not self.Minimized
end

function Window:SetUnlockMouseWhileOpen(enabled)
    self.UnlockMouseWhileOpen = enabled ~= false
    self:_refreshModal()
end

function Window:SetShowCustomCursor(enabled)
    self.ShowCustomCursor = enabled ~= false
    local toggle = self._interfaceCursorToggle
    if toggle and not toggle._destroyed then
        toggle:Set(self.ShowCustomCursor, true)
    end
    self:_refreshCursor()
end

-- Roblox auto-translates GUI text when the game has localization enabled.
-- SetAutoTranslate(false) keeps this window's text as written, now and for
-- everything created later; (true) hands it back to Roblox.
function Window:SetAutoTranslate(enabled)
    enabled = enabled ~= false
    Library.AutoTranslate = enabled
    for _, descendant in ipairs(self.Gui:GetDescendants()) do
        if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
            pcall(function()
                descendant.AutoLocalize = enabled
            end)
        end
    end
end

-- While the window is open the library draws its own cursor and keeps
-- MouseIconEnabled in check, so the pointer stays visible in games that hide
-- it to aim. Same approach as Obsidian: one render step bound at Last, with
-- the original icon state restored on close.
function Window:_refreshCursor()
    if not self._cursor then
        return
    end
    local active = not TOUCH and self._introDone and self.Open and not self.Minimized and not self._destroyed
    if active and not self._cursorBound then
        self._cursorBound = true
        self._originalMouseIconEnabled = UserInputService.MouseIconEnabled
        pcall(function()
            RunService:UnbindFromRenderStep(self._cursorBinding)
        end)
        RunService:BindToRenderStep(self._cursorBinding, Enum.RenderPriority.Last.Value, function()
            UserInputService.MouseIconEnabled = not self.ShowCustomCursor
            local pointer = pointerPosition() - self.Gui.AbsolutePosition
            self._cursor.Position = UDim2.fromOffset(pointer.X, pointer.Y)
            self._cursor.Visible = self.ShowCustomCursor
            if self._destroyed or not (self._introDone and self.Open and not self.Minimized and self.Gui.Parent) then
                self:_restoreMouseIcon()
            end
        end)
    elseif not active and self._cursorBound then
        self:_restoreMouseIcon()
    end
end

function Window:_restoreMouseIcon()
    self._cursorBound = false
    pcall(function()
        RunService:UnbindFromRenderStep(self._cursorBinding)
        RunService.RenderStepped:Wait()
    end)
    if self._originalMouseIconEnabled ~= nil then
        UserInputService.MouseIconEnabled = self._originalMouseIconEnabled
    end
    if self._cursor then
        self._cursor.Visible = false
    end
end

function Window:SetKeybind(key)
    self.Keybind = Keybinds.Resolve(key)
    if self._keyChipLabel then
        self._keyChipLabel.Text = keyName(self.Keybind)
    end
    local bind = self._interfaceKeybind
    if bind and not bind._destroyed and bind:Get() ~= self.Keybind then
        bind:Set(self.Keybind, true)
    end
end

-- The floating Keybind Menu created with this window. It lists this window's
-- Keybind widgets as "[Key] Name", keeps each row current in place, and is
-- hidden until opened.
function Window:SetKeybindMenu(enabled)
    local menu = self.KeybindMenu
    if menu and not menu.Destroyed then
        menu:SetVisible(enabled)
    end
end

function Window:ToggleKeybindMenu()
    local menu = self.KeybindMenu
    if menu and not menu.Destroyed then
        menu:ToggleVisible()
    end
end

function Window:Notify(opts)
    opts = normalize(opts, { Text = "Content", Message = "Content", Image = "Icon" })
    if self.Minimized and self._islandActivity then
        self._islandActivity(opts)
    end
    local duration = opts.Duration or 4
    local titleColor = NOTIFY_COLORS[opts.Type] or Theme.Text

    self._notifyOrder = self._notifyOrder + 1
    local outer = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        LayoutOrder = self._notifyOrder,
        Parent = self.NotifyHolder,
    })
    local slide = create("Frame", {
        Position = UDim2.fromOffset(320, 0),
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = outer,
    })
    local shadow = create("ImageLabel", {
        Position = UDim2.fromOffset(-20, -20),
        Size = UDim2.new(1, 40, 1, 40),
        BackgroundTransparency = 1,
        Image = Assets.Shadow,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 1,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
        Parent = slide,
    })
    local toast = create("CanvasGroup", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Parent = slide,
    })
    corner(toast, UDim.new(0, 10))
    local toastStroke = stroke(toast, Theme.Stroke)
    edgeHighlight(toast)
    glow(toast, UDim2.fromOffset(260, 120), UDim2.new(1, -10, 0, -10), 0.86, 90)

    local inner = create("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        Parent = toast,
    })
    padding(inner, 16, 16, 14, 24)

    local titleOffset = 0
    if opts.Icon then
        glowIcon(inner, opts.Icon, titleColor == Theme.Text and Theme.Accent or titleColor, UDim2.new(0, 0, 0, 8))
        titleOffset = 24
    end
    label({
        Position = UDim2.fromOffset(titleOffset, 0),
        Size = UDim2.new(1, -28 - titleOffset, 0, 16),
        Text = opts.Title or "Notification",
        TextSize = 14,
        TextColor3 = titleColor,
        Parent = inner,
    })
    local closeButton = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 6, 0, -5),
        Size = UDim2.fromOffset(24, 24),
        BackgroundTransparency = 1,
        Text = "×",
        TextColor3 = Theme.Muted,
        TextSize = 22,
        FontFace = Fonts.Bold,
        AutoButtonColor = false,
        Parent = inner,
    })
    closeButton.MouseEnter:Connect(function()
        tween(closeButton, { TextColor3 = Theme.Text }, 0.15)
    end)
    closeButton.MouseLeave:Connect(function()
        tween(closeButton, { TextColor3 = Theme.Muted }, 0.2)
    end)
    if opts.Content then
        label({
            Position = UDim2.fromOffset(titleOffset, 21),
            Size = UDim2.new(1, -titleOffset, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = opts.Content,
            TextSize = 13,
            FontFace = Fonts.Regular,
            TextColor3 = Theme.Muted,
            TextWrapped = true,
            TextTruncate = Enum.TextTruncate.None,
            TextYAlignment = Enum.TextYAlignment.Top,
            Parent = inner,
        })
    end

    local track = create("Frame", {
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 16, 1, -8),
        Size = UDim2.new(1, -32, 0, 3),
        BackgroundColor3 = Theme.Surface3,
        BorderSizePixel = 0,
        Parent = toast,
    })
    corner(track, UDim.new(1, 0))
    local progress = create("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Parent = track,
    })
    corner(progress, UDim.new(1, 0))

    task.defer(function()
        if outer.Parent then
            tween(outer, { Size = UDim2.new(1, 0, 0, toast.AbsoluteSize.Y) }, 0.3, Enum.EasingStyle.Quint)
        end
    end)
    tween(slide, { Position = UDim2.fromOffset(0, 0) }, 0.5, Enum.EasingStyle.Back)
    tween(toast, { GroupTransparency = 0 }, 0.3)
    tween(shadow, { ImageTransparency = 0.6 }, 0.4)
    tween(progress, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)

    local dismissed = false
    local function dismiss()
        if dismissed then
            return
        end
        dismissed = true
        for index, entry in ipairs(self._toasts) do
            if entry == dismiss then
                table.remove(self._toasts, index)
                break
            end
        end
        tween(slide, { Position = UDim2.fromOffset(320, 0) }, 0.3, Enum.EasingStyle.Quint)
        tween(toast, { GroupTransparency = 1 }, 0.2)
        tween(toastStroke, { Transparency = 1 }, 0.15)
        tween(shadow, { ImageTransparency = 1 }, 0.2)
        task.delay(0.22, function()
            outer.ClipsDescendants = true
            tween(outer, { Size = UDim2.new(1, 0, 0, -4) }, 0.22, Enum.EasingStyle.Quint)
            task.delay(0.24, function()
                outer:Destroy()
            end)
        end)
    end

    task.delay(duration, dismiss)
    closeButton.MouseButton1Click:Connect(dismiss)

    table.insert(self._toasts, dismiss)
    while #self._toasts > self.MaxNotifications do
        local oldest = table.remove(self._toasts, 1)
        oldest()
    end

    return { Dismiss = dismiss }
end

function Window:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    if self._cursorBound then
        self:_restoreMouseIcon()
    end
    for index, entry in ipairs(Library.Windows) do
        if entry == self then
            table.remove(Library.Windows, index)
            break
        end
    end
    for _, connection in ipairs(self._connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    self._connections = {}
    self._inputListeners = { Began = {}, Changed = {}, Ended = {}, Render = {} }
    self._frameSteps = {}

    local gui = self.Gui
    local removed = false
    local function remove()
        if removed then
            return
        end
        removed = true
        -- The Keybind Menu rides the same fade as the other overlays: its
        -- input was already cut with the window's connections, and it leaves
        -- with the screen gui.
        if self.KeybindMenu then
            self.KeybindMenu:Destroy()
        end
        if not pcall(gui.Destroy, gui) then
            pcall(function()
                gui.Enabled = false
            end)
        end
    end
    -- The fade out is decoration only. Input is already cut at this point, so
    -- if any of it fails the gui is removed straight away instead of being
    -- left frozen on screen.
    local ok, err = pcall(function()
        if self._dialog then
            self._dialog.Close()
        end
        self:_closePopups()
        local fit = self._fitScale or 1
        tween(self.Scale, { Scale = fit * 0.92 }, 0.22, Enum.EasingStyle.Quint)
        self:_fade(1, 0.2)
        tween(self.BodyStroke, { Transparency = 1 }, 0.12)
        tween(self.Shadow, { ImageTransparency = 1 }, 0.2)
        if self.MiniBar and self.MiniBar.Visible then
            tween(self.MiniBar, { GroupTransparency = 1 }, 0.18)
        end
        if self._backdrop then
            -- Frame steps are already cut, so the weather stops where it is.
            self._weatherField.Visible = false
            tween(self._backdropTintFrame, { BackgroundTransparency = 1 }, 0.2)
            tween(self._backdropHeat, { BackgroundTransparency = 1 }, 0.2)
        end
        for _, button in ipairs({ self.ToggleButton, self.OpenButton }) do
            if typeof(button) == "Instance" and button:IsA("GuiObject") then
                tween(button, { Size = UDim2.fromOffset(0, 0) }, 0.2, Enum.EasingStyle.Quint)
            end
        end
    end)
    if not ok then
        warn("[Aster UI] unload animation failed, removing the window directly: " .. tostring(err))
        remove()
        return
    end
    task.delay(0.24, remove)
end

Window.Unload = Window.Destroy

-- Unloads every window the library created, and with them anything the
-- library put on screen itself (draggable labels and the Keybind Menu).
function Library:Destroy()
    for index = #Library._draggableLabels, 1, -1 do
        local entry = Library._draggableLabels[index]
        if entry then
            pcall(function()
                entry:Destroy()
            end)
        end
    end
    for index = #Library.Windows, 1, -1 do
        local window = Library.Windows[index]
        if window then
            window:Destroy()
        end
    end
end

Library.Unload = Library.Destroy

-- A script thread that yielded inside an engine call (InvokeServer and the
-- like) resumes at game identity and can no longer touch the GUI in CoreGui.
-- Every public call checks for that: it raises the thread back to the identity
-- the library loaded at, or, when the executor cannot, runs the call on a
-- trusted Heartbeat thread and waits for its result.
local getIdentity = getthreadidentity or getidentity or get_thread_identity or (syn and syn.get_thread_identity)
local setIdentity = setthreadidentity or setidentity or set_thread_identity or (syn and syn.set_thread_identity)
local loadIdentity = nil
if getIdentity then
    local ok, identity = pcall(getIdentity)
    if ok and type(identity) == "number" then
        loadIdentity = identity
    end
end

local function threadLowered()
    local window = Library.Windows[#Library.Windows]
    local probe = window and window.Gui
    if typeof(probe) ~= "Instance" then
        return false
    end
    return not pcall(function()
        return probe.Name
    end)
end

local trustedQueue = {}
RunService.Heartbeat:Connect(function()
    if #trustedQueue == 0 then
        return
    end
    local queue = trustedQueue
    trustedQueue = {}
    for _, job in ipairs(queue) do
        job()
    end
end)

local function runTrusted(fn, ...)
    local args = table.pack(...)
    local result = nil
    table.insert(trustedQueue, function()
        result = table.pack(pcall(fn, table.unpack(args, 1, args.n)))
    end)
    while result == nil do
        task.wait()
    end
    if not result[1] then
        error(result[2], 0)
    end
    return table.unpack(result, 2, result.n)
end

local guardedObjects = setmetatable({}, { __mode = "k" })
local guardObject

local function guarded(fn)
    return function(...)
        if threadLowered() then
            if setIdentity then
                pcall(setIdentity, loadIdentity or 8)
            end
            if threadLowered() then
                return guardObject(runTrusted(fn, ...))
            end
        end
        return guardObject(fn(...))
    end
end

-- Elements carry their methods as closures, so each returned object gets its
-- public functions wrapped too; windows and tabs share the guarded metatables.
function guardObject(...)
    for index = 1, select("#", ...) do
        local object = select(index, ...)
        if type(object) == "table" and not guardedObjects[object] then
            local meta = getmetatable(object)
            if meta ~= Window and meta ~= Tab then
                guardedObjects[object] = true
                for key, value in pairs(object) do
                    if type(key) == "string" and type(value) == "function" and key:sub(1, 1) ~= "_" then
                        object[key] = guarded(value)
                    elseif type(key) == "number" and type(value) == "table" then
                        guardObject(value)
                    end
                end
            end
        end
    end
    return ...
end

for _, class in ipairs({ Library, Window, Tab }) do
    for key, value in pairs(class) do
        if type(key) == "string" and type(value) == "function" and key:sub(1, 1) ~= "_" then
            class[key] = guarded(value)
        end
    end
end

return Library
