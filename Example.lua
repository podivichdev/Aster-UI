--[[
    AirFlow example

    Loads the library from GitHub (replace YOURNAME with the account that
    hosts the repository) and builds a demo window with every common widget.
]]

local AirFlow = loadstring(game:HttpGet("https://raw.githubusercontent.com/YOURNAME/AirFlow/main/Library.lua"))()

local Window = AirFlow:CreateWindow({
    Name = "AirFlow",
    Title = "AirFlow Example",
    LoadingTitle = "AirFlow",
    LoadingSubtitle = "Example",
    ToggleUIKeybind = "RightControl",
    Theme = "Cybrion",
    Weather = "Matrix",
    ConfigurationSaving = { FolderName = "AirFlowExample" },
    ToggleButton = { Platform = "Mobile", Icon = "layout-grid" },
    Home = {
        Discord = "discord.gg/example",
        Stats = { "Players", "Session", "FPS", "Ping" },
    },
})

local Main = Window:Tab({ Name = "Main", Icon = "home" })
local Settings = Window:Tab({ Name = "Settings", Icon = "settings" })

-- Main tab ----------------------------------------------------------

Main:Section("Controls")

Main:Paragraph({
    Name = "Welcome",
    Content = "Every widget in AirFlow, on one tab. Toggle the window with RightControl.",
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
            Title = "AirFlow",
            Content = "Hello from the example script.",
            Duration = 4,
            Type = "Success",
        })
    end,
})

Main:Button({
    Name = "Read the flag value",
    Callback = function()
        print("[demo] slider value:", AirFlow.Flags["Demo.Speed"]:Get())
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
        AirFlow:SetTheme(value)
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

Settings:Section("Configs")

Settings:Button({
    Name = "Save config",
    Callback = function()
        print("[demo] saved:", Window:SaveConfig("Default"))
    end,
})

Settings:Button({
    Name = "Load config",
    Callback = function()
        print("[demo] loaded:", Window:LoadConfig("Default"))
    end,
})

-- Ready -------------------------------------------------------------

Window:Notify({
    Title = "AirFlow",
    Icon = "sparkles",
    Content = "Example loaded. RightControl toggles the window.",
    Duration = 6,
})
