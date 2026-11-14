-- Ways in besides /gestures: a key binding and a Settings > AddOns entry. (The minimap button and the
-- menu dial entry have their own files.)

local _, ns = ...;

-- Key binding (Bindings.xml): Options > Keybindings > AddOns.
BINDING_HEADER_GESTURECOMMANDS = "Gesture Commands";
BINDING_NAME_GESTURECOMMANDS_TOGGLE = "Open / close the setup window";
function GestureCommands_ToggleConfig()
	ns.ToggleConfig();
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
		ns.OpenConfig();
	end);
	panel.OnCommit = function() end;
	panel.OnDefault = function() end;
	panel.OnRefresh = function() end;
	local category = Settings.RegisterCanvasLayoutCategory(panel, "Gesture Commands");
	Settings.RegisterAddOnCategory(category);
end

RegisterSettings();
