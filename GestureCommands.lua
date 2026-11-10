-- Gesture Commands
-- Tap / hold / long-hold gestures for anything on the gamepad crossbar. A gesture attaches to a trigger
-- (a spell or item on a crossbar slot, or a macro that shows a spell): a tap does what the slot normally
-- does, a hold casts the gesture's hold action, a longer hold casts its long-hold action.
--
-- All of the decision making is secure. Each crossbar button's OnClick is wrapped (SecureHandlerWrapScript):
-- a press on a trigger slot is held back, and the release either runs the slot's own action or casts the
-- hold / long-hold action through a virtual button ("*type-GestureCast"). The restricted environment has no
-- clock, so a self-resetting state driver provides a secure tick (~0.2 s, sooner when the game fires driver
-- events) and holds are counted in ticks. Addon code only publishes configuration as header attributes out
-- of combat and reads the header's "armed" attribute for feedback; it never writes to Blizzard's buttons.

local ADDON_NAME, ns = ...;

local DEFAULT_HOLD_TICKS, DEFAULT_HOLD2_TICKS = 3, 7;
local MIN_HOLD_TICKS, MAX_HOLD_TICKS, MAX_HOLD2_TICKS = 2, 6, 12;
local RUMBLE_INTENSITY, RUMBLE_TIME, DOUBLE_RUMBLE_GAP = 0.5, 0.15, 0.25;
local MAX_ACTION_SLOT = 400; -- Covers the keyboard bars and the gamepad action storage (181+).
local MODES = { "hold", "long" };

ns.MODES = MODES;
ns.MODE_LABELS = { trigger = "Tap", hold = "Hold", long = "Long hold" };

local header = CreateFrame("Frame", "GestureCommandsHeader", UIParent, "SecureHandlerStateTemplate");
header:SetAttribute("enabled", false);
header:SetAttribute("armed", 0);
header:SetAttribute("holdTicks", DEFAULT_HOLD_TICKS);
header:SetAttribute("hold2Ticks", DEFAULT_HOLD2_TICKS);
ns.header = header;

-- Secure tick: the driver always resolves to "tock"; resetting the attribute to "tick" makes the next
-- driver update count as a change. "armed" is the hold stage: 0 tap, 1 hold, 2 long hold. A stage only arms
-- if the pressed gesture has an action for it. A press that is never released is dropped after ~5 s.
header:SetAttribute("_onstate-tick", [[
	if newstate ~= "tock" then
		return;
	end
	self:SetAttribute("state-tick", "tick");
	self:SetAttribute("tickcount", (self:GetAttribute("tickcount") or 0) + 1);

	if pressedSlot then
		ticks = (ticks or 0) + 1;
		local stage = armed or 0;
		local prefix = "g" .. pressedGesture .. "-";
		if ticks > 25 then
			pressedSlot = nil;
			pressedGesture = nil;
			armed = 0;
			self:SetAttribute("armed", 0);
		elseif stage < 1 and ticks >= (self:GetAttribute("holdTicks") or 3) and self:GetAttribute(prefix .. "hold-type") then
			armed = 1;
			self:SetAttribute("armed", 1);
		elseif stage < 2 and ticks >= (self:GetAttribute("hold2Ticks") or 7) and self:GetAttribute(prefix .. "long-type") then
			armed = 2;
			self:SetAttribute("armed", 2);
		end
	end
]]);

