-- Gesture Commands: setup window. A list of gestures on the left; on the right, three drop slots for the
-- selected gesture (Tap trigger, Hold, Long hold). Drag a spell, item, toy, mount or macro onto a slot;
-- right-click a slot to clear it. Editing is locked in combat because the secure configuration can only
-- be republished out of combat.

local _, ns = ...;

local MAX_ROWS = 10;
local SLOT_SIZE = 40;
local SLOT_HINTS = {
	trigger = "The button you press: drop a spell, item, or a macro that shows a spell here. Then drag this box (or the gesture in the list) onto your crossbar - that slot becomes the gesture. A tap does what the slot normally does.",
	hold = "Cast when you hold the button (about 0.5 s). Drag a spell, item, toy, mount or macro here.",
	long = "Cast when you keep holding the button (about 1.4 s). Drag a spell, item, toy, mount or macro here.",
};

local selected = nil;
local frame, rows, slots, statusText, enableCheck, holdText, hold2Text;

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
			local triggerName, triggerIcon = ns.GetActionDisplay(gesture.trigger);
			local holdName = ns.GetActionDisplay(gesture.hold);
			local longName = ns.GetActionDisplay(gesture.long);
			row.Icon:SetTexture(triggerIcon or 134400);
			row.Text:SetText(("%s\n|cff999999%s / %s|r"):format(triggerName or "(no trigger yet)", holdName or "-", longName or "-"));
			row.Selected:SetShown(index == selected);
			row.Conflict:SetShown(ns.conflicts and ns.conflicts[index] ~= nil);
			row:Show();
		else
			row:Hide();
		end
	end
	frame.TooMany:SetShown(#gestures > MAX_ROWS);

	local gesture = selected and gestures[selected];
	for mode, slot in pairs(slots) do
		local name, icon = ns.GetActionDisplay(gesture and gesture[mode]);
		slot.Icon:SetTexture(icon);
		slot.Icon:SetShown(icon ~= nil);
		slot.Name:SetText(name or (gesture and "|cff999999empty|r" or ""));
		slot:SetEnabled(gesture ~= nil);
	end
	frame.Editor.Empty:SetShown(gesture == nil);
	frame.Editor.Delete:SetEnabled(gesture ~= nil);

	enableCheck:SetChecked(db.enabled == true);
	holdText:SetText(("Hold: %d ticks (~%.1f s)"):format(ns.GetHoldTicks(), ns.GetHoldTicks() * 0.2));
	hold2Text:SetText(("Long hold: %d ticks (~%.1f s)"):format(ns.GetHold2Ticks(), ns.GetHold2Ticks() * 0.2));

	local status;
	if InCombatLockdown() then
		status = "|cffff6060Editing is locked in combat.|r";
	elseif ns.IsTotemCommandsActive() then
		status = "|cffff6060Totem Commands is on and uses the same buttons: type /totemcommands off.|r";
	elseif ns.conflicts and next(ns.conflicts) then
		status = "|cffffd100Two gestures share a trigger; only the later one is used.|r";
	elseif not db.enabled then
		status = "Off - tick Enabled to use your gestures.";
	else
		status = "|cff33ff99On.|r Press /gestures test to check your setup.";
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

local function CreateSlot(parent, mode, y)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	label:SetPoint("TOPLEFT", 16, y);
	label:SetText(ns.MODE_LABELS[mode] == "Tap" and "Tap (trigger)" or ns.MODE_LABELS[mode]);

	local slot = CreateFrame("Button", nil, parent);
	slot.mode = mode;
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
	if mode == "trigger" then
		slot:SetScript("OnDragStart", function()
			if selected then
				ns.PickupTrigger(selected);
			end
		end);
	end
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

local function CreateConfigFrame()
	frame = CreateFrame("Frame", "GestureCommandsFrame", UIParent, "BasicFrameTemplateWithInset");
	frame:SetSize(560, 480);
	frame:SetPoint("CENTER");
	frame:SetFrameStrata("DIALOG");
	frame:SetMovable(true);
	frame:EnableMouse(true);
	frame:RegisterForDrag("LeftButton");
	frame:SetScript("OnDragStart", frame.StartMoving);
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing);
	frame:SetScript("OnShow", Refresh);
	frame:Hide();
	tinsert(UISpecialFrames, "GestureCommandsFrame");

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	title:SetPoint("TOP", 0, -5);
	title:SetText("Gesture Commands");

	local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	intro:SetPoint("TOPLEFT", 14, -30);
	intro:SetPoint("TOPRIGHT", -14, -30);
	intro:SetJustifyH("LEFT");
	intro:SetText("Make a gesture, give it a Tap trigger and Hold / Long hold actions, then drag the gesture from the list onto your crossbar. A tap does what the slot normally does; holds cast your actions.");

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
			ns.PickupTrigger(index);
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
	slots = {
		trigger = CreateSlot(editor, "trigger", -12),
		hold = CreateSlot(editor, "hold", -82),
		long = CreateSlot(editor, "long", -152),
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
	open:SetScript("OnClick", function()
		if SettingsPanel and SettingsPanel:IsShown() then
			HideUIPanel(SettingsPanel);
		end
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
