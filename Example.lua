-- Aster UI example - https://github.com/podivichdev/Aster-UI

local Aster = loadstring(game:HttpGet("https://raw.githubusercontent.com/podivichdev/Aster-UI/main/Library.lua"))()

local Window = Aster:CreateWindow({
    Title = "Aster UI",
    Subtitle = "Full Example",
    LoadingTitle = "Aster UI",
    LoadingSubtitle = "Loading example…",
    ToggleUIKeybind = "RightControl",
    Icon = "None",
    Theme = "Cybrion",
    Weather = "Matrix",
    Backdrop = { Dim = true },
    AlwaysOnTop = true,
    AutoTranslate = false,
    ShowCustomCursor = false,
    UnlockMouseWhileOpen = true,
    ForceCheckbox = false,
    KeybindMenu = false,
    UIScale = 1,
    AdaptiveSize = true,
    Density = "Default",
    IslandDraggable = true,
    ConfigurationSaving = { FolderName = "AsterUI/Example" },
    ToggleButton = { Platform = "Mobile", Icon = "layout-grid" },
    Home = {
        Discord = "discord.gg/asterhub",
        Stats = { "FPS", "Ping", "Game", "Players", "ServerAge", "Session", "Executor" },
        HideName = false,
        HideAvatar = false,
    },
})

local Tabs = {
    Widgets = Window:Tab({ Name = "Widgets", Icon = "layout-dashboard", Desc = "Every common control" }),
    Advanced = Window:Tab({ Name = "Advanced", Icon = "layers", Desc = "Tables, status, viewport, order list" }),
    Layout = Window:Tab({ Name = "Layout", Icon = "columns-2", Desc = "Sections, groupboxes, island" }),
    Settings = Window:Tab({ Name = "Settings", Icon = "settings", Desc = "Managers + dialogs" }),
}

