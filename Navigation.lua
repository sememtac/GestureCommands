-- Gesture Commands: controller navigation for our windows. Open a window's panel with ns.Nav.Open(panel,
-- isPopup) from OnShow and ns.Nav.Close(panel) from OnHide.
--
-- By default (game in controller mode) the windows join Blizzard's gamepad UI like its own panels: LT / RT
-- and the View button reach them, SmartNavigation moves its cursor over their buttons, A clicks and B
-- closes. This only goes through the functions Blizzard wraps for outside callers (FrameShown, FrameHidden,
-- HandlePopupShown/Hide, RefreshButtonGroups), only out of combat, and our frames never set the fields its
-- focus manager reads directly (returnToPlayerControl and the like): any of that taints Blizzard's gamepad
-- state, after which it blocks its own crossbar code. The windows close when combat starts, while Blizzard
-- still takes the change, so its focus list never keeps a hidden window.
--
-- `/gestures padnav own` switches to our own navigation instead: while a window is open, out of combat, our
-- priority override bindings take the D-pad and A, B and X, and a highlight moves between the controls the
-- panel lists in GetNavControls() (GetNavDefault() picks the first). A secure state driver drops the
-- bindings when combat starts. Both honour a control's OnSmartNavClick and a panel's
-- SmartNavigationCloseHandler; a secure button marked navSecureClick gets A bound to it while highlighted.

local _, ns = ...;

local Nav = {};
ns.Nav = Nav;

local function UsesGamepadUI()
	return C_InputInterfaceStyle ~= nil and C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad;
end

local panelModes = {}; -- open panel -> "blizzard" | "own"

-------------------------------------------------------------------------------
-- Blizzard's gamepad UI
-------------------------------------------------------------------------------

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

-- SmartNavigation collects a panel's buttons when it opens; rescan after showing or hiding some.
local function RefreshButtonGroups(panel)
	if registered[panel] and not InCombatLockdown() and SmartNavigation and SmartNavigation.RefreshButtonGroups then
		pcall(SmartNavigation.RefreshButtonGroups, SmartNavigation, panel);
	end
end

-------------------------------------------------------------------------------
-- Own navigation: bindings
-------------------------------------------------------------------------------

local INPUT_NAME = "GestureCommandsNavInput";
local KEYS = {
	PADDUP = "UP",
	PADDDOWN = "DOWN",
	PADDLEFT = "LEFT",
	PADDRIGHT = "RIGHT",
	PAD1 = "A",
	PAD2 = "B",
	PAD3 = "X",
};
local DIRECTIONS = {
	UP = { 0, 1 },
	DOWN = { 0, -1 },
	LEFT = { -1, 0 },
	RIGHT = { 1, 0 },
};

local panels = {}; -- open panels, topmost last
local current = nil; -- highlighted control of the topmost panel
local bound = false;
local gaveUp = false;

-- Owns the override bindings. Secure, so it can drop them when combat starts: addon code can't change
-- bindings in combat.
local owner = CreateFrame("Frame", "GestureCommandsNavOwner", UIParent, "SecureHandlerStateTemplate");
owner:SetAttribute("_onstate-combat", [[
	if newstate == "1" then
		self:ClearBindings();
	end
]]);
local driverRegistered = false;
local function RegisterCombatDriver()
	if not driverRegistered and not InCombatLockdown() then
		RegisterStateDriver(owner, "combat", "[combat] 1; 0");
		driverRegistered = true;
	end
end
RegisterCombatDriver();

-- The bindings click this button, with the command as the mouse button.
local input = CreateFrame("Button", INPUT_NAME, UIParent);
input:RegisterForClicks("AnyDown");

local highlight = CreateFrame("Frame", nil, UIParent);
highlight:SetFrameStrata("FULLSCREEN_DIALOG");
highlight:Hide();
local function CreateEdge(point1, point2, width, height)
	local edge = highlight:CreateTexture(nil, "OVERLAY");
	edge:SetColorTexture(1, 0.82, 0, 1);
	edge:SetPoint(point1);
	edge:SetPoint(point2);
	if width then
		edge:SetWidth(width);
	else
		edge:SetHeight(height);
	end
