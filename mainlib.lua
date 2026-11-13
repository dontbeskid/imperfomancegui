--// Written by depso
--// MIT License
--// Copyright (c) 2024 Depso
-- ------------------------------------------------------------------
--// v2 (improved fork). What changed:
--//
--// THEMING (new):
--//   ImGui.Theme.Accent        - current accent color (default blue)
--//   ImGui:SetAccent(Color|Name) - recolor prefabs + every open window live
--//   ImGui:SetTheme(Name)      - apply a preset from ImGui.Themes
--//   ImGui:DetectAccent()      - auto-detect the prefab accent color
--//   ImGui:SetRainbow(Bool, Speed) - animated cycling accent (opt-in)
--//
--// FEATURES (new):
--//   ImGui:Notify({...})       - toast notifications (stacking, icon, timeout)
--//   ImGui:Prompt({...})       - modal with buttons, supports :Wait()
--//   Container:ThemePicker()   - dropdown that switches the theme live
--//   WindowConfig:Toggle()     - collapse/expand a window
--//   ImGui:SetWindowsVisible() + ImGui.ToggleKey (RightShift by default)
--//   ImGui:Destroy()           - full unload (GUI + global connections)
--//   ImGui.AnimationsEnabled   - global kill-switch for all tweens
--//
--// PERFORMANCE (design & animations untouched, same 0.1s tweens):
--//   - TweenInfo objects are cached (no allocation on every tween)
--//   - Conflicting tweens on the same instance/property are cancelled
--//     instead of piling up (hover spam / drag used to stack dozens)
--//   - Dragging & slider dragging write properties directly (no Tween
--//     object per mouse move). ImGui.SmoothDragging = true restores old
--//   - Instance.new parent is set AFTER properties (Roblox best practice)
--//   - MergeMetatables: config values resolve without pcall/closure
--//   - ImGui:Concat uses table.concat, hot table.find calls removed
--//   - Fixed: windows were registered into ImGui.windows (lowercase w),
--//     so ImGui.Windows was always empty
-- ------------------------------------------------------------------

local ImGui = {
	Version = "2.2",

	Animations = {
		Buttons = {
			MouseEnter = {
				BackgroundTransparency = 0.5,
			},
			MouseLeave = {
				BackgroundTransparency = 0.7,
			}
		},
		Tabs = {
			MouseEnter = {
				BackgroundTransparency = 0.5,
			},
			MouseLeave = {
				BackgroundTransparency = 1,
			}
		},
		Inputs = {
			MouseEnter = {
				BackgroundTransparency = 0,
			},
			MouseLeave = {
				BackgroundTransparency = 0.5,
			}
		},
		WindowBorder = {
			Selected = {
				Transparency = 0,
				Thickness = 1
			},
			Deselected = {
				Transparency = 0.7,
				Thickness = 1
			}
		},
	},

	Windows = {},
	Connections = {},
	Animation = TweenInfo.new(0.1),
	InstantTween = TweenInfo.new(0), --// cached, GetAnimation no longer allocates

	--// Global kill-switch for every animation (design stays the same)
	AnimationsEnabled = true,

	--// Direct position updates while dragging (cheaper & smoother).
	--// Set to true to restore the old tween-per-mouse-move behaviour
	SmoothDragging = false,

	--// Press to show/hide every window. Set to false/nil to disable
	ToggleKey = Enum.KeyCode.RightShift,

	UIAssetId = "rbxassetid://85607317875581",

	--// Theme settings
	Theme = {
		Accent = Color3.fromRGB(0, 120, 215), --// default accent (blue)
		Current = nil, --// accent color the prefabs are currently using
		Rainbow = false,
		RainbowSpeed = 0.35, --// hue cycles per second
	},

	--// Built-in accent presets: ImGui:SetAccent("Red") / ImGui:SetTheme("Midnight")
	Themes = {
		Blue = Color3.fromRGB(0, 120, 215),
		Midnight = Color3.fromRGB(88, 101, 242),
		Red = Color3.fromRGB(225, 65, 65),
		Green = Color3.fromRGB(70, 180, 100),
		Orange = Color3.fromRGB(255, 145, 45),
		Purple = Color3.fromRGB(155, 90, 220),
		Pink = Color3.fromRGB(235, 95, 155),
		Cyan = Color3.fromRGB(45, 190, 200),
		Yellow = Color3.fromRGB(235, 205, 65),
	},

	Notifications = {},
}

--// Color helper (matches colors within ~1/255 of a channel)
local function SameColor(A: Color3, B: Color3): boolean
	return math.abs(A.R - B.R) < 0.004
		and math.abs(A.G - B.G) < 0.004
		and math.abs(A.B - B.B) < 0.004
end

--// Universal functions
local NullFunction = function() end
local CloneRef = cloneref or function(_)return _ end
local function GetService(...): ServiceProvider
	return CloneRef(game:GetService(...))
end

function ImGui:Warn(...)
	if self.NoWarnings then return end
	return warn("[IMGUI]", ...)
end

--// Services 
local TweenService: TweenService = GetService("TweenService")
local UserInputService: UserInputService = GetService("UserInputService")
local Players: Players = GetService("Players")
local CoreGui = GetService("CoreGui")
local RunService: RunService = GetService("RunService")

--// LocalPlayer
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer.PlayerGui
local Mouse = LocalPlayer:GetMouse()

--// ImGui Config
local IsStudio = RunService:IsStudio()
ImGui.NoWarnings = not IsStudio

--// Prefabs
function ImGui:FetchUI()
	--// Cache check 
	local CacheName = "DepsoImGui"
	if _G[CacheName] then
		self:Warn("Prefabs loaded from Cache")
		return _G[CacheName]
	end

	local UI = nil

	--// Universal
	if not IsStudio then
		local UIAssetId = ImGui.UIAssetId
		UI = game:GetObjects(UIAssetId)[1]
	else --// Studio
		local UIName = "DepsoImGui"
		UI = PlayerGui:FindFirstChild(UIName) or script.DepsoImGui
	end

	_G[CacheName] = UI
	return UI
end

local UI = ImGui:FetchUI()
local Prefabs = UI.Prefabs
ImGui.Prefabs = Prefabs
Prefabs.Visible = false

--// NEW (v2.2): purge leftover demo elements shipped inside the prefab
--// asset. Depso's asset contains a demo TextButton "Item" with the text
--// "Skibidi toliet," that used to leak onto every cloned widget.
--// Junk NESTED inside a prefab is destroyed (nearest button ancestor).
--// Top-level prefabs (direct children of the Prefabs folder) are kept:
--// some of them ARE used widgets (e.g. the current asset ships the Button
--// prefab as a bare demo TextButton), so for those we only clear the junk
--// text - the widget code writes the real label afterwards.
do
	local JunkPatterns = { "skibidi", "toliet" }

	local function ContainsJunk(Value)
		local Lower = string.lower(Value)
		for _, Pattern in next, JunkPatterns do
			if string.find(Lower, Pattern, 1, true) then
				return true
			end
		end
		return false
	end

	function ImGui:PurgeDemoJunk(Root, PrefabsFolder)
		if not Root then return 0 end
		local Removed = 0
		for _, Desc in next, Root:GetDescendants() do
			local Matched = false
			if Desc:IsA("TextLabel") and ContainsJunk(Desc.Text) then
				Matched = true
			end
			if not Matched and ContainsJunk(Desc.Name) then
				Matched = true
			end
			if Matched then
				if PrefabsFolder and Desc.Parent == PrefabsFolder then
					--// top-level prefab in use: clear the junk text only
					if Desc:IsA("TextLabel") and Desc.Text ~= "" then
						Desc.Text = ""
						Removed += 1
					end
				else
					--// nested demo element: kill the whole demo button
					local Target = Desc
					local Ancestor = Desc.Parent
					while Ancestor and Ancestor ~= Root and not Ancestor:IsA("GuiButton") do
						Ancestor = Ancestor.Parent
					end
					if Ancestor and Ancestor ~= Root and Ancestor:IsA("GuiButton") then
						Target = Ancestor
					end
					Target:Destroy()
					Removed += 1
				end
			end
		end
		return Removed
	end

	ImGui.DemoJunkRemoved = ImGui:PurgeDemoJunk(UI, Prefabs)
end