-- Widgets
do
    local ControlsPage = Tabs.Widgets:SubTab({ Name = "Controls", Icon = "toggle-right" })
    local SelectionPage = Tabs.Widgets:SubTab({ Name = "Selection", Icon = "list" })
    local LookPage = Tabs.Widgets:SubTab({ Name = "Look", Icon = "palette" })
    local InputPage = Tabs.Widgets:SubTab({ Name = "Input", Icon = "keyboard" })

    local ControlsLeft = ControlsPage:AddLeftGroupbox({ Name = "Toggles & Sliders", Icon = "sliders-horizontal" })
    local ControlsRight = ControlsPage:AddRightGroupbox({ Name = "Buttons & Feedback", Icon = "zap" })

    ControlsLeft:Paragraph({
        Name = "Welcome",
        Content = "This example shows every public widget. Toggle the window with RightControl. Nothing here affects the game.",
    })

    ControlsLeft:Toggle({
        Name = "Enable feature",
        Desc = "Simple on / off switch.",
        Flag = "Demo.Enable",
        Default = false,
        Tooltip = "Example toggle",
        Callback = function(on)
            print("[demo] enable:", on)
        end,
    })

    ControlsLeft:Toggle({
        Name = "Risky option",
        Desc = "Starts on; has a longer description.",
        Flag = "Demo.Risky",
        Default = true,
        Callback = function(on)
            print("[demo] risky:", on)
        end,
    })

    ControlsLeft:Slider({
        Name = "Speed",
        Desc = "Drag or type the chip value.",
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

    ControlsLeft:Slider({
        Name = "Smoothness",
        Flag = "Demo.Smoothness",
        Min = 0,
        Max = 10,
        Step = 0.1,
        Default = 3,
        Callback = function(value)
            print("[demo] smoothness:", value)
        end,
    })

    ControlsLeft:Stepper({
        Name = "Volume",
        Desc = "− / + stepper.",
        Flag = "Demo.Volume",
        Min = 0,
        Max = 10,
        Step = 1,
        Default = 5,
        Callback = function(value)
            print("[demo] volume:", value)
        end,
    })

    ControlsRight:Button({
        Name = "Push notification",
        Style = "Primary",
        Icon = "bell",
        Callback = function()
            Window:Notify({
                Title = "Aster UI",
                Content = "Hello from the example script.",
                Icon = "sparkles",
                Duration = 4,
                Type = "Success",
            })
        end,
    })

    ControlsRight:Button({
        Name = "Read flag value",
        Callback = function()
            local speed = Aster.Flags["Demo.Speed"]
            print("[demo] slider value:", speed and speed:Get())
        end,
    })

    ControlsRight:Button({
        Name = "Secondary style",
        Style = "Secondary",
        Callback = function()
            print("[demo] secondary button")
        end,
    })

    ControlsRight:Divider()

    ControlsRight:Progress({
        Name = "Example progress",
        Flag = "Demo.Progress",
        Default = 35,
    })

    ControlsRight:Label({
        Text = "Live label (updates every 2s)",
        Update = function()
            return string.format("Clock: %s", os.date("%H:%M:%S"))
        end,
        UpdateRate = 2,
    })

    local SelectionLeft = SelectionPage:AddLeftGroupbox({ Name = "Dropdowns", Icon = "list" })
    local SelectionRight = SelectionPage:AddRightGroupbox({ Name = "Keybinds", Icon = "keyboard" })

    SelectionLeft:Dropdown({
        Name = "Mode",
        Flag = "Demo.Mode",
        Options = { "Legit", "Rage", "Hybrid" },
        Default = "Legit",
        AllowNone = false,
        Callback = function(value)
            print("[demo] mode:", value)
        end,
    })

    SelectionLeft:Dropdown({
        Name = "Targets",
        Desc = "Multi-select: callback receives a table.",
        Flag = "Demo.Targets",
        Options = { "Players", "Bots", "NPCs", "Props" },
        Default = { "Players" },
        Multi = true,
        Callback = function(values)
            print("[demo] targets:", table.concat(values, ", "))
        end,
    })

    SelectionLeft:Dropdown({
        Name = "Origin",
        Flag = "Demo.Origin",
        Options = { "Bottom", "Top", "Center", "Mouse" },
        Default = "Bottom",
        Callback = function(value)
            print("[demo] origin:", value)
        end,
    })

    SelectionRight:Keybind({
        Name = "Panic key",
        Flag = "Demo.PanicKey",
        Default = "P",
        Callback = function(key)
            print("[demo] panic pressed:", typeof(key) == "EnumItem" and key.Name or key)
        end,
        OnChanged = function(key)
            print("[demo] panic rebound:", typeof(key) == "EnumItem" and key.Name or key)
        end,
    })

    -- use Enum.UserInputType, not "MB2" strings
    SelectionRight:Keybind({
        Name = "Aim key",
        Desc = "Supports mouse buttons (MB1 / MB2 / MB3).",
        Flag = "Demo.AimKey",
        Default = Enum.UserInputType.MouseButton2,
        OnChanged = function(key)
            print("[demo] aim key:", typeof(key) == "EnumItem" and key.Name or key)
        end,
    })

    SelectionRight:Keybind({
        Name = "Fly key",
        Flag = "Demo.FlyKey",
        Default = "None",
        Callback = function()
            print("[demo] fly key pressed")
        end,
    })

    local LookLeft = LookPage:AddLeftGroupbox({ Name = "Colors", Icon = "palette" })
    local LookRight = LookPage:AddRightGroupbox({ Name = "Theme & Weather", Icon = "cloud-sun" })

    LookLeft:ColorPicker({
        Name = "Accent color",
        Flag = "Demo.Accent",
        Default = Color3.fromRGB(50, 230, 150),
        Callback = function(color)
            print("[demo] accent:", color)
        end,
    })

    LookLeft:ColorPicker({
        Name = "ESP color",
        Flag = "Demo.EspColor",
        Default = Color3.fromRGB(255, 0, 0),
        Callback = function(color)
            print("[demo] esp color:", color)
        end,
    })

    LookLeft:ColorPicker({
        Name = "FOV color",
        Flag = "Demo.FovColor",
        Default = Color3.fromRGB(237, 255, 181),
        Callback = function(color)
            print("[demo] fov color:", color)
        end,
    })

    LookRight:Dropdown({
        Name = "Theme preset",
        Options = {
            "Cybrion", "Midnight", "Ocean", "Rose", "Emerald", "Amber",
            "Mono", "Nebula", "Synthwave", "Sakura", "Velvet", "Crimson",
            "Sunset", "Gold", "Cyber", "Toxic", "Matcha", "Aurora", "Frost", "Abyss",
        },
        Default = "Cybrion",
        Callback = function(value)
            if Aster.SetTheme then
                Aster:SetTheme(value)
            elseif Window.SetTheme then
                Window:SetTheme(value)
            end
        end,
    })

    LookRight:Dropdown({
        Name = "Weather",
        Options = { "Snow", "Rain", "Hell Fire", "Sakura", "Fireflies", "Matrix", "None" },
        Default = "Matrix",
        Callback = function(value)
            if Window.SetWeather then
                Window:SetWeather(value)
            end
        end,
    })

    LookRight:Toggle({
        Name = "Dim backdrop",
        Desc = "Darkens the screen behind the window.",
        Flag = "Demo.Dim",
        Default = true,
        Callback = function(value)
            if Window.SetDim then
                Window:SetDim(value)
            end
        end,
    })

    local InputLeft = InputPage:AddLeftGroupbox({ Name = "Text & Numbers", Icon = "text-cursor-input" })
    local InputRight = InputPage:AddRightGroupbox({ Name = "Misc inputs", Icon = "pen-line" })

    InputLeft:Input({
        Name = "Profile name",
        Flag = "Demo.ProfileName",
        Placeholder = "type something…",
        Callback = function(text, enterPressed)
            print("[demo] profile:", text, "enter:", enterPressed)
        end,
    })

    InputLeft:Input({
        Name = "Numeric only",
        Flag = "Demo.Numeric",
        Placeholder = "0 – 999",
        Numeric = true,
        Default = "42",
        Callback = function(value, enterPressed)
            print("[demo] numeric:", value, "enter:", enterPressed)
        end,
    })

    InputRight:Paragraph({
        Name = "Note",
        Content = "Input callbacks fire on change and again when Enter is pressed (second arg = true).",
    })

    InputRight:Divider({ Text = "Optional divider text" })
    InputRight:Section("Section header")

    InputRight:Label({
        Text = "Static label with custom colour",
        Color = Color3.fromRGB(50, 230, 150),
    })
end

-- Advanced
do
    local DataPage = Tabs.Advanced:SubTab({ Name = "Data", Icon = "table" })
    local StatusPage = Tabs.Advanced:SubTab({ Name = "Status", Icon = "activity" })
    local MediaPage = Tabs.Advanced:SubTab({ Name = "Media", Icon = "image" })
    local OrderPage = Tabs.Advanced:SubTab({ Name = "Order", Icon = "list-ordered" })

    local DataBox = DataPage:AddLeftGroupbox({ Name = "Table", Icon = "table" })
    if DataBox.Table then
        DataBox:Table({
            Name = "Players (demo)",
            Columns = { "Name", "Team", "Ping" },
            Rows = {
                { "Alice", "Blue", "32" },
                { "Bob", "Red", "48" },
                { "Carol", "Blue", "21" },
            },
        })
    else
        DataBox:Paragraph({
            Name = "Table",
            Content = "Table widget is available when the library exposes Tab:Table / Groupbox:Table.",
        })
    end

    local DataRight = DataPage:AddRightGroupbox({ Name = "Order list", Icon = "list-ordered" })
    if DataRight.OrderList then
        DataRight:OrderList({
            Name = "Priority",
            Flag = "Demo.Order",
            Items = { "Head", "Torso", "Arms", "Legs" },
            MaxRows = 6,
            Numbered = true,
            Arrows = true,
            Callback = function(items)
                print("[demo] order:", table.concat(items, " > "))
            end,
        })
    else
        DataRight:Paragraph({
            Name = "OrderList",
            Content = "Drag or use arrows to reorder items. Flag stores the ordered list.",
        })
    end

    local StatusBox = StatusPage:AddLeftGroupbox({ Name = "Status rows", Icon = "heart-pulse" })
    if StatusBox.StatusList then
        StatusBox:StatusList({
            Name = "Systems",
            Entries = {
                { Name = "Aimbot", Status = "Online", Color = "Success" },
                { Name = "ESP", Status = "Idle", Color = "Warning" },
                { Name = "Fly", Status = "Offline", Color = "Error" },
            },
        })
    elseif StatusBox.Statuses then
        StatusBox:Statuses({
            { Name = "Aimbot", Status = "Online" },
            { Name = "ESP", Status = "Idle" },
            { Name = "Fly", Status = "Offline" },
        })
    elseif StatusBox.Status then
        StatusBox:Status({ Name = "Aimbot", Status = "Online" })
        StatusBox:Status({ Name = "ESP", Status = "Idle" })
        StatusBox:Status({ Name = "Fly", Status = "Offline" })
    else
        StatusBox:Paragraph({
            Name = "Status",
            Content = "Status / StatusList widgets show live coloured rows (Success / Warning / Error).",
        })
    end

    local StatusRight = StatusPage:AddRightGroupbox({ Name = "Progress demo", Icon = "loader" })
    StatusRight:Progress({
        Name = "Load",
        Flag = "Demo.LoadProgress",
        Default = 72,
    })
    StatusRight:Progress({
        Name = "Health",
        Flag = "Demo.HealthProgress",
        Default = 100,
    })

    local MediaLeft = MediaPage:AddLeftGroupbox({ Name = "Image", Icon = "image" })
    if MediaLeft.Image then
        MediaLeft:Image({
            Name = "Preview image",
            Image = "rbxassetid://103859712365480",
            Height = 160,
        })
    else
        MediaLeft:Paragraph({
            Name = "Image",
            Content = "Image card: pass Image = rbxassetid://… and optional Height.",
        })
    end

    local MediaRight = MediaPage:AddRightGroupbox({ Name = "Viewport", Icon = "box" })
    if MediaRight.Viewport then
        MediaRight:Viewport({
            Height = 180,
            Spin = true,
            SpinSpeed = 40,
            Angle = -20,
            Pitch = 10,
            FieldOfView = 30,
            Distance = 1.1,
            Caption = "Viewport demo",
        })
        MediaRight:Toggle({
            Name = "Spin",
            Default = true,
            Callback = function() end,
        })
    else
        MediaRight:Paragraph({
            Name = "Viewport",
            Content = "3D ViewportFrame card. Supports Spin, Angle, Pitch, FOV, Distance, Caption and Model.",
        })
    end

    local OrderBox = OrderPage:AddLeftGroupbox({ Name = "Reorder", Icon = "arrow-up-down" })
    if OrderBox.OrderList then
        OrderBox:OrderList({
            Name = "ESP stack",
            Flag = "Demo.EspStack",
            Items = { "Name", "Distance", "Health", "Team", "Box" },
            MaxRows = 8,
            Numbered = true,
            Arrows = true,
            Callback = function(items)
                print("[demo] esp stack:", table.concat(items, ", "))
            end,
        })
    else
        OrderBox:Paragraph({
            Name = "OrderList",
            Content = "Always-open reorderable list. Drag rows or use arrows.",
        })
    end
end

-- Layout
do
    local GroupPage = Tabs.Layout:SubTab({ Name = "Groupboxes", Icon = "layout-panel-left" })
    local SectionPage = Tabs.Layout:SubTab({ Name = "Sections", Icon = "separator-horizontal" })

    local Left = GroupPage:AddLeftGroupbox({ Name = "Left column", Icon = "panel-left" })
    local Right = GroupPage:AddRightGroupbox({ Name = "Right column", Icon = "panel-right" })

    Left:Toggle({ Name = "Left toggle A", Flag = "Demo.LeftA", Default = false })
    Left:Toggle({ Name = "Left toggle B", Flag = "Demo.LeftB", Default = true })
    Left:Slider({ Name = "Left slider", Flag = "Demo.LeftSlider", Min = 1, Max = 20, Default = 10 })

    Right:Dropdown({
        Name = "Right dropdown",
        Flag = "Demo.RightDrop",
        Options = { "One", "Two", "Three" },
        Default = "One",
    })
    Right:ColorPicker({
        Name = "Right colour",
        Flag = "Demo.RightColor",
        Default = Color3.fromRGB(128, 160, 246),
    })
    Right:Button({
        Name = "Right button",
        Style = "Primary",
        Callback = function()
            print("[demo] right button")
        end,
    })

    SectionPage:Section("First section")
    SectionPage:Toggle({ Name = "Loose toggle", Flag = "Demo.LooseToggle", Default = false })
    SectionPage:Divider()
    SectionPage:Section("Second section")
    SectionPage:Slider({
        Name = "Loose slider",
        Flag = "Demo.LooseSlider",
        Min = 0,
        Max = 50,
        Default = 25,
    })
    SectionPage:Paragraph({
        Name = "About columns",
        Content = "AddLeftGroupbox / AddRightGroupbox place panels on the two columns. IslandGroupbox floats outside the window body.",
    })
end

-- Island
if type(Window.IslandGroupbox) == "function" then
    local island = Window:IslandGroupbox({
        Name = "Quick Settings",
        Icon = "zap",
        Width = 300,
        Offset = 12,
        Tabs = { Tabs.Widgets, Tabs.Layout },
    })

    island:Toggle({
        Name = "Island toggle",
        Desc = "Same widgets, outside the window body.",
        Flag = "Demo.Island.Enabled",
        Default = true,
        Callback = function(on)
            print("[demo] island toggle:", on)
        end,
    })

    island:Dropdown({
        Name = "Preset",
        Flag = "Demo.Island.Preset",
        Options = { "Balanced", "Aggressive", "Stealth" },
        Default = "Balanced",
        Callback = function(value)
            print("[demo] island preset:", value)
        end,
    })

    island:Slider({
        Name = "Intensity",
        Flag = "Demo.Island.Intensity",
        Min = 0,
        Max = 100,
        Default = 40,
    })

    island:Button({
        Name = "Notify from island",
        Style = "Primary",
        Callback = function()
            Window:Notify({
                Title = "Island groupbox",
                Content = "This button lives outside the window body.",
                Duration = 4,
                Type = "Success",
            })
        end,
    })
else
    Window:Notify({
        Title = "Library out of date",
        Content = "IslandGroupbox is missing — update Library.lua.",
        Duration = 8,
        Type = "Warning",
    })
end

-- Settings
do
    Tabs.Settings:InterfaceManager({ Name = "Interface", Side = "Left", Icon = "tv-minimal" })
    Tabs.Settings:ConfigManager({ Name = "Configs", Side = "Left", Icon = "folder" })
    Tabs.Settings:ThemeManager({ Name = "Themes", Side = "Right", Icon = "palette" })

    local DialogBox = Tabs.Settings:AddLeftGroupbox({ Name = "Dialogs & API", Icon = "message-square" })

    DialogBox:Button({
        Name = "Confirm dialog",
        Style = "Primary",
        Callback = function()
            if Window.Dialog then
                Window:Dialog({
                    Title = "Confirm",
                    Content = "This is a demo dialog. Nothing will be deleted.",
                    Buttons = {
                        {
                            Name = "Cancel",
                            Callback = function()
                                print("[demo] dialog cancelled")
                            end,
                        },
                        {
                            Name = "OK",
                            Style = "Primary",
                            Callback = function()
                                print("[demo] dialog confirmed")
                            end,
                        },
                    },
                })
            else
                Window:Notify({
                    Title = "Dialog",
                    Content = "Window:Dialog is not available in this build.",
                    Type = "Warning",
                    Duration = 4,
                })
            end
        end,
    })

    DialogBox:Button({
        Name = "Info notification",
        Callback = function()
            Window:Notify({
                Title = "Info",
                Content = "Type = Info",
                Type = "Info",
                Duration = 3,
            })
        end,
    })

    DialogBox:Button({
        Name = "Warning notification",
        Callback = function()
            Window:Notify({
                Title = "Warning",
                Content = "Type = Warning",
                Type = "Warning",
                Duration = 3,
            })
        end,
    })

    DialogBox:Button({
        Name = "Error notification",
        Callback = function()
            Window:Notify({
                Title = "Error",
                Content = "Type = Error",
                Type = "Error",
                Duration = 3,
            })
        end,
    })

    DialogBox:Divider()

    DialogBox:Button({
        Name = "Print all flags",
        Callback = function()
            print("---- Aster.Flags ----")
            for name, handle in pairs(Aster.Flags) do
                local value = handle.Get and handle:Get() or handle.Value
                print(name, "=", value)
            end
        end,
    })
end

if Window.LoadAutoload then
    Window:LoadAutoload()
end

Window:Notify({
    Title = "Aster UI",
    Content = "Full example loaded. RightControl toggles the window.",
    Icon = "sparkles",
    Duration = 6,
    Type = "Success",
})

print("---- Aster UI Example loaded ----")
