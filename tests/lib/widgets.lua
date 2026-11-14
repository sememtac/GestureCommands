-- Strict widget mocks. Each widget type has an explicit method table; anything else is nil, as in the game,
-- so calling an unimplemented method fails the test instead of silently doing nothing. Events go to every
-- frame registered for them and OnUpdate runs on visible frames, like the game, so tests never need to find
-- the addon's frames.
--
-- Fields tests can read: kind, name, parent, template, shown, scripts, attrs, events, text, texture, atlas,
-- point (last SetPoint args), strata, level, enabled, checked, desaturated, textColor, locked, protected,
-- inputKey, center (set by tests for GetCenter).
local W = { frames = {}, focused = nil, inSecure = false, violations = {} }
local world -- set by W.install

local function classOf(kind)
	if kind == "Button" or kind == "CheckButton" or kind == "EditBox" or kind == "Frame" or kind == "Minimap" then return "Frame" end
	return kind
end

local Region = {}
function Region:SetPoint(...) self.point = { ... }; self.points = self.points or {}; self.points[#self.points + 1] = self.point end
function Region:ClearAllPoints() self.point = nil; self.points = {} end
function Region:SetAllPoints(target) self.point = { "ALL", target } end
function Region:SetSize(w, h) self.width, self.height = w, h end
function Region:SetWidth(w) self.width = w end
function Region:SetHeight(h) self.height = h end
function Region:GetWidth() return self.width or 0 end
function Region:SetAlpha(a) self.alpha = a end
function Region:IsShown() return self.shown end
function Region:IsVisible()
	if not self.shown then return false end
	if self.parent and self.parent.IsVisible then return self.parent:IsVisible() end
	return true
end
function Region:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Region:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:GetParent() return self.parent end
function Region:IsObjectType(t)
	if self.kind == t then return true end
	if t == "Button" and self.kind == "CheckButton" then return true end
	if t == "Frame" and classOf(self.kind) == "Frame" then return true end
	return false
end

local Texture = setmetatable({}, { __index = Region })
function Texture:SetTexture(t) self.texture = t end
function Texture:SetAtlas(a) self.atlas = a end
function Texture:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Texture:SetTexCoord(...) self.texCoord = { ... } end
function Texture:SetBlendMode(m) self.blend = m end
function Texture:SetDesaturated(v) self.desaturated = v end
function Texture:SetVertexColor(r, g, b, a) self.vertexColor = { r, g, b, a } end
function Texture:AddMaskTexture(m) self.masks = self.masks or {}; self.masks[#self.masks + 1] = m end

local MaskTexture = setmetatable({}, { __index = Region })
function MaskTexture:SetTexture(t) self.texture = t end

local FontString = setmetatable({}, { __index = Region })
function FontString:SetText(t) self.text = t end
function FontString:GetText() return self.text end
function FontString:SetJustifyH(v) self.justifyH = v end
function FontString:SetJustifyV(v) self.justifyV = v end
function FontString:SetWordWrap(v) self.wordWrap = v end
function FontString:SetTextColor(r, g, b) self.textColor = { r, g, b } end

local Frame = setmetatable({}, { __index = Region })
function Frame:SetScript(k, fn) self.scripts[k] = fn end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, fn)
	local old = self.scripts[k]
	self.scripts[k] = function(...) if old then old(...) end; fn(...) end
end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:UnregisterEvent(e) self.events[e] = nil end
function Frame:SetAttribute(k, v)
	if self.protected and world.inCombat() and not W.inSecure then
		error("addon SetAttribute on a protected frame in combat: " .. tostring(k), 2)
	end
	if self.blizzard and not W.inSecure then W.violations[#W.violations + 1] = tostring(k) end
	if world.onSetAttribute then world.onSetAttribute(self, k, v) else self.attrs[k] = v end
end
function Frame:GetAttribute(k) return self.attrs[k] end
function Frame:CreateTexture() return W.region("Texture", self) end
function Frame:CreateFontString() return W.region("FontString", self) end
function Frame:CreateMaskTexture() return W.region("MaskTexture", self) end
function Frame:SetFrameStrata(v) self.strata = v end
function Frame:GetFrameStrata() return self.strata or "MEDIUM" end
function Frame:SetFrameLevel(v) self.level = v end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:EnableMouse(v) self.mouse = v end
function Frame:SetMovable(v) self.movable = v end
function Frame:RegisterForDrag(...) self.drag = { ... } end
function Frame:StartMoving() self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:SetClampedToScreen(v) self.clamped = v end
function Frame:SetToplevel(v) self.toplevel = v end
function Frame:GetName() return self.name end
function Frame:GetCenter() if self.center then return self.center[1], self.center[2] end end
function Frame:GetEffectiveScale() return self.scale or 1 end
function Frame:GetID() return self.id or 0 end
function Frame:SetID(id) self.id = id end

local Button = setmetatable({}, { __index = Frame })
function Button:RegisterForClicks(...) self.clicks = { ... } end
function Button:SetHighlightTexture(t) self.highlight = t end
function Button:SetEnabled(v) self.enabled = not not v end
function Button:Enable() self.enabled = true end
function Button:Disable() self.enabled = false end
function Button:IsEnabled() return self.enabled end
function Button:LockHighlight() self.locked = true end
function Button:UnlockHighlight() self.locked = false end
function Button:SetText(t) self.text = t end
function Button:GetText() return self.text end
function Button:Click(mouseButton)
	if self.kind == "CheckButton" then self.checked = not self.checked end
	if self.scripts.OnClick then self.scripts.OnClick(self, mouseButton or "LeftButton", false) end
end

local CheckButton = setmetatable({}, { __index = Button })
function CheckButton:SetChecked(v) self.checked = not not v end
function CheckButton:GetChecked() return self.checked end

local EditBox = setmetatable({}, { __index = Frame })
function EditBox:SetText(t) self.text = t end
function EditBox:GetText() return self.text end
function EditBox:SetAutoFocus(v) self.autoFocus = v end
function EditBox:SetMaxLetters(n) self.maxLetters = n end
function EditBox:SetFocus() W.focused = self end
function EditBox:ClearFocus() if W.focused == self then W.focused = nil end end
function EditBox:HasFocus() return W.focused == self end
function EditBox:IsEnabled() return self.enabled ~= false end

-- InputIconTextureFrameTemplate (Blizzard's controller-glyph widget).
local InputIcon = setmetatable({}, { __index = Frame })
function InputIcon:SetInputKey(key) assert(type(key) == "string", "SetInputKey needs a key name"); self.inputKey = key end

local CLASSES = { Texture = Texture, FontString = FontString, MaskTexture = MaskTexture, Frame = Frame, Button = Button,
	CheckButton = CheckButton, EditBox = EditBox, InputIcon = InputIcon }

local function new(kind, parent, class)
	local o = { kind = kind, parent = parent, shown = true, scripts = {}, attrs = {}, events = {}, enabled = true, checked = false }
	return setmetatable(o, { __index = CLASSES[class or kind] or Frame })
end

function W.region(kind, parent)
	local r = new(kind, parent)
	W.frames[#W.frames + 1] = r
	return r
end

local function hasTemplate(template, name)
	return template ~= nil and (", " .. template .. ","):find(", " .. name .. ",", 1, true) ~= nil
end
W.hasTemplate = hasTemplate

function W.CreateFrame(kind, name, parent, template)
	local class = kind
	if hasTemplate(template, "UICheckButtonTemplate") then kind, class = "CheckButton", "CheckButton" end
	if hasTemplate(template, "InputBoxTemplate") then kind, class = "EditBox", "EditBox" end
	if hasTemplate(template, "InputIconTextureFrameTemplate") then class = "InputIcon" end
	assert(CLASSES[class] or class == "Frame", "CreateFrame: unsupported type " .. tostring(kind))
	local f = new(kind, parent, class)
	f.name, f.template = name, template
	if template and (template:find("SecureHandler") or template:find("SecureActionButton")) then f.protected = true end
	if hasTemplate(template, "BasicFrameTemplateWithInset") then f.CloseButton = W.CreateFrame("Button", nil, f) end
	if hasTemplate(template, "FocusFramesInterfaceTemplate") then
		for _, key in ipairs({ "LeftJumpHint", "RightJumpHint", "FocusJumpHint" }) do
			f[key] = W.CreateFrame("Frame", nil, f, "InputIconTextureFrameTemplate")
			f[key].shown = false
		end
		local glow = W.CreateFrame("Frame", nil, f)
		glow.shown = false
		glow.OnLoad = function(self) self.loadedWithLayout = rawget(f, "layoutType") end
		f.FrameGlow = glow
	end
	if name then _G[name] = f end
	W.frames[#W.frames + 1] = f
	return f
end

-- The game's event delivery: every frame registered for the event, in creation order.
function W.fireEvent(event, ...)
	for _, f in ipairs(W.frames) do
		if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

-- One frame: OnUpdate on every visible frame.
function W.update(elapsed)
	for _, f in ipairs(W.frames) do
		if f.scripts and f.scripts.OnUpdate and f:IsVisible() then f.scripts.OnUpdate(f, elapsed or 0.016) end
	end
end

function W.findByText(text, parent)
	for _, f in ipairs(W.frames) do
		if f.text == text and (not parent or f.parent == parent) then return f end
	end
end

-- world: inCombat(), onSetAttribute(frame, k, v) (optional).
function W.install(w)
	world = w
	CreateFrame = W.CreateFrame
end

return W
