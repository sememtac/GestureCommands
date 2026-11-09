-- Gesture Commands: setup window. A list of gestures on the left; on the right, the selected gesture's name
-- and icon (also shown on the crossbar) and three slots: Tap, Hold, Long hold. Click a slot to choose a spell,
-- item, mount or macro for it, or drag one onto it; right-click clears it. On the crossbar a gesture is its
-- Tap action: Bind (controller) puts that on the button pressed next; with a mouse, drag it to a slot.
-- Editing is locked in combat because the secure configuration can only change out of combat.
--
-- Controller: the window joins Blizzard's gamepad UI like its own panels (LT / RT, View, A, B), or uses
-- our own D-pad navigation with `/gestures padnav own`; see Navigation.lua.

local _, ns = ...;

local MAX_ROWS = 10;
local SLOT_SIZE = 40;
local SLOT_HINTS = {
	trigger = "What a tap does, and what you put on the crossbar: a spell, an item, or one of your macros that shows a spell or item (#showtooltip).",
	hold = "Cast when you hold the button (about 0.5 s): a spell, item, toy, mount or macro.",
	long = "Cast when you keep holding the button (about 1.4 s): a spell, item, toy, mount or macro.",
};

local selected = nil;
local frame, rows, slots, statusText, enableCheck, holdText, hold2Text;
local navControls = {};

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------