--// Styles
local AddionalStyles = {
	[{
		Name="Border"
	}] = function(GuiObject: GuiObject, Value, Class)
		local Outline = GuiObject:FindFirstChildOfClass("UIStroke")
		if not Outline then return end

		local BorderThickness = Class.BorderThickness
		if BorderThickness then
			Outline.Thickness = BorderThickness
		end

		Outline.Enabled = Value
	end,

	[{
		Name="Ratio"
	}] = function(GuiObject: GuiObject, Value, Class)
		local RatioAxis = Class.RatioAxis or "Height"
		local AspectRatio = Class.Ratio or 4/3
		local AspectType = Class.AspectType or Enum.AspectType.ScaleWithParentSize

		local Ratio = GuiObject:FindFirstChildOfClass("UIAspectRatioConstraint")
		if not Ratio then
			Ratio = ImGui:CreateInstance("UIAspectRatioConstraint", GuiObject)
		end

		Ratio.DominantAxis = Enum.DominantAxis[RatioAxis]
		Ratio.AspectType = AspectType
		Ratio.AspectRatio = AspectRatio
	end,

	[{
		Name="CornerRadius",
		Recursive=true
	}] = function(GuiObject: GuiObject, Value, Class)
		local UICorner = GuiObject:FindFirstChildOfClass("UICorner")
		if not UICorner then
			UICorner = ImGui:CreateInstance("UICorner", GuiObject)
		end

		UICorner.CornerRadius = Class.CornerRadius
	end,

	[{
		Name="Label"
	}] = function(GuiObject: GuiObject, Value, Class)
		local Label = GuiObject:FindFirstChild("Label")
		if not Label then return end

		Label.Text = Class.Label
		function Class:SetLabel(Text)
			Label.Text = Text
			return Class
		end
	end,

	[{
		Name="NoGradient",
		Aliases = {"NoGradientAll"},
		Recursive=true
	}] = function(GuiObject: GuiObject, Value, Class)
		local UIGradient = GuiObject:FindFirstChildOfClass("UIGradient")
		if not UIGradient then return end
		UIGradient.Enabled = not Value
	end,

	--// Addional functions for classes
	[{
		Name="Callback"
	}] = function(GuiObject: GuiObject, Value, Class)
		function Class:SetCallback(NewCallback)
			Class.Callback = NewCallback
			return Class
		end
		function Class:FireCallback(NewCallback)
			return Class.Callback(GuiObject)
		end
	end,

	[{
		Name="Value"
	}] = function(GuiObject: GuiObject, Value, Class)
		function Class:GetValue()
			return Class.Value
		end
	end,
}

function ImGui:GetName(Name: string)
	local Format = "%s_"
	return Format:format(Name)
end

function ImGui:CreateInstance(Class, Parent, Properties)
	local NewInstance = Instance.new(Class)
	for Key, Value in next, Properties or {} do
		NewInstance[Key] = Value
	end
	--// Parent is set last (Roblox best practice, avoids repeated
	--// parent/child property recalculation during setup)
	if Parent then
		NewInstance.Parent = Parent
	end
	return NewInstance
end

function ImGui:ApplyColors(ColorOverwrites, GuiObject: GuiObject, ElementType: string)
	for Info, Value in next, ColorOverwrites do
		local Key = Info
		local Recursive = false

		if typeof(Info) == "table" then
			Key = Info.Name or ""
			Recursive = Info.Recursive or false
		end

		--// Child object
		if typeof(Value) == "table" then
			local Element = GuiObject:FindFirstChild(Key, Recursive)

			if not Element then 
				if ElementType == "Window" then
					Element = GuiObject.Content:FindFirstChild(Key, Recursive)
					if not Element then continue end
				else 
					self:Warn(Key, "was not found in", GuiObject)
					self:Warn("Table:", Value)

					continue
				end
			end

			ImGui:ApplyColors(Value, Element)
			continue
		end

		--// Set property
		GuiObject[Key] = Value
	end
end

function ImGui:CheckStyles(GuiObject: GuiObject, Class, Colors)
	--// Addional styles
	for Info, Callback in next, AddionalStyles do
		local Value = Class[Info.Name]
		local Aliases = Info.Aliases

		if Aliases and not Value then
			for _, Alias in Info.Aliases do
				Value = Class[Alias]
				if Value then break end
			end
		end
		if Value == nil then continue end

		--// Stylise children
		Callback(GuiObject, Value, Class)
		if Info.Recursive then
			for _, Child in next, GuiObject:GetChildren() do
				Callback(Child, Value, Class)
			end
		end
	end

	--// Label functions/Styliser
	local ElementType = GuiObject.Name
	GuiObject.Name = self:GetName(ElementType)

	--// Apply Colors
	local Colors = Colors or {}
	local ColorOverwrites = Colors[ElementType]

	if ColorOverwrites then
		ImGui:ApplyColors(ColorOverwrites, GuiObject, ElementType)
	end

	--// Set properties
	for Key, Value in next, Class do
		pcall(function() --// If the property does not exist
			GuiObject[Key] = Value
		end)
	end
end

function ImGui:MergeMetatables(Class, Instance: GuiObject)
	local Metadata = {}

	--// Optimized: config values are resolved with a rawget first,
	--// so the hot path (methods & config values) skips the pcall +
	--// closure allocation the old version paid on every access
	Metadata.__index = function(_, Key)
		local ClassValue = rawget(Class, Key)
		if ClassValue ~= nil then
			return ClassValue
		end

		local suc, Value = pcall(function()
			local Value = Instance[Key]
			if typeof(Value) == "function" then
				return function(_, ...)
					return Value(Instance, ...)
				end
			end
			return Value
		end)
		return suc and Value or nil
	end

	Metadata.__newindex = function(_, Key, Value)
		local Key2 = Class[Key]
		if Key2 ~= nil or typeof(Value) == "function" then
			Class[Key] = Value
		else
			Instance[Key] = Value
		end
	end

	return setmetatable({}, Metadata)
end

