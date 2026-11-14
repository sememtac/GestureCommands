-- UI tests: the setup window, action picker, navigation (Blizzard's gamepad UI and our own), bind banner,
-- minimap button, addon compartment and the menu dial entry, against a fake engine.
-- Run: tests/run.ps1 (or luajit tests/ui_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
local H = dofile(lib .. "harness.lua")
local world = dofile(lib .. "world.lua").new()
local W = world.W
local check, fire, runTimers = H.check, world.fire, world.runTimers
world.time = 100

-- The UI's files (the engine is faked below).
local function isUIFile(file)
	return file:match("^UI/") ~= nil
end
local function templateUsed(name)
	for _, f in ipairs(W.frames) do if W.hasTemplate(f.template, name) then return true end end
	return false
end

-- ---- poison: nothing may touch Blizzard's gamepad UI or icon provider ----------------------------------
local touched = {}
local function poison(name)
	return setmetatable({}, { __index = function(_, k) touched[#touched + 1] = name .. "." .. tostring(k); return nil end,
		__newindex = function(_, k) touched[#touched + 1] = name .. "." .. tostring(k) .. "=" end })
end
local managerCalls = {}
local function record(name) return function(_, ...) managerCalls[#managerCalls + 1] = { name, ... } end end
local shownFrames = {}
local refuse = false -- the wrapper refusing a call (combat restriction): no effect, no result, no error
local function indexOf(f) for i, v in ipairs(shownFrames) do if v == f then return i end end end
local function show(f) if indexOf(f) then return false end; shownFrames[#shownFrames + 1] = f; return true end
local function hide(f) local i = indexOf(f); if not i then return false end; table.remove(shownFrames, i); return true end
local function wrapped(name, fn, returnsNothing)
	return function(self, f, ...)
		managerCalls[#managerCalls + 1] = { name, f, ... }
		if refuse then return end
		local result = fn(f)
		if not returnsNothing then return result end
	end
end
local managerMethods = {
	FrameShown = wrapped("FrameShown", show), FrameHidden = wrapped("FrameHidden", hide),
	HandlePopupShown = wrapped("HandlePopupShown", show, true), HandlePopupHide = wrapped("HandlePopupHide", hide, true),
	shownFrames = shownFrames,
}
local manager = setmetatable({}, { __index = function(_, k)
	if managerMethods[k] then return managerMethods[k] end
	touched[#touched + 1] = "FrameControlsManager." .. tostring(k)
end, __newindex = function(_, k) touched[#touched + 1] = "FrameControlsManager." .. tostring(k) .. "=" end })
GamepadMode = setmetatable({}, { __index = function(_, k)
	if k == "FrameControlsManager" then return manager end
	touched[#touched + 1] = "GamepadMode." .. tostring(k)
end, __newindex = function(_, k) touched[#touched + 1] = "GamepadMode." .. tostring(k) .. "=" end })
SmartNavigation = setmetatable({}, { __index = function(_, k)
	if k == "RefreshButtonGroups" then return record("RefreshButtonGroups") end
	touched[#touched + 1] = "SmartNavigation." .. tostring(k)
end, __newindex = function(_, k) touched[#touched + 1] = "SmartNavigation." .. tostring(k) .. "=" end })
local style = 1
Enum_InputDeviceInterfaceType = { Mkb = 0, Gamepad = 1 }
C_InputInterfaceStyle = { GetCurrentStyle = function() return style end }
InputUtil = poison("InputUtil")
IconDataProviderMixin = poison("IconDataProviderMixin")
GamepadSharedUtility = poison("GamepadSharedUtility")


-- ---- the rest of the game the UI reads -------------------------------------------------------------
Minimap = CreateFrame("Frame", "Minimap")
Minimap.width, Minimap.center, Minimap.scale = 140, { 1000, 700 }, 2
local cursorX, cursorY = 0, 0
function GetCursorPosition() return cursorX, cursorY end
local errors = world.messages
local settingsPanel
Settings = { RegisterCanvasLayoutCategory = function(panel, name) settingsPanel = panel; return { name = name } end, RegisterAddOnCategory = function() end }
function geterrorhandler() return function(e) error(e) end end

-- game data for the picker
Enum = { InputDeviceInterfaceType = Enum_InputDeviceInterfaceType, SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 } }
local book = {
	{ itemType = 1, name = "Lightning Bolt", spellID = 403, iconID = 1001 },
	{ itemType = 1, name = "Lightning Bolt", spellID = 529, iconID = 1001 }, -- rank 2
	{ itemType = 1, name = "Healing Wave", spellID = 331, iconID = 1002 },
	{ itemType = 1, name = "Ancestral Knowledge", spellID = 17485, iconID = 1003, isPassive = true },
	{ itemType = 2, name = "Chain Lightning", spellID = 421, iconID = 1004 },
	{ itemType = 1, name = "Call of the Elements", spellID = 66842, iconID = 1005 },
	{ itemType = 1, name = "Totemic Recall", spellID = 36936, iconID = 1006 },
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end,
	GetSpellBookItemInfo = function(i) return book[i] end,
}
C_Item = {
	GetItemSpell = function(id) if id == 5512 or id == 6948 then return "Use", 1 end end,
	GetItemNameByID = function(id) return ({ [5512] = "Healthstone", [6948] = "Hearthstone", [2589] = "Linen Cloth" })[id] end,
	GetItemIconByID = function(id) return 2000 + id end,
}
function GetInventoryItemID() return nil end
function GetInventoryItemTexture() return nil end
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and 3 or 0 end,
	GetContainerItemInfo = function(bag, slot) return ({ { itemID = 5512, iconFileID = 3001 }, { itemID = 2589, iconFileID = 3002 }, { itemID = 6948, iconFileID = 3003 } })[slot] end,
}
C_MountJournal = {
	GetMountIDs = function() return { 6, 7 } end,
	GetMountInfoByID = function(id) if id == 6 then return "Brown Horse", 458, 4001, false, true, 0, false, false, nil, false, true end
		return "Not Mine", 1, 4002, false, true, 0, false, false, nil, false, false end,
}
function GetNumMacros() return 1, 1 end
local macros = { [1] = { "Mount Up", 5001 }, [121] = { "Totems", 5002 } }
function GetMacroInfo(i) local m = macros[i]; if m then return m[1], m[2] end end
function GetMacroIcons(t) for i = 1, 100 do t[#t + 1] = 6000 + i end end
function GetLooseMacroIcons(t) t[#t + 1] = "INV_Misc_Loose" end
GetLooseMacroItemIcons = nil
function GetMacroItemIcons(t) t[#t + 1] = 6001 end -- duplicate, deduped
function GetFileIDFromPath(path) if path == "Interface\\Icons\\INV_Misc_Loose" then return 7777 end end

SPELL_ICONS = {}; for _, spell in ipairs(book) do SPELL_ICONS[spell.spellID] = spell.iconID end

-- ---- fake engine ----------------------------------------------------------------------------------
local db = { gestures = {} }
local calls = {}
-- Core is shared and real; the engine is fake.
local ns = {}
H.loadAddon(ns, function(file) return file:match("^Core/") ~= nil and file ~= "Core/DB.lua" end)
for k, v in pairs({
	MODE_LABELS = { trigger = "Tap", hold = "Hold", long = "Long hold" },
	conflicts = {},
	DB = function() return db end,
	GetHoldTicks = function() return db.holdTicks or 3 end,
	GetHold2Ticks = function() return db.hold2Ticks or 7 end,
	IsTotemCommandsActive = function() return TOTEM_ACTIVE == true end,
	SwitchFromTotemCommands = function() SWITCH_CALLS = (SWITCH_CALLS or 0) + 1; TOTEM_ACTIVE = false; return 1 end,
	Print = function(m) calls[#calls + 1] = "print:" .. m end,
	GetActionDisplay = function(a) if a then return a.name or (a.kind .. tostring(a.id)), SPELL_ICONS[a.id] or 99 end end,
	GetGestureName = function(g) return g.name or (g.trigger and g.trigger.name) or "Gesture" end,
	GetGestureIcon = function(g) return g.icon or 99 end,
	ReadCursor = function() local c = world.cursor; if c then return c.action, c[1] end end,
	MakeTrigger = function(a) local ok = { spell = true, item = true, toy = true, mount = true, macro = true }; if ok[a.kind] then return a end end,
	Publish = function() calls[#calls + 1] = "publish"; if ns.OnPublished then ns.OnPublished() end end,
	RunTest = function() calls[#calls + 1] = "test" end,
}) do ns[k] = v end
function ns.AddGesture(g) table.insert(db.gestures, g or {}); ns.Publish(); return #db.gestures end
function ns.RemoveGesture(i) table.remove(db.gestures, i); ns.Publish() end
function ns.SetGestureAction(i, mode, a) db.gestures[i][mode] = a; ns.Publish() end
function ns.SetGestureNameIcon(i, name, icon) calls[#calls + 1] = ("nameicon:%d:%s:%s"):format(i, name, tostring(icon)); db.gestures[i].name = name; db.gestures[i].icon = icon ~= 134400 and icon or nil; ns.Publish() end
function ns.PickupGesture(i) calls[#calls + 1] = "pickup:" .. i; return true end
local placingNow = false
function ns.StartPlacing(i) calls[#calls + 1] = "place:" .. i; placingNow = true; return true end
function ns.IsPlacing() return placingNow end
function ns.CancelPlacing() calls[#calls + 1] = "cancelplace"; placingNow = false end
function ns.SetEnabled(v) if world.combat then return false end; db.enabled = v; ns.Publish(); return true end

local api = dofile(lib .. "engine_api.lua")
local missing = {}
for _, name in ipairs(api) do if ns[name] == nil then missing[#missing + 1] = name end end
check(#missing == 0, "the fake engine provides the whole engine API (" .. table.concat(missing, ", ") .. ")")
H.loadAddon(ns, isUIFile)
check(settingsPanel ~= nil, "Settings > AddOns entry registered")

local owner = GestureCommandsNavOwner
check(owner and owner.template == "SecureHandlerStateTemplate", "bindings owned by a secure frame")
check(world.R.drivers[owner] and world.R.drivers[owner].values == "[combat] 1; 0", "combat state driver registered")
check(owner.attrs["_onstate-combat"] and owner.attrs["_onstate-combat"]:find("ClearBindings"), "secure snippet drops the bindings in combat")

local findByText = W.findByText
local function click(text, ...) local b = findByText(text); assert(b, "no button " .. text); b:Click(...) end
local function lastCallMatching(pattern) for i = #calls, 1, -1 do if calls[i]:find(pattern) then return calls[i] end end end
local function bound() return world.overrides[owner] ~= nil end
local function press(command) GestureCommandsNavInput.scripts.OnClick(GestureCommandsNavInput, command, true) end
local function chooseTab(label) for _, tab in ipairs(GestureCommandsPicker.tabs) do if tab.text == label then tab:Click() end end end

-- ======== Part 1: our own navigation (/gestures padnav own) ========
db.ownNavigation = true
ns.ToggleConfig()
local frame = GestureCommandsFrame
check(frame and frame:IsShown() and UISpecialFrames[1] == "GestureCommandsFrame", "/gestures opens the window; Escape closes it")
check(bound(), "window open: D-pad, A, B, X bound")
local keys = world.overrides[owner]
check(keys.PADDUP == "CLICK GestureCommandsNavInput:UP" and keys.PADDDOWN and keys.PADDLEFT and keys.PADDRIGHT
	and keys.PAD1 == "CLICK GestureCommandsNavInput:A" and keys.PAD2 == "CLICK GestureCommandsNavInput:B" and keys.PAD3 == "CLICK GestureCommandsNavInput:X",
	"binding targets")
check(rawget(frame, "returnToPlayerControl") == nil, "no Blizzard gamepad focus fields on our frame")
check(findByText("Totems preset") == nil, "no class-specific preset")
check(not frame.Editor.Header.shown, "no gesture selected: name/icon header hidden")
check(frame.New.locked, "highlight starts on New gesture")

-- New gesture with A: highlight goes to its Tap slot.
press("A")
check(#db.gestures == 1 and frame.Editor.Header.shown, "A on New gesture creates one")
local slots = {}; for _, f in ipairs(W.frames) do if rawget(f, "mode") then slots[f.mode] = f end end
check(slots.trigger.locked and not frame.New.locked, "highlight moves to the Tap slot")
check(not frame.Editor.Header.Edit.enabled and not frame.Editor.Header.Bind.enabled, "name/icon and bind need a trigger first")

-- A on the empty Tap slot opens the action picker; spells listed once per name, no passives / future spells.
press("A")
local picker = GestureCommandsPicker
check(picker and picker:IsShown() and picker.Title.text == "Choose: Tap", "A on a slot opens the action picker")
check(picker.template:find("BasicFrameTemplateWithInset") and not templateUsed("IconSelectorPopupFrameTemplate"), "plain picker, not Blizzard's icon selector")
local function cellNames() local t = {}; for _, c in ipairs(picker.cells) do if c.shown and c.entry then t[#t + 1] = c.entry.name or tostring(c.entry.icon) end end; return table.concat(t, ",") end
check(cellNames() == "Lightning Bolt,Healing Wave,Call of the Elements,Totemic Recall", "spells: one per name, no passive or future spells (" .. cellNames() .. ")")
check(picker.cells[1].locked and not slots.trigger.locked, "picker highlight starts on the first entry")
check(not picker.Clear.shown and not picker.NameBox.shown, "empty slot: no Clear; action mode has no name box")
chooseTab("Items")
check(cellNames() == "Healthstone,Hearthstone", "items: only ones with a Use effect (" .. cellNames() .. ")")
chooseTab("Mounts")
check(cellNames() == "Brown Horse", "mounts: collected only")
chooseTab("Spells")
ns.Nav.Select(picker.cells[3])
press("A")
check(db.gestures[1].trigger and db.gestures[1].trigger.name == "Call of the Elements", "A on a spell assigns it")
check(not picker:IsShown(), "picker closes after choosing")
check(slots.trigger.locked and not picker.cells[3].locked, "highlight back on the slot")
check(bound(), "still bound with the window open")

-- Hold slot: macros tab excludes the gestures' own macros.
db.gestures[1].macro = "Totems"
ns.Nav.Select(slots.hold)
press("A")
chooseTab("Macros")
check(cellNames() == "Mount Up,Totems", "macros: all your macros are offered (" .. cellNames() .. ")")
chooseTab("Spells")
ns.Nav.Select(picker.cells[4])
press("A")
check(db.gestures[1].hold and db.gestures[1].hold.name == "Totemic Recall", "hold assigned from the picker")
press("X")
check(db.gestures[1].hold == nil, "X clears the highlighted slot")
-- Any macro (or mount) can be the Tap.
local spellTap = db.gestures[1].trigger
ns.Nav.Select(slots.trigger)
press("A")
chooseTab("Macros")
ns.Nav.Select(picker.cells[1])
press("A")
check(not picker:IsShown() and db.gestures[1].trigger.kind == "macro", "any macro can be the Tap")
db.gestures[1].trigger = spellTap
-- With an action in the slot: Clear offered; B cancels.
ns.Nav.Select(slots.trigger)
press("A")
check(picker:IsShown() and picker.Clear.shown, "slot with an action: Clear offered")
press("B")
check(not picker:IsShown() and frame:IsShown(), "B closes only the picker")
check(db.gestures[1].trigger.name == "Call of the Elements", "cancel keeps the trigger")

-- Mouse drop still works.
world.cursor = { "spell", 1, "spell", 36936, action = { kind = "spell", id = 36936, name = "Totemic Recall" } }
slots.hold:Click("LeftButton")
check(db.gestures[1].hold and db.gestures[1].hold.name == "Totemic Recall" and not picker:IsShown(), "mouse: dropping on a slot assigns it")
check(frame.Editor.Header.Edit.enabled and frame.Editor.Header.Bind.enabled, "trigger set: name/icon and bind enabled")
local listRow; for _, f in ipairs(W.frames) do if rawget(f, "Detail") and f.shown and f.Text.text then listRow = listRow or f end end
check(listRow and listRow.Text.text == "Call of the Elements" and listRow.Detail.text == "Totemic Recall / -",
	"list row: name, and Hold / Long hold on its own line (" .. tostring(listRow and listRow.Detail.text) .. ")")

-- Name & icon.
ns.Nav.Select(frame.Editor.Header.Edit)
press("A")
check(picker:IsShown() and picker.Title.text == "Name & icon" and picker.NameBox.shown and picker.Okay.shown and not picker.Clear.shown, "Name & icon opens the picker in icon mode")
check(picker.NameBox.text == "Call of the Elements", "name box starts with the gesture's name")
check(picker.cells[1].entry.icon == 134400 and picker.cells[1].Chosen.shown and picker.cells[1].locked, "automatic icon first, chosen and highlighted")
check(cellNames():find("^Automatic[^,]*,Call of the Elements,Totemic Recall,Lightning Bolt,Healing Wave$") ~= nil, "suggested: auto, the gesture's icons, then spellbook icons (" .. cellNames() .. ")")
ns.Nav.Select(picker.NameBox)
press("A")
check(picker.NameBox:HasFocus(), "A on the name box starts typing")
press("B")
check(not picker.NameBox:HasFocus() and picker:IsShown(), "B stops typing without closing")
picker.NameBox.text = "Totems"
ns.Nav.Select(picker.cells[4])
press("A")
check(picker.cells[4].Chosen.shown and not picker.cells[1].Chosen.shown, "A on an icon chooses it")
ns.Nav.Select(picker.Okay)
press("A")
check(lastCallMatching("^nameicon") == "nameicon:1:Totems:1001", "OK saves the new name and icon (" .. tostring(lastCallMatching("^nameicon")) .. ")")
check(not picker:IsShown(), "picker closes on OK")
check(frame.Editor.Header.Name.text == "Totems" and frame.Editor.Header.Icon.texture == 1001, "header shows the new name and icon")
-- All icons: paged, deduped, path icons saved as file IDs.
click("Name & icon")
chooseTab("All icons")
check(picker.PageText.text == "Page 1 / 3", "all icons paged 40 at a time (" .. tostring(picker.PageText.text) .. ")")
check(not picker.Previous.enabled and picker.Next.enabled, "pager bounds")
picker.Next:Click()
check(picker.PageText.text == "Page 2 / 3", "next page")
picker.Last:Click()
check(picker.PageText.text == "Page 3 / 3" and not picker.Next.enabled, ">> stops at the last page")
picker.First:Click()
ns.Nav.Select(picker.cells[2])
press("A")
check(picker.cells[2].entry.icon == "Interface\\Icons\\INV_Misc_Loose", "path icons shown by path")
picker.Okay:Click()
check(lastCallMatching("^nameicon") == "nameicon:1:Totems:7777", "path icon saved as its file ID")

-- Bind: controller A -> close and take the next crossbar press; mouse -> cursor.
local bindButton = frame.Editor.Header.Bind
check(not bindButton.template:find("Secure"), "Bind is a plain button (the window stays unprotected)")
bindButton:Click("LeftButton")
check(calls[#calls] == "pickup:1" and frame:IsShown(), "mouse: Bind puts the gesture on the cursor")
ns.Nav.Select(bindButton)
press("A")
check(calls[#calls] == "place:1" and not frame:IsShown(), "controller: Bind closes the window and takes the next crossbar press")
check(not bound(), "window closed: D-pad handed back to the crossbar")
frame:Show()
check(not placingNow, "reopening the window cancels binding")
-- The bind banner.
ns.OnPlacingChanged(db.gestures[1], 160)
local banner = findByText("Bind Totems: press its crossbar button")
banner = banner and banner.parent
check(banner and banner.shown, "bind banner names the gesture")
local function bannerPrompts() local out = {}; for _, e in ipairs(banner.Footer.entries) do if e.Label.shown then out[#out + 1] = e.Label.text end end; return table.concat(out, ",") end
check(bannerPrompts() == "+,+,/,Change page", "banner shows the page-change glyphs (" .. bannerPrompts() .. ")")
world.time = 105.5; banner.scripts.OnUpdate(banner)
check(banner.Hint.text == "Open /gestures to cancel.  55 s", "banner counts down (" .. tostring(banner.Hint.text) .. ")")
ns.OnPlacingChanged(nil)
check(not banner.shown, "banner hidden when the bind ends")
check(bound(), "reopening the window binds again")

-- B closes the window.
ns.Nav.Select(frame.New)
press("B")
check(not frame:IsShown() and not bound(), "B closes the window and releases the D-pad")
frame:Show()

-- Blizzard taking a key back: re-bound once, and no loop if it can't be won.
world.blizzardBindings = { PADDUP = "CLICK InputFunctionBindingButton_PADDUP:LeftButton" }
local before = #world.bindingLog
fire("UPDATE_BINDINGS")
fire("UPDATE_BINDINGS")
check(#world.timers == 1, "binding changes checked once per frame")
runTimers()
check(#world.bindingLog > before and lastCallMatching("^print:couldn't take over"), "keys taken back once; gives up with a message when that fails")
local after = #world.bindingLog
fire("UPDATE_BINDINGS")
runTimers()
check(#world.bindingLog == after, "no rebinding loop")
world.blizzardBindings = {}

-- Combat: the secure driver drops the bindings; nothing from addon code; back after combat.
world.combat = true
world.tick() -- the combat state driver runs the secure snippet
check(not bound(), "combat start: the secure driver drops the D-pad bindings")
local n = #world.bindingLog
fire("PLAYER_REGEN_DISABLED")
frame:Hide()
check(#world.bindingLog == n, "in combat: no binding calls from addon code (closing the window included)")
frame:Show()
check(#world.bindingLog == n and not bound(), "in combat: opening the window doesn't bind")
click("Name & icon")
check(not picker:IsShown() and calls[#calls]:find("in combat"), "name/icon refused in combat")
world.combat = false
world.tick()
fire("PLAYER_REGEN_ENABLED")
check(bound(), "after combat: window still open, D-pad bound again")
world.combat = true
world.tick()
fire("PLAYER_REGEN_DISABLED")
check(frame:IsShown() and frame.Editor.Header.Bind.enabled ~= nil, "own navigation: the window may stay open in combat (locked)")
check(not bound(), "...with the D-pad back on the crossbar")
frame:Hide() -- closed with B or Escape in combat
world.combat = false
world.tick()
fire("PLAYER_REGEN_ENABLED")
check(not bound(), "closed in combat: the D-pad stays the crossbar's after combat")
frame:Show()

-- Delete, enable, ticks, test.
click("Delete gesture")
check(#db.gestures == 0 and not frame.Editor.Header.shown, "Delete removes the gesture")
local enable; for _, f in ipairs(W.frames) do if f.template == "UICheckButtonTemplate" then enable = f end end
ns.Nav.Select(enable)
press("A")
check(db.enabled == false, "A on Enabled turns it off")
local plus; for _, f in ipairs(W.frames) do if f.text == "+" then plus = plus or f end end
plus:Click()
check(db.holdTicks == 4, "+ raises the hold ticks")
click("Test")
check(calls[#calls] == "test", "Test runs the check")

-- ======== Part 2: Blizzard's gamepad UI (the default) ========
local function managerCall(name, target) for i = #managerCalls, 1, -1 do local c = managerCalls[i]; if c[1] == name and c[2] == target then return c end end end
local function managerCallsSince(n, name) local count = 0; for i = n + 1, #managerCalls do if managerCalls[i][1] == name then count = count + 1 end end; return count end
frame:Hide()
db.ownNavigation = nil
check(type(ns.CloseConfig) == "function", "padnav switch can close the window")
local m = #managerCalls
ns.ToggleConfig()
local shown = managerCall("FrameShown", frame)
check(shown and shown[3] == false and shown[4] == true, "window registered with Blizzard's focus manager (focused, not a popup)")
check(not bound(), "no override bindings of our own")
local r = #managerCalls
click("New gesture")
check(managerCall("RefreshButtonGroups", frame) and managerCallsSince(r, "RefreshButtonGroups") > 0, "new rows: SmartNavigation rescans the window")
local slots2 = {}; for _, f in ipairs(W.frames) do if rawget(f, "mode") then slots2[f.mode] = f end end
slots2.trigger:Click("LeftButton")
check(picker:IsShown() and managerCall("HandlePopupShown", picker), "picker opens as Blizzard popup (focus returns to the window after)")
check(not managerCall("FrameShown", picker), "popup not registered twice")
r = #managerCalls
chooseTab("Items")
check(managerCallsSince(r, "RefreshButtonGroups") > 0 and managerCall("RefreshButtonGroups", picker), "new page: picker rescanned")
picker.cells[1]:Click("LeftButton")
check(not picker:IsShown() and managerCall("HandlePopupHide", picker), "choosing closes the popup through Blizzard")
check(db.gestures[#db.gestures].trigger.name == "Healthstone", "item chosen as trigger")
click("Name & icon")
picker.NameBox:OnSmartNavClick()
check(picker.NameBox:HasFocus(), "A on the name box starts typing")
check(picker:SmartNavigationCloseHandler() == true and picker:IsShown() and not picker.NameBox:HasFocus(), "B stops typing first")
check(picker:SmartNavigationCloseHandler() == true and not picker:IsShown(), "then B closes the picker")
r = #managerCalls
frame.Editor.Header.Bind:OnSmartNavClick()
check(calls[#calls]:find("^place:") and not frame:IsShown() and managerCall("FrameHidden", frame), "controller Bind: window closes through Blizzard, the next crossbar press binds")
frame:Show()
check(frame:SmartNavigationCloseHandler() == true and not frame:IsShown() and managerCallsSince(r, "FrameHidden") == 2, "B closes the window itself (not via its close button)")
frame:Show()
-- Blizzard's LT / RT / View jump hints and focus glow, from the template its own panels use.
check(frame.template:find("FocusFramesInterfaceTemplate") and picker.template:find("FocusFramesInterfaceTemplate"), "windows use Blizzard's focus template")
check(frame.LeftJumpHint.strata == "DIALOG" and frame.RightJumpHint.strata == "DIALOG" and frame.FocusJumpHint.strata == "DIALOG", "jump hints drawn above the window")
check(picker.LeftJumpHint.strata == "FULLSCREEN", "picker jump hints drawn above the picker")
check(frame.FrameGlow.loadedWithLayout == "ButtonFrameTemplateNoPortrait", "focus glow uses Blizzard's plain-panel art")
-- Prompt footer with controller glyphs.
local function footerText(footer) local t = {}; for _, e in ipairs(footer.entries) do if e.Label.shown then t[#t + 1] = e.Label.text end end; return table.concat(t, ",") end
check(frame.Footer.shown and footerText(frame.Footer) == "Select,Close", "footer glyphs: A Select, B Close (" .. footerText(frame.Footer) .. ")")
check(footerText(picker.Footer) == "Choose,Back", "picker footer: A Choose, B Back")

-- Combat: windows close when it starts (while Blizzard still takes it); nothing in combat; catch up after.
frame:Show(); click("Name & icon")
check(picker:IsShown(), "window and picker open")
r = #managerCalls
fire("PLAYER_REGEN_DISABLED")
check(not frame:IsShown() and not picker:IsShown() and managerCallsSince(r, "FrameHidden") == 1 and managerCallsSince(r, "HandlePopupHide") == 1,
	"combat start: picker and window close and leave Blizzard's focus list")
world.combat = true
r = #managerCalls
frame:Show()
check(frame:IsShown() and #managerCalls == r, "opened in combat: no calls into Blizzard's gamepad UI")
world.combat = false
fire("PLAYER_REGEN_ENABLED")
check(managerCallsSince(r, "FrameShown") == 1, "after combat: registered")
world.combat = true
r = #managerCalls
frame:Hide()
check(#managerCalls == r, "closed in combat: no calls")
world.combat = false
fire("PLAYER_REGEN_ENABLED")
check(managerCallsSince(r, "FrameHidden") == 1, "after combat: unregistered")
fire("PLAYER_REGEN_ENABLED")
check(managerCallsSince(r, "FrameHidden") == 1, "no double unregister")

-- The restriction already active when combat starts: Blizzard refuses (silently); retried after combat.
frame:Show()
check(indexOf(frame), "window listed")
refuse = true
r = #managerCalls
fire("PLAYER_REGEN_DISABLED")
check(not frame:IsShown() and managerCallsSince(r, "FrameHidden") == 1 and indexOf(frame), "refused at combat start: still listed by Blizzard")
refuse = false
fire("PLAYER_REGEN_ENABLED")
check(managerCallsSince(r, "FrameHidden") == 2 and not indexOf(frame), "after combat: retried and gone from Blizzard's list")
-- Refused while opening: retried after combat too.
refuse = true
r = #managerCalls
frame:Show()
check(managerCallsSince(r, "FrameShown") == 1 and not indexOf(frame), "refused open: not listed")
refuse = false
fire("PLAYER_REGEN_ENABLED")
check(indexOf(frame), "after combat: listed")
click("Name & icon")
check(indexOf(picker), "picker listed as popup")
picker:Hide()
check(not indexOf(picker), "picker removed")
frame:Hide()
check(#shownFrames == 0, "Blizzard's focus list empty after closing")

-- Keyboard & mouse style: nothing registered, nothing bound.
style = 0
r = #managerCalls
frame:Show()
check(#managerCalls == r and not bound(), "keyboard/mouse: no gamepad registration or bindings")
check(not frame.Footer.shown, "keyboard/mouse: no controller glyphs")
frame:Hide()
style = 1

-- Our frames never carry fields Blizzard's focus manager or SmartNavigation read without a taint barrier.
local unsafe = { "returnToPlayerControl", "FrameControlManagerGroup", "skipGamepadAutoFocus", "disableFrameFocusPagingWhenFocused",
	"useCustomNavigation", "skipFrameDeactivation", "dismissOnUnfocus", "suspendedButton", "unsuspendToFrame",
	"smartNavigationProxyTarget", "customSmartNavOffsetX", "customSmartNavOffsetY", "smartNavigationVerticalCursor",
	"smartNavigationIgnoreGrid", "buttonContext", "blockSmartNavClick", "smartNavigationIgnored", "smartNavigationCanFocus",
	"isFocused", "lockedFocus", "FocusFrameParent" }
local found = {}
for _, f in ipairs(W.frames) do for _, key in ipairs(unsafe) do if rawget(f, key) ~= nil then found[#found + 1] = key end end end
check(#found == 0, "no unbarriered Blizzard gamepad fields on our frames (" .. table.concat(found, ", ") .. ")")
for i, c in ipairs(managerCalls) do assert(c[1] ~= nil) end

-- Totem Commands on: a button to switch over.
frame:Hide(); TOTEM_ACTIVE = true; frame:Show()
check(frame.SwitchTotem.shown and frame.scripts and true, "Totem Commands on: Switch button shown")
frame.SwitchTotem:Click()
check(SWITCH_CALLS == 1 and not frame.SwitchTotem.shown, "Switch: moves the gesture over; button gone once Totem Commands is off")
frame:Hide()

-- Key binding (Bindings.xml) to open the window.
check(BINDING_HEADER_GESTURECOMMANDS == "Gesture Commands" and BINDING_NAME_GESTURECOMMANDS_TOGGLE ~= nil, "key binding named")
frame:Hide(); GestureCommands_ToggleConfig()
check(frame:IsShown(), "key binding opens the window"); GestureCommands_ToggleConfig()
check(not frame:IsShown(), "...and closes it")

-- ======== Minimap button and the addon compartment entry ========
local mini = GestureCommandsMinimapButton
check(mini and mini.parent == Minimap and not mini.shown, "minimap button on the minimap, hidden until login")
fire("PLAYER_LOGIN")
local function near(a, b) return math.abs(a - b) < 0.01 end
check(mini.shown and mini.point[2] == Minimap and near(mini.point[4], math.cos(math.rad(200)) * 75) and near(mini.point[5], math.sin(math.rad(200)) * 75),
	"shown at login on the minimap's edge (default lower left)")
frame:Hide()
mini.scripts.OnClick(mini, "LeftButton")
check(frame:IsShown(), "click opens the window")
mini.scripts.OnClick(mini, "LeftButton")
check(not frame:IsShown(), "click again closes it")
-- Drag: the cursor straight above the minimap's centre (scaled 2x) -> 90 degrees.
mini.scripts.OnDragStart(mini)
cursorX, cursorY = 2000, 1600
mini.scripts.OnUpdate(mini)
mini.scripts.OnDragStop(mini)
check(near(db.minimapAngle, 90) and near(mini.point[4], 0) and near(mini.point[5], 75) and mini.scripts.OnUpdate == nil, "drag moves it around the edge and saves the angle")
ns.ToggleMinimapButton()
check(not mini.shown and db.minimapHidden == true and calls[#calls]:find("hidden"), "/gestures minimap hides it")
ns.ToggleMinimapButton()
check(mini.shown and db.minimapHidden == nil, "...and shows it again")
-- Addon compartment (minimap addons menu), called by name from the TOC.
GestureCommands_OnAddonCompartmentClick("GestureCommands", "LeftButton")
check(frame:IsShown(), "addons menu entry opens the window")
GestureCommands_OnAddonCompartmentClick("GestureCommands", "LeftButton")
check(not frame:IsShown() and type(GestureCommands_OnAddonCompartmentEnter) == "function" and type(GestureCommands_OnAddonCompartmentLeave) == "function",
	"addons menu entry toggles; tooltip hooks exist")

-- ======== Entry on the gamepad main menu dial (drawn and watched; the dial is closed by secure code) ========
GamepadRadial = CreateFrame("Frame", "GamepadRadial", UIParent)
GamepadRadial.shown = false
GamepadRadial.Background = GamepadRadial:CreateTexture()
GamepadRadial.SegmentHighlight = GamepadRadial:CreateTexture()
GamepadRadial.SegmentList = {}
for i = 1, 8 do
	local segment = CreateFrame("Frame", nil, GamepadRadial)
	segment.IsEmpty = function(self) return rawget(self, "handler") == nil end
	GamepadRadial.SegmentList[i] = segment
end
local radialPages = { { "a", "b", "c", "d", "e", "f", "g", "h" }, { "a", "b", "c", "d", "e", "f", "g", "h" }, { "time", "calendar", nil, nil, "pvp" } }
function GamepadRadial:ActivateRadial(page)
	self.currentMainMenuPageIndex = page
	for i, segment in ipairs(self.SegmentList) do segment.handler = radialPages[page][i] end
end
function GamepadRadial:BeginSelection(i) self.currentIndex = i; self.SegmentHighlight.desaturated = self.SegmentList[i]:IsEmpty() end
function GamepadRadial:EndSelection() self.currentIndex = 0 end
local secureCloses = 0
local frameHide = GamepadRadial.Hide
GamepadRadial.Hide = function(self, ...) if W.inSecure then secureCloses = secureCloses + 1 end; return frameHide(self, ...) end
local radialFields = {}; for k in pairs(GamepadRadial) do radialFields[k] = true end
fire("PLAYER_LOGIN")
local closer = GestureCommandsDialCloser
local radialEntry; for _, f in ipairs(W.frames) do if f.parent == GamepadRadial and rawget(f, "Icon") then radialEntry = f end end
check(radialEntry ~= nil, "dial entry made (as our own child frame of the dial)")
local snippet = closer and closer.attrs._onattributechanged
check(closer and closer.template == "SecureHandlerAttributeTemplate" and snippet and snippet:find('name == "close%-dial"') and snippet:find("dial:Hide%(true%)"),
	"the dial is closed by a secure handler's snippet")
check(closer.attrs["frameref-dial"] == GamepadRadial, "...with a frame reference to the dial")
local function openDial(page) GamepadRadial:Show(); GamepadRadial:ActivateRadial(page) end
-- Point at a slot and let go of the stick, as Blizzard's ProcessInput does (EndSelection after Trigger).
local function release(slotIndex) GamepadRadial:BeginSelection(slotIndex); GamepadRadial:EndSelection(); runTimers() end
frame:Hide(); wipe(errors)
openDial(2)
check(not radialEntry.shown, "not on the full pages")
GamepadRadial:ActivateRadial(3)
check(radialEntry.shown and radialEntry.Label.text == "Gesture Commands", "on the last page, in a free slot")
local p = radialEntry.Icon.point
check(p and p[2] == GamepadRadial.Background and math.abs(p[4]) < 0.01 and math.abs(p[5] - 100) < 0.01, "...the north slot, where Blizzard puts its icons")
check(radialEntry.Icon.desaturated == false and radialEntry.Label.textColor[1] == 1, "out of combat: normal colours")
GamepadRadial:BeginSelection(3)
check(GamepadRadial.SegmentHighlight.desaturated == false, "pointed at: highlighted in full colour (Blizzard greys empty slots)")
GamepadRadial:EndSelection(); runTimers()
check(secureCloses == 1 and not GamepadRadial.shown, "released on it: the dial closes (by the secure snippet)")
check(frame:IsShown(), "...and the window opens - no other button")
openDial(3); release(3)
check(secureCloses == 2 and not GamepadRadial.shown and not frame:IsShown(), "released on it again: dial closes, window closes (toggle, like Bags)")
-- Other entries, cancelling, or closing the dial with B: nothing of ours happens.
openDial(3); GamepadRadial:BeginSelection(3); GamepadRadial:BeginSelection(1); GamepadRadial:EndSelection(); GamepadRadial:Hide(); runTimers()
check(secureCloses == 2 and not frame:IsShown(), "released on another entry: no window")
openDial(3); GamepadRadial:BeginSelection(3); GamepadRadial.isCancelled = true; GamepadRadial:EndSelection(); GamepadRadial.isCancelled = false
check(secureCloses == 2 and GamepadRadial.shown, "cancelled selection: the dial stays")
GamepadRadial:Hide(); runTimers()
check(not frame:IsShown(), "...and closing it opens nothing")
-- In combat: shown as unavailable; releasing on it explains (the handler can't be used in combat).
world.combat = true
openDial(3)
check(radialEntry.Icon.desaturated == true and radialEntry.Label.textColor[1] == 0.5, "in combat: entry greyed")
GamepadRadial:BeginSelection(3)
check(GamepadRadial.SegmentHighlight.desaturated == true, "in combat: highlight stays grey")
GamepadRadial:EndSelection(); runTimers()
check(secureCloses == 2 and GamepadRadial.shown and errors[#errors]:find("after combat"), "in combat: released on it: explains, no secure call")
GamepadRadial:Hide(); runTimers()
check(not frame:IsShown(), "in combat: nothing opens")
world.combat = false
-- Blizzard filling the north slot one day: the next free one is used.
radialPages[3][3] = "new"
openDial(3)
p = radialEntry.Icon.point
check(radialEntry.shown and math.abs(p[4] + 70.71) < 0.01 and math.abs(p[5] - 70.71) < 0.01, "slot taken: moves to the next free slot")
release(4)
check(frame:IsShown(), "...and works there")
frame:Hide()
local added = {}; for k in pairs(GamepadRadial) do if not radialFields[k] and k ~= "currentMainMenuPageIndex" and k ~= "currentIndex" and k ~= "isCancelled" then added[#added + 1] = k end end
check(#added == 0, "nothing of ours stored in the dial's tables (" .. table.concat(added, ", ") .. ")")

-- Every secure snippet must pass Blizzard's compile rules and only use what the restricted environment has.
local snippetProblems = {}
for _, f in ipairs(W.frames) do
	for k, v in pairs(f.attrs) do
		if type(k) == "string" and k:match("^_on") and type(v) == "string" then
			for _, problem in ipairs(world.S.staticProblems(v, "self,name,value")) do snippetProblems[#snippetProblems + 1] = k .. ": " .. problem end
		end
	end
end
check(#snippetProblems == 0, "secure snippets compile under Blizzard's rules (" .. table.concat(snippetProblems, "; ") .. ")")

check(#touched == 0, "never touched Blizzard's gamepad UI or icon provider (" .. table.concat(touched, ", ") .. ")")
check(not templateUsed("IconSelectorPopupFrameTemplate"), "Blizzard's icon selector template not used")

H.finish()