local function Refresh()
	if not (frame and frame:IsShown()) then
		return;
	end
	local db = ns.DB();
	local gestures = db.gestures;
	if selected and not gestures[selected] then
		selected = #gestures > 0 and #gestures or nil;
	end

	for index, row in ipairs(rows) do
		local gesture = gestures[index];
		if gesture then
			local holdName = ns.GetActionDisplay(gesture.hold);
			local longName = ns.GetActionDisplay(gesture.long);
			row.Icon:SetTexture(ns.GetGestureIcon(gesture));
			row.Text:SetText(("%s\n|cff999999%s / %s|r"):format(gesture.trigger and ns.GetGestureName(gesture) or "(new gesture)",
				holdName or "-", longName or "-"));
			row.Selected:SetShown(index == selected);
			row.Conflict:SetShown(ns.conflicts and ns.conflicts[index] ~= nil);
			row:Show();
		else
			row:Hide();
		end
	end
	frame.TooMany:SetShown(#gestures > MAX_ROWS);

	local gesture = selected and gestures[selected];
	local editor = frame.Editor;
	editor.Header:SetShown(gesture ~= nil);
	if gesture then
		editor.Header.Icon:SetTexture(ns.GetGestureIcon(gesture));
		editor.Header.Name:SetText(gesture.trigger and ns.GetGestureName(gesture) or "|cff999999Choose its Tap first|r");
		editor.Header.Edit:SetEnabled(gesture.trigger ~= nil);
		editor.Header.Bind:SetEnabled(gesture.trigger ~= nil);
	end
	for mode, slot in pairs(slots) do
		local name, icon = ns.GetActionDisplay(gesture and gesture[mode]);
		slot.Icon:SetTexture(icon);
		slot.Icon:SetShown(icon ~= nil);
		slot.Name:SetText(name or (gesture and "|cff999999empty - click to choose|r" or ""));
		slot:SetEnabled(gesture ~= nil);
		slot.Label:SetShown(gesture ~= nil);
		slot:SetShown(gesture ~= nil);
	end
	editor.Empty:SetShown(gesture == nil);
	editor.Delete:SetEnabled(gesture ~= nil);

	enableCheck:SetChecked(db.enabled ~= false);
	holdText:SetText(("Hold: %d ticks (~%.1f s)"):format(ns.GetHoldTicks(), ns.GetHoldTicks() * 0.2));
	hold2Text:SetText(("Long hold: %d ticks (~%.1f s)"):format(ns.GetHold2Ticks(), ns.GetHold2Ticks() * 0.2));

	local status;
	if InCombatLockdown() then
		status = "|cffff6060Editing is locked in combat.|r";
	elseif ns.IsTotemCommandsActive() then
		status = "|cffff6060Totem Commands is on and uses the same buttons: type /totemcommands off.|r";
	elseif ns.conflicts and next(ns.conflicts) then
		status = "|cffffd100Two gestures have the same Tap; only the later one is used.|r";
	elseif db.enabled == false then
		status = "Off - tick Enabled to use your gestures.";
	else
		status = "|cff33ff99On.|r Press Test to check your setup.";
	end
	statusText:SetText(status);
	local ownNavigation = ns.Nav.UsesOwnNavigation();
	frame.Footer:SetShown(ownNavigation or ns.Nav.UsesGamepadUI());
	if ownNavigation then
		frame.Footer:SetPrompts({ { GAMEPAD_FACE_BOTTOM, "Select" }, { GAMEPAD_FACE_LEFT, "Clear" }, { GAMEPAD_FACE_RIGHT, "Close" } });
	else
		frame.Footer:SetPrompts({ { GAMEPAD_FACE_BOTTOM, "Select" }, { GAMEPAD_FACE_RIGHT, "Close" } });
	end
	ns.Nav.Refresh(frame);
end
ns.OnPublished = Refresh;

local function CanEdit()
	if InCombatLockdown() then
		ns.Print("can't change gestures in combat.");
		return false;
	end
	return true;
end
ns.CanEdit = CanEdit;

local function OpenNameIconPicker()
	if CanEdit() and selected then
		ns.OpenIconPicker(frame, selected);
	end
end

-------------------------------------------------------------------------------
-- Slots
-------------------------------------------------------------------------------

-- Sets a slot's action; a trigger must be something a crossbar slot shows. Returns true if it was taken.
local function AssignAction(mode, action)
	if not (CanEdit() and selected) then
		return false;
	end
	if action and mode == "trigger" then
		local trigger = ns.MakeTrigger(action);
		if not trigger then
			ns.Print("Tap must be a spell, an item, or a macro that shows one (#showtooltip).");
			return false;
		end
		action = trigger;
	end
	ns.SetGestureAction(selected, mode, action);
	return true;
end

local function OnSlotReceive(slot)
	if not (CanEdit() and selected) then
		return;
	end
	local action, cursorType = ns.ReadCursor();
	if not action then
		if cursorType then
			ns.Print(("%s can't be used in a gesture."):format(cursorType));
		end
		return;
	end
	ClearCursor();
	AssignAction(slot.mode, action);
end

local function ClearSlot(slot)
	if CanEdit() and selected then
		ns.SetGestureAction(selected, slot.mode, nil);
	end
end

local function ChooseForSlot(slot)
	if not (CanEdit() and selected) then
		return;
	end
	ns.OpenActionPicker(frame, selected, slot.mode, function(action)
		return AssignAction(slot.mode, action);
	end);
end

-- With the mouse: put the gesture's macro on the cursor to drop on a crossbar slot.
local function PickupSelected()
	if selected then
		ns.PickupGesture(selected);
	end
end

-- With the controller (A): close the window and let the next crossbar press choose the slot, because a
-- controller can't drop a cursor action on the crossbar. (The game's own bind screen can only be opened by
-- its spellbook, bags and Macros windows; from addon code it would taint the gamepad UI.)
local function BindWithController()
	if selected then
		local index = selected;
		frame:Hide();
		ns.StartPlacing(index);
	end
end