function ImGui:Concat(Table, Separator: " ")
	--// Optimized: table.concat instead of ..= in a loop
	local Strings = table.create(#Table)
	for Index, String in next, Table do
		Strings[Index] = tostring(String)
	end
	return table.concat(Strings, Separator)
end

function ImGui:ContainerClass(Frame: Frame, Class, Window)
	local ContainerClass = Class or {}
	local WindowConfig = ImGui.Windows[Window]

	function ContainerClass:NewInstance(Instance: Frame, Class, Parent)
		--// Config
		Class = Class or {}

		--// Set Parent
		Instance.Parent = Parent or Frame
		Instance.Visible = true

		--// TODO
		if WindowConfig and WindowConfig.NoGradientAll then
			Class.NoGradient = true
		end

		local Colors = WindowConfig and WindowConfig.Colors
		ImGui:CheckStyles(Instance, Class, Colors)

		--// External callback check
		if Class.NewInstanceCallback then
			Class.NewInstanceCallback(Instance)
		end

		--// Merge the class with the properties of the instance
		return ImGui:MergeMetatables(Class, Instance)
	end

	function ContainerClass:Button(Config)
		Config = Config or {}
		local Button = Prefabs.Button:Clone()
		local ObjectClass = self:NewInstance(Button, Config)

		--// FIXED (v2.2): the current prefab asset ships the Button prefab
		--// as a bare demo TextButton ("Skibidi toliet,") with no "Label"
		--// child, so the label style handler never ran and every button
		--// showed the junk text. Resolve the label target ourselves and
		--// always write Config.Label onto it.
		local LabelTarget = Button:FindFirstChild("Label")
		if not (LabelTarget and LabelTarget:IsA("TextLabel")) then
			LabelTarget = Button:IsA("TextLabel") and Button or nil
		end
		if LabelTarget then
			LabelTarget.Text = tostring(Config.Label or Config.Text or "")
			if type(Config.SetLabel) ~= "function" then
				function Config:SetLabel(Text)
					LabelTarget.Text = tostring(Text)
					return Config
				end
			end
		end

		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end
		Button.Activated:Connect(Callback)

		--// Apply animations
		ImGui:ApplyAnimations(Button, "Buttons")
		return ObjectClass
	end

	function ContainerClass:Image(Config)
		Config = Config or {}
		local Image = Prefabs.Image:Clone()

		--// Check for rbxassetid
		if tonumber(Config.Image) then
			Config.Image = `rbxassetid://{Config.Image}`
		end

		local ObjectClass = self:NewInstance(Image, Config)
		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end
		Image.Activated:Connect(Callback)

		--// Apply animations
		ImGui:ApplyAnimations(Image, "Buttons")
		return ObjectClass
	end

	function ContainerClass:ScrollingBox(Config)
		Config = Config or {}
		local Box = Prefabs.ScrollBox:Clone()
		local ContainClass = ImGui:ContainerClass(Box, Config, Window) 
		return self:NewInstance(Box, ContainClass)
	end

	function ContainerClass:Label(Config)
		Config = Config or {}
		local Label = Prefabs.Label:Clone()
		local ObjectClass = self:NewInstance(Label, Config)

		--// FIXED: SetLabel was only defined by the "Label" style handler
		--// (and only when the config had a .Label field), so it threw
		--// "missing method SetLabel" on plain Tab:Label({Text = ...})
		function Config:SetLabel(Text)
			local Target = Label:IsA("TextLabel") and Label or Label:FindFirstChild("Label")
			if Target then
				Target.Text = tostring(Text)
			end
			return Config
		end

		return ObjectClass
	end

	function ContainerClass:Checkbox(Config)
		Config = Config or {}
		local IsRadio = Config.IsRadio

		local CheckBox = Prefabs.CheckBox:Clone()
		local Tickbox: ImageButton = CheckBox.Tickbox
		local Tick: ImageLabel = Tickbox.Tick
		local Label = CheckBox.Label
		local ObjectClass = self:NewInstance(CheckBox, Config)

		--// Stylise to correct type
		if IsRadio then
			Tick.ImageTransparency = 1
			Tick.BackgroundTransparency = 0
		else
			Tickbox:FindFirstChildOfClass("UIPadding"):Remove()
			Tickbox:FindFirstChildOfClass("UICorner"):Remove()
		end

		--// Apply animations
		ImGui:ApplyAnimations(CheckBox, "Buttons", Tickbox)

		local Value = Config.Value or false

		--// Callback
		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end

		function Config:SetTicked(NewValue: boolean, NoAnimation: false)
			Value = NewValue
			Config.Value = Value

			--// Animations
			local Size = Value and UDim2.fromScale(1,1) or UDim2.fromScale(0,0)
			ImGui:Tween(Tick, {
				Size = Size
			}, nil, NoAnimation)
			ImGui:Tween(Label, {
				TextTransparency = Value and 0 or 0.3
			}, nil, NoAnimation)

			--// Fire callback
			Callback(Value)

			return Config
		end
		Config:SetTicked(Value, true)

		function Config:Toggle()
			Config:SetTicked(not Value)
			return Config
		end

		--// Connect functions
		local function Clicked()
			Value = not Value
			Config:SetTicked(Value)
		end
		CheckBox.Activated:Connect(Clicked)
		Tickbox.Activated:Connect(Clicked)

		return ObjectClass
	end

	function ContainerClass:RadioButton(Config)
		Config = Config or {}
		Config.IsRadio = true
		return self:Checkbox(Config)
	end

	function ContainerClass:Viewport(Config)
		Config = Config or {}
		local Model = Config.Model

		local Holder = Prefabs.Viewport:Clone()
		local Viewport: ViewportFrame = Holder.Viewport
		local WorldModel: WorldModel = Viewport.WorldModel
		Config.WorldModel = WorldModel
		Config.Viewport = Viewport

		function Config:SetCamera(Camera)
			Viewport.CurrentCamera = Camera
			Config.Camera = Camera
			Camera.CFrame = CFrame.new(0,0,0)
			return Config
		end

		local Camera = Config.Camera or ImGui:CreateInstance("Camera", Viewport)
		Config:SetCamera(Camera)

		function Config:SetModel(Model: Model, PivotTo: CFrame)
			WorldModel:ClearAllChildren()

			--// Set new model
			if Config.Clone then
				Model = Model:Clone()
			end
			if PivotTo then
				Model:PivotTo(PivotTo)
			end

			Model.Parent = WorldModel
			Config.Model = Model
			return Model
		end

		--// Set model
		if Model then
			Config:SetModel(Model)
		end

		local ContainClass = ImGui:ContainerClass(Holder, Config, Window) 
		return self:NewInstance(Holder, ContainClass)
	end

	function ContainerClass:InputText(Config)
		Config = Config or {}
		local TextInput = Prefabs.TextInput:Clone()
		local TextBox: TextBox = TextInput.Input
		local ObjectClass = self:NewInstance(TextInput, Config)

		TextBox.Text = Config.Value or ""
		TextBox.PlaceholderText = Config.PlaceHolder
		TextBox.MultiLine = Config.MultiLine == true

		--// Apply animations
		ImGui:ApplyAnimations(TextInput, "Inputs")

		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end
		TextBox:GetPropertyChangedSignal("Text"):Connect(function()
			local Value = TextBox.Text
			Config.Value = Value
			return Callback(Value)
		end)

		function Config:SetValue(Text)
			TextBox.Text = tostring(Text)
			Config.Value = Text
			return Config
		end

		function Config:Clear()
			TextBox.Text = ""
			return Config
		end

		return ObjectClass
	end

	function ContainerClass:InputTextMultiline(Config)
		Config = Config or {}
		Config.Label = ""
		Config.Size = UDim2.new(1, 0, 0, 38)
		Config.MultiLine = true
		return ContainerClass:InputText(Config)
	end

	function ContainerClass:GetRemainingHeight()
		local Padding = Frame:FindFirstChildOfClass("UIPadding")
		local UIListLayout = Frame:FindFirstChildOfClass("UIListLayout")

		local LayoutPaddding = UIListLayout.Padding
		local PaddingTop = Padding.PaddingTop
		local PaddingBottom = Padding.PaddingBottom

		local PaddingSizeY = PaddingTop+PaddingBottom+LayoutPaddding
		local OccupiedY = Frame.AbsoluteSize.Y+PaddingSizeY.Offset+3

		return UDim2.new(1, 0, 1, -OccupiedY) 
	end

	function ContainerClass:Console(Config)
		Config = Config or {}
		local Console: ScrollingFrame = Prefabs.Console:Clone()
		local Source: TextBox = Console.Source
		local Lines = Console.Lines

		if Config.Fill then
			Console.Size = ContainerClass:GetRemainingHeight()
		end

		--// Set values from config
		Source.TextEditable = Config.ReadOnly ~= true
		Source.Text = Config.Text or ""
		Source.TextWrapped = Config.TextWrapped == true
		Source.RichText = Config.RichText == true
		Lines.Visible = Config.LineNumbers == true

		function Config:UpdateLineNumbers()
			if not Config.LineNumbers then return end

			local LinesCount = #Source.Text:split("\n")
			local Format = Config.LinesFormat or "%s"

			--// Update lines text
			local Buffer = table.create(LinesCount)
			for i = 1, LinesCount do
				Buffer[i] = Format:format(i)
			end
			Lines.Text = table.concat(Buffer, "\n")

			Source.Size = UDim2.new(1, -Lines.AbsoluteSize.X, 0, 0)
			return Config
		end

		function Config:UpdateScroll()
			local CanvasSizeY = Console.AbsoluteCanvasSize.Y
			Console.CanvasPosition = Vector2.new(0, CanvasSizeY)
			return Config
		end

		function Config:SetText(Text)
			if not Config.Enabled then return end
			Source.Text = Text
			Config:UpdateLineNumbers()
			return Config
		end

		function Config:GetValue()
			return Source.Text
		end

		function Config:Clear(Text)
			Source.Text = ""
			Config:UpdateLineNumbers()
			return Config
		end

		function Config:AppendText(...)
			if not Config.Enabled then return end

			local MaxLines = Config.MaxLines or 100
			local NewString = "\n" .. ImGui:Concat({...}, " ") 

			Source.Text ..= NewString
			Config:UpdateLineNumbers()

			if Config.AutoScroll then
				Config:UpdateScroll()
			end

			local Lines = Source.Text:split("\n")
			if #Lines > MaxLines then
				Source.Text = Source.Text:sub(#Lines[1]+2)
			end
			return Config
		end

		--// Connect events
		Source.Changed:Connect(Config.UpdateLineNumbers)

		return self:NewInstance(Console, Config)
	end

	function ContainerClass:Table(Config)
		Config = Config or {}
		local Table: Frame = Prefabs.Table:Clone()
		local TableChildCount = #Table:GetChildren() --// Performance

		--// Configure Table style
		if Config.Fill then
			Table.Size = ContainerClass:GetRemainingHeight()
		end
		local RowName = "Row"

		local RowsCount = 0
		function Config:CreateRow()
			local RowClass = {}

			local Row: Frame = Table.RowTemp:Clone()
			local UIListLayout = Row:FindFirstChildOfClass("UIListLayout")
			UIListLayout.VerticalAlignment = Enum.VerticalAlignment[Config.Align or "Center"]

			local RowChildCount = #Row:GetChildren() --// Performance
			Row.Name = RowName
			Row.Visible = true

			--// Background colors
			if Config.RowBackground then
				Row.BackgroundTransparency = RowsCount % 2 == 1 and 0.92 or 1
			end

			function RowClass:CreateColumn(CConfig)
				CConfig = CConfig or {}
				local Column: Frame = Row.ColumnTemp:Clone()
				Column.Visible = true
				Column.Name = "Column"

				local Stroke = Column:FindFirstChildOfClass("UIStroke")
				Stroke.Enabled = Config.Border ~= false

				local ContainClass = ImGui:ContainerClass(Column, CConfig, Window) 
				return ContainerClass:NewInstance(Column, ContainClass, Row)
			end

			function RowClass:UpdateColumns()
				if not Row or not Table then return end
				local Columns = Row:GetChildren()
				local RowsCount = #Columns - RowChildCount

				for _, Column: Frame in next, Columns do
					if not Column:IsA("Frame") then continue end
					Column.Size = UDim2.new(1/RowsCount, 0, 0, 0)
				end
				return RowClass
			end
			Row.ChildAdded:Connect(RowClass.UpdateColumns)
			Row.ChildRemoved:Connect(RowClass.UpdateColumns)

			RowsCount += 1
			return ContainerClass:NewInstance(Row, RowClass, Table)
		end

		function Config:UpdateRows()
			local Rows = Table:GetChildren()
			local PaddingY = Table.UIListLayout.Padding.Offset + 2
			local RowsCount = #Rows - TableChildCount

			for _, Row: Frame in next, Rows do
				if not Row:IsA("Frame") then continue end
				Row.Size = UDim2.new(1, 0, 1/RowsCount, -PaddingY)
			end
			return Config
		end

		if Config.RowsFill then
			Table.AutomaticSize = Enum.AutomaticSize.None
			Table.ChildAdded:Connect(Config.UpdateRows)
			Table.ChildRemoved:Connect(Config.UpdateRows)
		end

		function Config:ClearRows()
			RowsCount = 0
			local PostRowName = ImGui:GetName(RowName)
			for _, Row: Frame in next, Table:GetChildren() do
				if not Row:IsA("Frame") then continue end

				if Row.Name == PostRowName then
					Row:Remove()
				end
			end
			return Config
		end

		return self:NewInstance(Table, Config) 
	end

	function ContainerClass:Grid(Config)
		Config = Config or {}
		Config.Grid = true

		return self:Table(Config)
	end

	function ContainerClass:CollapsingHeader(Config)
		Config = Config or {}
		local Title = Config.Title or ""
		Config.Name = Title

		local Header = Prefabs.CollapsingHeader:Clone()
		local Titlebar: TextButton = Header.TitleBar
		local Container: Frame = Header.ChildContainer
		Titlebar.Title.Text = Title

		--// Apply animations
		if Config.IsTree then
			ImGui:ApplyAnimations(Titlebar, "Tabs")
		else
			ImGui:ApplyAnimations(Titlebar, "Buttons")
		end

		--// Open Animations
		function Config:SetOpen(Open)
			local Animate = Config.NoAnimation ~= true
			Config.Open = Open
			ImGui:HeaderAnimate(Header, Animate, Open, Titlebar)
			return self
		end

		--// Toggle
		local ToggleButton = Titlebar.Toggle.ToggleButton
		local function Toggle()
			Config:SetOpen(not Config.Open)
		end
		Titlebar.Activated:Connect(Toggle)
		ToggleButton.Activated:Connect(Toggle)

		--// Custom toggle image
		if Config.Image then
			ToggleButton.Image = Config.Image 
		end

		--// Open
		Config:SetOpen(Config.Open or false)

		local ContainClass = ImGui:ContainerClass(Container, Config, Window) 
		return self:NewInstance(Header, ContainClass)
	end

	function ContainerClass:TreeNode(Config)
		Config = Config or {}
		Config.IsTree = true
		return self:CollapsingHeader(Config)
	end

	function ContainerClass:Separator(Config)
		Config = Config or {}
		local Separator = Prefabs.SeparatorText:Clone()
		local HeaderLabel = Separator.TextLabel
		HeaderLabel.Text = Config.Text or ""

		if not Config.Text then
			HeaderLabel.Visible = false
		end

		return self:NewInstance(Separator, Config)
	end

	function ContainerClass:Row(Config)
		Config = Config or {}
		local Row: Frame = Prefabs.Row:Clone()
		local UIListLayout = Row:FindFirstChildOfClass("UIListLayout")
		local UIPadding = Row:FindFirstChildOfClass("UIPadding")

		if Config.Spacing then
			UIListLayout.Padding = UDim.new(0, Config.Spacing)
		end

		function Config:Fill()
			local Children = Row:GetChildren()
			local Rows = #Children - 2 --// -UIListLayout + UIPadding

			--// Change layout
			local Padding = UIListLayout.Padding.Offset * 2
			UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

			--// Apply correct margins
			UIPadding.PaddingLeft = UIListLayout.Padding
			UIPadding.PaddingRight = UIListLayout.Padding

			for _, Child: Instance in next, Children do
				local YScale = 0
				if Child:IsA("ImageButton") then
					YScale = 1
				end
				pcall(function()
					Child.Size = UDim2.new(1/Rows, -Padding, YScale, 0)
				end)
			end
			return Config
		end

		local ContainClass = ImGui:ContainerClass(Row, Config, Window) 
		return self:NewInstance(Row, ContainClass)
	end

	--TODO
	-- Vertical 
	-- :SetPercentage
	-- This will use UIDragdetectors in the upcoming release, please do not report this!
	function ContainerClass:Slider(Config)
		Config = Config or {}

		--// Unpack config
		local Value = Config.Value or 0
		local ValueFormat = Config.Format or "%.d"
		local IsProgress = Config.Progress
		Config.Name = Config.Label or ""

		--// Slider element
		local Slider: TextButton = Prefabs.Slider:Clone()
		local UIPadding = Slider:FindFirstChildOfClass("UIPadding")
		local Grab: Frame = Slider.Grab
		local ValueText = Slider.ValueText
		local Label = Slider.Label

		--// Input data
		local Dragging = false
		local MouseMoveConnection = nil
		local InputType = Enum.UserInputType.MouseButton1

		local ObjectClass = self:NewInstance(Slider, Config)

		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end

		--// Apply Progress styles
		if IsProgress then
			local UIGradient = Grab:FindFirstChildOfClass("UIGradient")

			local PaddingSides = UDim.new(0,2)
			local Diff = UIPadding.PaddingLeft - PaddingSides

			Grab.AnchorPoint = Vector2.new(0, 0.5)
			UIGradient.Enabled = true

			UIPadding.PaddingLeft = PaddingSides
			UIPadding.PaddingRight = PaddingSides

			Label.Position = UDim2.new(1, 15-Diff.Offset, 0, 0)
		end

		--// NoTween: update the grab directly (used while dragging, no
		--// tween allocation per mouse move, way cheaper)
		function Config:SetValue(Value: number, Slider: false, NoTween: false)
			local MinValue = Config.MinValue
			local MaxValue = Config.MaxValue
			local Difference = MaxValue - MinValue
			local Percentage = (Value - MinValue) / Difference

			if not Slider then
				Value = tonumber(Value)
			else
				Percentage = Value
				Value = MinValue + (Difference * Percentage)
			end

			--// Animate grab
			local Props = {
				Position = UDim2.fromScale(Percentage, 0.5)
			}

			if IsProgress then
				Props = {
					Size = UDim2.fromScale(Percentage, 1)
				}
			end

			--// Animate
			if NoTween then
				for Key, PropValue in next, Props do
					Grab[Key] = PropValue
				end
			else
				ImGui:Tween(Grab, Props)
			end

			--// Update UI
			Config.Value = Value
			ValueText.Text = ValueFormat:format(Value, MaxValue) 

			--// Fire callback
			Callback(Value)

			return Config
		end

		------// Move events
		local function MouseMove()
			if Config.ReadOnly then return end
			if not Dragging then return end

			local MouseX = UserInputService:GetMouseLocation().X
			local LeftPos = Slider.AbsolutePosition.X

			local Percentage = (MouseX-LeftPos)/Slider.AbsoluteSize.X
			Percentage = math.clamp(Percentage, 0, 1)
			Config:SetValue(Percentage, true, true)
		end

		local function InputEnded(inputObject)
			if not Dragging then return end
			if inputObject.UserInputType ~= InputType then return end

			Dragging = false
			MouseMoveConnection:Disconnect()
			MouseMoveConnection = nil
		end

		--// Connect mouse events
		ImGui:ConnectHover({
			Parent = Slider,
			OnInput = function(MouseHovering, Input)
				if not MouseHovering then return end
				if Input.UserInputType ~= InputType then return end

				Dragging = true
				MouseMoveConnection = Mouse.Move:Connect(MouseMove) --// Save heavy performance
			end
		})

		--// Connect events
		Slider.Activated:Connect(MouseMove)
		UserInputService.InputEnded:Connect(InputEnded)

		--// Update UI
		Config:SetValue(Value)

		return ObjectClass
	end

	function ContainerClass:ProgressSlider(Config)
		Config = Config or {}
		Config.Progress = true
		return self:Slider(Config)
	end

	function ContainerClass:ProgressBar(Config)
		Config = Config or {}
		Config.Progress = true
		Config.ReadOnly = true
		Config.MinValue = 0
		Config.MaxValue = 100
		Config.Format = "% i%%"
		Config = self:Slider(Config)

		function Config:SetPercentage(Value: number)
			Config:SetValue(Value)
		end

		return Config
	end

	function ContainerClass:Keybind(Config)
		Config = Config or {}

		local Key = Config.Value
		local TobeNullKey = Config.NullKey or Enum.KeyCode.Backspace

		local Keybind: TextButton = Prefabs.Keybind:Clone()
		local ValueText: TextButton = Keybind.ValueText

		local ObjectClass = nil
		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end

		function Config:SetValue(NewKey: Enum.KeyCode)
			if not NewKey then return end

			if NewKey == TobeNullKey then
				ValueText.Text = "Not set"
				Config.Value = nil
			else
				ValueText.Text = NewKey.Name
				Config.Value = NewKey
			end
		end

		Keybind.Activated:Connect(function()
			ValueText.Text = "..."

			local NewKey = UserInputService.InputBegan:Wait()
			if not UserInputService.WindowFocused then return end 

			--// Reset back to previous if unknown
			local Previous = Config.Value
			if NewKey.KeyCode.Name == "Unknown" then
				return Config:SetValue(Previous)
			end

			task.wait(0.1) --// 👍 (was blocking wait())
			Config:SetValue(NewKey.KeyCode)
		end)

		Config.Connection = UserInputService.InputBegan:Connect(function(Input, GameProcessed)
			if not Config.IgnoreGameProcessed and GameProcessed then return end
			local KeyCode = Input.KeyCode
			local Match = Config.Value

			if KeyCode == TobeNullKey then return end
			if KeyCode ~= Match then return end 

			return Callback(Input.KeyCode)
		end)

		--// Update UI
		Config:SetValue(Key)

		ObjectClass = self:NewInstance(Keybind, Config)
		return ObjectClass
	end

	function ContainerClass:Combo(Config)
		Config = Config or {}
		Config.Open = false
		Config.Value = ""

		local Combo: TextButton = Prefabs.Combo:Clone()
		local Toggle: ImageButton = Combo.Toggle.ToggleButton
		local ValueText = Combo.ValueText
		ValueText.Text = Config.Placeholder or ""

		local Dropdown = nil
		local ObjectClass = self:NewInstance(Combo, Config)

		local ComboHovering = ImGui:ConnectHover({
			Parent = Combo
		})

		local function Callback(Value, ...)
			local func = Config.Callback or NullFunction
			Config:SetOpen(false)
			return func(ObjectClass, Value, ...)
		end

		function Config:SetValue(Value, ...)
			local Items = Config.Items or {}
			local DictValue = Items[Value]
			ValueText.Text = tostring(Value)
			Config.Value = Value

			return Callback(DictValue or Value) 
		end

		function Config:SetOpen(Open: true)
			local Animate = Config.NoAnimation ~= true
			ImGui:HeaderAnimate(Combo, Animate, Open, Combo, Toggle)
			Config.Open = Open

			if Open then
				Dropdown = ImGui:Dropdown({
					Parent = Combo,
					Items = Config.Items or {},
					SetValue = Config.SetValue,
					Closed = function()
						if not ComboHovering.Hovering then 
							Config:SetOpen(false)
						end
					end,
				})
			end

			return self
		end

		local function ToggleOpen()
			if Dropdown then
				Dropdown:Close()
			end
			Config:SetOpen(not Config.Open)
		end

		--// Connect events
		Combo.Activated:Connect(ToggleOpen)
		Toggle.Activated:Connect(ToggleOpen)
		ImGui:ApplyAnimations(Combo, "Buttons")

		if Config.Selected then
			Config:SetValue(Config.Selected)
		end

		return ObjectClass 
	end

	--// NEW: dropdown that switches the accent theme live
	function ContainerClass:ThemePicker(Config)
		Config = Config or {}

		local Names = {}
		for Name in next, ImGui.Themes do
			table.insert(Names, Name)
		end
		table.sort(Names)

		--// Find the preset matching the current accent (if any)
		local Selected = Config.Selected
		for Name, Color in next, ImGui.Themes do
			if SameColor(Color, ImGui.Theme.Accent) then
				Selected = Name
				break
			end
		end

		Config.Items = Names
		Config.Selected = Selected

		local UserCallback = Config.Callback
		Config.Callback = function(_, Value)
			ImGui:SetAccent(Value)
			if UserCallback then
				UserCallback(Value)
			end
		end

		return self:Combo(Config)
	end

	return ContainerClass
end

function ImGui:Dropdown(Config)
	local Parent: GuiObject = Config.Parent
	if not Parent then return end

	local Selection: ScrollingFrame = Prefabs.Selection:Clone()

	--// NEW: drop demo items shipped inside the Selection prefab
	--// (only Template is the real item source, anything else is junk)
	for _, Child in next, Selection:GetChildren() do
		if Child:IsA("TextButton") and Child.Name ~= "Template" then
			Child:Destroy()
		end
	end
	local UIStroke = Selection:FindFirstChildOfClass("UIStroke")

	local Padding = UIStroke.Thickness*2
	local Position = Parent.AbsolutePosition
	local Size = Parent.AbsoluteSize

	Selection.Parent = self.ScreenGui
	Selection.Position = UDim2.fromOffset(Position.X+Padding, Position.Y+Size.Y)

	local Hover = self:ConnectHover({
		Parent = Selection,
		OnInput = function(MouseHovering, Input)
			if not Input.UserInputType.Name:find("Mouse") then return end

			if not MouseHovering then
				Config:Close()
			end
		end,
	})

	function Config:Close()
		local CloseCallback = Config.Closed
		if CloseCallback then
			CloseCallback()
		end

		Hover:Disconnect()
		Selection:Remove()
	end

	local function SetValue(Value)
		Config:Close()
		Config:SetValue(Value)
	end

	--// Append items
	local ItemTemplate: TextButton = Selection.Template
	ItemTemplate.Visible = false

	for Index, Index2 in next, Config.Items do
		local Value = typeof(Index) ~= "number" and Index or Index2

		local NewItem: TextButton = ItemTemplate:Clone()
		NewItem.Text = tostring(Value)
		NewItem.Parent = Selection
		NewItem.Visible = true
		NewItem.Activated:Connect(function()
			return SetValue(Value)
		end)

		self:ApplyAnimations(NewItem, "Tabs")
	end

	--// Configure size of the frame
	-- Roblox does not support UISizeConstraint on a scrolling frame grr

	local MaxSizeY = Config.MaxSizeY or 200
	local YSize = math.clamp(Selection.AbsoluteCanvasSize.Y, Size.Y, MaxSizeY)
	Selection.Size = UDim2.fromOffset(Size.X-Padding, YSize)

	return Config
end

function ImGui:GetAnimation(Animation: boolean?)
	--// Optimized: both TweenInfos are cached, no allocation per call
	return Animation and self.Animation or self.InstantTween
end

--// Registry of running tweens, keyed by [Instance][Property].
--// Starting a new tween on the same property cancels the old one
--// instead of letting them pile up (hover spam used to stack dozens
--// of competing tweens and eat FPS)
local ActiveTweens = {}

function ImGui:Tween(Instance: GuiObject, Props: SharedTable, tweenInfo, NoAnimation: false)
	local tweenInfo = tweenInfo or ImGui:GetAnimation(not NoAnimation)

	--// Cancel conflicting tweens on the same properties
	local Previous = ActiveTweens[Instance]
	if Previous then
		for Key in next, Props do
			local Old = Previous[Key]
			if Old then
				Old:Cancel()
			end
		end
	end

	local Tween = TweenService:Create(Instance, 
		tweenInfo,
		Props
	)

	if not Previous then
		Previous = {}
		ActiveTweens[Instance] = Previous
	end
	for Key in next, Props do
		Previous[Key] = Tween
	end

	Tween.Completed:Once(function()
		for Key, Old in next, Previous do
			if Old == Tween then
				Previous[Key] = nil
			end
		end
	end)

	Tween:Play()
	return Tween
end

function ImGui:ApplyAnimations(Instance: GuiObject, Class: string, Target: GuiObject?)
	if not ImGui.AnimationsEnabled then return end --// global kill-switch

	local Animatons = ImGui.Animations
	local ColorProps = Animatons[Class]

	if not ColorProps then 
		return self:Warn("No colors for", Class)
	end

	--// Apply tweens for connections
	local Connections = {}
	for Connection, Props in next, ColorProps do
		if typeof(Props) ~= "table" then continue end
		local Target = Target or Instance
		local Callback = function()
			ImGui:Tween(Target, Props)
		end

		--// Connections
		Connections[Connection] = Callback
		Instance[Connection]:Connect(Callback)
	end

	--// Reset colors
	if Connections["MouseLeave"] then
		Connections["MouseLeave"]()
	end

	return Connections 
end

function ImGui:HeaderAnimate(Header: Instance, Animation, Open, TitleBar: Instance, Toggle)
	local ToggleButtion = Toggle or TitleBar.Toggle.ToggleButton

	--// Togle animation
	ImGui:Tween(ToggleButtion, {
		Rotation = Open and 90 or 0,
	})

	--// Container animation
	local Container: Frame = Header:FindFirstChild("ChildContainer")
	if not Container then return end

	local UIListLayout: UIListLayout = Container.UIListLayout
	local UIPadding: UIPadding = Container:FindFirstChildOfClass("UIPadding")
	local ContentSize = UIListLayout.AbsoluteContentSize

	if UIPadding then
		local Top = UIPadding.PaddingTop.Offset
		local Bottom = UIPadding.PaddingBottom.Offset
		ContentSize = Vector2.new(ContentSize.X, ContentSize.Y+Top+Bottom)
	end

	Container.AutomaticSize = Enum.AutomaticSize.None
	if not Open then
		Container.Size = UDim2.new(1, -10, 0, ContentSize.Y)
	end

	--// Animate
	local Tween = ImGui:Tween(Container, {
		Size = UDim2.new(1, -10, 0, Open and ContentSize.Y or 0),
		Visible = Open
	})
	Tween.Completed:Connect(function()
		if not Open then return end
		Container.AutomaticSize = Enum.AutomaticSize.Y
		Container.Size = UDim2.new(1, -10, 0, 0)
	end)
end

function ImGui:ApplyDraggable(Frame: Frame, Header: Frame)
	local Header = Header or Frame

	local Dragging = false
	local KeyBeganPos = nil
	local BeganPos = Frame.Position

	--// Whitelist
	local MouseButton1 = Enum.UserInputType.MouseButton1
	local Touch = Enum.UserInputType.Touch

	--// Optimized: direct enum comparison instead of table.find
	local function UserInputTypeAllowed(InputType: Enum.UserInputType)
		return InputType == MouseButton1 or InputType == Touch
	end

	--// Debounce 
	Header.InputBegan:Connect(function(Key)
		if UserInputTypeAllowed(Key.UserInputType) then
			Dragging = true
			KeyBeganPos = Key.Position
			BeganPos = Frame.Position
		end
	end)

	UserInputService.InputEnded:Connect(function(Key)
		if UserInputTypeAllowed(Key.UserInputType) then
			Dragging = false
		end
	end)

	--// Dragging
	local function Movement(Input)
		if not Dragging then return end

		local Delta = Input.Position - KeyBeganPos
		local Position = UDim2.new(
			BeganPos.X.Scale, 
			BeganPos.X.Offset + Delta.X, 
			BeganPos.Y.Scale, 
			BeganPos.Y.Offset + Delta.Y
		)

		--// Optimized: direct property write while dragging (the old
		--// version created & played a Tween object on EVERY mouse move).
		--// Set ImGui.SmoothDragging = true for the old tweened behaviour
		if ImGui.SmoothDragging then
			ImGui:Tween(Frame, {
				Position = Position
			})
		else
			Frame.Position = Position
		end
	end

	--// Connect movement events
	UserInputService.TouchMoved:Connect(Movement)
	UserInputService.InputChanged:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseMovement then 
			return Movement(Input)
		end
	end)
end


function ImGui:ApplyResizable(MinSize, Frame: Frame, Dragger: TextButton, Config)
	local DragStart
	local OrignialSize

	MinSize = MinSize or Vector2.new(160, 90)

	Dragger.MouseButton1Down:Connect(function()
		if DragStart then return end
		OrignialSize = Frame.AbsoluteSize			
		DragStart = Vector2.new(Mouse.X, Mouse.Y)
	end)	

	UserInputService.InputChanged:Connect(function(Input)
		if not DragStart or Input.UserInputType ~= Enum.UserInputType.MouseMovement then 
			return
		end

		local MousePos = Vector2.new(Mouse.X, Mouse.Y)
		local mouseMoved = MousePos - DragStart

		local NewSize = OrignialSize + mouseMoved
		NewSize = UDim2.fromOffset(
			math.max(MinSize.X, NewSize.X), 
			math.max(MinSize.Y, NewSize.Y)
		)

		Frame.Size = NewSize
		if Config then
			Config.Size = NewSize
		end
	end)

	UserInputService.InputEnded:Connect(function(Input)
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			DragStart = nil
		end
	end)	
end

function ImGui:ConnectHover(Config)
	local Parent = Config.Parent
	local Connections = {}
	Config.Hovering = false

	--// Connect Events
	table.insert(Connections, Parent.MouseEnter:Connect(function()
		Config.Hovering = true
	end))
	table.insert(Connections, Parent.MouseLeave:Connect(function()
		Config.Hovering = false
	end))

	if Config.OnInput then
		table.insert(Connections, UserInputService.InputBegan:Connect(function(Input)
			return Config.OnInput(Config.Hovering, Input)
		end))
	end

	function Config:Disconnect()
		for _, Connection in next, Connections do
			Connection:Disconnect()
		end
	end

	return Config
end

function ImGui:ApplyWindowSelectEffect(Window: GuiObject, TitleBar)
	local UIStroke = Window:FindFirstChildOfClass("UIStroke")

	local Colors = {
		Selected = {
			BackgroundColor3 = TitleBar.BackgroundColor3
		},
		Deselected = {
			BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		}
	}

	local function SetSelected(Selected)
		local Animations = ImGui.Animations
		local Type = Selected and "Selected" or "Deselected"

		ImGui:Tween(TitleBar, Colors[Type])
		ImGui:Tween(UIStroke, Animations.WindowBorder[Type])
	end

	self:ConnectHover({
		Parent = Window,
		OnInput = function(MouseHovering, Input)
			if Input.UserInputType.Name:find("Mouse") then
				SetSelected(MouseHovering)
			end
		end,
	})
end

function ImGui:SetWindowProps(Properties, IgnoreWindows)
	local Module = {
		OldProperties = {}
	}

	--// Collect windows & set properties
	for Window in next, ImGui.Windows do
		if IgnoreWindows and table.find(IgnoreWindows, Window) then continue end

		local OldValues = {}
		Module.OldProperties[Window] = OldValues

		for Key, Value in next, Properties do
			OldValues[Key] = Window[Key]
			Window[Key] = Value
		end
	end

	--// Revert to previous values
	function Module:Revert()
		for Window in next, ImGui.Windows do
			local OldValues = Module.OldProperties[Window]
			if not OldValues then continue end

			for Key, Value in next, OldValues do
				Window[Key] = Value
			end
		end
	end

	return Module
end

function ImGui:CreateWindow(WindowConfig)
	--// Create Window frame
	local Window: Frame = Prefabs.Window:Clone()
	Window.Parent = ImGui.ScreenGui
	Window.Visible = true
	WindowConfig.Window = Window

	local Content = Window.Content
	local Body = Content.Body

	--// Window Resize
	local Resize = Window.ResizeGrab
	Resize.Visible = WindowConfig.NoResize ~= true

	local MinSize = WindowConfig.MinSize or Vector2.new(160, 90)
	ImGui:ApplyResizable(
		MinSize, 
		Window, 
		Resize,
		WindowConfig
	)

	--// Title Bar
	local TitleBar: Frame = Content.TitleBar
	TitleBar.Visible = WindowConfig.NoTitleBar ~= true

	local Toggle = TitleBar.Left.Toggle
	Toggle.Visible = WindowConfig.NoCollapse ~= true
	ImGui:ApplyAnimations(Toggle.ToggleButton, "Tabs")

	local ToolBar = Content.ToolBar
	ToolBar.Visible = WindowConfig.TabsBar ~= false

	if not WindowConfig.NoDrag then
		ImGui:ApplyDraggable(Window)
	end

	--// Close Window 
	local CloseButton: TextButton = TitleBar.Close
	CloseButton.Visible = WindowConfig.NoClose ~= true

	function WindowConfig:Close()
		local Callback = WindowConfig.CloseCallback
		WindowConfig:SetVisible(false)
		if Callback then
			Callback(WindowConfig)
		end
		return WindowConfig
	end
	CloseButton.Activated:Connect(WindowConfig.Close)

	function WindowConfig:GetHeaderSizeY(): number
		local ToolbarY = ToolBar.Visible and ToolBar.AbsoluteSize.Y or 0
		local TitlebarY = TitleBar.Visible and TitleBar.AbsoluteSize.Y or 0
		return ToolbarY + TitlebarY
	end

	function WindowConfig:UpdateBody()
		local HeaderSizeY = self:GetHeaderSizeY()
		Body.Size = UDim2.new(1, 0, 1, -HeaderSizeY)
	end
	WindowConfig:UpdateBody()

	--// Open/Close
	WindowConfig.Open = true
	function WindowConfig:SetOpen(Open: true, NoAnimation: false)
		local WindowAbSize = Window.AbsoluteSize 
		local TitleBarSize = TitleBar.AbsoluteSize 

		self.Open = Open

		--// Call animations
		ImGui:HeaderAnimate(TitleBar, true, Open, TitleBar, Toggle.ToggleButton)
		ImGui:Tween(Resize, {
			TextTransparency = Open and 0.6 or 1,
			Interactable = Open
		}, nil, NoAnimation)
		ImGui:Tween(Window, {
			Size = Open and self.Size or UDim2.fromOffset(WindowAbSize.X, TitleBarSize.Y)
		}, nil, NoAnimation)
		ImGui:Tween(Body, {
			Visible = Open
		}, nil, NoAnimation)
		return self
	end

	--// NEW: collapse/expand helper
	function WindowConfig:Toggle(NoAnimation: boolean?)
		return self:SetOpen(not self.Open, NoAnimation)
	end

	function WindowConfig:SetVisible(Visible: boolean)
		Window.Visible = Visible 
		return self
	end

	function WindowConfig:SetTitle(Text)
		TitleBar.Left.Title.Text = tostring(Text)
		return self
	end
	function WindowConfig:Remove()
		ImGui.Windows[Window] = nil --// unregister
		Window:Remove()
		return self
	end

	Toggle.ToggleButton.Activated:Connect(function()
		local Open = not WindowConfig.Open
		WindowConfig.Open = Open
		return WindowConfig:SetOpen(Open)
	end)	

	function WindowConfig:CreateTab(Config)
		local Name = Config.Name or ""
		local TabButton = ToolBar.TabButton:Clone()
		TabButton.Name = Name
		TabButton.Text = Name
		TabButton.Visible = true
		TabButton.Parent = ToolBar
		Config.Button = TabButton

		local AutoSizeAxis = WindowConfig.AutoSize or "Y"
		local Content: Frame = Body.Template:Clone()

		--// NEW: purge demo elements shipped inside the Template prefab
		--// (helper classes like UIListLayout/UIPadding are kept)
		for _, Child in next, Content:GetChildren() do
			if Child:IsA("GuiObject") then
				Child:Destroy()
			end
		end
		Content.AutomaticSize = Enum.AutomaticSize[AutoSizeAxis]
		Content.Visible = Config.Visible or false
		Content.Name = Name
		Content.Parent = Body
		Config.Content = Content

		if AutoSizeAxis == "Y" then
			Content.Size = UDim2.fromScale(1, 0)
		elseif AutoSizeAxis == "X" then
			Content.Size = UDim2.fromScale(0, 1)
		end

		TabButton.Activated:Connect(function()
			WindowConfig:ShowTab(Config)
		end)

		function Config:GetContentSize()
			return Content.AbsoluteSize
		end

		--// Apply animations
		Config = ImGui:ContainerClass(Content, Config, Window)
		ImGui:ApplyAnimations(TabButton, "Tabs")

		--// Automatic sizes
		self:UpdateBody()
		if WindowConfig.AutoSize then
			Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				local Size = Config:GetContentSize()
				self:SetSize(Size)
			end)
		end

		return Config
	end

	function WindowConfig:SetPosition(Position)
		Window.Position = Position
		return self
	end

	function WindowConfig:SetSize(Size)
		local HeaderSizeY = self:GetHeaderSizeY()

		if typeof(Size) == "Vector2" then
			Size = UDim2.fromOffset(Size.X, Size.Y)
		end

		--// Apply new size
		local NewSize = UDim2.new(
			Size.X.Scale,
			Size.X.Offset,
			Size.Y.Scale,
			Size.Y.Offset + HeaderSizeY
		)
		self.Size = NewSize
		Window.Size = NewSize

		return self
	end

	--// Tab change system 
	function WindowConfig:ShowTab(TabClass: SharedTable)
		local TargetPage: Frame = TabClass.Content

		--// Page animation
		if not TargetPage.Visible and not TabClass.NoAnimation then
			TargetPage.Position = UDim2.fromOffset(0, 5)
		end

		--// Hide other tabs
		for _, Page in next, Body:GetChildren() do
			Page.Visible = Page == TargetPage
		end

		--// Page animation
		ImGui:Tween(TargetPage, {
			Position = UDim2.fromOffset(0, 0)
		})
		return self
	end

	function WindowConfig:Center() --// Without an Anchor point
		local Size = Window.AbsoluteSize
		local Position = UDim2.new(0.5,-Size.X/2,0.5,-Size.Y/2)
		self:SetPosition(Position)
		return self
	end

	--// Load Style Configs
	WindowConfig:SetTitle(WindowConfig.Title or "Depso UI")

	if not WindowConfig.Open then
		WindowConfig:SetOpen(WindowConfig.Open or true, true)
	end

	--// FIXED: was ImGui.windows (lowercase w) so windows were never registered
	ImGui.Windows[Window] = WindowConfig
	ImGui:CheckStyles(Window, WindowConfig, WindowConfig.Colors)

	--// Window section events
	if not WindowConfig.NoSelectEffect then
		ImGui:ApplyWindowSelectEffect(Window, TitleBar)
	end

	return ImGui:MergeMetatables(WindowConfig, Window)
