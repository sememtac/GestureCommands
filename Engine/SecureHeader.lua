-- The secure gesture engine. All of the decision making is secure. Each crossbar button's OnClick is wrapped
-- (SecureHandlerWrapScript): a press on a Tap slot is held back, and the release either runs the slot's own
-- action or casts the hold / long-hold action through a virtual button ("*type-GestureCast"). The restricted
-- environment has no clock, so a self-resetting state driver provides a secure tick (~0.2 s, sooner when the
-- game fires driver events) and holds are counted in ticks. Addon code only publishes configuration as header
-- attributes out of combat (Publish.lua) and reads the header's "armed" attribute for feedback; it never
-- writes to Blizzard's buttons.

local _, ns = ...;
local Engine = ns.Engine;

local header = CreateFrame("Frame", "GestureCommandsHeader", UIParent, "SecureHandlerStateTemplate");
header:SetAttribute("enabled", false);
header:SetAttribute("armed", 0);
header:SetAttribute("holdTicks", ns.DEFAULT_HOLD_TICKS);
header:SetAttribute("hold2Ticks", ns.DEFAULT_HOLD2_TICKS);
ns.header = header;

-- Secure tick: the driver always resolves to "tock"; resetting the attribute to "tick" makes the next
-- driver update count as a change. "armed" is the hold stage: 0 tap, 1 hold, 2 long hold. A stage only arms
-- if the pressed gesture has an action for it. A press that is never released is dropped after ~5 s.
header:SetAttribute("_onstate-tick", ns.Snippet("_onstate-tick", [[
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
]]));

-- Runs before Blizzard's OnClick on every wrapped crossbar button. Taps are looked up by slot number
-- ("g:slot:<n>", for mount, toy and macro Taps) or by what the slot shows ("g:spell:<id>" / "g:item:<id>";
-- a macro counts as what it shows); each holds the gesture number. The secure compiler refuses snippets with
-- the word "function" or a brace (see ns.Snippet), so the slot lookup is written out twice rather than shared.
local PRE_CLICK = ns.Snippet("OnClick-pre", [[
	-- The release of the press that placed a gesture does nothing either (a mouse click acts on release).
	if placedSlot then
		local placed = placedSlot;
		placedSlot = nil;
		if not down and placed == self:GetID() then
			return false;
		end
	end
	-- Place mode: the next crossbar press only says where to put a gesture. Not in combat: there every press
	-- does its action, and the gesture waits for a press after the fight.
	if control:GetAttribute("placing") and SecureCmdOptionParse("[combat] 1; 0") ~= "1" then
		if down then
			control:SetAttribute("placing", false);
			control:SetAttribute("placeSlot", self:GetID());
			placedSlot = self:GetID();
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
		-- The gesture this slot holds: by its number (a mount, toy or macro Tap), else by what it shows (a
		-- spell or item; a macro counts as what it shows).
		local gesture = control:GetAttribute("g:slot:" .. slot);
		if not gesture then
			local kind, id, subType = GetActionInfo(slot);
			if kind == "macro" then
				kind = subType;
			end
			if (kind == "spell" or kind == "item") and id then
				gesture = control:GetAttribute("g:" .. kind .. ":" .. id);
			end
		end
		if not gesture then
			return;
		end
		pressedSlot = slot;
		pressedPosition = control:GetAttribute("pos:" .. (self:GetName() or ""));
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
	if pressedSlot ~= slot and control:GetAttribute("pos:" .. (self:GetName() or "")) ~= pressedPosition then
		-- Another crossbar button released while the gesture is held: not ours.
		return;
	end
	local stage = armed or 0;
	local gesture = pressedGesture;
	armed = 0;
	pressedGesture = nil;
	control:SetAttribute("armed", 0);
	if pressedSlot ~= slot then
		-- The bar or page changed mid-hold: the release arrives at another bar's button in the same place,
		-- or at the same button now showing another page's slot. Drop the press.
		pressedSlot = nil;
		return;
	end
	pressedSlot = nil;

	-- The slot must still hold this gesture's Tap (the same lookup as on the press).
	local current = control:GetAttribute("g:slot:" .. slot);
	if not current then
		local kind, id, subType = GetActionInfo(slot);
		if kind == "macro" then
			kind = subType;
		end
		if (kind == "spell" or kind == "item") and id then
			current = control:GetAttribute("g:" .. kind .. ":" .. id);
		end
	end
	if current ~= gesture then
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
]]);

local POST_CLICK = ns.Snippet("OnClick-post", [[
	if message == "restore" then
		self:SetAttribute("useOnKeyDown", savedUseOnKeyDown);
		savedUseOnKeyDown = nil;
	end
]]);

local wrapped = {}; -- crossbar button -> true once its OnClick is wrapped
ns.wrapped = wrapped;

-- Wraps every crossbar button not wrapped yet (out of combat). "pos:<button name>" is the button's place on
-- its bar: the same physical button on every bar, so the secure code can tell a release after a bar or page
-- change from another button's release. By name, because changing page gives the same buttons new slots.
function Engine.WrapCrossbarButtons()
	for _, info in ipairs(ns.GetCrossbarButtons()) do
		local name = info.button:GetName();
		if name then
			header:SetAttribute("pos:" .. name, info.index);
		end
		if not wrapped[info.button] then
			local ok, err = pcall(SecureHandlerWrapScript, info.button, "OnClick", header, PRE_CLICK, POST_CLICK);
			if ok then
				wrapped[info.button] = true;
			else
				ns.Print(("could not hook %s button %d: %s"):format(info.bar, info.index, tostring(err)));
			end
		end
	end
end

-- After a reload in combat, once combat ends.
ns.On("PLAYER_LOGIN", function()
	ns.AfterCombat(function()
		RegisterStateDriver(header, "tick", "tock");
	end);
end);