local function CreateSlot(parent, mode, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	label:SetPoint("TOPLEFT", 16, y);
	label:SetText(ns.MODE_LABELS[mode]);

	local slot = CreateFrame("Button", nil, parent);
	slot.mode = mode;
	slot.Label = label;
	slot:SetSize(SLOT_SIZE, SLOT_SIZE);
	slot:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6);
	slot:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	slot:RegisterForDrag("LeftButton");

	local background = slot:CreateTexture(nil, "BACKGROUND");
	background:SetAllPoints();
	background:SetAtlas("UI-HUD-ActionBar-IconFrame-Background");
	slot.Icon = slot:CreateTexture(nil, "ARTWORK");
	slot.Icon:SetPoint("TOPLEFT", 2, -2);
	slot.Icon:SetPoint("BOTTOMRIGHT", -2, 2);
	slot:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");

	slot.Name = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	slot.Name:SetPoint("LEFT", slot, "RIGHT", 10, 0);
	slot.Name:SetPoint("RIGHT", parent, "RIGHT", -12, 0);
	slot.Name:SetJustifyH("LEFT");

	slot.OnNavSecondary = ClearSlot;
	slot:SetScript("OnReceiveDrag", OnSlotReceive);
	slot:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			ClearSlot(self);
		elseif GetCursorInfo() then
			OnSlotReceive(self);
		else
			ChooseForSlot(self);
		end
	end);
	slot:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(label:GetText());
		GameTooltip:AddLine(SLOT_HINTS[mode], 1, 1, 1, true);
		GameTooltip:AddLine("Click (A) to choose, or drag one here. Right-click to clear (or Clear in the list).", 0.6, 0.6, 0.6, true);
		GameTooltip:Show();
	end);
	slot:SetScript("OnLeave", GameTooltip_Hide);
	return slot;
end

-- "Hold: n ticks" text with -/+ buttons, at a fixed height above the frame's bottom edge.
local function CreateTicksControl(parent, bottom, apply)
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	text:SetPoint("BOTTOMLEFT", 262, bottom + 4);
	local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate");
	minus:SetSize(24, 20);
	minus:SetText("-");
	minus:SetPoint("BOTTOMLEFT", 460, bottom);
	local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate");
	plus:SetSize(24, 20);
	plus:SetText("+");
	plus:SetPoint("LEFT", minus, "RIGHT", 4, 0);
	minus:SetScript("OnClick", function() apply(-1); end);
	plus:SetScript("OnClick", function() apply(1); end);
	table.insert(navControls, minus);
	table.insert(navControls, plus);
	return text;
end

local function AdjustTicks(key, delta)
	if not CanEdit() then
		return;
	end
	local db = ns.DB();
	if key == "holdTicks" then
		db.holdTicks = math.min(6, math.max(2, ns.GetHoldTicks() + delta));
	else
		db.hold2Ticks = math.min(12, math.max(ns.GetHoldTicks() + 2, ns.GetHold2Ticks() + delta));
	end
	ns.Publish();
end

-------------------------------------------------------------------------------
-- Bind banner: shown while Bind waits for a crossbar press
-------------------------------------------------------------------------------

local banner;

local function ShowBindBanner(gesture, endsAt)
	if not gesture then
		if banner then
			banner:Hide();
		end
		return;
	end
	if not banner then
		banner = CreateFrame("Frame", nil, UIParent);
		banner:SetSize(470, 74);
		banner:SetPoint("TOP", 0, -140);
		banner:SetFrameStrata("DIALOG");
		local background = banner:CreateTexture(nil, "BACKGROUND");
		background:SetAllPoints();
		background:SetColorTexture(0, 0, 0, 0.65);
		banner.Icon = banner:CreateTexture(nil, "ARTWORK");
		banner.Icon:SetSize(44, 44);
		banner.Icon:SetPoint("LEFT", 12, 0);
		banner.Title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
		banner.Title:SetPoint("TOPLEFT", banner.Icon, "TOPRIGHT", 12, 2);
		banner.Footer = ns.Nav.CreatePromptFooter(banner);
		banner.Footer:SetPoint("LEFT", banner.Icon, "RIGHT", 12, -2);
		banner.Footer:SetPrompts({ { GAMEPAD_SHOULDER_LEFT, "+" }, { GAMEPAD_SHOULDER_RIGHT, "+" },
			{ GAMEPAD_DPAD_LEFT, "/" }, { GAMEPAD_DPAD_RIGHT, "Change page" } });
		banner.Hint = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
		banner.Hint:SetPoint("BOTTOMLEFT", banner.Icon, "BOTTOMRIGHT", 12, -4);
		banner:SetScript("OnUpdate", function(self)
			local secondsLeft = math.max(0, math.ceil(self.endsAt - GetTime()));
			if secondsLeft ~= self.secondsLeft then
				self.secondsLeft = secondsLeft;
				self.Hint:SetText(("Open /gestures to cancel.  %d s"):format(secondsLeft));
			end
		end);
	end
	banner.Icon:SetTexture(ns.GetGestureIcon(gesture));
	banner.Title:SetText(("Bind %s: press its crossbar button"):format(ns.GetGestureName(gesture)));
	banner.endsAt = endsAt;
	banner.secondsLeft = nil;
	banner:Show();