-- Runs before Blizzard's OnClick on every wrapped crossbar button. Triggers are looked up by what the slot
-- shows: "g:spell:<id>" / "g:item:<id>" hold the gesture number (a macro counts as the spell/item it shows).
local PRE_CLICK = [[
	-- Place mode: the next crossbar press only says where to put a gesture. Not in combat: there every press
	-- does its action, and the gesture waits for a press after the fight.
	if control:GetAttribute("placing") and SecureCmdOptionParse("[combat] 1; 0") ~= "1" then
		if down then
			control:SetAttribute("placing", false);
			control:SetAttribute("placeSlot", self:GetID());
			-- Drop any gesture press whose release never arrived (e.g. the window took focus mid-press).
			pressedSlot = nil;
			pressedGesture = nil;
			armed = 0;
			control:SetAttribute("armed", 0);
		end
		return false;
	end
	if not control:GetAttribute("enabled") then
		return;
	end
	local slot = self:GetID();
	if control:GetAttribute("debug") then
		control:SetAttribute("debugSeq", (control:GetAttribute("debugSeq") or 0) + 1);
		control:SetAttribute("debugLast", format("slot %d %s", slot, down and "down" or "up"));
	end

	if down then
		if slot <= 0 then
			return;
		end
		local kind, id, subType = GetActionInfo(slot);
		if kind == "macro" then
			kind = subType;
		end
		if (kind ~= "spell" and kind ~= "item") or not id then
			return;
		end
		local gesture = control:GetAttribute("g:" .. kind .. ":" .. id);
		if not gesture then
			return;
		end
		pressedSlot = slot;
		pressedGesture = gesture;
		ticks = 0;
		armed = 0;
		control:SetAttribute("armedGesture", gesture);
		control:SetAttribute("armed", 0);
		-- Don't act on press; the release decides.
		return false;
	end

	if not pressedSlot then
		return;
	end
	local stage = armed or 0;
	local gesture = pressedGesture;
	armed = 0;
	pressedGesture = nil;
	control:SetAttribute("armed", 0);
	if pressedSlot ~= slot then
		-- The crossbar page changed mid-hold, so this button now holds something else: drop the press.
		pressedSlot = nil;
		return;
	end
	pressedSlot = nil;

	-- The slot must still hold this gesture's trigger.
	local kind, id, subType = GetActionInfo(slot);
	if kind == "macro" then
		kind = subType;
	end
	if not kind or not id or control:GetAttribute("g:" .. kind .. ":" .. id) ~= gesture then
		return false;
	end

	-- Act on this release instead of on the (suppressed) press; the post-body puts Blizzard's value back.
	savedUseOnKeyDown = self:GetAttribute("useOnKeyDown");
	self:SetAttribute("useOnKeyDown", false);

	local mode = (stage == 2 and "long") or (stage == 1 and "hold") or nil;
	if mode then
		local prefix = "g" .. gesture .. "-" .. mode .. "-";
		local actionType = control:GetAttribute(prefix .. "type");
		if actionType then
			local attribute = "*" .. control:GetAttribute(prefix .. "attr") .. "-GestureCast";
			local value = control:GetAttribute(prefix .. "value");
			if self:GetAttribute("*type-GestureCast") ~= actionType then
				self:SetAttribute("*type-GestureCast", actionType);
			end
			if self:GetAttribute(attribute) ~= value then
				self:SetAttribute(attribute, value);
			end
			return "GestureCast", "restore";
		end
	end
	-- Tap: the slot's own action, on release.
	return nil, "restore";
]];

local POST_CLICK = [[
	if message == "restore" then
		self:SetAttribute("useOnKeyDown", savedUseOnKeyDown);
		savedUseOnKeyDown = nil;
	end
]];

local function Print(text)
	print("|cff33ff99Gesture Commands|r: " .. text);
end
ns.Print = Print;

-------------------------------------------------------------------------------
-- Saved data: per character, since gestures depend on the character's spells.
-------------------------------------------------------------------------------

local function DB()
	return GestureCommandsCharDB;
end
ns.DB = DB;

local function GetHoldTicks()
	return DB().holdTicks or DEFAULT_HOLD_TICKS;
end

local function GetHold2Ticks()
	return math.max(DB().hold2Ticks or DEFAULT_HOLD2_TICKS, GetHoldTicks() + 2);
end
ns.GetHoldTicks, ns.GetHold2Ticks = GetHoldTicks, GetHold2Ticks;

-------------------------------------------------------------------------------
-- Actions: { kind = "spell"|"item"|"toy"|"mount"|"macro", id = number, name = string }
-------------------------------------------------------------------------------

local function GetActionDisplay(action)
	if not action then
		return nil, nil;
	end
	if action.kind == "spell" then
		return C_Spell.GetSpellName(action.id) or action.name, C_Spell.GetSpellTexture(action.id);
	elseif action.kind == "item" or action.kind == "toy" then
		return C_Item.GetItemNameByID(action.id) or action.name, C_Item.GetItemIconByID(action.id);
	elseif action.kind == "mount" then
		local name, _, icon = C_MountJournal.GetMountInfoByID(action.id);
		return name or action.name, icon;
	elseif action.kind == "macro" then
		local name, icon = GetMacroInfo(action.name);
		return name or action.name, icon;
	end
	return action.name, nil;
end
ns.GetActionDisplay = GetActionDisplay;

-- Reads the cursor into an action. Spells, items, toys, mounts and macros are supported.
local function ReadCursor()
	local cursorType, info1, _, info3 = GetCursorInfo();
	if cursorType == "spell" and info3 then
		return { kind = "spell", id = info3, name = C_Spell.GetSpellName(info3) };
	elseif cursorType == "item" and info1 then
		local isToy = (PlayerHasToy and PlayerHasToy(info1)) or false;
		return { kind = isToy and "toy" or "item", id = info1, name = C_Item.GetItemNameByID(info1) };
	elseif cursorType == "mount" and info1 then
		return { kind = "mount", id = info1, name = (C_MountJournal.GetMountInfoByID(info1)) };
	elseif cursorType == "macro" and info1 then
		return { kind = "macro", name = (GetMacroInfo(info1)) };
	end
	return nil, cursorType;
end
ns.ReadCursor = ReadCursor;

