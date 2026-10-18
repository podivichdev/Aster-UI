--[[
    Aster UI example

    Loads the library from GitHub and builds a demo window with every
    common widget, plus a Config tab mirroring a real script's settings:
    interface options, the config manager, the theme manager and the
    direct config API.
]]

local Aster = loadstring(game:HttpGet("https://raw.githubusercontent.com/podivichdev/Aster-UI/main/Library.lua"))()

local Window = Aster:CreateWindow({
    Name = "AsterUI",
    Title = "Aster UI Example",
    LoadingTitle = "Aster UI",
    LoadingSubtitle = "Example",
    ToggleUIKeybind = "RightControl",
    Theme = "Cybrion",
    Weather = "Matrix",
    ConfigurationSaving = { FolderName = "AsterUIExample" },
    ToggleButton = { Platform = "Mobile", Icon = "layout-grid" },
    Home = {
        Discord = "discord.gg/example",
        Stats = { "Players", "Session", "FPS", "Ping" },
    },
})

local Main = Window:Tab({ Name = "Main", Icon = "home" })
local Settings = Window:Tab({ Name = "Settings", Icon = "settings" })
local Config = Window:Tab({ Name = "Config", Icon = "save" })

-- Main tab ----------------------------------------------------------

Main:Section("Controls")

Main:Paragraph({
    Name = "Welcome",
    Content = "Every widget in Aster UI, on one tab. Toggle the window with RightControl.",
})

Main:Toggle({
    Name = "Enable feature",
    Desc = "A simple on/off switch.",
    Flag = "Demo.Enable",
    Default = false,
    Callback = function(on)
        print("[demo] enable:", on)
    end,
})

Main:Slider({
    Name = "Speed",
    Desc = "OnRelease fires when you let go of the knob.",
    Flag = "Demo.Speed",
    Min = 0,
    Max = 100,
    Step = 1,
    Suffix = " u/s",
    Default = 50,
    Callback = function(value)
        print("[demo] speed:", value)
    end,
})

Main:Divider({ Text = "Selection" })

Main:Dropdown({
    Name = "Mode",
    Flag = "Demo.Mode",
    Options = { "Legit", "Rage", "Hybrid" },
    Default = "Legit",
    Callback = function(value)
        print("[demo] mode:", value)
    end,
})

Main:Dropdown({
    Name = "Targets",
    Desc = "Multi-select: the callback receives a table.",
    Flag = "Demo.Targets",
    Options = { "Players", "Bots", "NPCs" },
    Default = { "Players" },
    Multi = true,
    Callback = function(values)
        print("[demo] targets:", table.concat(values, ", "))
    end,
})

Main:Keybind({
    Name = "Panic key",
    Flag = "Demo.Key",
    Default = "P",
    Callback = function(key)
        print("[demo] pressed:", key.Name)
    end,
})

Main:Section("Actions")

Main:Button({
    Name = "Push a notification",
    Style = "Primary",
    Callback = function()
        Window:Notify({
            Title = "Aster UI",
            Content = "Hello from the example script.",
            Duration = 4,
            Type = "Success",
        })
    end,
})

Main:Button({
    Name = "Read the flag value",
    Callback = function()
        print("[demo] slider value:", Aster.Flags["Demo.Speed"]:Get())
    end,
})

-- Settings tab ------------------------------------------------------

Settings:Section("Look")

Settings:ColorPicker({
    Name = "Accent color",
    Flag = "Demo.Accent",
    Default = Color3.fromRGB(50, 230, 150),
    Callback = function(color)
        print("[demo] color:", color)
    end,
})

Settings:Dropdown({
    Name = "Theme",
    Options = { "Cybrion", "Midnight", "Nebula", "Synthwave", "Sakura", "Gold" },
    Default = "Cybrion",
    Callback = function(value)
        Aster:SetTheme(value)
    end,
})

