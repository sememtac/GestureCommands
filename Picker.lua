-- Gesture Commands: the picker window, a paged grid of icons used two ways: choosing a gesture's name and
-- icon (like the macro icon popup), and choosing the spell, item, mount or macro for one of a gesture's
-- slots without dragging (a controller can't put anything on the cursor). Plain buttons only, so the
-- controller reaches everything; it opens as a popup of the setup window (see Navigation.lua).

local _, ns = ...;

local COLUMNS, ROWS = 8, 5;
local PER_PAGE = COLUMNS * ROWS;
local CELL = 38;
local JUMP_PAGES = 10;
local QUESTION_MARK_ICON = 134400;
local ICON_FOLDER = "Interface\\Icons\\";
local ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120;

local SOURCES = {
	icon = {
		{ key = "suggested", label = "Suggested" },
		{ key = "all", label = "All icons" },
	},
	action = {
		{ key = "spells", label = "Spells" },
		{ key = "items", label = "Items" },
		{ key = "mounts", label = "Mounts" },
		{ key = "macros", label = "Macros" },
	},
};
local ACTION_HINTS = {
	trigger = "A tap does this. Pick a spell, a usable item, or one of your macros that shows a spell or item.",
	hold = "Cast when you hold the button.",
	long = "Cast when you keep holding the button.",
};

local picker;
local state = {}; -- mode ("icon"/"action"), gestureIndex, slotMode, onChosen, chosenIcon, source, page, entries

-------------------------------------------------------------------------------
-- Entries: { icon = texture, name = string?, action = action? }
-------------------------------------------------------------------------------

local function AddUnique(entries, seen, key, entry)
	if key ~= nil and not seen[key] then
		seen[key] = true;
		table.insert(entries, entry);
	end
end

-- Active, non-passive spells in the spellbook, once per name (a ranked spell is cast at its highest rank).
local function ForEachSpell(callback)
	if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then
		return;
	end
	local bank = Enum.SpellBookSpellBank.Player;
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line);
		if lineInfo then
			for slot = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
				local info = C_SpellBook.GetSpellBookItemInfo(slot, bank);
				if info and info.itemType == Enum.SpellBookItemType.Spell and not info.isPassive and not info.isOffSpec then
					callback(info);
				end
			end
		end
	end
end

local function GetSpellEntries()
	local entries, seen = {}, {};
	ForEachSpell(function(info)
		local action = { kind = "spell", id = info.spellID or info.actionID, name = info.name };
		AddUnique(entries, seen, info.name, { icon = info.iconID, name = info.name, action = action });
	end);
	return entries;
end

-- Equipped and carried items with a Use effect.
local function GetItemEntries()
	local entries, seen = {}, {};
	local function Add(itemID, icon)
		if itemID and C_Item.GetItemSpell(itemID) then
			local name = C_Item.GetItemNameByID(itemID);
			AddUnique(entries, seen, itemID, { icon = icon or C_Item.GetItemIconByID(itemID), name = name,
				action = { kind = "item", id = itemID, name = name } });
		end
	end
	for slot = 1, 19 do
		Add(GetInventoryItemID("player", slot), GetInventoryItemTexture("player", slot));
	end
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot);
			if info then
				Add(info.itemID, info.iconFileID);
			end
		end
	end
	return entries;
end

local function GetMountEntries()
	local entries = {};
	if not (C_MountJournal and C_MountJournal.GetMountIDs) then
		return entries;
	end
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local name, _, icon, _, _, _, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID);
		if name and isCollected and not shouldHideOnChar then
			table.insert(entries, { icon = icon, name = name, action = { kind = "mount", id = mountID, name = name } });
		end
	end
	table.sort(entries, function(a, b) return a.name < b.name; end);
	return entries;
end