end
ns.OnPlacingChanged = ShowBindBanner;

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------

local function CreateEditorHeader(editor)
	local header = CreateFrame("Frame", nil, editor);
	header:SetPoint("TOPLEFT", 0, 0);
	header:SetPoint("TOPRIGHT", 0, 0);
	header:SetHeight(60);
	editor.Header = header;

	local iconButton = CreateFrame("Button", nil, header);
	iconButton:SetSize(40, 40);
	iconButton:SetPoint("TOPLEFT", 12, -12);
	iconButton:RegisterForDrag("LeftButton");
	header.Icon = iconButton:CreateTexture(nil, "ARTWORK");
	header.Icon:SetAllPoints();
	iconButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	iconButton:SetScript("OnClick", OpenNameIconPicker);
	iconButton:SetScript("OnDragStart", PickupSelected);
	iconButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText("Gesture");
		GameTooltip:AddLine("Click to change the name and icon. Drag onto your crossbar to place it.", 1, 1, 1, true);
		GameTooltip:Show();
	end);
	iconButton:SetScript("OnLeave", GameTooltip_Hide);
	header.IconButton = iconButton;

	header.Name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	header.Name:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 8, -1);
	header.Name:SetPoint("RIGHT", -10, 0);
	header.Name:SetJustifyH("LEFT");

	header.Edit = CreateFrame("Button", nil, header, "UIPanelButtonTemplate");
	header.Edit:SetSize(110, 20);
	header.Edit:SetPoint("BOTTOMLEFT", iconButton, "BOTTOMRIGHT", 8, 0);
	header.Edit:SetText("Name & icon");
	header.Edit:SetScript("OnClick", OpenNameIconPicker);

	header.Bind = CreateFrame("Button", nil, header, "UIPanelButtonTemplate");
	header.Bind:SetSize(110, 20);
	header.Bind:SetPoint("LEFT", header.Edit, "RIGHT", 6, 0);
	header.Bind:SetText("Bind");
	header.Bind:SetScript("OnClick", PickupSelected);
	-- A controller's A press (SmartNavigation, or our own navigation) calls this instead of clicking.
	header.Bind.OnSmartNavClick = BindWithController;
	header.Bind:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText("Bind");
		GameTooltip:AddLine("Controller (A): closes this window - then press the crossbar button you want the gesture on (L1 / R1 for the other bars; both shoulders + D-pad left / right change the page). Nothing is cast by that press. With another window still open, press View first to get back to the game.", 1, 1, 1, true);
		GameTooltip:AddLine("Mouse: puts the gesture on your cursor to drop on a crossbar slot.", 0.6, 0.6, 0.6, true);
		GameTooltip:Show();
	end);
	header.Bind:SetScript("OnLeave", GameTooltip_Hide);
end

