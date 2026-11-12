--// Written by depso
--// MIT License
--// Copyright (c) 2024 Depso
--// Optimized & extended version

local ImGui = {
	Animations = {
		Buttons = {
			MouseEnter = { BackgroundTransparency = 0.5 },
			MouseLeave = { BackgroundTransparency = 0.7 }
		},
		Tabs = {
			MouseEnter = { BackgroundTransparency = 0.5 },
			MouseLeave = { BackgroundTransparency = 1 }
		},
		Inputs = {
			MouseEnter = { BackgroundTransparency = 0 },
			MouseLeave = { BackgroundTransparency = 0.5 }
		},
		WindowBorder = {
			Selected   = { Transparency = 0,   Thickness = 1 },
			Deselected = { Transparency = 0.7, Thickness = 1 }
		},
	},

	Windows = {},
	Animation = TweenInfo.new(0.1),
	UIAssetId = "rbxassetid://85607317875581",

	--// === NEW: Theme system ===
	Theme = {
		Name = "Blue",
		Accent = Color3.fromRGB(85, 120, 255),
		AccentDark = Color3.fromRGB(60, 90, 200),
		AccentLight = Color3.fromRGB(120, 150, 255),
	},

	--// === NEW: Preset themes ===
	Themes = {
		Blue   = { Accent = Color3.fromRGB(85, 120, 255),  AccentDark = Color3.fromRGB(60, 90, 200),   AccentLight = Color3.fromRGB(120, 150, 255) },
		Purple = { Accent = Color3.fromRGB(160, 90, 255),  AccentDark = Color3.fromRGB(120, 60, 210),  AccentLight = Color3.fromRGB(190, 130, 255) },
		Green  = { Accent = Color3.fromRGB(60, 200, 120),  AccentDark = Color3.fromRGB(40, 160, 90),   AccentLight = Color3.fromRGB(100, 230, 160) },
		Red    = { Accent = Color3.fromRGB(230, 70, 70),   AccentDark = Color3.fromRGB(190, 50, 50),   AccentLight = Color3.fromRGB(255, 110, 110) },
		Orange = { Accent = Color3.fromRGB(255, 150, 50),  AccentDark = Color3.fromRGB(210, 115, 30),  AccentLight = Color3.fromRGB(255, 180, 100) },
		Pink   = { Accent = Color3.fromRGB(255, 100, 180), AccentDark = Color3.fromRGB(210, 70, 140),  AccentLight = Color3.fromRGB(255, 140, 210) },
		Dark   = { Accent = Color3.fromRGB(60, 60, 70),    AccentDark = Color3.fromRGB(40, 40, 50),    AccentLight = Color3.fromRGB(90, 90, 100) },
		Light  = { Accent = Color3.fromRGB(220, 220, 230), AccentDark = Color3.fromRGB(180, 180, 190), AccentLight = Color3.fromRGB(245, 245, 250) },
	},
}

--// Universal functions
local NullFunction = function() end
local CloneRef = cloneref or function(_) return _ end
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

--// === NEW: Global input dispatcher (performance) ===
--// Один connection вместо десятков per-element
local _inputEndedHandlers = {}
local _inputChangedHandlers = {}

UserInputService.InputEnded:Connect(function(input)
	for i = #_inputEndedHandlers, 1, -1 do
		local h = _inputEndedHandlers[i]
		if h(input) then
			table.remove(_inputEndedHandlers, i)
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	for i = #_inputChangedHandlers, 1, -1 do
		local h = _inputChangedHandlers[i]
		if h(input) then
			table.remove(_inputChangedHandlers, i)
		end
	end
end)

function ImGui:_OnInputEnded(handler)
	table.insert(_inputEndedHandlers, handler)
end

function ImGui:_OnInputChanged(handler)
	table.insert(_inputChangedHandlers, handler)
end

--// Prefabs
function ImGui:FetchUI()
	local CacheName = "DepsoImGui"
	if _G[CacheName] then
		self:Warn("Prefabs loaded from Cache")
		return _G[CacheName]
	end

	local UI = nil
	if not IsStudio then
		UI = game:GetObjects(ImGui.UIAssetId)[1]
	else
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

--// === NEW: Cache strokes/corners to avoid FindFirstChildOfClass churn ===
local function GetStroke(obj)
	return obj:FindFirstChildOfClass("UIStroke")
end
local function GetCorner(obj)
	return obj:FindFirstChildOfClass("UICorner")
end
ImGui.GetStroke = GetStroke
ImGui.GetCorner = GetCorner

