-- Feedback while holding: a rumble (two for a long hold) and "Release for <action>" when a hold stage arms.
-- A read-only poll of the secure header, which also finishes place mode and prints debug output.

local _, ns = ...;
local Engine = ns.Engine;
local header = ns.header;

local RUMBLE_INTENSITY, RUMBLE_TIME, DOUBLE_RUMBLE_GAP = 0.5, 0.15, 0.25;

function Engine.Rumble()
	if C_GamePad and C_GamePad.SetVibration then
		C_GamePad.SetVibration("Low", RUMBLE_INTENSITY);
		C_Timer.After(RUMBLE_TIME, function() C_GamePad.StopVibration(); end);
	end
end

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
		ns.Print("secure hook ran: " .. tostring(header:GetAttribute("debugLast")));
	end

	local stage = header:GetAttribute("armed") or 0;
	if stage ~= lastStage and stage > 0 then
		local gesture = ns.DB() and ns.DB().gestures[header:GetAttribute("armedGesture") or 0];
		local mode = ns.MODES[stage];
		local name = ns.GetActionDisplay(gesture and gesture[mode]);
		Engine.Rumble();
		if stage == 2 then
			C_Timer.After(DOUBLE_RUMBLE_GAP, Engine.Rumble);
		end
		UIErrorsFrame:AddMessage("Release for " .. (name or ns.MODE_LABELS[mode]), 0.2, 1, 0.6);
	end
	lastStage = stage;
end);
