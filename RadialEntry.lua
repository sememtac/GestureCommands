-- Gesture Commands: an entry on the game's gamepad main menu, the radial "dial" opened with the menu button.
--
-- Blizzard's dial has no way for addons to add entries, and writing into its tables would taint it: its
-- show / hide switches the gamepad bindings and UI focus, which is how the blocked-action dialogs started.
-- So this only draws and watches. Our icon and label sit over a free slot on the dial's last page (in frames
-- of our own), and hooksecurefunc post-hooks on its selection methods notice when that slot is chosen. Only
-- Blizzard's code may close the dial, so the setup window opens as soon as the dial closes (B).

local _, ns = ...;

local RADIAL_PAGE = 3; -- the last main menu page, which has free slots
local PREFERRED_SLOTS = { 3, 4, 8, 7, 6 }; -- slots go counter-clockwise from east; north first
local SLOT_DEGREES = 45;
local ICON_RADIUS = 100; -- where Blizzard puts its atlas icons (segment at 150, pulled 50 towards the centre)
local ICON_SIZE = 50;
local LABEL_OFFSETS = { -- from the icon, as Blizzard places its labels
	[3] = { 0, 60 },
	[4] = { -30, 45 },
	[6] = { -30, -45 },
	[7] = { 0, -60 },
	[8] = { 30, -45 },
};

local entry; -- our icon + label, a child of the dial
local slot = nil; -- the dial slot we're drawn in on the current page, or nil
local hoveredSlot = nil; -- the slot the stick last highlighted
local openWhenClosed = false;

local function GetFreeSlot(radial)
	if radial.currentMainMenuPageIndex ~= RADIAL_PAGE or not radial.SegmentList then
		return nil;
	end
	for _, index in ipairs(PREFERRED_SLOTS) do
		local segment = radial.SegmentList[index];
		if segment and segment:IsEmpty() then
			return index;
		end
	end
	return nil;
end

local function UpdateLabel()
	entry.Label:SetText(openWhenClosed and "Gesture Commands\n|cffffffff(B to open)|r" or "Gesture Commands");
end

-- After Blizzard fills the dial for a page.
local function OnActivateRadial(radial)
	slot = GetFreeSlot(radial);
	if not slot then
		entry:Hide();
		return;
	end
	local angle = math.rad((slot - 1) * SLOT_DEGREES);
	entry.Icon:ClearAllPoints();
	entry.Icon:SetPoint("CENTER", radial.Background, "CENTER", ICON_RADIUS * math.cos(angle), ICON_RADIUS * math.sin(angle));
	local offset = LABEL_OFFSETS[slot] or { 0, -45 };
	entry.Label:ClearAllPoints();
	entry.Label:SetPoint("CENTER", entry.Icon, "CENTER", offset[1], offset[2]);
	UpdateLabel();
	entry:Show();
end

-- After Blizzard highlights a slot: for ours, show the highlight in full colour (Blizzard greys it out
-- for an empty slot).
local function OnBeginSelection(radial, segmentIndex)
	hoveredSlot = segmentIndex;
	if slot and segmentIndex == slot and radial.SegmentHighlight then
		radial.SegmentHighlight:SetDesaturated(false);
	end
end

-- After the stick is released (or the selection cancelled).
local function OnEndSelection(radial)
	if radial.isCancelled then
		return;
	end
	openWhenClosed = slot ~= nil and hoveredSlot == slot;
	if openWhenClosed then
		UIErrorsFrame:AddMessage("Gesture Commands opens when you close the menu (B).", 1, 0.82, 0);
	end
	UpdateLabel();
end

local function OnRadialHidden()
	if openWhenClosed then
		openWhenClosed = false;
		-- After Blizzard has finished closing the dial and handing focus back.
		C_Timer.After(0, function()
			if not (GestureCommandsFrame and GestureCommandsFrame:IsShown()) then
				ns.ToggleConfig();
			end
		end);
	end
	hoveredSlot = nil;
end

local function SetUp()
	local radial = GamepadRadial;
	if entry or not (radial and radial.ActivateRadial and radial.Background) then
		return;
	end
	entry = CreateFrame("Frame", nil, radial);
	entry:SetAllPoints(radial.Background);
	entry:SetFrameLevel(radial:GetFrameLevel() + 20);
	entry:Hide();
	entry.Icon = entry:CreateTexture(nil, "ARTWORK");
	entry.Icon:SetSize(ICON_SIZE, ICON_SIZE);
	entry.Icon:SetTexture("Interface\\AddOns\\GestureCommands\\Icon");
	local mask = entry:CreateMaskTexture();
	mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE");
	mask:SetAllPoints(entry.Icon);
	entry.Icon:AddMaskTexture(mask);
	entry.Label = entry:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	entry.Label:SetSize(90, 40);
	entry.Label:SetJustifyH("CENTER");
	entry.Label:SetJustifyV("MIDDLE");

	hooksecurefunc(radial, "ActivateRadial", OnActivateRadial);
	hooksecurefunc(radial, "BeginSelection", OnBeginSelection);
	hooksecurefunc(radial, "EndSelection", OnEndSelection);
	radial:HookScript("OnHide", OnRadialHidden);
end

local events = CreateFrame("Frame");
events:RegisterEvent("PLAYER_LOGIN");
events:SetScript("OnEvent", SetUp);