--// Styles
local AddionalStyles = {
	[{
		Name = "Border"
	}] = function(GuiObject, Value, Class)
		local Outline = GetStroke(GuiObject)
		if not Outline then return end
		if Class.BorderThickness then
			Outline.Thickness = Class.BorderThickness
		end
		Outline.Enabled = Value
	end,

	[{
		Name = "Ratio"
	}] = function(GuiObject, Value, Class)
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
		Name = "CornerRadius",
		Recursive = true
	}] = function(GuiObject, Value, Class)
		local UICorner = GetCorner(GuiObject)
		if not UICorner then
			UICorner = ImGui:CreateInstance("UICorner", GuiObject)
		end
		UICorner.CornerRadius = Class.CornerRadius
	end,

	[{
		Name = "Label"
	}] = function(GuiObject, Value, Class)
		local Label = GuiObject:FindFirstChild("Label")
		if not Label then return end
		Label.Text = Class.Label
		function Class:SetLabel(Text)
			Label.Text = Text
			return Class
		end
	end,

	[{
		Name = "NoGradient",
		Aliases = { "NoGradientAll" },
		Recursive = true
	}] = function(GuiObject, Value, Class)
		local UIGradient = GuiObject:FindFirstChildOfClass("UIGradient")
		if not UIGradient then return end
		UIGradient.Enabled = not Value
	end,

	[{
		Name = "Callback"
	}] = function(GuiObject, Value, Class)
		function Class:SetCallback(NewCallback)
			Class.Callback = NewCallback
			return Class
		end
		function Class:FireCallback(...)
			return Class.Callback(GuiObject, ...)
		end
	end,

	[{
		Name = "Value"
	}] = function(GuiObject, Value, Class)
		function Class:GetValue()
			return Class.Value
		end
	end,

	--// === NEW: Disabled state ===
	[{
		Name = "Disabled"
	}] = function(GuiObject, Value, Class)
		function Class:SetDisabled(state)
			Class.Disabled = state
			GuiObject.Active = not state
			GuiObject.Interactable = not state
			for _, d in GuiObject:GetDescendants() do
				if d:IsA("GuiObject") then
					d.Active = not state
					d.Interactable = not state
				end
			end
			return Class
		end
	end,
}

function ImGui:GetName(Name: string)
	return "%s_":format(Name)
end

function ImGui:CreateInstance(Class, Parent, Properties)
	local Instance = Instance.new(Class, Parent)
	for Key, Value in next, Properties or {} do
		Instance[Key] = Value
	end
	return Instance
end

function ImGui:ApplyColors(ColorOverwrites, GuiObject, ElementType)
	for Info, Value in next, ColorOverwrites do
		local Key = Info
		local Recursive = false
		if typeof(Info) == "table" then
			Key = Info.Name or ""
			Recursive = Info.Recursive or false
		end

		if typeof(Value) == "table" then
			local Element = GuiObject:FindFirstChild(Key, Recursive)
			if not Element then
				if ElementType == "Window" then
					Element = GuiObject.Content:FindFirstChild(Key, Recursive)
					if not Element then continue end
				else
					warn(Key, "was not found in", GuiObject)
					continue
				end
			end
			ImGui:ApplyColors(Value, Element)
			continue
		end
		GuiObject[Key] = Value
	end
end

--// === NEW: Accent color application ===
function ImGui:ApplyAccentTo(GuiObject)
	local accent = self.Theme.Accent
	local accentDark = self.Theme.AccentDark
	local accentLight = self.Theme.AccentLight

	local function tryApply(obj)
		if not obj or not obj:IsA("GuiObject") then return end
		-- Только для элементов, помеченных как "accent-capable" по имени/классу
		local n = obj.Name
		local cls = obj.ClassName

		-- UIStroke с градиентом — красим
		local stroke = GetStroke(obj)
		if stroke and (obj:GetAttribute("AccentStroke") or n:find("Grab") or n:find("Fill") or n:find("Toggle") or n:find("Tick")) then
			stroke.Color = accent
		end

		-- UIGradient — перекрашиваем стопы
		local gradient = obj:FindFirstChildOfClass("UIGradient")
		if gradient and (obj:GetAttribute("AccentGradient") or n:find("Grab") or n:find("Fill")) then
			gradient.Color = ColorSequence.new(accentLight, accent)
		end

		-- Фоновые элементы, помеченные атрибутом
		if obj:GetAttribute("AccentBackground") then
			obj.BackgroundColor3 = accent
		end
	end

	tryApply(GuiObject)
	for _, d in GuiObject:GetDescendants() do
		tryApply(d)
	end
end

function ImGui:SetAccentColor(color: Color3)
	self.Theme.Accent = color
	self.Theme.AccentDark = color:Lerp(Color3.new(0, 0, 0), 0.25)
	self.Theme.AccentLight = color:Lerp(Color3.new(1, 1, 1), 0.25)
	self.Theme.Name = "Custom"

	-- Перекрасить все существующие окна
	for Window, Config in next, self.Windows do
		self:ApplyAccentTo(Window)
		self:ApplyAccentTo(Config.Button or Window)
	end
	return self
end

function ImGui:SetTheme(name: string)
	local t = self.Themes[name]
	if not t then
		self:Warn("Unknown theme:", name)
		return self
	end
	self.Theme.Name = name
	self.Theme.Accent = t.Accent
	self.Theme.AccentDark = t.AccentDark
	self.Theme.AccentLight = t.AccentLight

	for Window, Config in next, self.Windows do
		self:ApplyAccentTo(Window)
	end
	return self
end

function ImGui:GetTheme()
	return self.Theme.Name, self.Theme.Accent
end

function ImGui:CheckStyles(GuiObject, Class, Colors)
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

		Callback(GuiObject, Value, Class)
		if Info.Recursive then
			for _, Child in next, GuiObject:GetChildren() do
				Callback(Child, Value, Class)
			end
		end
	end

	local ElementType = GuiObject.Name
	GuiObject.Name = self:GetName(ElementType)

	local Colors = Colors or {}
	local ColorOverwrites = Colors[ElementType]
	if ColorOverwrites then
		ImGui:ApplyColors(ColorOverwrites, GuiObject, ElementType)
	end

	for Key, Value in next, Class do
		pcall(function()
			GuiObject[Key] = Value
		end)
	end
end

