-- \\ @ Zedronius

local require = require(script.Parent.Parent.loader).load(script)

local runService = game:GetService("RunService")

local fusion = require("Fusion")
local innerScope = fusion.innerScope
local Children = fusion.Children

local util = require("UIUtils")
local timeLib = require("TimeLib")

local components = util.components{}

type UsedAs<T> = fusion.UsedAs<T>
type Scope = fusion.Scope
type Child = fusion.Child

local FONT = Font.new(
	"rbxasset://fonts/families/FredokaOne.json",
	Enum.FontWeight.Medium,
	Enum.FontStyle.Normal
)

return function(scope: Scope, uiService: {})
	local scope = innerScope(scope, fusion, util, components)

	local phase = scope:Value("Next")
	local phaseEndTime = scope:Value(os.time())
	local now = scope:Value(os.time())

	local accumulator = 0
	scope:Add(runService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator >= 0.25 then
			accumulator = 0
			now:set(os.time())
		end
	end))

	local phaseLabel = scope:Computed(function(use)
		local current = use(phase)
		if current == "Join" then
			return "RACE BEGINS IN:"
		elseif current == "Race" then
			return "RACE ENDS IN:"
		end
		return "NEXT RACE IN:"
	end)

	local timeLeft = scope:Computed(function(use)
		local remaining = math.max(use(phaseEndTime) - use(now), 0)
		return timeLib.hms(remaining)
	end)

	local widget = {}

	widget.Element = scope:New "Frame" {
		Name = "RaceWidget",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.12),
		Size = UDim2.fromScale(0.3, 0.07),

		[Children] = {
			scope:New "Frame" {
				Name = "Bar",
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 0,
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromScale(1, 0.55),

				[Children] = {
					scope:New "UICorner" {
						CornerRadius = UDim.new(0.3, 0),
					},

					scope:New "UIStroke" {
						Color = Color3.fromRGB(36, 34, 60),
						Thickness = 4,
					},

					scope:New "UIGradient" {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(92, 243, 255)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(64, 117, 255)),
						}),
						Rotation = 90,
					},

					scope:New "ImageLabel" {
						Name = "Texture",
						BackgroundTransparency = 1,
						Image = "rbxassetid://15323071887",
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromScale(1, 1),
						ZIndex = 0,
					},

					scope:New "TextLabel" {
						Name = "Label",
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundTransparency = 1,
						FontFace = FONT,
						Position = UDim2.fromScale(0.05, 0.5),
						Size = UDim2.fromScale(0.6, 0.9),
						Text = phaseLabel,
						TextColor3 = Color3.new(1, 1, 1),
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Left,

						[Children] = {
							scope:New "UIStroke" {
								Color = Color3.fromRGB(33, 38, 77),
								Thickness = 4,
							},
						}
					},

					scope:New "TextLabel" {
						Name = "Timer",
						AnchorPoint = Vector2.new(1, 0.5),
						BackgroundTransparency = 1,
						FontFace = FONT,
						Position = UDim2.fromScale(0.95, 0.5),
						Size = UDim2.fromScale(0.35, 0.9),
						Text = timeLeft,
						TextColor3 = Color3.new(1, 1, 1),
						TextScaled = true,
						TextXAlignment = Enum.TextXAlignment.Right,

						[Children] = {
							scope:New "UIStroke" {
								Color = Color3.fromRGB(33, 38, 77),
								Thickness = 4,
							},
						}
					},
				}
			},

		}
	}

	function widget:SetPhase(newPhase: string, endTime: number)
		phase:set(newPhase)
		phaseEndTime:set(endTime)
	end

	function widget:SetJoined(_: boolean)
	end

	return widget
end