-- The Tap ("trigger") is what a crossbar slot shows: a spell, an item, or one of the player's macros that
-- shows a spell or item (#showtooltip / its first /cast). Returns the spell or item it stands for - for a
-- macro, what it shows right now - or nil if there is none (e.g. the macro was deleted).
local function ResolveTrigger(trigger)
	if not trigger then
		return nil;
	elseif trigger.kind == "spell" or trigger.kind == "item" then
		return trigger;
	elseif trigger.kind == "macro" then
		local index = GetMacroIndexByName(trigger.name);
		if not index or index == 0 then
			return nil;
		end
		local spellID = GetMacroSpell(index);
		if spellID then
			return { kind = "spell", id = spellID, name = C_Spell.GetSpellName(spellID) };
		end
		local _, itemLink = GetMacroItem(index);
		local itemID = itemLink and C_Item.GetItemInfoInstant(itemLink);
		if itemID then
			return { kind = "item", id = itemID, name = C_Item.GetItemNameByID(itemID) };
		end
	end
	return nil;
end

-- A dropped action as a Tap, or nil if it can't be one. A toy counts as its item; a macro stays a macro, so
-- binding the gesture puts the macro itself on the crossbar and a tap runs it.
local function MakeTrigger(action)
	if action and action.kind == "toy" then
		return { kind = "item", id = action.id, name = action.name };
	end
	return ResolveTrigger(action) and action or nil;
end
ns.MakeTrigger = MakeTrigger;

-- How the secure code casts an action: SecureActionButton type, the attribute it reads, and the value.
local function GetCastSpec(action)
	if action.kind == "spell" then
		-- By name, so a ranked spell always casts the highest rank the character knows.
		local name = C_Spell.GetSpellName(action.id) or action.name;
		return "spell", "spell", name or action.id;
	elseif action.kind == "item" then
		return "item", "item", "item:" .. action.id;
	elseif action.kind == "toy" then
		return "toy", "toy", action.id;
	elseif action.kind == "mount" then
		local _, spellID = C_MountJournal.GetMountInfoByID(action.id);
		if spellID then
			return "spell", "spell", spellID;
		end
	elseif action.kind == "macro" then
		return "macro", "macro", action.name;
	end
	return nil;
end

-- Every slot key that should trigger this gesture. Ranked spells have one ID per rank, so any action slot
-- showing a spell with the trigger's name counts, as do the trigger's own ID and the highest known rank.
local function GetTriggerKeys(trigger)
	local keys = {};
	trigger = ResolveTrigger(trigger);
	if not trigger then
		return keys;
	elseif trigger.kind == "item" then
		keys["item:" .. trigger.id] = true;
		return keys;
	end
	keys["spell:" .. trigger.id] = true;
	local name = C_Spell.GetSpellName(trigger.id) or trigger.name;
	if name then
		local info = C_Spell.GetSpellInfo(name);
		if info and info.spellID then
			keys["spell:" .. info.spellID] = true;
		end
		for slot = 1, MAX_ACTION_SLOT do
			local kind, id, subType = GetActionInfo(slot);
			if kind == "macro" then
				kind = subType;
			end
			if kind == "spell" and id and C_Spell.GetSpellName(id) == name then
				keys["spell:" .. id] = true;
			end
		end
	end
	return keys;
end

-------------------------------------------------------------------------------
-- Crossbar buttons
-------------------------------------------------------------------------------

local function GetPageUnit()
	return GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit;
end

-- The crossbar buttons that hold bindable actions: the top bar's left cluster (its right cluster is
-- Interact/Inspect/Back/Jump), all eight buttons of the left, right and bottom bars, and the stance and
-- possess bars that can take over one of those bars' slots.
local function GetCrossbarButtons()
	local pageUnit = GetPageUnit();
	local bars = pageUnit and pageUnit.actionBars;
	if not bars then
		return {};
	end

	local buttons = {};
	local layout = { { "topBar", 4 }, { "leftBar", 8 }, { "rightBar", 8 }, { "bottomBar", 8 }, { "stanceBar", 8 }, { "possessBar", 8 } };
	for _, entry in ipairs(layout) do
		local barKey, count = entry[1], entry[2];
		local bar = bars[barKey];
		for index = 1, count do
			local button = bar and bar.GetActionButtonByIndex and bar:GetActionButtonByIndex(index);
			-- Only standard action buttons; the possess bar uses pet buttons.
			if button and button.GetAttribute and button:GetAttribute("type") == "action" then
				table.insert(buttons, { button = button, bar = barKey, index = index });
			end
		end
	end
	return buttons;
end
ns.GetCrossbarButtons = GetCrossbarButtons;

local wrapped = {};
ns.wrapped = wrapped;
local function WrapCrossbarButtons()
	for _, info in ipairs(GetCrossbarButtons()) do
		if not wrapped[info.button] then
			local ok, err = pcall(SecureHandlerWrapScript, info.button, "OnClick", header, PRE_CLICK, POST_CLICK);
			if ok then
				wrapped[info.button] = true;
			else
				Print(("could not hook %s button %d: %s"):format(info.bar, info.index, tostring(err)));
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Gesture icons and names on the crossbar
-------------------------------------------------------------------------------

