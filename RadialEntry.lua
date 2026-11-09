-- Gesture Commands: an entry on the game's gamepad main menu, the radial "dial" opened with the menu button.
-- Release the stick on it, like any other entry: the dial closes and the setup window opens (or closes, if
-- it was open - like Bags).
--
-- Blizzard's dial has no way for addons to add entries, and writing into its tables or closing it from
-- addon code would taint it: its show / hide switches the gamepad bindings and UI focus, which is how the
-- blocked-action dialogs started. So:
-- - Our icon and label sit over a free slot on the dial's last page, in frames of our own; hooksecurefunc
--   post-hooks on its selection methods see the stick point at and be released on that slot.
-- - The dial is closed by a secure handler's snippet: setting an attribute from addon code runs it as
--   secure code (attribute changes are a taint barrier), so the dial's OnHide runs untainted, just as when
--   one of Blizzard's own entries closes it. Out of combat only (the handler can't be touched in combat).

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

local entry; -- our icon and label, a child of the dial
local slot = nil; -- the dial slot we're drawn in on the current page, or nil
local hoveredSlot = nil; -- the slot the stick points at
local chosen = false; -- released on our slot: toggle the window once the dial has closed
local closeCount = 0;

local closer = CreateFrame("Frame", "GestureCommandsDialCloser", UIParent, "SecureHandlerAttributeTemplate");
closer:SetAttribute("_onattributechanged", [[
	if name == "close-dial" then
		local dial = self:GetFrameRef("dial");
		if dial and dial:IsVisible() then
			dial:Hide(true);
		end
	end
]]);

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
	-- In combat the dial can't be closed for us, so the entry shows as unavailable, like Blizzard's
	-- disabled ones.
	local inCombat = InCombatLockdown();
	entry.Icon:SetDesaturated(inCombat);
	entry.Label:SetTextColor((inCombat and DISABLED_FONT_COLOR or NORMAL_FONT_COLOR):GetRGB());
	entry:Show();
end

-- After Blizzard highlights a slot: ours in full colour (Blizzard greys the highlight of an empty slot).
local function OnBeginSelection(radial, segmentIndex)
	hoveredSlot = segmentIndex;
	if slot and segmentIndex == slot and not InCombatLockdown() and radial.SegmentHighlight then
		radial.SegmentHighlight:SetDesaturated(false);
	end
end

-- After the stick is released (or the selection cancelled).
local function OnEndSelection(radial)
	local released = not radial.isCancelled and slot ~= nil and hoveredSlot == slot;
	hoveredSlot = nil;
	if not released then
		return;
	end
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage("Gesture Commands: open it after combat (or type /gestures).", 1, 0.82, 0);
		return;
	end
	chosen = true;
	closeCount = closeCount + 1;
	closer:SetAttribute("close-dial", closeCount);
end

local function OnRadialHidden()
	hoveredSlot = nil;
	if chosen then
		chosen = false;
		-- After Blizzard has finished closing the dial and handing focus back.
		C_Timer.After(0, ns.ToggleConfig);
	end
end

local function SetUp()
	local radial = GamepadRadial;
	if entry or not (radial and radial.ActivateRadial and radial.Background) or InCombatLockdown() then
		return;
	end
	SecureHandlerSetFrameRef(closer, "dial", radial);

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
	entry.Label:SetText("Gesture Commands");

	hooksecurefunc(radial, "ActivateRadial", OnActivateRadial);
	hooksecurefunc(radial, "BeginSelection", OnBeginSelection);
	hooksecurefunc(radial, "EndSelection", OnEndSelection);
	radial:HookScript("OnHide", OnRadialHidden);
end

local events = CreateFrame("Frame");
events:RegisterEvent("PLAYER_LOGIN");
events:RegisterEvent("PLAYER_REGEN_ENABLED");
events:SetScript("OnEvent", SetUp);
