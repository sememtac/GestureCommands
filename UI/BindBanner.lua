-- Bind banner: shown while Bind (place mode) waits for a crossbar press.

local _, ns = ...;

local banner;

local function ShowBindBanner(gesture, endsAt)
	if not gesture then
		if banner then
			banner:Hide();
		end
		return;
	end
	if not banner then
		banner = CreateFrame("Frame", nil, UIParent);
		banner:SetSize(470, 74);
		banner:SetPoint("TOP", 0, -140);
		banner:SetFrameStrata("DIALOG");
		local background = banner:CreateTexture(nil, "BACKGROUND");
		background:SetAllPoints();
		background:SetColorTexture(0, 0, 0, 0.65);
		banner.Icon = banner:CreateTexture(nil, "ARTWORK");
		banner.Icon:SetSize(44, 44);
		banner.Icon:SetPoint("LEFT", 12, 0);
		banner.Title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
		banner.Title:SetPoint("TOPLEFT", banner.Icon, "TOPRIGHT", 12, 2);
		banner.Footer = ns.Nav.CreatePromptFooter(banner);
		banner.Footer:SetPoint("LEFT", banner.Icon, "RIGHT", 12, -2);
		banner.Footer:SetPrompts({ { GAMEPAD_SHOULDER_LEFT, "+" }, { GAMEPAD_SHOULDER_RIGHT, "+" },
			{ GAMEPAD_DPAD_LEFT, "/" }, { GAMEPAD_DPAD_RIGHT, "Change page" } });
		banner.Hint = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
		banner.Hint:SetPoint("BOTTOMLEFT", banner.Icon, "BOTTOMRIGHT", 12, -4);
		banner:SetScript("OnUpdate", function(self)
			local secondsLeft = math.max(0, math.ceil(self.endsAt - GetTime()));
			if secondsLeft ~= self.secondsLeft then
				self.secondsLeft = secondsLeft;
				self.Hint:SetText(("Open /gestures to cancel.  %d s"):format(secondsLeft));
			end
		end);
	end
	banner.Icon:SetTexture(ns.GetGestureIcon(gesture));
	banner.Title:SetText(("Bind %s: press its crossbar button"):format(ns.GetGestureName(gesture)));
	banner.endsAt = endsAt;
	banner.secondsLeft = nil;
	banner:Show();
end
ns.OnPlacingChanged = ShowBindBanner;