end
CreateEdge("TOPLEFT", "TOPRIGHT", nil, 2);
CreateEdge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 2);
CreateEdge("TOPLEFT", "BOTTOMLEFT", 2, nil);
CreateEdge("TOPRIGHT", "BOTTOMRIGHT", 2, nil);

-- What a key clicks: our input button, or for A a highlighted secure button itself (navSecureClick). Addon
-- code can't click a secure button, but a key bound to it is a real press.
local function GetClickTarget(key, command)
	if key == "PAD1" and current and current.navSecureClick then
		return current:GetName(), "LeftButton";
	end
	return INPUT_NAME, command;
end

local function OwnsKeys()
	for key, command in pairs(KEYS) do
		if GetBindingAction(key, true) ~= ("CLICK %s:%s"):format(GetClickTarget(key, command)) then
			return false;
		end
	end
	return true;
end

-- Cleared first so ours are the newest overrides, which take precedence over older ones (Blizzard's gamepad
-- code sets its own on UIParent).
local function Bind()
	if InCombatLockdown() then
		return;
	end
	ClearOverrideBindings(owner);
	for key, command in pairs(KEYS) do
		SetOverrideBindingClick(owner, true, key, GetClickTarget(key, command));
	end
	bound = true;
end

local function Unbind()
	if bound and not InCombatLockdown() then
		ClearOverrideBindings(owner);
	end
	bound = false;
end

-- Blizzard's gamepad code re-applies its overrides when its own focus changes; take the keys back once if
-- that left ours underneath, and stop trying if it didn't help (no loop).
local checkPending = false;
local function CheckKeys()
	checkPending = false;
	if bound and not gaveUp and not InCombatLockdown() and not OwnsKeys() then
		Bind();
		if not OwnsKeys() then
			gaveUp = true;
			ns.Print("couldn't take over the D-pad for this window - use the mouse, or close other windows first.");
		end
	end
end

function Nav.IsBound()
	return bound;
end

-------------------------------------------------------------------------------
-- Own navigation: highlight
-------------------------------------------------------------------------------

