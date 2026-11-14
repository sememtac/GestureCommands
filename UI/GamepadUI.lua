-- Blizzard's gamepad UI (the default in controller mode): our windows join it like its own panels. This only
-- goes through the functions Blizzard wraps for outside callers (FrameShown, FrameHidden,
-- HandlePopupShown/Hide, RefreshButtonGroups), only out of combat, and our frames never set the fields its
-- focus manager reads directly (returnToPlayerControl and the like): any of that taints Blizzard's gamepad
-- state, after which it blocks its own crossbar code. The windows close when combat starts, while Blizzard
-- still takes the change, so its focus list never keeps a hidden window. See Navigation.lua.

local _, ns = ...;
local Nav = ns.Nav;

local registered = {}; -- panel -> true (frame) or "popup", while Blizzard's focus manager has it
local blizzardPanels = {}; -- open panel -> isPopup

local function GetFrameControlsManager()
	return GamepadMode and GamepadMode.FrameControlsManager;
end

-- Whether the focus manager lists the panel (nil if we can't tell). Needed because its wrapped functions
-- don't raise an error when they refuse a call (in combat): they return nothing, and the popup ones return
-- nothing even when they do take it.
local function IsListed(manager, panel)
	local shownFrames = manager.shownFrames;
	if type(shownFrames) ~= "table" then
		return nil;
	end
	for _, frame in ipairs(shownFrames) do
		if frame == panel then
			return true;
		end
	end
	return false;
end

local function Register(panel)
	local manager = GetFrameControlsManager();
	if registered[panel] or not manager or InCombatLockdown() then
		return;
	end
	local isPopup = blizzardPanels[panel];
	local ok, result;
	if isPopup then
		ok, result = pcall(manager.HandlePopupShown, manager, panel);
		result = ok or nil;
	else
		-- true if added, false if it already was; nothing if refused.
		ok, result = pcall(manager.FrameShown, manager, panel, false, true);
	end
	local listed = IsListed(manager, panel);
	if listed or (listed == nil and ok and result ~= nil) then
		registered[panel] = isPopup and "popup" or true;
	end
end

-- A refused call leaves the panel registered, so it's retried after combat.
local function Unregister(panel)
	local manager = GetFrameControlsManager();
	if not registered[panel] or not manager or InCombatLockdown() then
		return;
	end
	local ok, result;
	if registered[panel] == "popup" then
		ok, result = pcall(manager.HandlePopupHide, manager, panel);
		result = ok or nil;
	else
		ok, result = pcall(manager.FrameHidden, manager, panel);
	end
	local listed = IsListed(manager, panel);
	if listed == false or (listed == nil and ok and result ~= nil) then
		registered[panel] = nil;
	end
end

Nav.modes.blizzard = {
	Open = function(panel, isPopup)
		blizzardPanels[panel] = isPopup and true or false;
		Register(panel);
	end,

	Close = function(panel)
		blizzardPanels[panel] = nil;
		Unregister(panel);
	end,

	-- SmartNavigation collects a panel's buttons when it opens; rescan after showing or hiding some.
	Refresh = function(panel)
		if registered[panel] and not InCombatLockdown() and SmartNavigation and SmartNavigation.RefreshButtonGroups then
			pcall(SmartNavigation.RefreshButtonGroups, SmartNavigation, panel);
		end
	end,
};

-- Windows close when combat starts, while Blizzard still takes the change.
ns.On("PLAYER_REGEN_DISABLED", function()
	local open = {};
	for panel in pairs(blizzardPanels) do
		table.insert(open, panel);
	end
	for _, panel in ipairs(open) do
		panel:Hide();
	end
end);

-- Catch up on windows opened or closed in combat.
ns.On("PLAYER_REGEN_ENABLED", function()
	for panel in pairs(registered) do
		if blizzardPanels[panel] == nil then
			Unregister(panel);
		end
	end
	for panel in pairs(blizzardPanels) do
		Register(panel);
	end
end);
