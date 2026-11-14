-- Engine tests: the secure gesture engine, publishing, binding, labels, migrations, slash commands.
-- Run: tests/run.ps1 (or luajit tests/engine_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
local H = dofile(lib .. "harness.lua")
local world = dofile(lib .. "world.lua").new()
local W = world.W
local check = H.check

-- The engine's files: everything but the UI.
local function isEngineFile(file)
	return not file:match("^UI/")
end

-- ---- game data ---------------------------------------------------------------------------------
-- ---- game data ---------------------------------------------------------------------------------
local SPELLS = { [66842] = "Call of the Elements", [36936] = "Totemic Recall", [900001] = "Totemic Call",
	[403] = "Lightning Bolt", [529] = "Lightning Bolt", [331] = "Healing Wave", [458] = "Brown Horse" }
local KNOWN_BEST = { ["Call of the Elements"] = 66842, ["Totemic Recall"] = 36936, ["Totemic Call"] = 900001,
	["Lightning Bolt"] = 529, ["Healing Wave"] = 331 }
local ITEMS = { [5512] = "Healthstone", [54452] = "Ethereal Portal" }
local TOYS = { [54452] = true }
local MOUNTS = { [6] = { "Brown Horse", 458 } }
-- Macros: kept sorted by name like the real list, so indices shift when macros are added or renamed.
local MACROS = { { name = "Bolt", icon = 4001, body = "/cast Lightning Bolt" }, { name = "Panic", icon = 4002, body = "/say help" } }
local macroLimit = 30
local function sortMacros() table.sort(MACROS, function(a, b) return a.name < b.name end) end


C_Spell = {
	GetSpellName = function(id) return SPELLS[id] end,
	GetSpellTexture = function(id) return SPELLS[id] and 1000 + id end,
	GetSpellInfo = function(name) local id = KNOWN_BEST[name]; if id then return { spellID = id, name = name } end end,
	PickupSpell = function(id) world.cursor = { "spell", 1, "spell", id } end,
}
C_Item = {
	GetItemNameByID = function(id) return ITEMS[id] end,
	GetItemIconByID = function(id) return ITEMS[id] and 2000 + id end,
	GetItemInfoInstant = function(link) return tonumber(tostring(link):match("item:(%d+)")) end,
	PickupItem = function(id) world.cursor = { "item", id } end,
}
function PlayerHasToy(id) return TOYS[id] == true end
C_MountJournal = { GetMountInfoByID = function(id) local m = MOUNTS[id]; if m then return m[1], m[2], 3000 + id end end,
	GetNumDisplayedMounts = function() return 1 end, GetDisplayedMountID = function() return 6 end,
	Pickup = function(index) world.cursor = { "mount", 6 } end }
C_ToyBox = { PickupToyBoxItem = function(id) world.cursor = { "item", id } end }
local function macroIndex(nameOrIndex)
	if type(nameOrIndex) == "number" then return nameOrIndex end
	for i, m in ipairs(MACROS) do if m.name == nameOrIndex then return i end end
end
function GetMacroInfo(x) local m = MACROS[macroIndex(x) or 0]; if m then return m.name, m.icon, m.body end end
function GetMacroIndexByName(n) return macroIndex(n) or 0 end
function GetMacroSpell(i) local m = MACROS[i]; local spell = m and m.body:match("^/cast (.+)$"); return spell and KNOWN_BEST[spell] end
function CreateMacro() error("the addon must not create macros") end
function EditMacro() error("the addon must not edit macros") end
MAX_ACCOUNT_MACROS = 0 -- every test macro counts as a character macro
function DeleteMacro(x) assert(not world.combat); table.remove(MACROS, macroIndex(x)) end
function PickupMacro(i) world.cursor = { "macro", i } end
C_ActionBar = { PutActionInSlot = function(slot)
	assert(not world.combat, "placing in combat")
	local c = world.cursor
	if c and c[1] == "macro" then
		world.actions[slot] = { "macro", GetMacroSpell(c[2]), "spell", name = MACROS[c[2]].name }
	elseif c and c[1] == "spell" then
		world.actions[slot] = { "spell", c[4] }
	elseif c and c[1] == "item" then
		world.actions[slot] = { "item", c[2] }
	elseif c and c[1] == "mount" then
		world.actions[slot] = { "summonmount", c[2] }
	end
	world.cursor = nil
end }
function C_ActionBar.GetActionTexture(slot)
	local a = world.actions[slot]
	if not a then return nil end
	if a[1] == "spell" then return 1000 + a[2] elseif a[1] == "item" then return 2000 + a[2] end
	return MACROS[macroIndex(a.name) or 0] and MACROS[macroIndex(a.name)].icon
end
function C_ActionBar.UsesActionText(slot) local a = world.actions[slot]; return a ~= nil and a[1] == "macro" end
function C_ActionBar.GetActionText(slot) local a = world.actions[slot]; return a and a.name end
function GetActionText(slot) local a = world.actions[slot]; return a and a.name end
function GetMacroItem() return nil end


-- ---- load ---------------------------------------------------------------------------------------
local bars = world.buildCrossbar()
local ns = {}
H.loadAddon(ns, isEngineFile)
local missing = {}
for _, name in ipairs(dofile(lib .. "engine_api.lua")) do if ns[name] == nil then missing[#missing + 1] = name end end
check(#missing == 0, "the engine provides its whole API (" .. table.concat(missing, ", ") .. ")")
check(#ns.snippetErrors == 0 and #ns.snippets == 3, "the engine's secure snippets pass the load-time check")
local header = GestureCommandsHeader
local fire, runTimers, poll, press, last = world.fire, world.runTimers, world.poll, world.press, world.lastCast
local function tick() world.tick() end
local function click(btn, button, down) world.click(btn, button, down) end
local function call(fn, ...) return fn(...) end
local function slash(m) SlashCmdList.GESTURECOMMANDS(m) end
local printed, messages = world.printed, world.messages
local rumbles = 0
C_GamePad.SetVibration = function() rumbles = rumbles + 1 end

local B = bars.leftBar.buttons
world.actions[B[1].id] = { "spell", 66842 }               -- Call of the Elements
world.actions[B[2].id] = { "spell", 529 }                 -- Lightning Bolt rank 2
world.actions[B[3].id] = { "macro", 529, "spell" }        -- macro showing Lightning Bolt
world.actions[B[4].id] = { "item", 5512 }                 -- Healthstone
world.actions[B[5].id] = { "spell", 331 }                 -- Healing Wave (no gesture)
world.actions[60] = { "spell", 403 }                      -- Lightning Bolt rank 1 on a keyboard bar

fire("ADDON_LOADED", "GestureCommands"); fire("PLAYER_LOGIN"); runTimers()
check(header.attrs.enabled == true and next(world.R.wraps) == nil, "fresh install: on by default, but nothing hooked until a gesture exists")
TotemCommandsHeader = { GetAttribute = function(_, k) if k == "enabled" then return true end end }
call(ns.Publish)
check(header.attrs.enabled == false, "default-on still stays off while Totem Commands is on")
TotemCommandsHeader = nil
call(ns.Publish)

-- Gestures: totems preset, Lightning Bolt (rank 1 dragged) -> hold macro, long mount; Healthstone -> hold toy.
local totems = call(ns.AddGesture, { trigger = { kind = "spell", id = 66842, name = "Call of the Elements" },
	hold = { kind = "spell", id = 36936 }, long = { kind = "spell", id = 900001 } })
local bolt = call(ns.AddGesture, { trigger = { kind = "spell", id = 403, name = "Lightning Bolt" },
	hold = { kind = "macro", name = "Panic" }, long = { kind = "mount", id = 6 } })
local stone = call(ns.AddGesture, { trigger = { kind = "item", id = 5512 }, hold = { kind = "toy", id = 54452 } })
check(totems == 1 and bolt == 2 and stone == 3, "three gestures added")
check(call(ns.SetEnabled, true) and header.attrs.enabled == true, "enabled")
local hooked = 0; for _ in pairs(world.R.wraps) do hooked = hooked + 1 end
check(hooked == 36, "36 crossbar/stance buttons hooked")

world.casts = {}
press(B[1], 1); press(B[1], 4); press(B[1], 8)
check(world.casts[1] == "slot:spell:66842" and world.casts[2] == "spell:Totemic Recall" and world.casts[3] == "spell:Totemic Call",
	"totems: tap = slot, hold = Totemic Recall, long = Totemic Call (spells cast by name)")
check(B[1].attrs.useOnKeyDown == true, "useOnKeyDown restored to Blizzard's value")

world.casts = {}
press(B[2], 1); press(B[2], 3); press(B[2], 7)
check(world.casts[1] == "slot:spell:529" and world.casts[2] == "macro:Panic" and world.casts[3] == "spell:458",
	"rank 2 on the bar triggers a rank-1 gesture; hold = macro by name, long = mount spell")
check(header.attrs["g:spell:403"] == 2 and header.attrs["g:spell:529"] == 2, "every rank of the trigger is a key")

world.casts = {}
press(B[3], 1); press(B[3], 3)
check(world.casts[1] == "slot:macro:529" and world.casts[2] == "macro:Panic", "a macro showing the spell triggers too; tap runs the macro")

world.casts = {}
press(B[4], 1); press(B[4], 3); press(B[4], 9)
check(world.casts[1] == "slot:item:5512" and world.casts[2] == "toy:54452" and world.casts[3] == "toy:54452",
	"item trigger; hold = toy; no long action -> a long hold stays at hold")

world.casts = {}
press(B[5], 4)
check(#world.casts == 1 and last() == "slot:spell:331", "slot without a gesture: normal cast on press")

-- Another crossbar button pressed and released during a hold: it does its own action, and the hold goes on.
world.casts = {}
click(B[1], "LeftButton", true)
for _ = 1, 2 do tick(); poll() end
click(B[5], "LeftButton", true); click(B[5], "LeftButton", false)
for _ = 1, 2 do tick(); poll() end
click(B[1], "LeftButton", false); poll()
check(world.casts[1] == "slot:spell:331" and world.casts[2] == "spell:Totemic Recall", "another button mid-hold: it casts, and the hold still casts")
-- The crossbar page changes mid-hold: the release arrives at the button now in the pressed one's place.
local samePlace = bars.rightBar.buttons[1]
check(header.attrs["pos:" .. B[1].id] == 1 and header.attrs["pos:" .. samePlace.id] == 1, "crossbar positions published")
world.casts = {}
click(B[1], "LeftButton", true)
for _ = 1, 4 do tick(); poll() end
click(samePlace, "LeftButton", false); poll()
check(#world.casts == 0 and header.attrs.armed == 0, "page changed mid-hold: the press is dropped")
press(B[1], 1)
check(last() == "slot:spell:66842", "...and the next tap works")

-- Only a long hold: short holds stay taps.
call(ns.SetGestureAction, stone, "hold", nil)
call(ns.SetGestureAction, stone, "long", { kind = "spell", id = 331 })
world.casts = {}; rumbles = 0; wipe(messages)
press(B[4], 4); press(B[4], 7)
check(world.casts[1] == "slot:item:5512" and world.casts[2] == "spell:Healing Wave", "long-only gesture: 4 ticks = tap, 7 = long")
check(rumbles == 1 and messages[1] == "Release for Healing Wave", "feedback names the action that will cast")

-- Delete a gesture: its keys are unpublished.
call(ns.RemoveGesture, bolt)
check(header.attrs["g:spell:529"] == nil and header.attrs["g:spell:403"] == nil, "deleting a gesture removes its keys")
check(header.attrs["g:item:5512"] == 2, "remaining gestures renumbered")
world.casts = {}
press(B[2], 4)
check(#world.casts == 1 and last() == "slot:spell:529", "deleted gesture's trigger behaves normally again")

-- Two gestures with the same trigger are flagged.
call(ns.AddGesture, { trigger = { kind = "spell", id = 66842 } })
check(ns.conflicts[3] == 1, "duplicate trigger flagged")
call(ns.RemoveGesture, 3)

-- Combat: config changes deferred/refused, gestures keep working.
world.combat = true
check(not call(ns.SetEnabled, false), "can't turn off in combat")
call(ns.SetGestureAction, 1, "hold", { kind = "spell", id = 331 })
check(header.attrs["g1-hold-value"] == "Totemic Recall", "edits in combat wait for combat to end")
world.casts = {}
press(B[1], 4)
check(last() == "spell:Totemic Recall", "in combat: hold still casts")
world.combat = false
fire("PLAYER_REGEN_ENABLED"); runTimers()
check(header.attrs["g1-hold-value"] == "Healing Wave", "after combat: the edit is published")

-- Totem Commands running on the same buttons.
call(ns.SetEnabled, false)
TotemCommandsHeader = { GetAttribute = function(_, k) if k == "enabled" then return true end end }
check(not call(ns.SetEnabled, true) and header.attrs.enabled == false, "refuses to turn on while Totem Commands is on")
TotemCommandsHeader = nil
check(call(ns.SetEnabled, true), "turns on once Totem Commands is off")

-- Dragging a gesture out of the window picks up its trigger (highest rank for spells).
local rankIndex = call(ns.AddGesture, { trigger = { kind = "spell", id = 403, name = "Lightning Bolt" } }); world.cursor = nil
check(call(ns.PickupGesture, rankIndex) and world.cursor[1] == "spell" and world.cursor[4] == 529, "drag gesture: rank-1 trigger is picked up at the highest rank (529)")
call(ns.RemoveGesture, rankIndex)
world.cursor = nil
local stoneIndex; for i, g in ipairs(GestureCommandsCharDB.gestures) do if g.trigger and g.trigger.kind == "item" then stoneIndex = i end end
check(call(ns.PickupGesture, stoneIndex) and world.cursor[1] == "item" and world.cursor[2] == 5512, "drag gesture: item trigger picks up the item")
local emptyIndex = call(ns.AddGesture, {}); world.cursor = nil
check(not call(ns.PickupGesture, emptyIndex) and world.cursor == nil and printed[#printed]:find("Tap first"), "drag gesture without a Tap explains why")
call(ns.RemoveGesture, emptyIndex)
world.combat = true; world.cursor = nil
check(not call(ns.PickupGesture, 1) and world.cursor == nil, "no placing in combat")
world.combat = false

-- Cursor reading for the setup window.
world.cursor = { "spell", 12, "spell", 529, 403 }
local a = call(ns.ReadCursor); check(a.kind == "spell" and a.id == 529, "cursor: spell")
world.cursor = { "item", 54452 }; a = call(ns.ReadCursor); check(a.kind == "toy" and a.id == 54452, "cursor: toy item -> toy")
world.cursor = { "item", 5512 }; a = call(ns.ReadCursor); check(a.kind == "item", "cursor: item")
world.cursor = { "mount", 6 }; a = call(ns.ReadCursor); check(a.kind == "mount" and a.name == "Brown Horse", "cursor: mount")
world.cursor = { "macro", 1 }; a = call(ns.ReadCursor); check(a.kind == "macro" and a.name == "Bolt", "cursor: macro by name")
local t = call(ns.MakeTrigger, a); check(t and t.kind == "macro" and t.name == "Bolt", "a macro that shows a spell can be the Tap, and stays a macro")
check(call(ns.MakeTrigger, { kind = "macro", name = "Panic" }) ~= nil, "any macro can be the Tap (even one that shows nothing)")
check(call(ns.MakeTrigger, { kind = "mount", id = 6 }) ~= nil and call(ns.MakeTrigger, { kind = "toy", id = 54452 }) ~= nil, "mounts and toys can be the Tap")
check(call(ns.MakeTrigger, { kind = "battlepet", id = 9 }) == nil, "other kinds can't")
world.cursor = { "battlepet", 9 }; local _, ct = call(ns.ReadCursor); check(ct == "battlepet", "unsupported cursor types are reported")

-- ---- no macros of our own; name & icon only label the gesture -------------------------------------
local function findMacro(name) for _, m in ipairs(MACROS) do if m.name == name then return m end end end
local macroCount = #MACROS
local g = GestureCommandsCharDB.gestures[1]
call(ns.SetGestureNameIcon, 1, "Totems", 136097)
check(g.name == "Totems" and g.icon == 136097 and ns.GetGestureName(g) == "Totems" and ns.GetGestureIcon(g) == 136097, "name and icon label the gesture")
call(ns.SetGestureNameIcon, 1, "", 134400)
check(g.name == nil and g.icon == nil and ns.GetGestureName(g) == "Call of the Elem" and ns.GetGestureIcon(g) == 67842, "empty name / '?' icon: the Tap action's (name cut to 16)")
call(ns.SetGestureNameIcon, 1, "Totems", nil)
local temp = call(ns.AddGesture, { trigger = { kind = "spell", id = 331, name = "Healing Wave" } })
call(ns.RemoveGesture, temp)
check(#MACROS == macroCount and g.macro == nil, "adding, renaming and deleting gestures never touches your macros")
world.cursor = nil
check(call(ns.PickupGesture, 1) and world.cursor[1] == "spell" and world.cursor[4] == 66842, "dragging a gesture picks up its Tap spell")

-- ---- the gesture's icon on the crossbar ---------------------------------------------------------------
local function blizzardUpdate(btn)
	btn.icon:SetTexture(C_ActionBar.GetActionTexture(btn.id))
	btn.Name:SetText(C_ActionBar.UsesActionText(btn.id) and C_ActionBar.GetActionText(btn.id) or "")
end
blizzardUpdate(B[1]); blizzardUpdate(B[5])
check(B[1].icon.texture == 67842, "no icon chosen: the crossbar shows the Tap's own icon")
call(ns.SetGestureNameIcon, 1, "Totems", 136097)
check(B[1].icon.texture == 136097, "chosen icon shown on the crossbar button holding the Tap")
check(B[1].Name.text == "Totems", "the gesture's name shown as the button's text")
check(B[5].icon.texture == 1331, "other buttons untouched")
blizzardUpdate(B[1])
check(B[1].icon.texture == 136097 and B[1].Name.text == "Totems", "Blizzard re-setting icon and text (update, shapeshift): ours go back on")
world.combat = true; blizzardUpdate(B[1]); world.combat = false
check(B[1].icon.texture == 136097, "...in combat too")
local held = world.actions[B[1].id]
world.actions[B[1].id] = { "spell", 331 }; blizzardUpdate(B[1])
check(B[1].icon.texture == 1331 and B[1].Name.text == "", "slot now holds something else (page / new action): Blizzard's icon and text stay")
world.actions[B[1].id] = held; blizzardUpdate(B[1])
check(B[1].icon.texture == 136097, "...and the Tap back: the gesture icon again")
call(ns.SetGestureNameIcon, 1, "Totems", nil)
check(B[1].icon.texture == 67842 and B[1].Name.text == "Totems", "icon cleared: the Tap's own icon is back (name kept)")
call(ns.SetGestureNameIcon, 1, "", nil)
check(B[1].Name.text == "", "name cleared: no text, as for any spell")
call(ns.SetGestureNameIcon, 1, "Totems", 136097)

-- One of your macros as the Tap: on the crossbar it is the gesture, a tap runs the macro.
MACROS[#MACROS + 1] = { name = "Heal", icon = 4003, body = "/cast Healing Wave" }; sortMacros()
world.actions[B[6].id] = { "macro", 331, "spell", name = "Heal" }
local heal = call(ns.AddGesture, { trigger = { kind = "macro", name = "Heal" }, hold = { kind = "spell", id = 36936 } })
check(header.attrs["g:slot:" .. B[6].id] == heal and header.attrs["g:spell:331"] == nil, "macro Tap: keyed by the slots holding that macro (not by the spell it shows)")
check(ns.GetGestureName(GestureCommandsCharDB.gestures[heal]) == "Heal" and ns.GetGestureIcon(GestureCommandsCharDB.gestures[heal]) == 4003, "macro Tap: the macro's name and icon")
world.actions[B[6].id] = { "macro", 331, "spell", name = "Heal" }
call(ns.Publish); world.casts = {}
press(B[6], 1); press(B[6], 4)
check(world.casts[1] == "slot:macro:331" and world.casts[2] == "spell:Totemic Recall", "macro Tap on the crossbar: tap runs the macro, hold casts")
world.cursor = nil
check(call(ns.PickupGesture, heal) and world.cursor[1] == "macro" and MACROS[world.cursor[2]].name == "Heal", "dragging it picks up your macro")
-- Your macro deleted: explained, nothing bound.
table.remove(MACROS, macroIndex("Heal")); world.cursor = nil
check(not call(ns.PickupGesture, heal) and world.cursor == nil and printed[#printed]:find("doesn't exist any more"), "deleted macro Tap: explained")
check(not call(ns.StartPlacing, heal) and printed[#printed]:find("isn't available any more"), "deleted macro Tap: Bind refuses")
call(ns.Publish)
check(header.attrs["g:slot:" .. B[6].id] == nil, "deleted macro Tap: no longer published")
call(ns.RemoveGesture, heal); world.actions[B[6].id] = nil
world.combat = true; world.cursor = nil
check(not call(ns.PickupGesture, 1) and world.cursor == nil, "no placing in combat")
world.combat = false

-- ---- any action as the Tap: mounts, toys, macros that show nothing --------------------------------------
-- The secure code can't see their IDs, so the slots holding them are published by number.
world.actions[B[7].id] = { "summonmount", 6 }
world.actions[B[8].id] = { "macro", 0, "", name = "Panic" }
local horse = call(ns.AddGesture, { trigger = { kind = "mount", id = 6, name = "Brown Horse" }, hold = { kind = "spell", id = 36936 } })
local panic = call(ns.AddGesture, { trigger = { kind = "macro", name = "Panic" }, long = { kind = "spell", id = 331 } })
check(header.attrs["g:slot:" .. B[7].id] == horse and header.attrs["g:slot:" .. B[8].id] == panic, "mount and plain-macro Taps: their slots published")
world.casts = {}
press(B[7], 1); press(B[7], 4)
check(world.casts[1] == "slot:summonmount:6" and world.casts[2] == "spell:Totemic Recall", "mount Tap: tap summons the mount, hold casts")
world.casts = {}
press(B[8], 1); press(B[8], 8)
check(world.casts[1] == "slot:macro:0" and world.casts[2] == "spell:Healing Wave", "macro that shows nothing: tap runs it, long hold casts")
world.cursor = nil
check(call(ns.PickupGesture, horse) and world.cursor[1] == "mount" and world.cursor[2] == 6, "dragging a mount gesture picks up the mount")
-- Bind a mount gesture with a crossbar press.
local mountTarget = bars.bottomBar.buttons[5]
world.actions[mountTarget.id] = nil
call(ns.StartPlacing, horse)
click(mountTarget, "LeftButton", true); poll(); click(mountTarget, "LeftButton", false); poll()
check(world.actions[mountTarget.id] and world.actions[mountTarget.id][1] == "summonmount", "Bind: the mount goes on the pressed button")
call(ns.Publish)
check(header.attrs["g:slot:" .. mountTarget.id] == horse, "...and that slot is now the gesture")
-- A toy as the Tap.
local toy = call(ns.AddGesture, { trigger = { kind = "toy", id = 54452, name = "Ethereal Portal" } })
world.cursor = nil
check(call(ns.PickupGesture, toy) and world.cursor[1] == "item" and world.cursor[2] == 54452, "dragging a toy gesture picks up the toy (from the toy box)")
local toyTarget = bars.bottomBar.buttons[6]
world.actions[toyTarget.id] = { "item", 54452 }
call(ns.Publish)
check(header.attrs["g:slot:" .. toyTarget.id] == toy, "toy Tap: its slots published")
-- Moved off a slot: no longer the gesture there.
world.actions[B[7].id] = { "spell", 331 }
call(ns.Publish)
check(header.attrs["g:slot:" .. B[7].id] == nil, "the slot now holds something else: unpublished")
for _, index in ipairs({ toy, panic, horse }) do call(ns.RemoveGesture, index) end
world.actions[B[7].id], world.actions[B[8].id], world.actions[mountTarget.id], world.actions[toyTarget.id] = nil, nil, nil, nil
call(ns.Publish)

-- ---- place mode (controllers) ---------------------------------------------------------------------
local target = bars.rightBar.buttons[3]
world.actions[target.id] = { "spell", 331 }
wipe(messages)
local notified = {}
ns.OnPlacingChanged = function(gesture, endsAt) notified[#notified + 1] = { gesture and gesture.name or false, endsAt } end
check(call(ns.StartPlacing, 1) and header.attrs.placing == true, "place mode: armed")
check(notified[1] and notified[1][1] == "Totems" and notified[1][2] == 1060, "place mode: the banner is told what and until when (60 s)")
check(messages[#messages]:find("Press the crossbar button for Totems"), "place mode: tells you to press a crossbar button")
world.casts = {}
click(target, "LeftButton", true); poll(); click(target, "LeftButton", false); poll()
check(#world.casts == 0, "place mode: the press doesn't cast anything")
check(world.actions[target.id][1] == "spell" and world.actions[target.id][2] == 66842, "place mode: the gesture's Tap is now in that slot")
check(header.attrs.placing == false and not ns.IsPlacing() and messages[#messages] == "Totems placed", "place mode: done, with confirmation")
check(notified[#notified][1] == false, "place mode: banner hidden once placed")
world.casts = {}
press(target, 4)
check(last() == "spell:Healing Wave", "the placed gesture works immediately")

-- A gesture press whose release never arrived (window took focus) must not survive place mode.
click(B[1], "LeftButton", true)                      -- down only on the gesture button
local target4 = bars.rightBar.buttons[4]
call(ns.StartPlacing, 1)
click(target4, "LeftButton", true); poll()
for _ = 1, 10 do tick(); poll() end                  -- still holding the placing press
check(header.attrs.armed == 0, "stale press: no hold stage arms while the placing press is held")
click(target4, "LeftButton", false); poll()
check(world.actions[target4.id] and world.actions[target4.id][1] == "spell", "stale press: the placing press still picks the target slot")
world.casts = {}
press(B[1], 1)
check(last() == "slot:spell:66842", "stale press: the gesture button works normally again")

-- Works even when gestures are switched off.
call(ns.SetEnabled, false)
local target2 = bars.bottomBar.buttons[2]
world.actions[target2.id] = nil
call(ns.StartPlacing, 1)
click(target2, "LeftButton", true); poll(); click(target2, "LeftButton", false); poll()
check(world.actions[target2.id] and world.actions[target2.id][1] == "spell", "place mode works while gestures are off")
call(ns.SetEnabled, true)

-- In combat: presses do their action (nothing swallowed); the bind waits for a press after the fight.
local target3 = bars.bottomBar.buttons[3]
world.actions[target3.id] = { "spell", 331 }
call(ns.StartPlacing, 1)
world.combat = true; world.casts = {}
click(target3, "LeftButton", true); poll(); click(target3, "LeftButton", false); poll()
check(#world.casts == 1 and world.actions[target3.id][1] == "spell" and ns.IsPlacing(), "in combat: the press casts as usual and binds nothing")
world.combat = false; world.casts = {}
click(target3, "LeftButton", true); poll(); click(target3, "LeftButton", false); poll()
check(#world.casts == 0 and world.actions[target3.id][1] == "spell" and not ns.IsPlacing(), "after combat: the next press binds")

-- Running out in combat: cancelled once the fight ends (the secure state can't change in combat).
world.timers = {}
call(ns.StartPlacing, 1)
world.combat = true
runTimers()
check(ns.IsPlacing() and header.attrs.placing == true, "ran out in combat: still armed (can't change it in combat)")
world.combat = false
fire("PLAYER_REGEN_ENABLED"); runTimers()
check(not ns.IsPlacing() and header.attrs.placing == false and notified[#notified][1] == false, "...cancelled when combat ends")

-- Timeout.
world.timers = {}
call(ns.StartPlacing, 1)
runTimers()
check(not ns.IsPlacing() and header.attrs.placing == false and printed[#printed]:find("cancelled"), "place mode times out")

-- Slash commands.
slash("hold 9"); check(printed[#printed]:find("must be"), "hold out of range rejected")
slash("hold 4"); check(header.attrs.holdTicks == 4, "hold setting published")
slash("test"); for _ = 1, 12 do tick() end; runTimers()
local sawTicks = false; for _, l in ipairs(printed) do if l:find("secure ticks: %d+ in 2 s %(working%)") then sawTicks = true end end
check(sawTicks, "test reports the secure tick working")

fire("ADDON_ACTION_FORBIDDEN", "GestureCommands", "EnableGamePadStick()")
check(printed[#printed]:find("Blizzard blocked EnableGamePadStick%(%) %(forbidden%)"), "reports which function Blizzard blocked")
local n = #printed
fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "CastSpellByName()")
check(#printed == n, "ignores other addons' blocked actions")

check(#W.violations == 0, "addon code never set attributes on Blizzard's buttons" .. (#W.violations > 0 and (": " .. table.concat(W.violations, ", ")) or ""))
-- ---- switching from Totem Commands -------------------------------------------------------------------
local totemOn = true
TotemCommandsHeader = { GetAttribute = function(_, k) if k == "enabled" then return totemOn end end }
TotemCommandsDB = { enabled = true, holdTicks = 4, hold2Ticks = 9 }
SlashCmdList.TOTEMCOMMANDS = function(msg) if msg == "off" then totemOn = false; TotemCommandsDB.enabled = false end end
call(ns.Publish)
check(header.attrs.enabled == false, "Totem Commands on: Gesture Commands stays off")
local keptGestures = GestureCommandsCharDB.gestures
GestureCommandsCharDB.gestures = {}
local savedHold, savedHold2 = GestureCommandsCharDB.holdTicks, GestureCommandsCharDB.hold2Ticks
GestureCommandsCharDB.holdTicks, GestureCommandsCharDB.hold2Ticks = nil, nil
local switched = call(ns.SwitchFromTotemCommands)
local tg = GestureCommandsCharDB.gestures[1]
check(switched == 1 and tg and tg.trigger.id == 66842 and tg.hold.id == 36936 and tg.long.id == 900001,
	"switch: the totem gesture (Call of the Elements / Totemic Recall / Totemic Call, ranks by name)")
check(GestureCommandsCharDB.holdTicks == 4 and GestureCommandsCharDB.hold2Ticks == 9, "switch: Totem Commands' hold lengths kept")
check(not totemOn and TotemCommandsDB.enabled == false and header.attrs.enabled == true, "switch: Totem Commands off (its own command), Gesture Commands on")
check(printed[#printed]:find("switched"), "switch: confirmed")
totemOn = true
check(call(ns.SwitchFromTotemCommands) == 1 and #GestureCommandsCharDB.gestures == 1, "switching again: no duplicate gesture")
world.combat = true; totemOn = true
check(call(ns.SwitchFromTotemCommands) == false and totemOn, "no switching in combat")
world.combat = false
GestureCommandsCharDB.gestures = keptGestures
GestureCommandsCharDB.holdTicks, GestureCommandsCharDB.hold2Ticks = savedHold, savedHold2
TotemCommandsHeader, TotemCommandsDB, SlashCmdList.TOTEMCOMMANDS = nil, nil, nil
call(ns.Publish)

-- ---- upgrading: the macros earlier versions made for gestures are removed ---------------------------
GestureCommandsCharDB = { gestures = {
	{ trigger = { kind = "spell", id = 66842, name = "Call of the Elements" }, macro = "Call of the Elem" },
	{ trigger = { kind = "spell", id = 331, name = "Healing Wave" }, macro = "Healing Wave" },
	{ trigger = { kind = "item", id = 5512 }, macro = "Gone" },
} }
MACROS[#MACROS + 1] = { name = "Call of the Elem", icon = 134400, body = "/cast Call of the Elements" }
MACROS[#MACROS + 1] = { name = "Healing Wave", icon = 134400, body = "/cast Healing Wave\n/say Healing!" } -- edited by the player
sortMacros()
local userMacros = #MACROS - 2
world.actions[61] = { "macro", 66842, "spell", name = "Call of the Elem" }
world.actions[62] = { "macro", 331, "spell", name = "Healing Wave" }
-- A fresh session: the first one's frames stop receiving events, a new copy of the addon loads.
for _, f in ipairs(W.frames) do f.events = {} end
H.loadAddon({}, isEngineFile)
local fireUpgrade = world.fire
fireUpgrade("ADDON_LOADED", "GestureCommands"); fireUpgrade("PLAYER_LOGIN")
world.combat = true
fireUpgrade("PLAYER_ENTERING_WORLD")
check(findMacro("Call of the Elem") ~= nil, "upgrade in combat: waits")
world.combat = false
fireUpgrade("PLAYER_REGEN_ENABLED"); runTimers()
check(findMacro("Call of the Elem") == nil, "upgrade: the addon's old gesture macro is deleted")
check(world.actions[61][1] == "spell" and world.actions[61][2] == 66842, "upgrade: the slot that held it now holds the Tap spell")
check(findMacro("Healing Wave") and world.actions[62][1] == "macro", "upgrade: a macro the player edited is left alone (and stays on its slot)")
check(#MACROS == userMacros + 1, "upgrade: no other macros touched")
local forgot = true; for _, gesture in ipairs(GestureCommandsCharDB.gestures) do if gesture.macro then forgot = false end end
check(forgot, "upgrade: gestures no longer point at macros")
check(printed[#printed]:find("removed 1 macro "), "upgrade: tells the player")
local printedBefore = #printed
fireUpgrade("PLAYER_ENTERING_WORLD")
check(#printed == printedBefore, "upgrade: runs once")

H.finish()
