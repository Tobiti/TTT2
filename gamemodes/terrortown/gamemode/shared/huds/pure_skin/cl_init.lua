local surface = surface

-- Fonts
surface.CreateFont("PureSkinMSTACKImageMsg", {font = "Trebuchet24", size = 21, weight = 1000})
surface.CreateFont("PureSkinMSTACKMsg", {font = "Trebuchet18", size = 15, weight = 900})
surface.CreateFont("PureSkinRole", {font = "Trebuchet24", size = 30, weight = 700})
surface.CreateFont("PureSkinBar", {font = "Trebuchet24", size = 21, weight = 1000})
surface.CreateFont("PureSkinWep", {font = "Trebuchet24", size = 21, weight = 1000})
surface.CreateFont("PureSkinWepNum", {font = "Trebuchet24", size = 21, weight = 700})

-- base drawing functions
include("cl_drawing_functions.lua")

local base = "hud_base"

DEFINE_BASECLASS(base)

HUD.Base = base

local defaultColor = Color(49, 71, 94)

HUD.previewImage = Material("vgui/ttt/huds/pure_skin/preview.png")

local savingKeys

function HUD:GetSavingKeys()
	if not savingKeys then
		savingKeys = BaseClass.GetSavingKeys(self)
		savingKeys.basecolor = {
			typ = "color",
			desc = "BaseColor",
			OnChange = function(slf, col)
				for _, elem in ipairs(slf:GetElements()) do
					local el = hudelements.GetStored(elem)
					if el then
						el.basecolor = col
					end
				end
			end
		}
	end

	return table.Copy(savingKeys)
end

HUD.basecolor = defaultColor

function HUD:Initialize()
	self:ForceElement("pure_skin_playerinfo")
	self:ForceElement("pure_skin_roundinfo")
	self:ForceElement("pure_skin_wswitch")
	self:ForceElement("pure_skin_drowning")
	self:ForceElement("pure_skin_mstack")
	self:ForceElement("pure_skin_items")
	self:ForceElement("pure_skin_miniscoreboard")
	self:ForceElement("pure_skin_punchometer")
	self:ForceElement("pure_skin_target")

	BaseClass.Initialize(self)
end

function HUD:Loaded()
	for _, elem in ipairs(self:GetElements()) do
		local el = hudelements.GetStored(elem)
		if el then
			el.basecolor = self.basecolor
		end
	end
end

function HUD:Reset()
	self.basecolor = defaultColor
end

-- Voice overriding
include("cl_voice.lua")

-- Popup overriding
include("cl_popup.lua")