-- A gesture with its own icon or name shows it on every crossbar button that holds its Tap: the icon in the
-- button's icon, the name in the text line macros use. Whenever Blizzard sets either we set ours over it, in
-- hooksecurefunc post-hooks so Blizzard's code stays untainted; the icon's mask, cooldown and usable / range
-- colouring stay Blizzard's. Out-of-combat changes to gestures are applied with RefreshCrossbarLabels.
local gestureKeyOwners = {}; -- "spell:<id>" / "item:<id>" -> gesture index, from the last Publish
local regionButtons = {}; -- crossbar button icon texture / name font string -> its button
local shownIcons, shownNames = {}, {}; -- crossbar button -> the gesture icon / name we put on it
local settingRegion = false;

local function GetButtonSlot(button)
	return button.action or button:GetID();
end

local function GetSlotGesture(slot)
	local kind, id, subType = GetActionInfo(slot);
	if kind == "macro" then
		kind = subType;
	end
	local index = kind and id and gestureKeyOwners[kind .. ":" .. id];
	return index and DB().gestures[index];
end

local function SetRegion(region, method, value)
	settingRegion = true;
	region[method](region, value);
	settingRegion = false;
end

local function OnIconSet(texture)
	if settingRegion then
		return;
	end
	local button = regionButtons[texture];
	local gesture = GetSlotGesture(GetButtonSlot(button));
	shownIcons[button] = gesture and gesture.icon;
	if shownIcons[button] then
		SetRegion(texture, "SetTexture", shownIcons[button]);
	end
end

local function OnNameSet(fontString)
	if settingRegion then
		return;
	end
	local button = regionButtons[fontString];
	local gesture = GetSlotGesture(GetButtonSlot(button));
	shownNames[button] = gesture and gesture.name;
	if shownNames[button] then
		SetRegion(fontString, "SetText", shownNames[button]);
	end
end

local function RefreshCrossbarLabels()
	local any = false;
	for _, gesture in ipairs(DB().gestures) do
		any = any or gesture.icon ~= nil or gesture.name ~= nil;
	end
	if any then
		for _, info in ipairs(GetCrossbarButtons()) do
			local button = info.button;
			if button.icon and not regionButtons[button.icon] then
				regionButtons[button.icon] = button;
				hooksecurefunc(button.icon, "SetTexture", OnIconSet);
			end
			if button.Name and not regionButtons[button.Name] then
				regionButtons[button.Name] = button;
				hooksecurefunc(button.Name, "SetText", OnNameSet);
			end
		end
	end
	for region, button in pairs(regionButtons) do
		local slot = GetButtonSlot(button);
		local gesture = GetSlotGesture(slot);
		if region == button.icon then
			local icon = gesture and gesture.icon;
			if icon then
				SetRegion(region, "SetTexture", icon);
			elseif shownIcons[button] then
				-- No longer a gesture with an icon: back to the action's own.
				SetRegion(region, "SetTexture", C_ActionBar.GetActionTexture(slot));
			end
			shownIcons[button] = icon;
		else
			local name = gesture and gesture.name;
			if name then
				SetRegion(region, "SetText", name);
			elseif shownNames[button] then
				SetRegion(region, "SetText", C_ActionBar.UsesActionText(slot) and C_ActionBar.GetActionText(slot) or "");
			end
			shownNames[button] = name;
		end
	end
end
ns.RefreshCrossbarLabels = RefreshCrossbarLabels;

-- Totem Commands wraps the same buttons; both acting on one press would cast twice.
local function IsTotemCommandsActive()
	return TotemCommandsHeader ~= nil and TotemCommandsHeader:GetAttribute("enabled") == true;
end
ns.IsTotemCommandsActive = IsTotemCommandsActive;

-- Totem Commands, the shaman-only addon Gesture Commands grew out of, is one fixed gesture. Switching moves
-- it over: that gesture (unless there already is one on Call of the Elements), its hold lengths, and Totem
-- Commands turned off through its own command. Spells by name for the rank the character knows, with the
-- IDs for other languages.
local TOTEM_SPELLS = {
	trigger = { 66842, "Call of the Elements" },
	hold = { 36936, "Totemic Recall" },
	long = { 437009, "Totemic Call" },
};

local function GetTotemSpell(mode)
	local id, name = TOTEM_SPELLS[mode][1], TOTEM_SPELLS[mode][2];
	local info = C_Spell.GetSpellInfo(name);
	id = info and info.spellID or id;
	name = C_Spell.GetSpellName(id) or name;
	return { kind = "spell", id = id, name = name };
end

-------------------------------------------------------------------------------
-- Publishing: configuration -> secure header attributes (out of combat only)
-------------------------------------------------------------------------------

local publishedAttributes = {};

local function SetPublished(name, value)
	header:SetAttribute(name, value);
	publishedAttributes[name] = true;
end

