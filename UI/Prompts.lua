-- Controller look for our windows: Blizzard's jump hints and focus glow, and a prompt footer.

local _, ns = ...;
local Nav = ns.Nav;

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
