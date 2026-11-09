-- Gesture Commands: setup window. A list of gestures on the left; on the right, the selected gesture's name
-- and icon (edited like a macro's) and three drop slots: Tap (trigger), Hold, Long hold. Drag a spell, item,
-- toy, mount or macro onto a slot; right-click a slot to clear it; drag a gesture (or press Place on bar) to
-- put it on the crossbar. Editing is locked in combat because the secure configuration and the gesture
-- macros can only change out of combat. The window and the name/icon popup register with the gamepad UI so
-- they can be focused and navigated with a controller.

local _, ns = ...;

local MAX_ROWS = 10;
local SLOT_SIZE = 40;
local QUESTION_MARK_ICON = 134400;
local SLOT_HINTS = {
	trigger = "The button you press: drop a spell, item, or a macro that shows a spell here. A tap does this.",
	hold = "Cast when you hold the button (about 0.5 s). Drag a spell, item, toy, mount or macro here.",
	long = "Cast when you keep holding the button (about 1.4 s). Drag a spell, item, toy, mount or macro here.",
};

local selected = nil;
local frame, popup, rows, slots, statusText, enableCheck, holdText, hold2Text;

-------------------------------------------------------------------------------
-- Gamepad UI: register our windows with the controller cursor (out of combat only; Blizzard refuses it in
-- combat). Both calls are SecureHelper-wrapped by Blizzard for use by outside code.
-------------------------------------------------------------------------------

local function GetFrameControlsManager()
	return InputUtil and InputUtil.IsGamepadUIEnabled() and GamepadMode and GamepadMode.FrameControlsManager;
end

local function GamepadFrameShown(window, isPopup)
	local manager = GetFrameControlsManager();
	if manager and not InCombatLockdown() and pcall(manager.FrameShown, manager, window, isPopup, true) then
		window.gamepadRegistered = true;
	end
end

local function GamepadFrameHidden(window)
	local manager = GamepadMode and GamepadMode.FrameControlsManager;
	if window.gamepadRegistered == true and manager and not InCombatLockdown() then
		pcall(manager.FrameHidden, manager, window);
		window.gamepadRegistered = false;
	end
end

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
		editor.Header.Name:SetText(gesture.trigger and ns.GetGestureName(gesture) or "|cff999999Give it a Tap trigger first|r");
		editor.Header.Edit:SetEnabled(gesture.trigger ~= nil);
		editor.Header.Place:SetEnabled(gesture.trigger ~= nil);
	end
	for mode, slot in pairs(slots) do
		local name, icon = ns.GetActionDisplay(gesture and gesture[mode]);
		slot.Icon:SetTexture(icon);
		slot.Icon:SetShown(icon ~= nil);
		slot.Name:SetText(name or (gesture and "|cff999999empty|r" or ""));
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
		status = "|cffffd100Two gestures share a trigger; only the later one is used.|r";
	elseif db.enabled == false then
		status = "Off - tick Enabled to use your gestures.";
	else
		status = "|cff33ff99On.|r Press Test to check your setup.";
	end
	statusText:SetText(status);
end
ns.OnPublished = Refresh;

local function CanEdit()
	if InCombatLockdown() then
		ns.Print("can't change gestures in combat.");
		return false;
	end
	return true;
end

-------------------------------------------------------------------------------
-- Name & icon popup (Blizzard's macro-style icon selector)
-------------------------------------------------------------------------------

local PopupMixin = {};

-- Not the template's OnShow/OnHide: in gamepad mode those enter/leave a SmartNavigation focus group,
-- which only Blizzard's own code may do (addon calls show "Interface action blocked").
function PopupMixin:OnShow()
	local border = self.BorderBox;
	border.SelectedIconArea.SelectedIconButton:SetIconSelector(self);
	border.IconSelectorEditBox:SetIconSelector(self);
	self.iconDataProvider = self.iconDataProvider or CreateAndInitFromMixin(IconDataProviderMixin, IconDataProviderExtraType.Spellbook);
	self:SetIconFilter(IconSelectorPopupFrameIconFilterTypes.All);
	self:Update();
	border.IconSelectorEditBox:OnTextChanged();

	self.IconSelector:SetSelectedCallback(function(_, icon)
		border.SelectedIconArea.SelectedIconButton:SetIconTexture(icon);
		self:SetSelectedIconText();
	end);

	-- Choosing by dragging an action onto the popup isn't wired up, so always show the icon grid; and keep
	-- OK/Cancel visible with a controller (the template hides them in favour of a secure-only footer).
	border.IconDragArea:Hide();
	border.IconSelectionText:Show();
	border.IconTypeDropdown:Show();
	self.IconSelector:Show();
	border.OkayButton:Show();
	border.CancelButton:Show();

	GamepadFrameShown(self, true);
end

function PopupMixin:OnHide()
	GamepadFrameHidden(self);
end

function PopupMixin:Update()
	local gesture = ns.DB().gestures[self.gestureIndex];
	if not gesture then
		return;
	end
	local border = self.BorderBox;
	local icon = gesture.icon or QUESTION_MARK_ICON;
	border.IconSelectorEditBox:SetText(ns.GetGestureName(gesture));
	border.IconSelectorEditBox:HighlightText();
	self.IconSelector:SetSelectedIndex(self:GetIndexOfIcon(icon));
	border.SelectedIconArea.SelectedIconButton:SetIconTexture(icon);

	self.IconSelector:SetSelectionsDataProvider(GenerateClosure(self.GetIconByIndex, self), GenerateClosure(self.GetNumIcons, self));
	self.IconSelector:ScrollToSelectedIndex();
	self:SetSelectedIconText();
end

function PopupMixin:OkayButton_OnClick()
	if CanEdit() then
		local icon = self.BorderBox.SelectedIconArea.SelectedIconButton:GetIconTexture();
		ns.SetGestureNameIcon(self.gestureIndex, self.BorderBox.IconSelectorEditBox:GetText(), icon);
	end
	self:Hide();
end

function PopupMixin:CancelButton_OnClick()
	self:Hide();
end

local function OpenNameIconPopup()
	if not (CanEdit() and selected) then
		return;
	end
	if not popup then
		popup = CreateFrame("Frame", "GestureCommandsIconPopup", frame, "IconSelectorPopupFrameTemplate");
		Mixin(popup, PopupMixin);
		popup:SetScript("OnShow", popup.OnShow);
		popup:SetScript("OnHide", popup.OnHide);
		popup:SetScript("OnEvent", nil);
		popup:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, 0);
		popup:SetFrameStrata("DIALOG");
		popup:SetToplevel(true);
		popup:EnableMouse(true);
		popup.BorderBox.EditBoxHeaderText:SetText("Gesture name (shown on the macro):");
		popup.BorderBox.IconSelectorEditBox:SetMaxLetters(16);
		-- Controller: A on the name box starts typing (keyboard needed); B closes the popup.
		popup.BorderBox.IconSelectorEditBox.OnSmartNavClick = function(editBox) editBox:SetFocus(); end;
		popup.SmartNavigationCloseHandler = function(self)
			self:Hide();
			return true;
		end;
		popup:Hide();
	end
	popup.gestureIndex = selected;
	popup:Hide();
	popup:Show();
end

-------------------------------------------------------------------------------
-- Drop slots
-------------------------------------------------------------------------------

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
	if slot.mode == "trigger" then
		local trigger = ns.MakeTrigger(action);
		if not trigger then
			ns.Print("a trigger must be a spell or item, or a macro that shows one (#showtooltip).");
			ClearCursor();
			return;
		end
		action = trigger;
	end
	ClearCursor();
	ns.SetGestureAction(selected, slot.mode, action);
end

-- With a mouse: put the gesture's macro on the cursor to drop on a slot. With a controller there's no way to
-- drop a cursor action on the crossbar, so close the window (focus goes back to the game) and let the next
-- crossbar press choose the slot.
local function PlaceSelected()
	if not selected then
		return;
	end
	if GetFrameControlsManager() then
		local index = selected;
		frame:Hide();
		ns.StartPlacing(index);
	else
		ns.PickupGesture(selected);
	end
end

local function CreateSlot(parent, mode, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	label:SetPoint("TOPLEFT", 16, y);
	label:SetText(mode == "trigger" and "Tap (trigger)" or ns.MODE_LABELS[mode]);

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

	slot:SetScript("OnReceiveDrag", OnSlotReceive);
	slot:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "RightButton" then
			if CanEdit() and selected then
				ns.SetGestureAction(selected, self.mode, nil);
			end
		elseif GetCursorInfo() then
			OnSlotReceive(self);
		end
	end);
	slot:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(label:GetText());
		GameTooltip:AddLine(SLOT_HINTS[mode], 1, 1, 1, true);
		GameTooltip:AddLine("Right-click to clear.", 0.6, 0.6, 0.6);
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
	iconButton:SetScript("OnClick", OpenNameIconPopup);
	iconButton:SetScript("OnDragStart", PlaceSelected);
	iconButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText("Gesture");
		GameTooltip:AddLine("Click to change the name and icon. Drag onto your crossbar to place it.", 1, 1, 1, true);
		GameTooltip:Show();
	end);
	iconButton:SetScript("OnLeave", GameTooltip_Hide);

	header.Name = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	header.Name:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 8, -1);
	header.Name:SetPoint("RIGHT", -10, 0);
	header.Name:SetJustifyH("LEFT");

	header.Edit = CreateFrame("Button", nil, header, "UIPanelButtonTemplate");
	header.Edit:SetSize(110, 20);
	header.Edit:SetPoint("BOTTOMLEFT", iconButton, "BOTTOMRIGHT", 8, 0);
	header.Edit:SetText("Name & icon");
	header.Edit:SetScript("OnClick", OpenNameIconPopup);

	header.Place = CreateFrame("Button", nil, header, "UIPanelButtonTemplate");
	header.Place:SetSize(110, 20);
	header.Place:SetPoint("LEFT", header.Edit, "RIGHT", 6, 0);
	header.Place:SetText("Place on bar");
	header.Place:SetScript("OnClick", PlaceSelected);
	header.Place:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText("Place on bar");
		GameTooltip:AddLine("Controller: closes this window - then press the crossbar button you want the gesture on. Mouse: puts the gesture on your cursor to drop on a crossbar slot.", 1, 1, 1, true);
		GameTooltip:Show();
	end);
	header.Place:SetScript("OnLeave", GameTooltip_Hide);