-- Account and character macros.
local function GetMacroEntries()
	local entries = {};
	local function Add(index)
		local name, icon = GetMacroInfo(index);
		if name then
			table.insert(entries, { icon = icon, name = name, action = { kind = "macro", name = name } });
		end
	end
	local numAccount, numCharacter = GetNumMacros();
	for index = 1, numAccount do
		Add(index);
	end
	for index = ACCOUNT_MACROS + 1, ACCOUNT_MACROS + numCharacter do
		Add(index);
	end
	return entries;
end

local AUTO_ICON_ENTRY = { icon = QUESTION_MARK_ICON, name = "Automatic: the Tap action's icon" };

-- The gesture's own actions' icons, then the spellbook's.
local function GetSuggestedIcons()
	local entries, seen = { AUTO_ICON_ENTRY }, { [QUESTION_MARK_ICON] = true };
	local gesture = ns.DB().gestures[state.gestureIndex];
	for _, mode in ipairs({ "trigger", "hold", "long" }) do
		local name, icon = ns.GetActionDisplay(gesture and gesture[mode]);
		AddUnique(entries, seen, icon, { icon = icon, name = name });
	end
	ForEachSpell(function(info)
		AddUnique(entries, seen, info.iconID, { icon = info.iconID, name = info.name });
	end);
	return entries;
end

-- Every icon the macro popup offers. Read into our own table: Blizzard's icon provider keeps its list in
-- shared state that the macro UI also uses.
local allIcons;
local function GetAllIcons()
	if not allIcons then
		local textures = {};
		for _, functionName in ipairs({ "GetLooseMacroIcons", "GetLooseMacroItemIcons", "GetMacroIcons", "GetMacroItemIcons" }) do
			local fill = _G[functionName];
			if fill then
				fill(textures);
			end
		end
		allIcons = { AUTO_ICON_ENTRY };
		local seen = { [QUESTION_MARK_ICON] = true };
		for _, texture in ipairs(textures) do
			local icon = tonumber(texture) or (ICON_FOLDER .. texture);
			AddUnique(allIcons, seen, icon, { icon = icon });
		end
	end
	return allIcons;
end

local BUILDERS = {
	suggested = GetSuggestedIcons,
	all = GetAllIcons,
	spells = GetSpellEntries,
	items = GetItemEntries,
	mounts = GetMountEntries,
	macros = GetMacroEntries,
};

-- Macros store a file ID; icons only known by path are converted when possible.
local function GetIconForSaving(icon)
	if type(icon) == "string" and GetFileIDFromPath then
		local fileID = GetFileIDFromPath(icon);
		if fileID and fileID > 0 then
			return fileID;
		end
	end
	return icon;
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------