-- Returns false if it has to wait for combat to end.
local function Publish()
	if InCombatLockdown() then
		ns.pendingPublish = true;
		return false;
	end
	ns.pendingPublish = false;

	for name in pairs(publishedAttributes) do
		header:SetAttribute(name, nil);
	end
	wipe(publishedAttributes);

	ns.conflicts = {};
	local owner = {};
	gestureKeyOwners = owner;
	for index, gesture in ipairs(DB().gestures) do
		if gesture.trigger then
			for key in pairs(GetTriggerKeys(gesture.trigger)) do
				if owner[key] and owner[key] ~= index then
					ns.conflicts[index] = owner[key];
				end
				owner[key] = index;
				SetPublished("g:" .. key, index);
			end
			for _, mode in ipairs(MODES) do
				local action = gesture[mode];
				local actionType, attribute, value;
				if action then
					actionType, attribute, value = GetCastSpec(action);
				end
				if actionType then
					local prefix = "g" .. index .. "-" .. mode .. "-";
					SetPublished(prefix .. "type", actionType);
					SetPublished(prefix .. "attr", attribute);
					SetPublished(prefix .. "value", value);
				end
			end
		end
	end

	-- On unless the player turned it off; buttons are only hooked once there is a gesture to act on.
	local enabled = DB().enabled ~= false and not IsTotemCommandsActive();
	if enabled and #DB().gestures > 0 then
		WrapCrossbarButtons();
	end
	header:SetAttribute("holdTicks", GetHoldTicks());
	header:SetAttribute("hold2Ticks", GetHold2Ticks());
	header:SetAttribute("debug", DB().debug == true);
	header:SetAttribute("enabled", enabled);
	RefreshCrossbarLabels();
	if ns.OnPublished then
		ns.OnPublished();
	end
	return true;
end
ns.Publish = Publish;

function ns.SetEnabled(enabled)
	if InCombatLockdown() then
		Print("can't change this in combat.");
		return false;
	end
	if enabled and IsTotemCommandsActive() then
		Print("Totem Commands is on and uses the same buttons. Type /totemcommands off first.");
		return false;
	end
	DB().enabled = enabled;
	Publish();
	return true;
end

-------------------------------------------------------------------------------
-- Gestures
-------------------------------------------------------------------------------

-- A gesture's name and icon, if chosen, label it in the setup window and on the crossbar buttons that hold
-- its Tap action (RefreshCrossbarLabels).
local NAME_LENGTH = 16;
local QUESTION_MARK_ICON = 134400; -- "automatic": the Tap action's icon

local function TruncateUTF8(text, maxChars)
	local out, count = {}, 0;
	for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		count = count + 1;
		if count > maxChars then
			break;
		end
		table.insert(out, char);
	end
	return table.concat(out);
end

function ns.GetGestureName(gesture)
	if gesture.name and gesture.name ~= "" then
		return gesture.name;
	end
	local triggerName = GetActionDisplay(gesture.trigger);
	return TruncateUTF8(triggerName or "Gesture", NAME_LENGTH);
end

function ns.GetGestureIcon(gesture)
	if gesture.icon then
		return gesture.icon;
	end
	local _, icon = GetActionDisplay(gesture.trigger);
	return icon or QUESTION_MARK_ICON;
end

function ns.AddGesture(gesture)
	gesture = gesture or {};
	table.insert(DB().gestures, gesture);
	Publish();
	return #DB().gestures;
end

function ns.RemoveGesture(index)
	table.remove(DB().gestures, index);
	Publish();
end

function ns.SetGestureAction(index, mode, action)
	local gesture = DB().gestures[index];
	if not gesture then
		return;
	end
	gesture[mode] = action;
	Publish();
end

-- An empty name or nil icon goes back to the Tap action's.
function ns.SetGestureNameIcon(index, name, icon)
	local gesture = DB().gestures[index];
	if not gesture then
		return;
	end
	name = name and strtrim(name) or "";
	gesture.name = name ~= "" and TruncateUTF8(name, NAME_LENGTH) or nil;
	gesture.icon = (icon and icon ~= QUESTION_MARK_ICON) and icon or nil;
	RefreshCrossbarLabels();
	if ns.OnPublished then
		ns.OnPublished();
	end
end

-- Place mode, for controllers: there is no way to drop a cursor action on the crossbar with a gamepad, so
-- the next crossbar press (caught and swallowed by the secure hook) picks the slot, and the gesture's Tap
-- action is put there out of combat. Times out if no crossbar button is pressed; the setup window shows a banner
-- meanwhile (ns.OnPlacingChanged).
local PLACE_TIMEOUT = 60;
local placing = nil; -- { index = gesture index, token = unique id, endsAt = GetTime() deadline, expired = bool }

function ns.IsPlacing()
	return placing ~= nil;
end

local function NotifyPlacing()
	if ns.OnPlacingChanged then
		ns.OnPlacingChanged(placing and DB().gestures[placing.index], placing and placing.endsAt);
	end
end

function ns.CancelPlacing(quiet)
	if not placing or InCombatLockdown() then
		return;
	end
	placing = nil;
	header:SetAttribute("placing", false);
	header:SetAttribute("placeSlot", nil);
	NotifyPlacing();
	if not quiet then
		Print("bind cancelled (no crossbar button pressed).");
	end
end