end

function ImGui:CreateModal(Config)
	local ModalEffect = Prefabs.ModalEffect:Clone()
	ModalEffect.BackgroundTransparency = 1
	ModalEffect.Parent = ImGui.FullScreenGui
	ModalEffect.Visible = true

	ImGui:Tween(ModalEffect, {
		BackgroundTransparency = 0.6
	})

	--// Config
	Config = Config or {}
	Config.TabsBar = Config.TabsBar ~= nil and Config.TabsBar or false
	Config.NoCollapse = true
	Config.NoResize = true
	Config.NoClose = true
	Config.NoSelectEffect = true
	Config.Parent = ModalEffect

	--// Center
	Config.AnchorPoint = Vector2.new(0.5, 0.5)
	Config.Position = UDim2.fromScale(0.5, 0.5)

	--// Create Window
	local Window = self:CreateWindow(Config)
	Config = Window:CreateTab({
		Visible = true
	})

	--// Disable other windows
	local WindowManger = ImGui:SetWindowProps({
		Interactable = false
	}, {Window.Window})

	--// Close functions
	local WindowClose = Window.Close
	function Config:Close()
		local Tween = ImGui:Tween(ModalEffect, {
			BackgroundTransparency = 1
		})
		Tween.Completed:Connect(function()
			ModalEffect:Remove()
		end)

		WindowManger:Revert()
		WindowClose()
	end

	return Config