end

local function CreateConfigFrame()
	frame = CreateFrame("Frame", "GestureCommandsFrame", UIParent, "BasicFrameTemplateWithInset");
	frame:SetSize(560, 500);
	frame:SetPoint("CENTER");
	frame:SetFrameStrata("DIALOG");
	frame:SetMovable(true);
	frame:EnableMouse(true);
	frame:RegisterForDrag("LeftButton");
	frame:SetScript("OnDragStart", frame.StartMoving);
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing);
	-- Controller: closing this window hands focus back to the game rather than to another window.
	frame.returnToPlayerControl = true;
	frame:SetScript("OnShow", function(self)
		if ns.IsPlacing() then
			ns.CancelPlacing(true);
		end
		Refresh();
		GamepadFrameShown(self, false);
	end);
	frame:SetScript("OnHide", function(self)
		if popup then
			popup:Hide();
		end
		GamepadFrameHidden(self);
	end);
	frame:Hide();
	tinsert(UISpecialFrames, "GestureCommandsFrame");

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	title:SetPoint("TOP", 0, -5);
	title:SetText("Gesture Commands");

	local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	intro:SetPoint("TOPLEFT", 14, -30);
	intro:SetPoint("TOPRIGHT", -14, -30);
	intro:SetJustifyH("LEFT");
	intro:SetText("A gesture is a macro for your gamepad: give it a Tap trigger plus Hold / Long hold actions, a name and an icon, then place it on your crossbar. A tap does the trigger; holds cast your actions.");

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
			GameTooltip:AddLine("Drag onto your crossbar to place this gesture.", 1, 1, 1, true);
			GameTooltip:Show();
		end);
		row:SetScript("OnLeave", GameTooltip_Hide);
		rows[index] = row;
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
		end
	end);

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

	local test = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
	test:SetSize(70, 22);
	test:SetPoint("LEFT", enableCheck.text, "RIGHT", 16, 0);
	test:SetText("Test");
	test:SetScript("OnClick", ns.RunTest);

	holdText = CreateTicksControl(frame, 88, function(delta) AdjustTicks("holdTicks", delta); end);
	hold2Text = CreateTicksControl(frame, 64, function(delta) AdjustTicks("hold2Ticks", delta); end);

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	statusText:SetPoint("BOTTOMLEFT", 16, 12);
	statusText:SetPoint("BOTTOMRIGHT", -16, 12);
	statusText:SetJustifyH("LEFT");

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