function ns.StartPlacing(index)
	if InCombatLockdown() then
		Print("can't place actions in combat.");
		return false;
	end
	local gesture = DB().gestures[index];
	if not (gesture and gesture.trigger) then
		Print("choose this gesture's Tap first.");
		return false;
	end
	if not ResolveTrigger(gesture.trigger) then
		Print(("this gesture's Tap (%s) isn't available any more - choose it again."):format(tostring(GetActionDisplay(gesture.trigger))));
		return false;
	end
	WrapCrossbarButtons();
	local token = {};
	placing = { index = index, token = token, endsAt = GetTime() + PLACE_TIMEOUT };
	header:SetAttribute("placeSlot", nil);
	header:SetAttribute("placing", true);
	UIErrorsFrame:AddMessage(("Press the crossbar button for %s"):format(ns.GetGestureName(gesture)), 0.2, 1, 0.6);
	NotifyPlacing();
	C_Timer.After(PLACE_TIMEOUT, function()
		if placing and placing.token == token then
			-- Can't change the secure state in combat: cancel when it ends.
			if InCombatLockdown() then
				placing.expired = true;
			else
				ns.CancelPlacing();
			end
		end
	end);
	return true;
end

-- Called by the feedback poll when the secure hook has reported a slot.
local function FinishPlacing(slot)
	local index = placing and placing.index;
	local gesture = index and DB().gestures[index];
	placing = nil;
	header:SetAttribute("placeSlot", nil);
	NotifyPlacing();
	if not (gesture and ns.PickupGesture(index)) then
		return;
	end
	(C_ActionBar.PutActionInSlot or PlaceAction)(slot);
	ClearCursor();
	if GetActionInfo(slot) then
		UIErrorsFrame:AddMessage(("%s placed"):format(ns.GetGestureName(gesture)), 0.2, 1, 0.6);
		if C_GamePad and C_GamePad.SetVibration then
			C_GamePad.SetVibration("Low", RUMBLE_INTENSITY);
			C_Timer.After(RUMBLE_TIME, function() C_GamePad.StopVibration(); end);
		end
	else
		Print("couldn't place the gesture on that slot.");
	end
end
ns.FinishPlacing = FinishPlacing;

-- Puts the gesture's Tap action on the cursor so it can be dropped on a crossbar slot; that slot then has
-- the gesture. Ranked spells use the highest rank the character knows; a macro Tap is the macro itself.
function ns.PickupGesture(index)
	if InCombatLockdown() then
		Print("can't place actions in combat.");
		return false;
	end
	local gesture = DB().gestures[index];
	local trigger = gesture and gesture.trigger;
	if not trigger then
		Print("choose this gesture's Tap first.");
		return false;
	end
	if trigger.kind == "macro" then
		local macroIndex = GetMacroIndexByName(trigger.name);
		if not macroIndex or macroIndex == 0 then
			Print(("the macro %s doesn't exist any more - choose this gesture's Tap again."):format(tostring(trigger.name)));
			return false;
		end
		PickupMacro(macroIndex);
	elseif trigger.kind == "item" then
		C_Item.PickupItem(trigger.id);
	else
		local name = C_Spell.GetSpellName(trigger.id) or trigger.name;
		local best = name and C_Spell.GetSpellInfo(name);
		C_Spell.PickupSpell(best and best.spellID or trigger.id);
	end
	return true;
end


-- Before 0.10 the addon made a character macro for every gesture ("/cast <Tap>" or "/use item:<id>").
-- Remove the ones that are still exactly that, after putting the Tap itself on any action slot that held
-- one so bound gestures keep working. A macro the player has edited is left alone. Out of combat only;
-- returns false to be retried.
local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120;

local function RemoveOldGestureMacros()
	if InCombatLockdown() then
		return false;
	end
	local removed = 0;
	for index, gesture in ipairs(DB().gestures) do
		local name, trigger = gesture.macro, gesture.trigger;
		gesture.macro = nil;
		local macroIndex = name and GetMacroIndexByName(name);
		if macroIndex and macroIndex > MAX_ACCOUNT_MACROS and trigger and (trigger.kind == "spell" or trigger.kind == "item") then
			local _, _, body = GetMacroInfo(macroIndex);
			local madeBody = trigger.kind == "item" and ("/use item:" .. trigger.id)
				or ("/cast " .. (C_Spell.GetSpellName(trigger.id) or trigger.name or ""));
			if body and strtrim(body) == madeBody then
				for slot = 1, MAX_ACTION_SLOT do
					if GetActionInfo(slot) == "macro" and GetActionText(slot) == name and ns.PickupGesture(index) then
						(C_ActionBar.PutActionInSlot or PlaceAction)(slot);
						ClearCursor();
					end
				end
				DeleteMacro(macroIndex);
				removed = removed + 1;
			end
		end
	end
	if removed > 0 then
		Print(("removed %d macro%s that earlier versions made for your gestures; action slots that held them now hold the Tap itself."):format(
			removed, removed == 1 and "" or "s"));
	end
	return true;
end