Settings:Dropdown({
    Name = "Weather",
    Options = { "Snow", "Rain", "Hell Fire", "Sakura", "Fireflies", "Matrix", "None" },
    Default = "Matrix",
    Callback = function(value)
        Window:SetWeather(value)
    end,
})

Settings:Section("Input")

Settings:Input({
    Name = "Profile name",
    Flag = "Demo.Name",
    Placeholder = "type something...",
    Callback = function(text, enterPressed)
        print("[demo] text:", text, "enter:", enterPressed)
    end,
})

Settings:Stepper({
    Name = "Volume",
    Flag = "Demo.Volume",
    Min = 0,
    Max = 10,
    Step = 1,
    Default = 5,
    Callback = function(value)
        print("[demo] volume:", value)
    end,
})

Settings:Progress({
    Name = "Example progress",
    Flag = "Demo.Progress",
    Default = 35,
})

-- Config tab ---------------------------------------------------------
-- Everything a real script exposes in its settings: how the menu itself
-- is driven, the two managers, and the window methods behind them.
-- Naming note: Tab:Create* and group:Create* are aliases of the plain
-- names (Tab:Toggle == Tab:CreateToggle), both styles are the same call.

local interface = Config:AddLeftGroupbox({ Name = "Interface", Icon = "monitor" })

interface:CreateKeybind({
    Name = "Menu key",
    CurrentKeybind = "RightControl",
    Flag = "MenuKey",
    OnChanged = function(key)
        if key then
            Window:SetKeybind(key)
        end
    end,
})

interface:CreateDropdown({
    Name = "Toggle button",
    Options = { "Mobile only", "Mobile & PC" },
    CurrentOption = "Mobile only",
    AllowNone = false,
    Flag = "ToggleButtonPlatform",
    Callback = function(option)
        Window:SetToggleButtonPlatform(option == "Mobile & PC" and "Both" or "Mobile")
    end,
})

interface:CreateToggle({
    Name = "Backdrop",
    CurrentValue = true,
    Flag = "Backdrop",
    Callback = function(value)
        Window:SetBackdrop(value)
    end,
})

interface:CreateButton({
    Name = "Unload",
    Icon = "power",
    Callback = function()
        Window:Confirm({
            Title = "Unload?",
            Content = "Every feature is switched off and the menu closes.",
            ConfirmText = "Unload",
            Callback = function()
                Window:Destroy()
            end,
        })
    end,
})

-- Ready-made managers: the config manager carries every operation
-- (create, save, load, delete, rename, reset, autoload, share codes),
-- the theme manager handles themes, backgrounds and weather.
Config:CreateConfigManager({ Name = "Configs", Side = "Left" })
Config:CreateThemeManager({ Name = "Themes", Side = "Right" })

-- The direct config API ----------------------------------------------
-- Same operations, callable straight from code. Saved files live in
-- this script's own folder (Window.ConfigFolder); Reset only puts the
-- flagged widgets back to their defaults.

local api = Config:Groupbox({ Name = "Config API", Icon = "code", Side = "Right" })

local function report(ok, title, detail)
    Window:Notify({
        Title = title,
        Content = detail,
        Type = ok and "Success" or "Error",
        Duration = 3,
    })
end

local nameInput = api:Input({ Name = "Config name", Placeholder = "example" })

local function pickedName()
    local name = nameInput:Get()
    if type(name) == "string" and name ~= "" then
        return name
    end
    report(false, "No name", "Type a config name in the box first")
    return nil
end

local status
local function refresh()
    if not status then
        return
    end
    status:Set(("loaded: %s   |   autoload: %s   |   %d saved"):format(
        Window.LoadedConfig or "none",
        Window:GetAutoload() or "none",
        #Window:ListConfigs()
    ))
end

Window:OnConfigChanged(refresh)