function ImGui:MergeMetatables(Class, Instance)
	local Metadata = {}
	Metadata.__index = function(self, Key)
		local suc, Value = pcall(function()
			local Value = Instance[Key]
			if typeof(Value) == "function" then
				return function(...)
					return Value(Instance, ...)
				end
			end
			return Value
		end)
		return suc and Value or Class[Key]
	end
	Metadata.__newindex = function(self, Key, Value)
		local Key2 = Class[Key]
		if Key2 ~= nil or typeof(Value) == "function" then
			Class[Key] = Value
		else
			Instance[Key] = Value
		end
	end
	return setmetatable({}, Metadata)
end

--// === FIX: без string ..= — быстрее ===
function ImGui:Concat(Table, Separator: " ")
	local parts = table.create(#Table)
	for Index, String in next, Table do
		parts[Index] = tostring(String)
	end
	return table.concat(parts, Separator)
end

function ImGui:ContainerClass(Frame: Frame, Class, Window)
	local ContainerClass = Class or {}
	local WindowConfig = ImGui.Windows[Window]

	function ContainerClass:NewInstance(Instance, Class, Parent)
		Class = Class or {}
		Instance.Parent = Parent or Frame
		Instance.Visible = true

		if WindowConfig.NoGradientAll then
			Class.NoGradient = true
		end

		local Colors = WindowConfig.Colors
		ImGui:CheckStyles(Instance, Class, Colors)
		ImGui:ApplyAccentTo(Instance)

		if Class.NewInstanceCallback then
			Class.NewInstanceCallback(Instance)
		end
		return ImGui:MergeMetatables(Class, Instance)
	end

	function ContainerClass:Button(Config)
		Config = Config or {}
		local Button = Prefabs.Button:Clone()
		local ObjectClass = self:NewInstance(Button, Config)

		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end
		Button.Activated:Connect(Callback)
		ImGui:ApplyAnimations(Button, "Buttons")
		return ObjectClass
	end

	function ContainerClass:Image(Config)
		Config = Config or {}
		local Image = Prefabs.Image:Clone()
		if tonumber(Config.Image) then
			Config.Image = `rbxassetid://{Config.Image}`
		end
		local ObjectClass = self:NewInstance(Image, Config)
		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end
		Image.Activated:Connect(Callback)
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
		return self:NewInstance(Label, Config)
	end

	function ContainerClass:Checkbox(Config)
		Config = Config or {}
		local IsRadio = Config.IsRadio
		local CheckBox = Prefabs.CheckBox:Clone()
		local Tickbox: ImageButton = CheckBox.Tickbox
		local Tick: ImageLabel = Tickbox.Tick
		local Label = CheckBox.Label
		local ObjectClass = self:NewInstance(CheckBox, Config)

		if IsRadio then
			Tick.ImageTransparency = 1
			Tick.BackgroundTransparency = 0
		else
			local pad = Tickbox:FindFirstChildOfClass("UIPadding")
			if pad then pad:Remove() end
			local corner = GetCorner(Tickbox)
			if corner then corner:Remove() end
		end

		ImGui:ApplyAnimations(CheckBox, "Buttons", Tickbox)

		local Value = Config.Value or false
		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end

		function Config:SetTicked(NewValue, NoAnimation)
			Value = NewValue
			Config.Value = Value
			local Size = Value and UDim2.fromScale(1, 1) or UDim2.fromScale(0, 0)
			ImGui:Tween(Tick, { Size = Size }, nil, NoAnimation)
			ImGui:Tween(Label, { TextTransparency = Value and 0 or 0.3 }, nil, NoAnimation)
			Callback(Value)
			return Config
		end
		Config:SetTicked(Value, true)

		function Config:Toggle()
			Config:SetTicked(not Value)
			return Config
		end

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
			Camera.CFrame = CFrame.new(0, 0, 0)
			return Config
		end

		local Camera = Config.Camera or ImGui:CreateInstance("Camera", Viewport)
		Config:SetCamera(Camera)

		function Config:SetModel(Model: Model, PivotTo: CFrame)
			WorldModel:ClearAllChildren()
			if Config.Clone then Model = Model:Clone() end
			if PivotTo then Model:PivotTo(PivotTo) end
			Model.Parent = WorldModel
			Config.Model = Model
			return Model
		end

		if Model then Config:SetModel(Model) end
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

		ImGui:ApplyAnimations(TextInput, "Inputs")

		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end

		--// FIX: debounce — не дёргаем callback каждый символ
		local pending = false
		TextBox:GetPropertyChangedSignal("Text"):Connect(function()
			if pending then return end
			pending = true
			task.defer(function()
				pending = false
				local Value = TextBox.Text
				Config.Value = Value
				Callback(Value)
			end)
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

	--// === FIX: кэш UIListLayout/UIPadding ===
	function ContainerClass:GetRemainingHeight()
		local Padding = Frame:FindFirstChildOfClass("UIPadding")
		local UIListLayout = Frame:FindFirstChildOfClass("UIListLayout")
		local LayoutPaddding = UIListLayout.Padding
		local PaddingSizeY = Padding.PaddingTop + Padding.PaddingBottom + LayoutPaddding
		local OccupiedY = Frame.AbsoluteSize.Y + PaddingSizeY.Offset + 3
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

		Source.TextEditable = Config.ReadOnly ~= true
		Source.Text = Config.Text or ""
		Source.TextWrapped = Config.TextWrapped == true
		Source.RichText = Config.RichText == true
		Lines.Visible = Config.LineNumbers == true

		function Config:UpdateLineNumbers()
			if not Config.LineNumbers then return end
			local LinesCount = #Source.Text:split("\n")
			local Format = Config.LinesFormat or "%s"
			local t = table.create(LinesCount)
			for i = 1, LinesCount do
				t[i] = Format:format(i) .. (i ~= LinesCount and '\n' or '')
			end
			Lines.Text = table.concat(t)
			Source.Size = UDim2.new(1, -Lines.AbsoluteSize.X, 0, 0)
			return Config
		end

		function Config:UpdateScroll()
			Console.CanvasPosition = Vector2.new(0, Console.AbsoluteCanvasSize.Y)
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
		function Config:Clear()
			Source.Text = ""
			Config:UpdateLineNumbers()
			return Config
		end

		function Config:AppendText(...)
			if not Config.Enabled then return end
			local MaxLines = Config.MaxLines or 100
			local NewString = "\n" .. ImGui:Concat({ ... }, " ")
			Source.Text ..= NewString
			Config:UpdateLineNumbers()
			if Config.AutoScroll then Config:UpdateScroll() end
			local Lines = Source.Text:split("\n")
			if #Lines > MaxLines then
				Source.Text = Source.Text:sub(#Lines[1] + 2)
			end
			return Config
		end

		Source.Changed:Connect(Config.UpdateLineNumbers)
		return self:NewInstance(Console, Config)
	end

	--// === FIX: rows/columns без repeated GetChildren ===
	function ContainerClass:Table(Config)
		Config = Config or {}
		local Table: Frame = Prefabs.Table:Clone()
		local TableChildCount = #Table:GetChildren()

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

			local RowChildCount = #Row:GetChildren()
			Row.Name = RowName
			Row.Visible = true

			if Config.RowBackground then
				Row.BackgroundTransparency = RowsCount % 2 == 1 and 0.92 or 1
			end

			function RowClass:CreateColumn(CConfig)
				CConfig = CConfig or {}
				local Column: Frame = Row.ColumnTemp:Clone()
				Column.Visible = true
				Column.Name = "Column"
				local Stroke = GetStroke(Column)
				if Stroke then Stroke.Enabled = Config.Border ~= false end

				local ContainClass = ImGui:ContainerClass(Column, CConfig, Window)
				return ContainerClass:NewInstance(Column, ContainClass, Row)
			end

			--// FIX: отложенный пересчёт колонок
			local updateQueued = false
			local function UpdateColumns()
				if updateQueued then return end
				updateQueued = true
				task.defer(function()
					updateQueued = false
					if not Row or not Table then return end
					local Columns = Row:GetChildren()
					local RowsCount2 = #Columns - RowChildCount
					if RowsCount2 <= 0 then return end
					local sz = UDim2.new(1 / RowsCount2, 0, 0, 0)
					for _, Column in next, Columns do
						if Column:IsA("Frame") then Column.Size = sz end
					end
				end)
			end
			function RowClass:UpdateColumns() UpdateColumns() return RowClass end

			Row.ChildAdded:Connect(UpdateColumns)
			Row.ChildRemoved:Connect(UpdateColumns)

			RowsCount += 1
			return ContainerClass:NewInstance(Row, RowClass, Table)
		end

		local updateRowsQueued = false
		local function UpdateRows()
			if updateRowsQueued then return end
			updateRowsQueued = true
			task.defer(function()
				updateRowsQueued = false
				local Rows = Table:GetChildren()
				local PaddingY = Table.UIListLayout.Padding.Offset + 2
				local RowsCount2 = #Rows - TableChildCount
				if RowsCount2 <= 0 then return end
				local sz = UDim2.new(1, 0, 1 / RowsCount2, -PaddingY)
				for _, Row in next, Rows do
					if Row:IsA("Frame") then Row.Size = sz end
				end
			end)
		end
		function Config:UpdateRows() UpdateRows() return Config end

		if Config.RowsFill then
			Table.AutomaticSize = Enum.AutomaticSize.None
			Table.ChildAdded:Connect(UpdateRows)
			Table.ChildRemoved:Connect(UpdateRows)
		end

		function Config:ClearRows()
			RowsCount = 0
			local PostRowName = ImGui:GetName(RowName)
			for _, Row in next, Table:GetChildren() do
				if Row:IsA("Frame") and Row.Name == PostRowName then
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

		if Config.IsTree then
			ImGui:ApplyAnimations(Titlebar, "Tabs")
		else
			ImGui:ApplyAnimations(Titlebar, "Buttons")
		end

		function Config:SetOpen(Open)
			local Animate = Config.NoAnimation ~= true
			Config.Open = Open
			ImGui:HeaderAnimate(Header, Animate, Open, Titlebar)
			return self
		end

		local ToggleButton = Titlebar.Toggle.ToggleButton
		local function Toggle()
			Config:SetOpen(not Config.Open)
		end
		Titlebar.Activated:Connect(Toggle)
		ToggleButton.Activated:Connect(Toggle)

		if Config.Image then
			ToggleButton.Image = Config.Image
		end

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
		if not Config.Text then HeaderLabel.Visible = false end
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
			local Rows = #Children - 2
			local Padding = UIListLayout.Padding.Offset * 2
			UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			UIPadding.PaddingLeft = UIListLayout.Padding
			UIPadding.PaddingRight = UIListLayout.Padding
			for _, Child in next, Children do
				local YScale = Child:IsA("ImageButton") and 1 or 0
				pcall(function()
					Child.Size = UDim2.new(1 / Rows, -Padding, YScale, 0)
				end)
			end
			return Config
		end

		local ContainClass = ImGui:ContainerClass(Row, Config, Window)
		return self:NewInstance(Row, ContainClass)
	end

	--// === FIX: слайдер без per-instance InputEnded ===
	function ContainerClass:Slider(Config)
		Config = Config or {}
		local Value = Config.Value or 0
		local ValueFormat = Config.Format or "%.d"
		local IsProgress = Config.Progress
		Config.Name = Config.Label or ""

		local Slider: TextButton = Prefabs.Slider:Clone()
		local UIPadding = Slider:FindFirstChildOfClass("UIPadding")
		local Grab: Frame = Slider.Grab
		local ValueText = Slider.ValueText
		local Label = Slider.Label

		local Dragging = false
		local InputType = Enum.UserInputType.MouseButton1
		local ObjectClass = self:NewInstance(Slider, Config)

		local function Callback(...)
			local func = Config.Callback or NullFunction
			return func(ObjectClass, ...)
		end

		if IsProgress then
			local UIGradient = Grab:FindFirstChildOfClass("UIGradient")
			local PaddingSides = UDim.new(0, 2)
			local Diff = UIPadding.PaddingLeft - PaddingSides
			Grab.AnchorPoint = Vector2.new(0, 0.5)
			if UIGradient then UIGradient.Enabled = true end
			UIPadding.PaddingLeft = PaddingSides
			UIPadding.PaddingRight = PaddingSides
			Label.Position = UDim2.new(1, 15 - Diff.Offset, 0, 0)
		end

		function Config:SetValue(Value, SliderMode)
			local MinValue = Config.MinValue
			local MaxValue = Config.MaxValue
			local Difference = MaxValue - MinValue
			local Percentage = (Value - MinValue) / Difference
			if not SliderMode then
				Value = tonumber(Value)
			else
				Percentage = Value
				Value = MinValue + (Difference * Percentage)
			end
			local Props = IsProgress
				and { Size = UDim2.fromScale(Percentage, 1) }
				or { Position = UDim2.fromScale(Percentage, 0.5) }
			ImGui:Tween(Grab, Props)
			Config.Value = Value
			ValueText.Text = ValueFormat:format(Value, MaxValue)
			Callback(Value)
			return Config
		end

		--// FIX: глобальный InputChanged только пока тянем
		local moveHandler
		local function MouseMove()
			if Config.ReadOnly or not Dragging then return end
			local MouseX = UserInputService:GetMouseLocation().X
			local Percentage = (MouseX - Slider.AbsolutePosition.X) / Slider.AbsoluteSize.X
			Config:SetValue(math.clamp(Percentage, 0, 1), true)
		end

		local hover = ImGui:ConnectHover({
			Parent = Slider,
			OnInput = function(MouseHovering, Input)
				if not MouseHovering or Input.UserInputType ~= InputType then return end
				Dragging = true
				if not moveHandler then
					moveHandler = UserInputService.InputChanged:Connect(function(i)
						if i.UserInputType == Enum.UserInputType.MouseMovement then
							MouseMove()
						end
					end)
				end
			end
		})

		ImGui:_OnInputEnded(function(input)
			if not Dragging or input.UserInputType ~= InputType then return false end
			Dragging = false
			return true
		end)

		Slider.Activated:Connect(MouseMove)
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
		function Config:SetPercentage(Value) Config:SetValue(Value) end
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

		function Config:SetValue(NewKey)
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
			local Previous = Config.Value
			if NewKey.KeyCode.Name == "Unknown" then
				return Config:SetValue(Previous)
			end
			task.wait(.1)
			Config:SetValue(NewKey.KeyCode)
		end)

		Config.Connection = UserInputService.InputBegan:Connect(function(Input, GameProcessed)
			if not Config.IgnoreGameProcessed and GameProcessed then return end
			if Input.KeyCode == TobeNullKey then return end
			if Input.KeyCode ~= Config.Value then return end
			return Callback(Input.KeyCode)
		end)

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

		local ComboHovering = ImGui:ConnectHover({ Parent = Combo })

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

		function Config:SetOpen(Open)
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
			if Dropdown then Dropdown:Close() end
			Config:SetOpen(not Config.Open)
		end

		Combo.Activated:Connect(ToggleOpen)
		Toggle.Activated:Connect(ToggleOpen)
		ImGui:ApplyAnimations(Combo, "Buttons")

		if Config.Selected then Config:SetValue(Config.Selected) end
		return ObjectClass
	end

	return ContainerClass
end

--// === NEW: Tooltip ===
function ImGui:Tooltip(Config)
	Config = Config or {}
	local Parent = Config.Parent
	if not Parent then return end
	local text = Config.Text or ""
	local tip = self:CreateInstance("TextLabel", self.FullScreenGui, {
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 20, 25),
		BackgroundTransparency = 0.1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		ZIndex = 100,
	})
	tip:AddChild if false then end
	local pad = Instance.new("UIPadding", tip)
	pad.PaddingLeft = UDim.new(0, 6); pad.PaddingRight = UDim.new(0, 6)
	pad.PaddingTop = UDim.new(0, 3); pad.PaddingBottom = UDim.new(0, 3)
	local corner = Instance.new("UICorner", tip); corner.CornerRadius = UDim.new(0, 4)
	local stroke = Instance.new("UIStroke", tip); stroke.Color = self.Theme.Accent; stroke.Thickness = 1

	Parent.MouseEnter:Connect(function()
		local pos = Parent.AbsolutePosition
		tip.Position = UDim2.fromOffset(pos.X, pos.Y - tip.AbsoluteSize.Y - 4)
		tip.Visible = true
	end)
	Parent.MouseLeave:Connect(function()
		tip.Visible = false
	end)
	return tip
end

--// === NEW: Notifications ===
function ImGui:Notification(Config)
	Config = Config or {}
	local Title = Config.Title or "Notification"
	local Text = Config.Text or ""
	local Type = Config.Type or "Info"
	local Duration = Config.Duration or 4

	local colors = {
		Success = Color3.fromRGB(60, 200, 120),
		Info    = self.Theme.Accent,
		Warn    = Color3.fromRGB(255, 180, 50),
		Error   = Color3.fromRGB(230, 70, 70),
	}
	local color = colors[Type] or colors.Info

	local holder = self:CreateInstance("Frame", self.FullScreenGui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 20),
		Size = UDim2.fromOffset(280, 60),
		BackgroundColor3 = Color3.fromRGB(25, 25, 30),
		BackgroundTransparency = 0.05,
		Visible = true,
	})
	local stroke = Instance.new("UIStroke", holder); stroke.Color = color; stroke.Thickness = 1.5
	local corner = Instance.new("UICorner", holder); corner.CornerRadius = UDim.new(0, 6)

	local bar = self:CreateInstance("Frame", holder, {
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	})
	local bc = Instance.new("UICorner", bar); bc.CornerRadius = UDim.new(0, 2)

	self:CreateInstance("TextLabel", holder, {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -20, 0, 16),
		Text = Title,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	self:CreateInstance("TextLabel", holder, {
		Position = UDim2.fromOffset(12, 28),
		Size = UDim2.new(1, -20, 1, -36),
		Text = Text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(200, 200, 210),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
	})

	--// stack
	local stack = self._notifStack or {}
	self._notifStack = stack
	table.insert(stack, holder)
	local y = 20
	for _, n in stack do
		self:Tween(n, { Position = UDim2.new(1, -20, 0, y) })
		y += 70
	end

	task.delay(Duration, function()
		local idx = table.find(stack, holder)
		if idx then table.remove(stack, idx) end
		local tw = self:Tween(holder, { Position = UDim2.new(1, 20, 0, holder.Position.Y.Offset), BackgroundTransparency = 1 })
		tw.Completed:Connect(function() holder:Remove() end)
	end)
	return holder
end

--// === NEW: FPS/Ping monitor ===
local _fpsData = { fps = 60, frames = 0, last = tick() }
RunService.RenderStepped:Connect(function()
	_fpsData.frames += 1
	local now = tick()
	if now - _fpsData.last >= 1 then
		_fpsData.fps = _fpsData.frames / (now - _fpsData.last)
		_fpsData.frames = 0
		_fpsData.last = now
	end
end)

function ImGui:GetFPS() return math.floor(_fpsData.fps + 0.5) end
function ImGui:GetPing() return math.floor(LocalPlayer:GetNetworkPing() * 1000 + 0.5) end

function ImGui:Dropdown(Config)
	local Parent = Config.Parent
	if not Parent then return end
	local Selection: ScrollingFrame = Prefabs.Selection:Clone()
	local UIStroke = GetStroke(Selection)
	local Padding = UIStroke.Thickness * 2
	local Position = Parent.AbsolutePosition
	local Size = Parent.AbsoluteSize

	Selection.Parent = self.ScreenGui
	Selection.Position = UDim2.fromOffset(Position.X + Padding, Position.Y + Size.Y)
	ImGui:ApplyAccentTo(Selection)

	local Hover = self:ConnectHover({
		Parent = Selection,
		OnInput = function(MouseHovering, Input)
			if not Input.UserInputType.Name:find("Mouse") then return end
			if not MouseHovering then Config:Close() end
		end,
	})

	function Config:Close()
		local CloseCallback = Config.Closed
		if CloseCallback then CloseCallback() end
		Hover:Disconnect()
		Selection:Remove()
	end

	local function SetValue(Value)
		Config:Close()
		Config:SetValue(Value)
	end

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

	local MaxSizeY = Config.MaxSizeY or 200
	local YSize = math.clamp(Selection.AbsoluteCanvasSize.Y, Size.Y, MaxSizeY)
	Selection.Size = UDim2.fromOffset(Size.X - Padding, YSize)
	return Config
end

function ImGui:GetAnimation(Animation)
	return Animation and self.Animation or TweenInfo.new(0)
end

function ImGui:Tween(Instance, Props, tweenInfo, NoAnimation)
	local tweenInfo = tweenInfo or ImGui:GetAnimation(not NoAnimation)
	local Tween = TweenService:Create(Instance, tweenInfo, Props)
	Tween:Play()
	return Tween
end

function ImGui:ApplyAnimations(Instance, Class, Target)
	local Animatons = ImGui.Animations
	local ColorProps = Animatons[Class]
	if not ColorProps then return warn("No colors for", Class) end

	local Connections = {}
	for Connection, Props in next, ColorProps do
		if typeof(Props) ~= "table" then continue end
		local T = Target or Instance
		local Callback = function() ImGui:Tween(T, Props) end
		Connections[Connection] = Callback
		Instance[Connection]:Connect(Callback)
	end
	if Connections["MouseLeave"] then Connections["MouseLeave"]() end
	return Connections
end

function ImGui:HeaderAnimate(Header, Animation, Open, TitleBar, Toggle)
	local ToggleButtion = Toggle or TitleBar.Toggle.ToggleButton
	ImGui:Tween(ToggleButtion, { Rotation = Open and 90 or 0 }):Play()

	local Container: Frame = Header:FindFirstChild("ChildContainer")
	if not Container then return end

	local UIListLayout: UIListLayout = Container.UIListLayout
	local UIPadding: UIPadding = Container:FindFirstChildOfClass("UIPadding")
	local ContentSize = UIListLayout.AbsoluteContentSize
	if UIPadding then
		ContentSize = Vector2.new(ContentSize.X, ContentSize.Y + UIPadding.PaddingTop.Offset + UIPadding.PaddingBottom.Offset)
	end

	Container.AutomaticSize = Enum.AutomaticSize.None
	if not Open then
		Container.Size = UDim2.new(1, -10, 0, ContentSize.Y)
	end

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

--// === FIX: один InputChanged для драга ===
local _dragHandlers = {}
UserInputService.InputChanged:Connect(function(Input)
	for i = #_dragHandlers, 1, -1 do
		local h = _dragHandlers[i]
		if h(Input) then table.remove(_dragHandlers, i) end
	end
end)
UserInputService.InputEnded:Connect(function(Input)
	for i = #_dragHandlers, 1, -1 do
		local h = _dragHandlers[i]
		if h(Input, true) then table.remove(_dragHandlers, i) end
	end
end)

function ImGui:ApplyDraggable(Frame: Frame, Header: Frame)
	local Header = Header or Frame
	local Dragging = false
	local KeyBeganPos = nil
	local BeganPos = Frame.Position

	local UserInputTypes = { Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch }
	local function Allowed(t) return table.find(UserInputTypes, t) end

	Header.InputBegan:Connect(function(Key)
		if Allowed(Key.UserInputType) then
			Dragging = true
			KeyBeganPos = Key.Position
			BeganPos = Frame.Position
		end
	end)

	--// FIX: без per-window InputEnded/InputChanged
	table.insert(_dragHandlers, function(Input, isEnded)
		if isEnded then
			if Allowed(Input.UserInputType) then Dragging = false end
			return false
		end
		if not Dragging then return false end
		if Input.UserInputType ~= Enum.UserInputType.MouseMovement and Input.UserInputType ~= Enum.UserInputType.Touch then return false end
		local Delta = Input.Position - KeyBeganPos
		ImGui:Tween(Frame, {
			Position = UDim2.new(BeganPos.X.Scale, BeganPos.X.Offset + Delta.X, BeganPos.Y.Scale, BeganPos.Y.Offset + Delta.Y)
		}):Play()
		return false
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

	--// FIX: один handler на все окна
	local handler
	handler = function(Input, isEnded)
		if isEnded then
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then DragStart = nil end
			return false
		end
		if not DragStart or Input.UserInputType ~= Enum.UserInputType.MouseMovement then return false end
		local MousePos = Vector2.new(Mouse.X, Mouse.Y)
		local mouseMoved = MousePos - DragStart
		local NewSize = OrignialSize + mouseMoved
		NewSize = UDim2.fromOffset(math.max(MinSize.X, NewSize.X), math.max(MinSize.Y, NewSize.Y))
		Frame.Size = NewSize
		if Config then Config.Size = NewSize end
		return false
	end
	table.insert(_dragHandlers, handler)
end

function ImGui:ConnectHover(Config)
	local Parent = Config.Parent
	local Connections = {}
	Config.Hovering = false
	table.insert(Connections, Parent.MouseEnter:Connect(function() Config.Hovering = true end))
	table.insert(Connections, Parent.MouseLeave:Connect(function() Config.Hovering = false end))
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
	local UIStroke = GetStroke(Window)
	local Colors = {
		Selected = { BackgroundColor3 = TitleBar.BackgroundColor3 },
		Deselected = { BackgroundColor3 = Color3.fromRGB(0, 0, 0) }
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
	local Module = { OldProperties = {} }
	for Window in next, ImGui.Windows do
		if table.find(IgnoreWindows, Window) then continue end
		local OldValues = {}
		Module.OldProperties[Window] = OldValues
		for Key, Value in next, Properties do
			OldValues[Key] = Window[Key]
			Window[Key] = Value
		end
	end
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
	local Window: Frame = Prefabs.Window:Clone()
	Window.Parent = ImGui.ScreenGui
	Window.Visible = true
	WindowConfig.Window = Window

	local Content = Window.Content
	local Body = Content.Body
	local Resize = Window.ResizeGrab
	Resize.Visible = WindowConfig.NoResize ~= true

	local MinSize = WindowConfig.MinSize or Vector2.new(160, 90)
	ImGui:ApplyResizable(MinSize, Window, Resize, WindowConfig)

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

	local CloseButton: TextButton = TitleBar.Close
	CloseButton.Visible = WindowConfig.NoClose ~= true

	function WindowConfig:Close()
		local Callback = WindowConfig.CloseCallback
		WindowConfig:SetVisible(false)
		if Callback then Callback(WindowConfig) end
		return WindowConfig
	end
	CloseButton.Activated:Connect(WindowConfig.Close)

	function WindowConfig:GetHeaderSizeY(): number
		local ToolbarY = ToolBar.Visible and ToolBar.AbsoluteSize.Y or 0
		local TitlebarY = TitleBar.Visible and TitleBar.AbsoluteSize.Y or 0
		return ToolbarY + TitlebarY
	end

	function WindowConfig:UpdateBody()
		Body.Size = UDim2.new(1, 0, 1, -self:GetHeaderSizeY())
	end
	WindowConfig:UpdateBody()

	WindowConfig.Open = true
	function WindowConfig:SetOpen(Open, NoAnimation)
		local WindowAbSize = Window.AbsoluteSize
		local TitleBarSize = TitleBar.AbsoluteSize
		self.Open = Open
		ImGui:HeaderAnimate(TitleBar, true, Open, TitleBar, Toggle.ToggleButton)
		ImGui:Tween(Resize, { TextTransparency = Open and 0.6 or 1, Interactable = Open }, nil, NoAnimation)
		ImGui:Tween(Window, { Size = Open and self.Size or UDim2.fromOffset(WindowAbSize.X, TitleBarSize.Y) }, nil, NoAnimation)
		ImGui:Tween(Body, { Visible = Open }, nil, NoAnimation)
		return self
	end

	function WindowConfig:SetVisible(Visible)
		Window.Visible = Visible
		return self
	end
	function WindowConfig:SetTitle(Text)
		TitleBar.Left.Title.Text = tostring(Text)
		return self
	end
	function WindowConfig:Remove()
		Window:Remove()
		return self
	end

	Toggle.ToggleButton.Activated:Connect(function()
		local Open = not WindowConfig.Open
		WindowConfig.Open = Open
		return WindowConfig:SetOpen(Open)
	end)

	--// === NEW: minimized (collapses to titlebar) ===
	function WindowConfig:SetMinimized(state)
		return WindowConfig:SetOpen(not state)
	end

	--// === NEW: opacity ===
	function WindowConfig:SetOpacity(alpha)
		for _, d in Window:GetDescendants() do
			if d:IsA("GuiObject") then
				d.BackgroundTransparency = math.clamp(1 - alpha, 0, 1)
			end
		end
		return WindowConfig
	end

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

		function Config:GetContentSize() return Content.AbsoluteSize end

		Config = ImGui:ContainerClass(Content, Config, Window)
		ImGui:ApplyAnimations(TabButton, "Tabs")
		ImGui:ApplyAccentTo(TabButton)

		self:UpdateBody()
		if WindowConfig.AutoSize then
			local pending = false
			Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				if pending then return end
				pending = true
				task.defer(function()
					pending = false
					self:SetSize(Config:GetContentSize())
				end)
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
		local NewSize = UDim2.new(Size.X.Scale, Size.X.Offset, Size.Y.Scale, Size.Y.Offset + HeaderSizeY)
		self.Size = NewSize
		Window.Size = NewSize
		return self
	end

	function WindowConfig:ShowTab(TabClass)
		local TargetPage: Frame = TabClass.Content
		if not TargetPage.Visible and not TabClass.NoAnimation then
			TargetPage.Position = UDim2.fromOffset(0, 5)
		end
		for _, Page in next, Body:GetChildren() do
			Page.Visible = Page == TargetPage
		end
		ImGui:Tween(TargetPage, { Position = UDim2.fromOffset(0, 0) })
		return self
	end

	function WindowConfig:Center()
		local Size = Window.AbsoluteSize
		self:SetPosition(UDim2.new(0.5, -Size.X / 2, 0.5, -Size.Y / 2))
		return self
	end

	WindowConfig:SetTitle(WindowConfig.Title or "Depso UI")
	if not WindowConfig.Open then
		WindowConfig:SetOpen(WindowConfig.Open or true, true)
	end

	ImGui.Windows[Window] = WindowConfig
	ImGui:CheckStyles(Window, WindowConfig, WindowConfig.Colors)
	ImGui:ApplyAccentTo(Window)

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
	ImGui:Tween(ModalEffect, { BackgroundTransparency = 0.6 })

	Config = Config or {}
	Config.TabsBar = Config.TabsBar ~= nil and Config.TabsBar or false
	Config.NoCollapse = true
	Config.NoResize = true
	Config.NoClose = true
	Config.NoSelectEffect = true
	Config.Parent = ModalEffect
	Config.AnchorPoint = Vector2.new(0.5, 0.5)
	Config.Position = UDim2.fromScale(0.5, 0.5)

	local Window = self:CreateWindow(Config)
	Config = Window:CreateTab({ Visible = true })

	local WindowManger = ImGui:SetWindowProps({ Interactable = false }, { Window.Window })

	local WindowClose = Window.Close
	function Config:Close()
		local Tween = ImGui:Tween(ModalEffect, { BackgroundTransparency = 1 })
		Tween.Completed:Connect(function() ModalEffect:Remove() end)
		WindowManger:Revert()
		WindowClose()
	end
	return Config
end

--// === NEW: показать/скрыть все окна ===
function ImGui:ToggleAllWindows(state)
	for Window, Config in next, ImGui.Windows do
		Config:SetVisible(state)
	end
	return self
end

--// GuiParent + отключённые ненужные фичи для FPS
local GuiParent = IsStudio and PlayerGui or CoreGui
ImGui.ScreenGui = ImGui:CreateInstance("ScreenGui", GuiParent, {
	DisplayOrder = 9999,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
ImGui.FullScreenGui = ImGui:CreateInstance("ScreenGui", GuiParent, {
	DisplayOrder = 99999,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

return ImGui