function ns.SwitchFromTotemCommands()
	if InCombatLockdown() then
		Print("can't switch in combat.");
		return false;
	end
	local trigger = GetTotemSpell("trigger");
	local index;
	for existing, gesture in ipairs(DB().gestures) do
		local shown = ResolveTrigger(gesture.trigger);
		if shown and shown.kind == "spell" and C_Spell.GetSpellName(shown.id) == trigger.name then
			index = existing;
		end
	end
	if not index then
		table.insert(DB().gestures, { trigger = trigger, hold = GetTotemSpell("hold"), long = GetTotemSpell("long") });
		index = #DB().gestures;
	end
	local totemDB = TotemCommandsDB;
	if totemDB then
		DB().holdTicks = DB().holdTicks or totemDB.holdTicks;
		DB().hold2Ticks = DB().hold2Ticks or totemDB.hold2Ticks;
	end
	if SlashCmdList.TOTEMCOMMANDS then
		SlashCmdList.TOTEMCOMMANDS("off");
	end
	DB().enabled = true;
	Publish();
	Print(IsTotemCommandsActive() and "couldn't turn Totem Commands off - type /totemcommands off."
		or "switched: your totem gesture is set up here, and Totem Commands is off (you can remove it).");
	return index;
end

-------------------------------------------------------------------------------
-- Feedback and debug
-------------------------------------------------------------------------------

local function Rumble()
	if C_GamePad and C_GamePad.SetVibration then
		C_GamePad.SetVibration("Low", RUMBLE_INTENSITY);
		C_Timer.After(RUMBLE_TIME, function() C_GamePad.StopVibration(); end);
	end
end

