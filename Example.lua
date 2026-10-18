--[[
    Aster UI example

    Loads the library from GitHub and builds a demo window: every common
    widget on the Main tab, and a Config tab mirroring a real script's
    settings (interface options, config manager, theme manager).
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
local Config = Window:Tab({ Name = "Config", Icon = "settings" })

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

Main:Section("Look")

Main:ColorPicker({
    Name = "Accent color",
    Flag = "Demo.Accent",
    Default = Color3.fromRGB(50, 230, 150),
    Callback = function(color)
        print("[demo] color:", color)
    end,
})

Main:Dropdown({
    Name = "Theme",
    Options = { "Cybrion", "Midnight", "Nebula", "Synthwave", "Sakura", "Gold" },
    Default = "Cybrion",
    Callback = function(value)
        Aster:SetTheme(value)
    end,
})

Main:Dropdown({
    Name = "Weather",
    Options = { "Snow", "Rain", "Hell Fire", "Sakura", "Fireflies", "Matrix", "None" },
    Default = "Matrix",
    Callback = function(value)
        Window:SetWeather(value)
    end,
})

Main:Section("Input")

Main:Input({
    Name = "Profile name",
    Flag = "Demo.Name",
    Placeholder = "type something...",
    Callback = function(text, enterPressed)
        print("[demo] text:", text, "enter:", enterPressed)
    end,
})

Main:Stepper({
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

Main:Progress({
    Name = "Example progress",
    Flag = "Demo.Progress",
    Default = 35,
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

-- Config tab ---------------------------------------------------------
-- What a real script keeps in its settings: the options that drive the
-- menu itself, the ready-made config manager (create, save, load,
-- delete, rename, reset, autoload, share codes) and the theme manager
-- (themes, backgrounds, weather).
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

Config:CreateConfigManager({ Name = "Configs", Side = "Left" })
Config:CreateThemeManager({ Name = "Themes", Side = "Right" })

-- Ready -------------------------------------------------------------

Window:Notify({
    Title = "Aster UI",
    Icon = "sparkles",
    Content = "Example loaded. RightControl toggles the window.",
    Duration = 6,
})