local function CreateConfigFrame()
	frame = CreateFrame("Frame", "GestureCommandsFrame", UIParent, "BasicFrameTemplateWithInset, FocusFramesInterfaceTemplate");
	frame:SetSize(560, 500);
	frame:SetPoint("CENTER");
	frame:SetFrameStrata("DIALOG");
	frame:SetMovable(true);
	frame:EnableMouse(true);
	frame:RegisterForDrag("LeftButton");
	frame:SetScript("OnDragStart", frame.StartMoving);
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing);
	frame:SetScript("OnShow", function(self)
		if ns.IsPlacing() then
			ns.CancelPlacing(true);
		end
		Refresh();
		ns.Nav.Open(self);
	end);
	frame:SetScript("OnHide", function(self)
		ns.ClosePicker();
		ns.Nav.Close(self);
	end);
	-- Controller B: close it ourselves. Without this, Blizzard's gamepad UI would press the close button,
	-- running its panel manager from our frame.
	function frame:SmartNavigationCloseHandler()
		self:Hide();
		return true;
	end
	frame:Hide();
	tinsert(UISpecialFrames, "GestureCommandsFrame");

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	title:SetPoint("TOP", 0, -5);
	title:SetText("Gesture Commands");

	local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	intro:SetPoint("TOPLEFT", 14, -30);
	intro:SetPoint("TOPRIGHT", -14, -30);
	intro:SetJustifyH("LEFT");
	intro:SetText("A gesture gives one crossbar button three actions: choose what a Tap, a Hold and a Long hold do - spells, items, mounts or your own macros - then bind it to your crossbar.");

	-- Gesture list
	rows = {};
	for index = 1, MAX_ROWS do
		local row = CreateFrame("Button", nil, frame);
		row:SetSize(230, 28);
		row:SetPoint("TOPLEFT", 14, -62 - (index - 1) * 30);
		row.Icon = row:CreateTexture(nil, "ARTWORK");
		row.Icon:SetSize(24, 24);
		row.Icon:SetPoint("LEFT", 2, 0);
		row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
		row.Text:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0);
		row.Text:SetPoint("RIGHT", -16, 0);
		row.Text:SetJustifyH("LEFT");
		row.Text:SetWordWrap(false);
		row.Selected = row:CreateTexture(nil, "BACKGROUND");
		row.Selected:SetAllPoints();
		row.Selected:SetColorTexture(1, 0.82, 0, 0.18);
		row.Conflict = row:CreateFontString(nil, "OVERLAY", "GameFontRedSmall");
		row.Conflict:SetPoint("RIGHT", -2, 0);
		row.Conflict:SetText("!");
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");
		row:SetScript("OnClick", function()
			selected = index;
			Refresh();
		end);
		row:RegisterForDrag("LeftButton");
		row:SetScript("OnDragStart", function()
			selected = index;
			Refresh();
			ns.PickupGesture(index);
		end);
		row:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetText(self.Text:GetText() or "");
			GameTooltip:AddLine("Click (A) to edit. Drag onto your crossbar to place this gesture.", 1, 1, 1, true);
			GameTooltip:Show();
		end);
		row:SetScript("OnLeave", GameTooltip_Hide);
		rows[index] = row;
		table.insert(navControls, row);
	end
	frame.TooMany = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
	frame.TooMany:SetPoint("TOPLEFT", 16, -62 - MAX_ROWS * 30);
	frame.TooMany:SetText(("Only the first %d gestures are shown."):format(MAX_ROWS));

	local new = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
	new:SetSize(110, 22);
	new:SetPoint("BOTTOMLEFT", 14, 84);
	new:SetText("New gesture");
	new:SetScript("OnClick", function()
		if CanEdit() then
			selected = ns.AddGesture({});
			Refresh();
			-- Straight on to choosing its trigger.
			ns.Nav.Select(slots.trigger);
		end
	end);
	frame.New = new;
	table.insert(navControls, new);

	frame.Footer = ns.Nav.CreatePromptFooter(frame);
	frame.Footer:SetPoint("BOTTOMLEFT", 16, 38);

	-- Editor for the selected gesture
	local editor = CreateFrame("Frame", nil, frame, "InsetFrameTemplate");
	editor:SetPoint("TOPLEFT", 256, -60);
	editor:SetPoint("BOTTOMRIGHT", -12, 116);
	frame.Editor = editor;
	CreateEditorHeader(editor);
	slots = {
		trigger = CreateSlot(editor, "trigger", -66),
		hold = CreateSlot(editor, "hold", -136),
		long = CreateSlot(editor, "long", -206),
	};
	editor.Empty = editor:CreateFontString(nil, "OVERLAY", "GameFontDisable");
	editor.Empty:SetPoint("CENTER");
	editor.Empty:SetText("Select or create a gesture.");
	editor.Delete = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate");
	editor.Delete:SetSize(120, 22);
	editor.Delete:SetPoint("BOTTOMRIGHT", -8, 8);
	editor.Delete:SetText("Delete gesture");
	editor.Delete:SetScript("OnClick", function()
		if CanEdit() and selected then
			ns.RemoveGesture(selected);
			Refresh();
		end
	end);
	for _, control in ipairs({ editor.Header.IconButton, editor.Header.Edit, editor.Header.Bind, slots.trigger, slots.hold, slots.long, editor.Delete }) do
		table.insert(navControls, control);
	end

	-- Bottom: on/off, hold lengths, test, status
	enableCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate");
	enableCheck:SetPoint("BOTTOMLEFT", 254, 30);
	enableCheck.text = enableCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	enableCheck.text:SetPoint("LEFT", enableCheck, "RIGHT", 2, 0);
	enableCheck.text:SetText("Enabled");
	enableCheck:SetScript("OnClick", function(self)
		if not ns.SetEnabled(self:GetChecked()) then
			self:SetChecked(not self:GetChecked());
		end
		Refresh();
	end);
	table.insert(navControls, enableCheck);

	local test = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
	test:SetSize(70, 22);
	test:SetPoint("LEFT", enableCheck.text, "RIGHT", 16, 0);
	test:SetText("Test");
	test:SetScript("OnClick", ns.RunTest);
	table.insert(navControls, test);

	holdText = CreateTicksControl(frame, 88, function(delta) AdjustTicks("holdTicks", delta); end);
	hold2Text = CreateTicksControl(frame, 64, function(delta) AdjustTicks("hold2Ticks", delta); end);

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	statusText:SetPoint("BOTTOMLEFT", 16, 12);
	statusText:SetPoint("BOTTOMRIGHT", -16, 12);
	statusText:SetJustifyH("LEFT");

	-- Controller navigation
	function frame:GetNavControls()
		return navControls;
	end
	function frame:GetNavDefault()
		return rows[selected or 0] or new;
	end

	ns.Nav.SetUpFocusVisuals(frame);

	frame:RegisterEvent("PLAYER_REGEN_DISABLED");
	frame:RegisterEvent("PLAYER_REGEN_ENABLED");
	frame:SetScript("OnEvent", Refresh);
