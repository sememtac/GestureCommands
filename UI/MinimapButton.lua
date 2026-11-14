-- Gesture Commands: the minimap button (click to open the setup window, drag it around the minimap's edge;
-- `/gestures minimap` hides or shows it) and the entry in the minimap's addon compartment menu, which the
-- game builds from the TOC's AddonCompartmentFunc lines.

local _, ns = ...;

local ICON = "Interface\\AddOns\\GestureCommands\\Icon";
local DEFAULT_ANGLE = 200; -- degrees counter-clockwise from the right: the minimap's lower left

local button = CreateFrame("Button", "GestureCommandsMinimapButton", Minimap);
button:SetSize(31, 31);
button:SetFrameStrata("MEDIUM");
button:SetFrameLevel(8);
button:RegisterForClicks("AnyUp");
button:RegisterForDrag("LeftButton");
button:SetHighlightTexture(136477); -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
button:Hide();

local background = button:CreateTexture(nil, "BACKGROUND");
background:SetSize(20, 20);
background:SetTexture(136467); -- Interface\Minimap\UI-Minimap-Background
background:SetPoint("TOPLEFT", 7, -5);
local icon = button:CreateTexture(nil, "ARTWORK");
icon:SetSize(18, 18);
icon:SetTexture(ICON);
icon:SetTexCoord(0.06, 0.94, 0.06, 0.94);
icon:SetPoint("TOPLEFT", 7, -6);
local border = button:CreateTexture(nil, "OVERLAY");
border:SetSize(53, 53);
border:SetTexture(136430); -- Interface\Minimap\MiniMap-TrackingBorder
border:SetPoint("TOPLEFT");

local function UpdatePosition()
	local angle = math.rad(ns.DB().minimapAngle or DEFAULT_ANGLE);
	local radius = Minimap:GetWidth() / 2 + 5;
	button:ClearAllPoints();
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius);
end

local function ShowTooltip(owner, canDrag)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT");
	GameTooltip:SetText("Gesture Commands");
	GameTooltip:AddLine("Click to open the setup window.", 1, 1, 1);
	if canDrag then
		GameTooltip:AddLine("Drag to move this button. /gestures minimap hides it.", 0.6, 0.6, 0.6, true);
	end
	GameTooltip:Show();
end

button:SetScript("OnClick", function()
	ns.ToggleConfig();
end);
button:SetScript("OnEnter", function(self)
	ShowTooltip(self, true);
end);
button:SetScript("OnLeave", GameTooltip_Hide);
button:SetScript("OnDragStart", function(self)
	GameTooltip_Hide();
	self:LockHighlight();
	self:SetScript("OnUpdate", function()
		local centerX, centerY = Minimap:GetCenter();
		local scale = Minimap:GetEffectiveScale();
		local cursorX, cursorY = GetCursorPosition();
		ns.DB().minimapAngle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX));
		UpdatePosition();
	end);
end);
button:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil);
	self:UnlockHighlight();
end);

local function Refresh()
	UpdatePosition();
	button:SetShown(not ns.DB().minimapHidden);
end

-- `/gestures minimap`.
function ns.ToggleMinimapButton()
	ns.DB().minimapHidden = not ns.DB().minimapHidden or nil;
	Refresh();
	ns.Print(ns.DB().minimapHidden and "minimap button hidden (/gestures minimap shows it again; it's also in the minimap's addons menu)."
		or "minimap button shown.");
end

local events = CreateFrame("Frame");
events:RegisterEvent("PLAYER_LOGIN");
events:SetScript("OnEvent", Refresh);

-- The addon compartment calls these by name (see the TOC).
function GestureCommands_OnAddonCompartmentClick()
	ns.ToggleConfig();
end

function GestureCommands_OnAddonCompartmentEnter(_, menuButton)
	ShowTooltip(menuButton, false);
end

function GestureCommands_OnAddonCompartmentLeave()
	GameTooltip_Hide();
end