-- Read-only poll of the secure hold stage (and, in debug mode, of the secure hook's activity).
local lastStage, lastDebugSeq = 0, 0;
local feedback = CreateFrame("Frame");
feedback:SetScript("OnUpdate", function()
	local placeSlot = header:GetAttribute("placeSlot");
	if placeSlot and ns.IsPlacing() and not InCombatLockdown() then
		ns.FinishPlacing(placeSlot);
	end

	local debugSeq = header:GetAttribute("debugSeq") or 0;
	if debugSeq ~= lastDebugSeq then
		lastDebugSeq = debugSeq;
		Print("secure hook ran: " .. tostring(header:GetAttribute("debugLast")));
	end

	local stage = header:GetAttribute("armed") or 0;
	if stage ~= lastStage and stage > 0 then
		local gesture = DB() and DB().gestures[header:GetAttribute("armedGesture") or 0];
		local name = GetActionDisplay(gesture and gesture[MODES[stage]]);
		Rumble();
		if stage == 2 then
			C_Timer.After(DOUBLE_RUMBLE_GAP, Rumble);
		end
		UIErrorsFrame:AddMessage("Release for " .. (name or ns.MODE_LABELS[MODES[stage]]), 0.2, 1, 0.6);
	end
	lastStage = stage;
end);

local function GetBarName(bar)
	local pageUnit = GetPageUnit();
	for key, candidate in pairs(pageUnit and pageUnit.actionBars or {}) do
		if candidate == bar then
			return key;
		end
	end
	return tostring(bar);
end

local function OnPressActionButton(_, index, _, down)
	if not (down and DB() and DB().debug) then
		return;
	end
	local pageUnit = GetPageUnit();
	local bar = pageUnit and pageUnit:GetActiveBar();
	local button = bar and bar.GetActionButtonByIndex and bar:GetActionButtonByIndex(index);
	local slot = button and button:GetID();
	local kind, id, subType = GetActionInfo(slot or 0);
	Print(("press: button %d on %s, hooked=%s, slot=%s, action=%s %s %s"):format(index, GetBarName(bar),
		tostring(button and wrapped[button] == true), tostring(slot), tostring(kind), tostring(id), tostring(subType or "")));
end

function ns.RunTest()
	local db = DB();
	Print(("%d gesture(s); %s; hold %d ticks, long hold %d ticks (about 0.2 s each)."):format(#db.gestures,
		header:GetAttribute("enabled") and "on" or "off", GetHoldTicks(), GetHold2Ticks()));
	if IsTotemCommandsActive() then
		Print("Totem Commands is on - turn it off (/totemcommands off) to use Gesture Commands.");
	end
	for index, gesture in ipairs(db.gestures) do
		local parts = {};
		for _, mode in ipairs({ "trigger", "hold", "long" }) do
			table.insert(parts, ns.MODE_LABELS[mode] .. ": " .. tostring((GetActionDisplay(gesture[mode])) or "-"));
		end
		local slots = 0;
		if gesture.trigger then
			local keys = GetTriggerKeys(gesture.trigger);
			for _, info in ipairs(GetCrossbarButtons()) do
				local kind, id, subType = GetActionInfo(info.button:GetID());
				if kind == "macro" then
					kind = subType;
				end
				if kind and id and keys[kind .. ":" .. id] then
					slots = slots + 1;
				end
			end
		end
		Print(("%d. %s  (on %d crossbar slot%s of this page)%s"):format(index, table.concat(parts, ", "), slots,
			slots == 1 and "" or "s", ns.conflicts and ns.conflicts[index] and " - same Tap as another gesture!" or ""));
	end
	local start = header:GetAttribute("tickcount") or 0;
	C_Timer.After(2, function()
		local ticks = (header:GetAttribute("tickcount") or 0) - start;
		Print(("secure ticks: %d in 2 s (%s)"):format(ticks, ticks >= 4 and "working" or "NOT working - please report"));
	end);
end

-------------------------------------------------------------------------------
-- Events and slash command
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame");
frame:RegisterEvent("ADDON_LOADED");
frame:RegisterEvent("PLAYER_LOGIN");
frame:RegisterEvent("PLAYER_ENTERING_WORLD");
frame:RegisterEvent("PLAYER_REGEN_ENABLED");
frame:RegisterEvent("SPELLS_CHANGED");
frame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS");
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED");
-- The "blocked from an action" dialog doesn't say which function; report it so problems can be traced.
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN");
frame:RegisterEvent("ADDON_ACTION_BLOCKED");
frame:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_ACTION_FORBIDDEN" or event == "ADDON_ACTION_BLOCKED" then
		local addonName, functionName = ...;
		if addonName == ADDON_NAME then
			Print(("Blizzard blocked %s (%s) - please report this."):format(tostring(functionName),
				event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked in combat"));
		end
		return;
	end
	if event == "PLAYER_REGEN_ENABLED" and placing and placing.expired then
		-- A bind that ran out in combat.
		ns.CancelPlacing();
	end
	-- Action slots are known once the world is entered.
	if (event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED") and not self.oldMacrosChecked then
		self.oldMacrosChecked = RemoveOldGestureMacros();
	end
	if event == "ADDON_LOADED" then
		if ... == ADDON_NAME then
			GestureCommandsCharDB = GestureCommandsCharDB or {};
			GestureCommandsCharDB.gestures = GestureCommandsCharDB.gestures or {};
		end
	elseif event == "PLAYER_LOGIN" then
		self.loggedIn = true;
		RegisterStateDriver(header, "tick", "tock");
		if GamepadMainActionBarFrame and GamepadMainActionBarFrame.PressActionButton then
			hooksecurefunc(GamepadMainActionBarFrame, "PressActionButton", OnPressActionButton);
		end
		-- Give Blizzard's gamepad bars a frame to finish their own setup first.
		C_Timer.After(0, Publish);
	elseif self.loggedIn then
		-- Spells learned, slots changed, forms changed or combat ended: republish (debounced, out of combat).
		if not self.publishQueued then
			self.publishQueued = true;
			C_Timer.After(0.5, function()
				self.publishQueued = false;
				Publish();
			end);
		end
	end
end);

SLASH_GESTURECOMMANDS1 = "/gestures";
SLASH_GESTURECOMMANDS2 = "/gesturecommands";
SlashCmdList.GESTURECOMMANDS = function(msg)
	msg = strtrim(msg or ""):lower();
	local holdArg = msg:match("^hold%s+(%d+)$");
	local hold2Arg = msg:match("^hold2%s+(%d+)$");
	if msg == "" then
		if ns.ToggleConfig then
			ns.ToggleConfig();
		end
	elseif msg == "test" then
		ns.RunTest();
	elseif msg == "on" or msg == "off" then
		if ns.SetEnabled(msg == "on") then
			Print(msg == "on" and "on." or "off - crossbar buttons behave normally.");
		end
	elseif msg == "minimap" then
		if ns.ToggleMinimapButton then
			ns.ToggleMinimapButton();
		end
	elseif msg == "padnav own" or msg == "padnav blizzard" then
		DB().ownNavigation = msg == "padnav own" or nil;
		if ns.CloseConfig then
			ns.CloseConfig();
		end
		Print(DB().ownNavigation and "the window now uses its own controller navigation (D-pad, A, B, X; LT / RT don't reach it)."
			or "the window now uses the game's controller navigation (LT / RT, View, A, B).");
	elseif msg == "debug" or holdArg or hold2Arg then
		if InCombatLockdown() then
			Print("can't change this in combat.");
			return;
		end
		if msg == "debug" then
			DB().debug = not DB().debug;
			Print("debug output " .. (DB().debug and "on." or "off."));
		elseif holdArg then
			local ticks = tonumber(holdArg);
			if ticks < MIN_HOLD_TICKS or ticks > MAX_HOLD_TICKS then
				Print(("hold must be %d to %d ticks (about 0.2 s each)."):format(MIN_HOLD_TICKS, MAX_HOLD_TICKS));
				return;
			end
			DB().holdTicks = ticks;
			Print(("hold: %d ticks."):format(ticks));
		else
			local ticks = tonumber(hold2Arg);
			if ticks < GetHoldTicks() + 2 or ticks > MAX_HOLD2_TICKS then
				Print(("hold2 must be %d to %d ticks."):format(GetHoldTicks() + 2, MAX_HOLD2_TICKS));
				return;
			end
			DB().hold2Ticks = ticks;
			Print(("long hold: %d ticks."):format(ticks));
		end
		Publish();
	else
		Print("/gestures opens the window. Also: on, off, test, debug, hold <n>, hold2 <n>, minimap, padnav own|blizzard.");
	end
end;