local function GetNumPages()
	return math.max(1, math.ceil(#state.entries / PER_PAGE));
end

local function ShowPage()
	state.page = math.min(math.max(state.page, 1), GetNumPages());
	local offset = (state.page - 1) * PER_PAGE;
	for index, cell in ipairs(picker.cells) do
		local entry = state.entries[offset + index];
		cell.entry = entry;
		if entry then
			cell.Icon:SetTexture(entry.icon or QUESTION_MARK_ICON);
			cell.Chosen:SetShown(state.mode == "icon" and entry.icon == state.chosenIcon);
			cell:Show();
		else
			cell:Hide();
		end
	end
	local numPages = GetNumPages();
	picker.PageText:SetText(("Page %d / %d"):format(state.page, numPages));
	picker.First:SetEnabled(state.page > 1);
	picker.Previous:SetEnabled(state.page > 1);
	picker.Next:SetEnabled(state.page < numPages);
	picker.Last:SetEnabled(state.page < numPages);
	picker.Empty:SetShown(#state.entries == 0);
	ns.Nav.Refresh(picker);
end

local function TurnPage(delta)
	state.page = state.page + delta;
	ShowPage();
end

local function SetSource(key)
	state.source = key;
	state.entries = BUILDERS[key]();
	state.page = 1;
	if state.mode == "icon" then
		for index, entry in ipairs(state.entries) do
			if entry.icon == state.chosenIcon then
				state.page = math.ceil(index / PER_PAGE);
				break;
			end
		end
	end
	for _, tab in ipairs(picker.tabs) do
		tab:SetEnabled(tab.key ~= key);
	end
	ShowPage();
end

local function UpdatePreview()
	local icon = state.chosenIcon;
	if icon == QUESTION_MARK_ICON then
		local gesture = ns.DB().gestures[state.gestureIndex];
		local _, triggerIcon = ns.GetActionDisplay(gesture and gesture.trigger);
		icon = triggerIcon or QUESTION_MARK_ICON;
	end
	picker.Preview:SetTexture(icon);
end

local function OnCellClick(cell)
	local entry = cell.entry;
	if not entry then
		return;
	end
	if state.mode == "icon" then
		state.chosenIcon = entry.icon;
		for _, other in ipairs(picker.cells) do
			other.Chosen:SetShown(other.entry ~= nil and other.entry.icon == state.chosenIcon);
		end
		UpdatePreview();
	elseif state.onChosen(entry.action) then
		picker:Hide();
	end
end

local function Save()
	if state.mode == "icon" and ns.CanEdit() then
		ns.SetGestureNameIcon(state.gestureIndex, picker.NameBox:GetText(), GetIconForSaving(state.chosenIcon));
	end
	picker:Hide();
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------

local function CreateButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate");
	button:SetSize(width, 22);
	button:SetText(text);
	return button;
end

local function CreatePicker()
	picker = CreateFrame("Frame", "GestureCommandsPicker", UIParent, "BasicFrameTemplateWithInset, FocusFramesInterfaceTemplate");
	picker:SetSize(COLUMNS * CELL + 32, 402);
	-- Above the setup window (DIALOG), below the controller highlight (FULLSCREEN_DIALOG).
	picker:SetFrameStrata("FULLSCREEN");
	picker:SetClampedToScreen(true);
	picker:EnableMouse(true);
	picker:Hide();
	tinsert(UISpecialFrames, "GestureCommandsPicker");

	picker.Title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	picker.Title:SetPoint("TOP", 0, -5);

	-- Name row (icon mode) or hint (action mode)
	picker.NameLabel = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	picker.NameLabel:SetPoint("TOPLEFT", 16, -40);
	picker.NameLabel:SetText("Name:");
	picker.NameBox = CreateFrame("EditBox", nil, picker, "InputBoxTemplate");
	picker.NameBox:SetSize(180, 20);
	picker.NameBox:SetPoint("LEFT", picker.NameLabel, "RIGHT", 12, 0);
	picker.NameBox:SetAutoFocus(false);
	picker.NameBox:SetMaxLetters(16);
	picker.NameBox:SetScript("OnEnterPressed", picker.NameBox.ClearFocus);
	picker.NameBox:SetScript("OnEscapePressed", picker.NameBox.ClearFocus);
	picker.NameBox:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText("Gesture name");
		GameTooltip:AddLine("Labels the gesture in this window. Type it with the keyboard (A starts typing, B stops). Empty uses the Tap action's name.", 1, 1, 1, true);
		GameTooltip:Show();
	end);
	picker.NameBox:SetScript("OnLeave", GameTooltip_Hide);
	-- Controller A: start typing (there's no on-screen keyboard; a keyboard types).
	function picker.NameBox:OnSmartNavClick()
		self:SetFocus();
	end
	picker.Preview = picker:CreateTexture(nil, "ARTWORK");
	picker.Preview:SetSize(32, 32);
	picker.Preview:SetPoint("TOPRIGHT", -18, -30);
	picker.Hint = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	picker.Hint:SetPoint("TOPLEFT", 16, -32);
	picker.Hint:SetPoint("TOPRIGHT", -16, -32);
	picker.Hint:SetJustifyH("LEFT");

	-- Source tabs
	picker.tabs = {};
	for index = 1, 4 do
		local tab = CreateButton(picker, "", 76);
		tab:SetPoint("TOPLEFT", 14 + (index - 1) * 80, -68);
		tab:SetScript("OnClick", function(self)
			SetSource(self.key);
		end);
		picker.tabs[index] = tab;
	end

	-- Grid
	picker.cells = {};
	for index = 1, PER_PAGE do
		local column, row = (index - 1) % COLUMNS, math.floor((index - 1) / COLUMNS);
		local cell = CreateFrame("Button", nil, picker);
		cell:SetSize(CELL - 4, CELL - 4);
		cell:SetPoint("TOPLEFT", 18 + column * CELL, -98 - row * CELL);
		cell.Icon = cell:CreateTexture(nil, "ARTWORK");
		cell.Icon:SetAllPoints();
		cell.Chosen = cell:CreateTexture(nil, "OVERLAY");
		cell.Chosen:SetTexture("Interface\\Buttons\\CheckButtonHilight");
		cell.Chosen:SetBlendMode("ADD");
		cell.Chosen:SetAllPoints();
		cell.Chosen:Hide();
		cell:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
		cell:SetScript("OnClick", OnCellClick);
		cell:SetScript("OnEnter", function(self)
			local entry = self.entry;
			local action = entry and entry.action;
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			if action and action.kind == "spell" then
				GameTooltip:SetSpellByID(action.id);
			elseif action and action.kind == "item" then
				GameTooltip:SetItemByID(action.id);
			elseif entry and entry.name then
				GameTooltip:SetText(entry.name);
			else
				GameTooltip:Hide();
				return;
			end
			GameTooltip:Show();
		end);
		cell:SetScript("OnLeave", GameTooltip_Hide);
		picker.cells[index] = cell;
	end
	picker.Empty = picker:CreateFontString(nil, "OVERLAY", "GameFontDisable");
	picker.Empty:SetPoint("TOP", 0, -180);
	picker.Empty:SetText("Nothing here.");

	-- Pager
	local pagerY = -98 - ROWS * CELL - 6;
	picker.First = CreateButton(picker, "<<", 34);
	picker.First:SetPoint("TOPLEFT", 16, pagerY);
	picker.First:SetScript("OnClick", function() TurnPage(-JUMP_PAGES); end);
	picker.Previous = CreateButton(picker, "<", 34);
	picker.Previous:SetPoint("LEFT", picker.First, "RIGHT", 4, 0);
	picker.Previous:SetScript("OnClick", function() TurnPage(-1); end);
	picker.Last = CreateButton(picker, ">>", 34);
	picker.Last:SetPoint("TOPRIGHT", -16, pagerY);
	picker.Last:SetScript("OnClick", function() TurnPage(JUMP_PAGES); end);
	picker.Next = CreateButton(picker, ">", 34);
	picker.Next:SetPoint("RIGHT", picker.Last, "LEFT", -4, 0);
	picker.Next:SetScript("OnClick", function() TurnPage(1); end);
	picker.PageText = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	picker.PageText:SetPoint("TOP", 0, pagerY - 5);

	picker.Footer = ns.Nav.CreatePromptFooter(picker);
	picker.Footer:SetPoint("BOTTOMLEFT", 18, 42);
	picker.Footer:SetPrompts({ { GAMEPAD_FACE_BOTTOM, "Choose" }, { GAMEPAD_FACE_RIGHT, "Back" } });

	-- Bottom buttons
	picker.Okay = CreateButton(picker, "OK", 90);
	picker.Okay:SetPoint("BOTTOMLEFT", 16, 12);
	picker.Okay:SetScript("OnClick", Save);
	picker.Clear = CreateButton(picker, "Clear", 90);
	picker.Clear:SetPoint("BOTTOMLEFT", 16, 12);
	picker.Clear:SetScript("OnClick", function()
		if state.onChosen(nil) then
			picker:Hide();
		end
	end);
	picker.Cancel = CreateButton(picker, "Cancel", 90);
	picker.Cancel:SetPoint("BOTTOMRIGHT", -16, 12);
	picker.Cancel:SetScript("OnClick", function() picker:Hide(); end);

	-- Controller navigation
	function picker:GetNavControls()
		local controls = { self.NameBox };
		for _, tab in ipairs(self.tabs) do
			table.insert(controls, tab);
		end
		for _, cell in ipairs(self.cells) do
			table.insert(controls, cell);
		end
		for _, button in ipairs({ self.First, self.Previous, self.Next, self.Last, self.Okay, self.Clear, self.Cancel }) do
			table.insert(controls, button);
		end
		return controls;
	end
	function picker:GetNavDefault()
		for _, cell in ipairs(self.cells) do
			if cell:IsShown() and (state.mode ~= "icon" or (cell.entry and cell.entry.icon == state.chosenIcon)) then
				return cell;
			end
		end
		return self.cells[1];
	end
	-- Controller B: stop typing, else close. Without this, Blizzard's gamepad UI would press the close button,
	-- running its panel manager from our frame.
	function picker:SmartNavigationCloseHandler()
		if self.NameBox:HasFocus() then
			self.NameBox:ClearFocus();
		else
			self:Hide();
		end
		return true;
	end
	picker:SetScript("OnShow", function(self)
		self.navCurrent = nil;
		self.Footer:SetShown(ns.Nav.UsesGamepadUI() or ns.Nav.UsesOwnNavigation());
		ns.Nav.Open(self, true);
	end);
	ns.Nav.SetUpFocusVisuals(picker);
	picker:SetScript("OnHide", function(self)
		self.NameBox:ClearFocus();
		ns.Nav.Close(self);
	end);
end

local function Open(anchor, mode)
	if not picker then
		CreatePicker();
	end
	picker:Hide();
	local sources = SOURCES[mode];
	for index, tab in ipairs(picker.tabs) do
		local source = sources[index];
		tab.key = source and source.key;
		tab:SetText(source and source.label or "");
		tab:SetShown(source ~= nil);
	end
	local isIcon = mode == "icon";
	picker.NameLabel:SetShown(isIcon);
	picker.NameBox:SetShown(isIcon);
	picker.Preview:SetShown(isIcon);
	picker.Okay:SetShown(isIcon);
	picker.Clear:SetShown(not isIcon);
	picker.Hint:SetShown(not isIcon);
	picker:ClearAllPoints();
	picker:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0);
	SetSource(sources[1].key);
	picker:Show();
end

-- Name and icon for a gesture; OK saves both.
function ns.OpenIconPicker(anchor, gestureIndex)
	local gesture = ns.DB().gestures[gestureIndex];
	if not gesture then
		return;
	end
	state = { mode = "icon", gestureIndex = gestureIndex, chosenIcon = gesture.icon or QUESTION_MARK_ICON };
	Open(anchor, "icon");
	picker.Title:SetText("Name & icon");
	picker.NameBox:SetText(ns.GetGestureName(gesture));
	UpdatePreview();
end

-- A spell, item, mount or macro for one of a gesture's slots. onChosen(action) gets nil for Clear and
-- returns true if it took the choice (the picker then closes).
function ns.OpenActionPicker(anchor, gestureIndex, slotMode, onChosen)
	local gesture = ns.DB().gestures[gestureIndex];
	if not gesture then
		return;
	end
	state = { mode = "action", gestureIndex = gestureIndex, slotMode = slotMode, onChosen = onChosen };
	Open(anchor, "action");
	picker.Title:SetText("Choose: " .. ns.MODE_LABELS[slotMode]);
	picker.Hint:SetText(ACTION_HINTS[slotMode]);
	picker.Clear:SetShown(gesture[slotMode] ~= nil);
end

function ns.ClosePicker()
	if picker then
		picker:Hide();
	end
end

function ns.IsPickerShown()
	return picker ~= nil and picker:IsShown();
end