api:ButtonRow({
    { Name = "Save", Callback = function()
        local name = pickedName()
        if not name then
            return
        end
        local ok, err = Window:SaveConfig(name)
        report(ok, ok and "Config saved" or "Save failed", ok and name or tostring(err))
    end },
    { Name = "Load", Callback = function()
        local name = pickedName()
        if not name then
            return
        end
        local ok, err = Window:LoadConfig(name)
        report(ok, ok and "Config loaded" or "Load failed", ok and name or tostring(err))
    end },
})

api:ButtonRow({
    { Name = "Delete", Style = "Danger", Callback = function()
        local name = pickedName()
        if not name then
            return
        end
        local ok, err = Window:DeleteConfig(name)
        report(ok, ok and "Config deleted" or "Delete failed", ok and name or tostring(err))
    end },
    { Name = "Rename", Callback = function()
        local name = pickedName()
        if not name then
            return
        end
        local newName = name .. " 2"
        local ok, err = Window:RenameConfig(name, newName)
        if ok then
            nameInput:Set(newName)
        end
        report(ok, ok and "Config renamed" or "Rename failed", ok and (name .. " -> " .. newName) or tostring(err))
    end },
})

api:ButtonRow({
    { Name = "Set autoload", Callback = function()
        local name = pickedName()
        if not name then
            return
        end
        local ok, err = Window:SetAutoload(name)
        report(ok, ok and "Autoload set" or "Autoload failed", ok and name or tostring(err))
    end },
    { Name = "Clear autoload", Callback = function()
        local ok, err = Window:SetAutoload(nil)
        report(ok, ok and "Autoload cleared" or "Clear failed", ok and "none" or tostring(err))
    end },
})

api:Dropdown({
    Name = "Autoload mode",
    Options = { "All accounts", "This account" },
    Default = Window:GetAutoloadMode() == "Account" and "This account" or "All accounts",
    AllowNone = false,
    Callback = function(choice)
        local ok, err = Window:SetAutoloadMode(choice == "This account" and "Account" or "Global")
        report(ok ~= false, "Autoload mode", ok ~= false and choice or tostring(err))
    end,
})

api:ButtonRow({
    { Name = "Export (copy)", Callback = function()
        local name = pickedName()
        if not name then
            return
        end
        local code, err = Window:ExportConfig(name)
        if not code then
            report(false, "Export failed", tostring(err))
            return
        end
        Window:CopyToClipboard(code, "Config code")
        report(true, "Exported", "Code for '" .. name .. "' copied to the clipboard")
    end },
    { Name = "Refresh", Callback = refresh },
})

api:Divider({ Text = "share" })

local codeInput = api:Input({ Name = "Config code", Placeholder = "paste a config code here" })

api:Button({
    Name = "Import code",
    Callback = function()
        local code = codeInput:Get()
        if type(code) ~= "string" or code == "" then
            report(false, "Nothing to import", "Paste a config code first")
            return
        end
        -- A name as the second argument also saves the config; nil only
        -- applies the settings. force = true accepts codes from other folders.
        local ok, err = Window:ImportConfig(code, nil, true)
        report(ok, ok and "Config imported" or "Import failed", ok and "Applied to the current settings" or tostring(err))
    end,
})

api:Button({
    Name = "Clear workspace",
    Style = "Danger",
    Callback = function()
        Window:Confirm({
            Title = "Clear workspace?",
            Content = "Deletes every config, theme, autoload and setting inside " .. Window.ConfigFolder .. ".",
            Icon = "trash-2",
            ConfirmText = "Clear",
            Callback = function()
                local ok = Window:ClearWorkspace()
                report(ok, ok and "Workspace cleared" or "Clear incomplete",
                    ok and "Everything was deleted" or "Some files could not be deleted")
                refresh()
            end,
        })
    end,
})

status = api:Paragraph({ Name = "Status", Content = "-" })
refresh()

-- Ready -------------------------------------------------------------

Window:Notify({
    Title = "Aster UI",
    Icon = "sparkles",
    Content = "Example loaded. RightControl toggles the window.",
    Duration = 6,
})
