-- Gesture Commands: an entry on the game's gamepad main menu, the radial "dial" opened with the menu button.
--
-- Blizzard's dial has no way for addons to add entries, and writing into its tables, or closing it from
-- addon code, would taint it: its show / hide switches the gamepad bindings and UI focus, which is how the
-- blocked-action dialogs started. So this only draws and watches. Our icon and label sit over a free slot
-- on the dial's last page (in frames of our own), and hooksecurefunc post-hooks on its selection methods
-- see when the stick points at that slot. While it does (out of combat), A is bound to Blizzard's own
-- "main menu" binding, so pressing A closes the dial through Blizzard's code; seeing A down as the dial
-- closes, we open or close the setup window, like the Bags entry.

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
local TOGGLE_BINDING = "OPENRADIAL"; -- Blizzard's binding for the menu button: shows / hides the dial
local CHOOSE_KEY = GAMEPAD_FACE_BOTTOM or "PAD1"; -- A

local entry; -- our icon, label and prompt, a child of the dial
local slot = nil; -- the dial slot we're drawn in on the current page, or nil
local hoveredSlot = nil; -- the slot the stick points at
local chooseBound = false;

-- Owns the A binding. Secure, so it can drop it when combat starts (addon code can't then).
local owner = CreateFrame("Frame", "GestureCommandsDialOwner", UIParent, "SecureHandlerStateTemplate");
owner:SetAttribute("_onstate-combat", [[
	if newstate == "1" then
		self:ClearBindings();
	end
]]);

local function BindChoose()
	if not chooseBound and not InCombatLockdown() then
		SetOverrideBinding(owner, true, CHOOSE_KEY, TOGGLE_BINDING);
		chooseBound = true;
	end
end

local function UnbindChoose()
	if chooseBound and not InCombatLockdown() then
		ClearOverrideBindings(owner);
	end
	chooseBound = false;
end

local function IsWindowShown()
	return GestureCommandsFrame ~= nil and GestureCommandsFrame:IsShown();
end

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

local function ShowPrompt(shown)
	entry.Prompt:SetShown(shown);
	entry.PromptText:SetShown(shown);
	if shown then
		entry.PromptText:SetText(IsWindowShown() and "Close" or "Open");
	end
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
	-- In combat A can't be bound, so the entry shows as unavailable, like Blizzard's disabled ones.
	local inCombat = InCombatLockdown();
	entry.Icon:SetDesaturated(inCombat);
	entry.Label:SetTextColor((inCombat and DISABLED_FONT_COLOR or NORMAL_FONT_COLOR):GetRGB());
	ShowPrompt(hoveredSlot == slot and not inCombat);
	entry:Show();
end

-- After Blizzard highlights a slot.
local function OnBeginSelection(radial, segmentIndex)
	hoveredSlot = segmentIndex;
	if slot and segmentIndex == slot and not InCombatLockdown() then
		-- Full-colour highlight (Blizzard greys it for an empty slot), and A chooses.
		if radial.SegmentHighlight then
			radial.SegmentHighlight:SetDesaturated(false);
		end
		BindChoose();
		ShowPrompt(true);
	else
		UnbindChoose();
		ShowPrompt(false);
	end
end

-- After the stick is released (or the selection cancelled): releasing on our slot can't close the dial.
local function OnEndSelection(radial)
	if not radial.isCancelled and slot and hoveredSlot == slot then
		UIErrorsFrame:AddMessage(InCombatLockdown() and "Gesture Commands: open it after combat (or type /gestures)."
			or "Gesture Commands: point at it and press A.", 1, 0.82, 0);
	end
	hoveredSlot = nil;
	UnbindChoose();
	ShowPrompt(false);
end

local function OnRadialHidden()
	local chosen = slot ~= nil and hoveredSlot == slot and chooseBound and IsKeyDown(CHOOSE_KEY);
	hoveredSlot = nil;
	UnbindChoose();
	if chosen then
		-- After Blizzard has finished closing the dial and handing focus back.
		C_Timer.After(0, ns.ToggleConfig);
	end
end

local function SetUp()
	local radial = GamepadRadial;
	if entry or not (radial and radial.ActivateRadial and radial.Background) or InCombatLockdown() then
		return;
	end
	RegisterStateDriver(owner, "combat", "[combat] 1; 0");

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
	entry.Prompt = CreateFrame("Frame", nil, entry, "InputIconTextureFrameTemplate");
	entry.Prompt:SetSize(26, 26);
	entry.Prompt:SetInputKey(CHOOSE_KEY);
	entry.Prompt:SetPoint("CENTER", entry.Icon, "CENTER", -14, -40);
	entry.PromptText = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	entry.PromptText:SetPoint("LEFT", entry.Prompt, "RIGHT", 2, 0);
	ShowPrompt(false);

	hooksecurefunc(radial, "ActivateRadial", OnActivateRadial);
	hooksecurefunc(radial, "BeginSelection", OnBeginSelection);
	hooksecurefunc(radial, "EndSelection", OnEndSelection);
	radial:HookScript("OnHide", OnRadialHidden);
end

local events = CreateFrame("Frame");
events:RegisterEvent("PLAYER_LOGIN");
events:RegisterEvent("PLAYER_REGEN_ENABLED");
events:RegisterEvent("PLAYER_REGEN_DISABLED");
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		-- The secure driver has dropped the A binding.
		chooseBound = false;
	else
		SetUp();
	end
end);
