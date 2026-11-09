-- Gesture Commands: controller navigation for our own windows.
--
-- Blizzard's gamepad UI (SmartNavigation and its frame focus manager) can't take an addon window without
-- tainting its shared state, after which Blizzard blocks its own crossbar and interact code. So our windows
-- don't join it: while one is open, out of combat, our own priority override bindings take the D-pad and
-- the A, B and X buttons, and a highlight moves between the window's controls. A secure state driver drops
-- the bindings the moment combat starts, so the crossbar always has its D-pad in a fight.
--
-- A panel is a frame with GetNavControls() (its buttons, check buttons and edit boxes) and optionally
-- GetNavDefault() and OnNavBack(); open it with ns.Nav.Open(panel) from OnShow and ns.Nav.Close(panel) from
-- OnHide.

local _, ns = ...;

local Nav = {};
ns.Nav = Nav;

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
local activating = false;

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

-------------------------------------------------------------------------------
-- Bindings
-------------------------------------------------------------------------------

local function OwnsKeys()
	for key, command in pairs(KEYS) do
		if GetBindingAction(key, true) ~= ("CLICK %s:%s"):format(INPUT_NAME, command) then
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
		SetOverrideBindingClick(owner, true, key, INPUT_NAME, command);
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
-- Highlight
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

local function Activate(control)
	if control:IsObjectType("EditBox") then
		control:SetFocus();
		return;
	end
	activating = true;
	local ok, err = pcall(control.Click, control, "LeftButton");
	activating = false;
	if not ok then
		geterrorhandler()(err);
	end
end

-- True while a control is being clicked with the controller's A button (not the mouse).
function Nav.IsActivating()
	return activating;
end

local function OnInput(command)
	local panel = TopPanel();
	if not panel then
		return;
	end
	if command == "B" then
		if current and current:IsObjectType("EditBox") and current:HasFocus() then
			current:ClearFocus();
		elseif panel.OnNavBack then
			panel:OnNavBack();
		else
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

-------------------------------------------------------------------------------
-- Panels
-------------------------------------------------------------------------------

local function Remove(panel)
	for index = #panels, 1, -1 do
		if panels[index] == panel then
			table.remove(panels, index);
			return true;
		end
	end
	return false;
end

function Nav.Open(panel)
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

function Nav.Close(panel)
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

-- Moves the highlight to a control of the topmost panel.
function Nav.Select(control)
	if TopPanel() and IsUsable(control) then
		Select(control);
	end
end

-- After a panel changes which controls are shown or enabled: keep the highlight on a usable one.
function Nav.Refresh()
	local panel = TopPanel();
	if not panel then
		return;
	end
	if not IsUsable(current) then
		Select(nil);
		Select(FindDefault(panel, panel.navCurrent));
	end
end

local events = CreateFrame("Frame");
events:RegisterEvent("PLAYER_REGEN_DISABLED");
events:RegisterEvent("PLAYER_REGEN_ENABLED");
events:RegisterEvent("UPDATE_BINDINGS");
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		-- The secure driver has dropped the bindings.
		bound = false;
	elseif event == "PLAYER_REGEN_ENABLED" then
		RegisterCombatDriver();
		if #panels > 0 then
			Bind();
		end
	elseif event == "UPDATE_BINDINGS" and bound and not checkPending then
		checkPending = true;
		C_Timer.After(0, CheckKeys);
	end
end);