local function TopPanel()
	return panels[#panels];
end

local function IsUsable(control)
	return control ~= nil and control:IsVisible() and (control.IsEnabled == nil or control:IsEnabled()) and true or false;
end

local function FindDefault(panel, preferred)
	if IsUsable(preferred) then
		return preferred;
	end
	local default = panel.GetNavDefault and panel:GetNavDefault();
	if IsUsable(default) then
		return default;
	end
	for _, control in ipairs(panel:GetNavControls()) do
		if IsUsable(control) then
			return control;
		end
	end
	return nil;
end

local function Select(control)
	if current == control then
		return;
	end
	local previous = current;
	current = control;
	if bound and not InCombatLockdown() and ((previous and previous.navSecureClick) or (control and control.navSecureClick)) then
		SetOverrideBindingClick(owner, true, "PAD1", GetClickTarget("PAD1", "A"));
	end
	if previous then
		if previous:IsObjectType("EditBox") then
			previous:ClearFocus();
		end
		if previous.UnlockHighlight then
			previous:UnlockHighlight();
		end
		local onLeave = previous:GetScript("OnLeave");
		if onLeave then
			onLeave(previous);
		end
	end
	if not control then
		highlight:Hide();
		return;
	end
	highlight:ClearAllPoints();
	highlight:SetPoint("TOPLEFT", control, "TOPLEFT", -3, 3);
	highlight:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", 3, -3);
	highlight:Show();
	if control.LockHighlight then
		control:LockHighlight();
	end
	-- Show the control's tooltip, as hovering it with the mouse would.
	local onEnter = control:GetScript("OnEnter");
	if onEnter then
		onEnter(control);
	end
end

-- The nearest usable control in a direction: mostly along it, with sideways distance counting double.
local function FindNext(panel, from, dx, dy)
	local fromX, fromY = from:GetCenter();
	if not fromX then
		return nil;
	end
	local best, bestScore;
	for _, control in ipairs(panel:GetNavControls()) do
		if control ~= from and IsUsable(control) then
			local x, y = control:GetCenter();
			if x then
				local offsetX, offsetY = x - fromX, y - fromY;
				local along = offsetX * dx + offsetY * dy;
				if along > 4 then
					local score = along + 2 * (math.abs(offsetX * dy) + math.abs(offsetY * dx));
					if not bestScore or score < bestScore then
						best, bestScore = control, score;
					end
				end
			end
		end
	end
	return best;
end

-- Like SmartNavigation: a control's OnSmartNavClick replaces the click.
local function Activate(control)
	local ok, err;
	if control.navSecureClick then
		return; -- A is bound to the button itself while it's highlighted
	elseif control.OnSmartNavClick then
		ok, err = pcall(control.OnSmartNavClick, control);
	elseif control:IsObjectType("EditBox") then
		ok = true;
		control:SetFocus();
	else
		ok, err = pcall(control.Click, control, "LeftButton");
	end
	if not ok then
		geterrorhandler()(err);
	end
end

local function OnInput(command)
	local panel = TopPanel();
	if not panel then
		return;
	end
	if command == "B" then
		if current and current:IsObjectType("EditBox") and current:HasFocus() then
			current:ClearFocus();
		elseif not (panel.SmartNavigationCloseHandler and panel:SmartNavigationCloseHandler()) then
			panel:Hide();
		end
		return;
	end
	if not IsUsable(current) then
		Select(FindDefault(panel));
		return;
	end
	local direction = DIRECTIONS[command];
	if direction then
		local nextControl = FindNext(panel, current, direction[1], direction[2]);
		if nextControl then
			Select(nextControl);
		end
	elseif command == "A" then
		Activate(current);
	elseif command == "X" and current.OnNavSecondary then
		current:OnNavSecondary();
	end
end
Nav.OnInput = OnInput;

input:SetScript("OnClick", function(_, command)
	OnInput(command);
end);

local function Remove(panel)
	for index = #panels, 1, -1 do
		if panels[index] == panel then
			table.remove(panels, index);
			return true;
		end
	end
	return false;
end

local function OwnOpen(panel)
	local top = TopPanel();
	if top and top ~= panel then
		top.navCurrent = current;
	end
	Remove(panel);
	table.insert(panels, panel);
	Select(nil);
	Select(FindDefault(panel, panel.navCurrent));
	gaveUp = false;
	RegisterCombatDriver();
	Bind();
end

local function OwnClose(panel)
	local wasTop = TopPanel() == panel;
	if not Remove(panel) then
		return;
	end
	if wasTop then
		panel.navCurrent = current;
		Select(nil);
		local top = TopPanel();
		if top then
			Select(FindDefault(top, top.navCurrent));
		end
	end
	if #panels == 0 then
		Unbind();
	end
end

-------------------------------------------------------------------------------
-- Panels
-------------------------------------------------------------------------------

function Nav.UsesOwnNavigation()
	return ns.DB().ownNavigation == true;
end

function Nav.Open(panel, isPopup)
	local mode = Nav.UsesOwnNavigation() and "own" or (UsesGamepadUI() and "blizzard") or nil;
	panelModes[panel] = mode;
	if mode == "own" then
		OwnOpen(panel);
	elseif mode == "blizzard" then
		blizzardPanels[panel] = isPopup and true or false;
		Register(panel);
	end
end

function Nav.Close(panel)
	local mode = panelModes[panel];
	panelModes[panel] = nil;
	if mode == "own" then
		OwnClose(panel);
	elseif mode == "blizzard" then
		blizzardPanels[panel] = nil;
		Unregister(panel);
	end
end

-- Moves our highlight to a control of the topmost panel (own navigation only).
function Nav.Select(control)
	if TopPanel() and IsUsable(control) then
		Select(control);
	end
end

-- After a panel shows, hides or disables some of its controls.
function Nav.Refresh(panel)
	if panelModes[panel] == "blizzard" then
		RefreshButtonGroups(panel);
		return;
	end
	local top = TopPanel();
	if top and not IsUsable(current) then
		Select(nil);
		Select(FindDefault(top, top.navCurrent));
	end
end

Nav.UsesGamepadUI = UsesGamepadUI;

-------------------------------------------------------------------------------
-- Controller look: Blizzard's jump hints and focus glow, and a prompt footer
-------------------------------------------------------------------------------

-- For a frame created with FocusFramesInterfaceTemplate, Blizzard's focus manager shows the LT / RT / View
-- jump hints and the focus glow on it, calling its mixin through a taint barrier. Lift the hints to the
-- frame's strata, and give the glow the frame art Blizzard uses for plain panels.
function Nav.SetUpFocusVisuals(frame)
	for _, key in ipairs({ "LeftJumpHint", "RightJumpHint", "FocusJumpHint" }) do
		if frame[key] then
			frame[key]:SetFrameStrata(frame:GetFrameStrata());
		end
	end
	local glow = frame.FrameGlow;
	if glow and glow.OnLoad then
		frame.layoutType = "ButtonFrameTemplateNoPortrait";
		glow:OnLoad();
	end
end

-- A row of controller button glyphs with labels, like the prompt footers on Blizzard's panels. Drawn only:
-- the buttons themselves are handled by the gamepad UI (or our own navigation).
function Nav.CreatePromptFooter(parent)
	local footer = CreateFrame("Frame", nil, parent);
	footer:SetSize(1, 22);
	footer.entries = {};
	-- prompts: { { gamepad key (GAMEPAD_FACE_BOTTOM...), label }, ... }
	function footer:SetPrompts(prompts)
		local previous;
		for index, prompt in ipairs(prompts) do
			local entry = self.entries[index];
			if not entry then
				entry = { Icon = CreateFrame("Frame", nil, self, "InputIconTextureFrameTemplate") };
				entry.Icon:SetSize(22, 22);
				entry.Label = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
				entry.Label:SetPoint("LEFT", entry.Icon, "RIGHT", 3, 0);
				self.entries[index] = entry;
			end
			entry.Icon:ClearAllPoints();
			if previous then
				entry.Icon:SetPoint("LEFT", previous.Label, "RIGHT", 12, 0);
			else
				entry.Icon:SetPoint("LEFT", self, "LEFT", 0, 0);
			end
			entry.Icon:SetInputKey(prompt[1]);
			entry.Label:SetText(prompt[2]);
			entry.Icon:Show();
			entry.Label:Show();
			previous = entry;
		end
		for index = #prompts + 1, #self.entries do
			self.entries[index].Icon:Hide();
			self.entries[index].Label:Hide();
		end
	end
	return footer;
end

local events = CreateFrame("Frame");
events:RegisterEvent("PLAYER_REGEN_DISABLED");
events:RegisterEvent("PLAYER_REGEN_ENABLED");
events:RegisterEvent("UPDATE_BINDINGS");
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		-- The secure driver has dropped our bindings. Windows in Blizzard's gamepad UI close now, while it
		-- still takes the change.
		bound = false;
		local open = {};
		for panel in pairs(blizzardPanels) do
			table.insert(open, panel);
		end
		for _, panel in ipairs(open) do
			panel:Hide();
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		RegisterCombatDriver();
		if #panels > 0 then
			Bind();
		end
		-- Catch up on windows opened or closed in combat.
		for panel in pairs(registered) do
			if blizzardPanels[panel] == nil then
				Unregister(panel);
			end
		end
		for panel in pairs(blizzardPanels) do
			Register(panel);
		end
	elseif event == "UPDATE_BINDINGS" and bound and not checkPending then
		checkPending = true;
		C_Timer.After(0, CheckKeys);
	end
end);