end

function ns.ToggleConfig()
	if not frame then
		CreateConfigFrame();
	end
	frame:SetShown(not frame:IsShown());
end

-- Key binding (Bindings.xml): Options > Keybindings > AddOns.
BINDING_HEADER_GESTURECOMMANDS = "Gesture Commands";
BINDING_NAME_GESTURECOMMANDS_TOGGLE = "Open / close the setup window";
function GestureCommands_ToggleConfig()
	ns.ToggleConfig();
end

function ns.CloseConfig()
	if frame and frame:IsShown() then
		frame:Hide();
	end
end

-- Settings > AddOns entry: a button that opens the window.
local function RegisterSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then
		return;
	end
	local panel = CreateFrame("Frame");
	local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
	text:SetPoint("TOPLEFT", 16, -16);
	text:SetText("Gesture Commands: tap, hold and long-hold gestures for the gamepad crossbar.");
	local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate");
	open:SetSize(200, 24);
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12);
	open:SetText("Open Gesture Commands");
	-- Opens on top of the Settings panel (DIALOG strata); closing Settings from addon code would run
	-- Blizzard's panel manager tainted.
	open:SetScript("OnClick", function()
		if not (frame and frame:IsShown()) then
			ns.ToggleConfig();
		end
	end);
	panel.OnCommit = function() end;
	panel.OnDefault = function() end;
	panel.OnRefresh = function() end;
	local category = Settings.RegisterCanvasLayoutCategory(panel, "Gesture Commands");
	Settings.RegisterAddOnCategory(category);
end

RegisterSettings();