end

-- ------------------------------------------------------------------
--// THEMING
-- ------------------------------------------------------------------

--// Auto-detects the accent color the prefabs were made with
function ImGui:DetectAccent(Root)
	Root = Root or Prefabs
	local Counts, Colors = {}, {}

	local function Count(Color: Color3)
		local _, Saturation, Value = Color3.toHSV(Color)
		if Saturation < 0.25 or Value < 0.15 then return end

		local Key = string.format("%d,%d,%d", Color.R * 255, Color.G * 255, Color.B * 255)
		Counts[Key] = (Counts[Key] or 0) + 1
		Colors[Key] = Color
	end

	for _, Object in next, Root:GetDescendants() do
		if Object:IsA("GuiObject") then
			Count(Object.BackgroundColor3)
		elseif Object:IsA("UIStroke") then
			Count(Object.Color)
		end
	end

	local BestKey, BestCount = nil, 0
	for Key, CountValue in next, Counts do
		if CountValue > BestCount then
			BestKey, BestCount = Key, CountValue
		end
	end

	return BestKey and Colors[BestKey] or nil
end

--// Recolors every element inside Root that uses the From color
function ImGui:ApplyAccent(Root, From: Color3, To: Color3)
	if SameColor(From, To) then return end

	for _, Object in next, Root:GetDescendants() do
		pcall(function()
			if Object:IsA("GuiObject") then
				if SameColor(Object.BackgroundColor3, From) then
					Object.BackgroundColor3 = To
				end
				if SameColor(Object.TextColor3, From) then
					Object.TextColor3 = To
				end
				--// FIXED: ImageColor3 only exists on image elements,
				--// reading it on TextButton/Frame threw and killed SetAccent
				if Object:IsA("ImageLabel") or Object:IsA("ImageButton") then
					if SameColor(Object.ImageColor3, From) then
						Object.ImageColor3 = To
					end
				end
			elseif Object:IsA("UIStroke") then
			if SameColor(Object.Color, From) then
				Object.Color = To
			end
		elseif Object:IsA("UIGradient") then
			local Changed = false
			local Keypoints = table.create(#Object.Color.Keypoints)

			for Index, Keypoint in next, Object.Color.Keypoints do
				local Color = Keypoint.Value
				if SameColor(Color, From) then
					Color = To
					Changed = true
				end
				Keypoints[Index] = ColorSequenceKeypoint.new(Keypoint.Time, Color)
			end

			if Changed then
					Object.Color = ColorSequence.new(Keypoints)
				end
			end
		end)
	end
end

--// Set the accent color. Accepts a Color3 or a preset name from ImGui.Themes.
--// Recolors the prefabs (so all future elements match) and every open window
function ImGui:SetAccent(Color)
	if typeof(Color) == "string" then
		Color = self.Themes[Color]
	end
	if typeof(Color) ~= "Color3" then
		return self:Warn("SetAccent: expected a Color3 or a preset name, got", typeof(Color))
	end

	--// Rainbow overrides the accent every frame, stop it first
	if self.Theme.RainbowConnection then
		self.Theme.RainbowConnection:Disconnect()
		self.Theme.RainbowConnection = nil
		self.Theme.Rainbow = false
	end

	local From = self.Theme.Current or self.Theme.Accent
	self.Theme.Accent = Color
	self.Theme.Current = Color

	--// Prefabs: every element created from now on uses the new accent
	ImGui:ApplyAccent(Prefabs, From, Color)

	--// Windows that already exist
	for Window in next, self.Windows do
		ImGui:ApplyAccent(Window, From, Color)
	end

	return self
end

function ImGui:GetAccent(): Color3
	return self.Theme.Accent
end

--// Apply a theme: ImGui:SetTheme("Red") or ImGui:SetTheme(Color3.new(1, 0, 0))
function ImGui:SetTheme(Theme)
	if typeof(Theme) == "string" then
		return self:SetAccent(self.Themes[Theme] or self.Theme.Accent)
	end
	return self:SetAccent(Theme)
end

--// Animated rainbow accent (opt-in). The accent color cycles on Heartbeat
function ImGui:SetRainbow(Enabled: boolean, Speed: number?)
	local Theme = self.Theme
	Theme.RainbowSpeed = Speed or Theme.RainbowSpeed

	if Theme.RainbowConnection then
		Theme.RainbowConnection:Disconnect()
		Theme.RainbowConnection = nil
	end
	Theme.Rainbow = Enabled == true

	if not Theme.Rainbow then return self end

	--// Collect every object that currently uses the accent color
	local Records = {}
	local function Collect(Root)
		for _, Object in next, Root:GetDescendants() do
			if Object:IsA("GuiObject") then
				if SameColor(Object.BackgroundColor3, Theme.Current) then
					table.insert(Records, {Object = Object, Property = "BackgroundColor3"})
				end
				if SameColor(Object.TextColor3, Theme.Current) then
					table.insert(Records, {Object = Object, Property = "TextColor3"})
				end
				if SameColor(Object.ImageColor3, Theme.Current) then
					table.insert(Records, {Object = Object, Property = "ImageColor3"})
				end
			elseif Object:IsA("UIStroke") then
				if SameColor(Object.Color, Theme.Current) then
					table.insert(Records, {Object = Object, Property = "Color"})
				end
			elseif Object:IsA("UIGradient") then
				if SameColor(Object.Color.Keypoints[1].Value, Theme.Current) then
					local Times = {}
					for Index, Keypoint in next, Object.Color.Keypoints do
						Times[Index] = Keypoint.Time
					end
					table.insert(Records, {Object = Object, Property = "Color", Gradient = Times})
				end
			end
		end
	end

	Collect(Prefabs)
	for Window in next, self.Windows do
		Collect(Window)
	end

	local _, Saturation, Value = Color3.toHSV(Theme.Current)

	Theme.RainbowConnection = RunService.Heartbeat:Connect(function()
		local Hue = (os.clock() * Theme.RainbowSpeed) % 1
		local Color = Color3.fromHSV(Hue, math.max(Saturation, 0.55), math.max(Value, 0.8))

		Theme.Accent = Color
		Theme.Current = Color

		for _, Record in next, Records do
			local Object = Record.Object
			if Object.Parent then
				if Record.Gradient then
					local Keypoints = table.create(#Record.Gradient)
					for Index, Time in next, Record.Gradient do
						Keypoints[Index] = ColorSequenceKeypoint.new(Time, Color)
					end
					Object.Color = ColorSequence.new(Keypoints)
				else
					Object[Record.Property] = Color
				end
			end
		end
	end)

	return self
end

-- ------------------------------------------------------------------
--// NEW: toast notifications
-- ------------------------------------------------------------------

function ImGui:Notify(Config)
	Config = Config or {}
	local AccentColor = self.Theme.Current or self.Theme.Accent

	--// Holder (created once)
	local Holder = self.NotifyHolder
	if not Holder then
		Holder = ImGui:CreateInstance("Frame", self.ScreenGui, {
			Name = "Notifications",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 10),
			Size = UDim2.fromOffset(280, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		})
		ImGui:CreateInstance("UIListLayout", Holder, {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		})
		self.NotifyHolder = Holder
	end

	local Duration = Config.Duration or 3

	--// Style sources: pull the real ImGui look from the prefabs so
	--// notifications always match the current window/theme
	local WindowPrefab = Prefabs.Window
	local CardColor = WindowPrefab and WindowPrefab.BackgroundColor3
		or Color3.fromRGB(24, 24, 30)

	local TitleFont, TitleSize = Enum.Font.GothamMedium, 14
	pcall(function()
		local Ref = WindowPrefab.Content.TitleBar.Left.Title
		if Ref:IsA("TextLabel") then
			TitleFont = Ref.Font
			TitleSize = Ref.TextSize
		end
	end)
	local BodyColor = Color3.fromRGB(180, 180, 190)
	pcall(function()
		if Prefabs.Label:IsA("TextLabel") then
			BodyColor = Prefabs.Label.TextColor3
		end
	end)

	--// Notification frame (mini ImGui window: card color + accent
	--// stroke + left accent strip + accent title in the prefab font)
	local Frame = ImGui:CreateInstance("Frame", Holder, {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = CardColor,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = -math.floor(os.clock()), --// newest on top
	})
	ImGui:CreateInstance("UICorner", Frame, {CornerRadius = UDim.new(0, 8)})
	local Stroke = ImGui:CreateInstance("UIStroke", Frame, {
		Color = AccentColor,
		Thickness = 1,
		Transparency = 1,
	})
	ImGui:CreateInstance("UIPadding", Frame, {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 12),
	})
	ImGui:CreateInstance("UIListLayout", Frame, {
		Padding = UDim.new(0, 4),
		VerticalAlignment = Enum.VerticalAlignment.Top,
	})

	--// Left accent strip (same accent line the windows use)
	ImGui:CreateInstance("Frame", Frame, {
		Name = "AccentBar",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = AccentColor,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})

	--// Header (icon + title)
	local Header = ImGui:CreateInstance("Frame", Frame, {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
	})
	ImGui:CreateInstance("UIListLayout", Header, {
		Padding = UDim.new(0, 6),
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})

	local Icon = nil
	if Config.Icon then
		local Image = tonumber(Config.Icon) and `rbxassetid://{Config.Icon}` or Config.Icon
		Icon = ImGui:CreateInstance("ImageLabel", Header, {
			Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1,
			Image = Image,
			ImageTransparency = 1,
		})
	end

	local Title = ImGui:CreateInstance("TextLabel", Header, {
		Size = UDim2.new(1, Icon and -24 or 0, 1, 0),
		BackgroundTransparency = 1,
		Text = tostring(Config.Title or "Notification"),
		TextColor3 = AccentColor,
		TextSize = TitleSize,
		Font = TitleFont,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTransparency = 1,
	})

	local BodyText = tostring(Config.Text or "")
	local Body = nil
	if BodyText ~= "" then
		Body = ImGui:CreateInstance("TextLabel", Frame, {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text = BodyText,
			TextWrapped = true,
			RichText = Config.RichText == true,
			TextColor3 = BodyColor,
			TextSize = math.max(12, TitleSize - 1),
			Font = TitleFont,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTransparency = 1,
		})
	end

	--// Entry animation (same duration/tween style as the rest of the UI)
	local Info = TweenInfo.new(0.25)
	ImGui:Tween(Frame, {BackgroundTransparency = 0.08}, Info)
	ImGui:Tween(Stroke, {Transparency = 0.55}, Info)
	ImGui:Tween(Title, {TextTransparency = 0}, Info)
	if Icon then
		ImGui:Tween(Icon, {ImageTransparency = 0}, Info)
	end
	if Body then
		ImGui:Tween(Body, {TextTransparency = 0}, Info)
	end
	pcall(function()
		ImGui:Tween(Frame.AccentBar, {BackgroundTransparency = 0}, Info)
	end)

	--// API
	local Notification = {
		Frame = Frame,
	}
	local Closed = false

	function Notification:Close()
		if Closed then return end
		Closed = true

		--// Stop tracking
		local Index = table.find(ImGui.Notifications, Notification)
		if Index then
			table.remove(ImGui.Notifications, Index)
		end

		local CloseInfo = TweenInfo.new(0.2)
		ImGui:Tween(Frame, {BackgroundTransparency = 1}, CloseInfo)
		ImGui:Tween(Stroke, {Transparency = 1}, CloseInfo)
		ImGui:Tween(Title, {TextTransparency = 1}, CloseInfo)
		pcall(function()
			ImGui:Tween(Frame.AccentBar, {BackgroundTransparency = 1}, CloseInfo)
		end)
		if Icon then
			ImGui:Tween(Icon, {ImageTransparency = 1}, CloseInfo)
		end
		if Body then
			ImGui:Tween(Body, {TextTransparency = 1}, CloseInfo)
		end

		task.delay(0.22, function()
			Frame:Destroy()
		end)

		if Config.Closed then
			Config.Closed(Notification)
		end
	end

	function Notification:SetTitle(Text)
		Title.Text = tostring(Text)
		return self
	end

	function Notification:SetText(Text)
		if Body then
			Body.Text = tostring(Text)
		end
		return self
	end

	table.insert(self.Notifications, Notification)

	task.delay(Duration, function()
		Notification:Close()
	end)

	return Notification
end

-- ------------------------------------------------------------------
--// NEW: modal prompt with buttons (supports :Wait())
-- ------------------------------------------------------------------

function ImGui:Prompt(Config)
	Config = Config or {}

	local Signal = Instance.new("BindableEvent")
	local Result = nil

	--// Modal window
	local ModalConfig = {
		Title = Config.Title or "Prompt",
		NoAnimation = Config.NoAnimation,
	}
	if Config.Size then
		ModalConfig.Size = Config.Size
	else
		ModalConfig.AutoSize = "Y" --// grow with content
	end

	local Modal = self:CreateModal(ModalConfig)

	if Config.Text then
		Modal:Label({
			Text = tostring(Config.Text),
			TextWrapped = true,
			TextSize = 14,
		})
	end

	--// Buttons: {"OK"} or {{"Yes", callback}, "No", ...}
	local Buttons = Config.Buttons or {"OK"}
	local Row = Modal:Row({})
	for _, ButtonInfo in next, Buttons do
		local Name, Callback = ButtonInfo, nil
		if typeof(ButtonInfo) == "table" then
			Name, Callback = ButtonInfo[1], ButtonInfo[2]
		end

		Row:Button({
			Label = tostring(Name),
			Callback = function()
				Result = Name
				Modal:Close()
				Signal:Fire(Name)
				if Callback then
					Callback(Name)
				end
			end,
		})
	end
	pcall(function()
		Row:Fill()
	end)

	local Prompt = {}
	function Prompt:Wait()
		return Signal.Event:Wait()
	end
	function Prompt:GetResult()
		return Result
	end
	function Prompt:Close()
		Modal:Close()
	end
	return Prompt
end

-- ------------------------------------------------------------------
--// Global helpers & unload
-- ------------------------------------------------------------------

function ImGui:SetWindowsVisible(Visible: boolean)
	ImGui.WindowsVisible = Visible
	for _, WindowConfig in next, self.Windows do
		WindowConfig:SetVisible(Visible)
	end
	return self
end
ImGui.WindowsVisible = true

function ImGui:Destroy()
	for _, Connection in next, self.Connections do
		pcall(function()
			Connection:Disconnect()
		end)
	end
	table.clear(self.Connections)
	table.clear(self.Windows)
	table.clear(self.Notifications)

	local Theme = self.Theme
	if Theme.RainbowConnection then
		Theme.RainbowConnection:Disconnect()
		Theme.RainbowConnection = nil
	end

	if self.NotifyHolder then
		self.NotifyHolder:Destroy()
		self.NotifyHolder = nil
	end

	self.ScreenGui:Destroy()
	self.FullScreenGui:Destroy()
	self.Destroyed = true
end

local GuiParent = IsStudio and PlayerGui or CoreGui
ImGui.ScreenGui = ImGui:CreateInstance("ScreenGui", GuiParent, {
	DisplayOrder = 9999,
	ResetOnSpawn = false
})
ImGui.FullScreenGui = ImGui:CreateInstance("ScreenGui", GuiParent, {
	DisplayOrder = 99999,
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.None
})

--// Detect the accent color the prefabs were made with
ImGui.Theme.Detected = ImGui:DetectAccent(Prefabs) or ImGui.Theme.Accent
ImGui.Theme.Current = ImGui.Theme.Detected

--// Global show/hide keybind (cleaned up by ImGui:Destroy)
table.insert(ImGui.Connections, UserInputService.InputBegan:Connect(function(Input, GameProcessed)
	if GameProcessed then return end
	if ImGui.ToggleKey and Input.KeyCode == ImGui.ToggleKey then
		ImGui:SetWindowsVisible(not ImGui.WindowsVisible)
	end
end))

--// Load marker: if this line is NOT in your console, the executor is
--// still running an OLD copy of the library (re-upload mainlib.lua!)
print("[DepsoImGui v" .. ImGui.Version .. "] loaded | demo-junk purged: "
	.. tostring(ImGui.DemoJunkRemoved) .. " element(s)")

return ImGui
 
