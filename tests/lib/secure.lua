-- Emulation of Blizzard's restricted ("secure snippet") execution, built from its source:
-- - BuildRestrictedClosure (RestrictedExecution.lua) refuses a body containing "function" or a brace, and a
--   signature with anything but names, commas, spaces and a trailing "...".
-- - Snippets only see the restricted environment (tests/lib/restricted_env.lua, generated from
--   RestrictedEnvironment.lua / RestrictedExecution.lua) and frame handles only have HANDLE methods
--   (RestrictedFrames.lua); a handle to an unprotected frame is invalid in combat.
-- - GetActionInfo is scrubbed: only spell, companion, item, macro, flyout and outfit actions keep their ID.
local S = {}

local allowed = dofile(debug.getinfo(1, "S").source:gsub("^@", ""):gsub("secure%.lua$", "restricted_env.lua"))
S.build = allowed.build
local ALLOWED_GLOBALS, HANDLE_METHODS = {}, {}
for _, name in ipairs(allowed.globals) do ALLOWED_GLOBALS[name] = true end
for _, name in ipairs(allowed.handleMethods) do HANDLE_METHODS[name] = true end
S.ALLOWED_GLOBALS, S.HANDLE_METHODS = ALLOWED_GLOBALS, HANDLE_METHODS

local SAFE_ACTION_TYPES = { spell = true, companion = true, item = true, macro = true, flyout = true, outfit = true }

-- Blizzard's refusals, with its messages. Returns nil or the error.
function S.compileError(body, signature)
	body, signature = tostring(body or ""), tostring(signature or "self,...")
	if body:match("function") then return "The function keyword is not permitted" end
	if body:match("[{}]") then return "Direct table creation is not permitted" end
	if signature:match("function") then return "The function keyword is not permitted" end
	if not signature:match("^[a-zA-Z_0-9, ]*[.]*$") then return "Signature contains invalid characters (" .. signature .. ")" end
	local ok, err = loadstring("return function (" .. signature .. ") " .. body .. "\nend")
	if not ok then return err end
	return nil
end

local KEYWORDS = {}
for word in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%S+") do
	KEYWORDS[word] = true
end
local STRING_METHODS = {}
for name in pairs(string) do STRING_METHODS[name] = true end

-- Static problems in a snippet: Blizzard's refusals, plus calls / indexing of names the restricted
-- environment doesn't have, and method calls that aren't frame-handle (or string) methods.
function S.staticProblems(body, signature)
	local problems = {}
	local err = S.compileError(body, signature)
	if err then problems[#problems + 1] = err end
	local code = body:gsub("%-%-[^\n]*", ""):gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")
	local known = { self = true, control = true }
	for name in (signature or ""):gmatch("[%a_][%w_]*") do known[name] = true end
	for list in code:gmatch("local%s+([%a_][%w_%s,]*)") do
		for name in list:gmatch("[%a_][%w_]*") do known[name] = true end
	end
	for list in code:gmatch("for%s+([%a_][%w_%s,]*)%s+[=i]") do
		for name in list:gmatch("[%a_][%w_]*") do known[name] = true end
	end
	-- Names that are called or indexed, and aren't a field (after "." or ":").
	local pos = 1
	while true do
		local s, e, name = code:find("([%a_][%w_]*)", pos)
		if not s then break end
		local before = code:sub(1, s - 1):match("([^%s]?)%s*$")
		local after = code:match("^%s*([%(%.:%[]?)", e + 1)
		if before ~= "." and before ~= ":" and after ~= "" and not KEYWORDS[name] and not known[name] and not ALLOWED_GLOBALS[name] then
			problems[#problems + 1] = "uses " .. name .. ", which the restricted environment doesn't have"
		end
		pos = e + 1
	end
	for method in code:gmatch(":%s*([%a_][%w_]*)%s*%(") do
		if not HANDLE_METHODS[method] and not STRING_METHODS[method] then
			problems[#problems + 1] = "calls :" .. method .. "(), which frame handles don't have"
		end
	end
	return problems
end

-- A secure runtime for one test world. `world` provides: GetActionInfo(slot) (unscrubbed), inCombat(),
-- and optionally functions = { name = impl } for restricted globals the snippets use.
function S.new(world)
	local R = { headerEnvs = {}, wraps = {}, drivers = {}, frameRefs = {} }

	local emulated = {
		GetActionInfo = function(slot)
			local kind, id, subType = world.GetActionInfo(slot)
			if SAFE_ACTION_TYPES[kind] then return kind, id, subType end
			return kind
		end,
		format = string.format,
		SecureCmdOptionParse = function(options)
			assert(options == "[combat] 1; 0", "SecureCmdOptionParse: only [combat] is emulated")
			return world.inCombat() and "1" or "0"
		end,
	}
	for name, impl in pairs(world.functions or {}) do emulated[name] = impl end

	local handleCache = setmetatable({}, { __mode = "k" })
	local function handle(frame)
		if handleCache[frame] then return handleCache[frame] end
		local function frameFor()
			if world.inCombat() and not frame.protected then error("Invalid frame handle", 3) end
			return frame
		end
		local methods = {
			GetID = function() return frameFor().id or 0 end,
			GetAttribute = function(_, k) return frameFor().attrs[k] end,
			SetAttribute = function(_, k, v) R.setAttribute(frameFor(), k, v, true) end,
			GetFrameRef = function(_, label)
				local ref = (frameFor().attrs or {})["frameref-" .. label]
				return ref and handle(ref) or nil
			end,
			IsVisible = function() return frameFor():IsVisible() end,
			IsShown = function() return frameFor():IsShown() end,
			Hide = function(_, skipAttr) local f = frameFor(); f:Hide(); if not skipAttr then f.attrs.statehidden = true end end,
			Show = function(_, skipAttr) local f = frameFor(); f:Show(); if not skipAttr then f.attrs.statehidden = nil end end,
			ClearBindings = function() if world.ClearOverrideBindings then world.ClearOverrideBindings(frameFor()) end end,
		}
		local h = setmetatable({}, { __index = function(_, k)
			if methods[k] then return methods[k] end
			if HANDLE_METHODS[k] then error("frame handle method :" .. k .. "() is real but not emulated in tests/lib/secure.lua", 2) end
			return nil
		end })
		handleCache[frame] = h
		return h
	end
	R.handle = handle

	function R.run(header, selfFrame, signature, body, ...)
		local err = S.compileError(body, signature)
		if err then error("Blizzard refuses this snippet: " .. err, 2) end
		R.headerEnvs[header] = R.headerEnvs[header] or {}
		local shared, control = R.headerEnvs[header], handle(header)
		local env = setmetatable({}, {
			__index = function(_, k)
				if k == "control" then return control end
				local v = shared[k]
				if v ~= nil then return v end
				if emulated[k] then return emulated[k] end
				if ALLOWED_GLOBALS[k] then error("restricted function " .. k .. " is real but not emulated in tests/lib/secure.lua", 2) end
				return nil
			end,
			__newindex = function(_, k, v) shared[k] = v end,
		})
		local def = assert(loadstring("return function (" .. signature .. ") " .. body .. "\nend"))
		setfenv(def, {})
		local fn = def()
		setfenv(fn, env)
		local was = world.enterSecure and world.enterSecure()
		local r = { fn(handle(selfFrame), ...) }
		if world.leaveSecure then world.leaveSecure(was) end
		return unpack(r)
	end

	-- Attribute changes on secure handler templates run their snippets (as Blizzard's templates do).
	function R.setAttribute(frame, k, v, fromSecure)
		frame.attrs[k] = v
		if type(k) ~= "string" then return end
		if frame.template and frame.template:find("SecureHandlerStateTemplate") then
			local state = k:match("^state%-(.+)$")
			local body = state and frame.attrs["_onstate-" .. state]
			if body then R.run(frame, frame, "self,stateid,newstate", body, state, v) end
		end
		if frame.template and frame.template:find("SecureHandlerAttributeTemplate") and not k:match("^_") then
			local body = frame.attrs._onattributechanged
			if body then R.run(frame, frame, "self,name,value", body, k, v) end
		end
	end

	function R.wrapScript(frame, script, header, pre, post)
		assert(not world.inCombat(), "SecureHandlerWrapScript in combat")
		assert(script == "OnClick", "only OnClick wraps are emulated")
		local err = S.compileError(pre, "self,button,down") or (post and S.compileError(post, "self,message,button,down"))
		if err then error("Blizzard refuses this snippet: " .. err, 2) end
		R.wraps[frame] = { header = header, pre = pre, post = post }
	end

	-- A click on a wrapped button: pre-body, Blizzard's OnClick (onClick), post-body.
	function R.click(button, mouseButton, down, onClick)
		local w, message = R.wraps[button], nil
		if w then
			local newButton
			newButton, message = R.run(w.header, button, "self,button,down", w.pre, mouseButton, down)
			if newButton == false then return end
			if newButton then mouseButton = tostring(newButton) end
		end
		onClick(button, mouseButton, down)
		if w and w.post and message ~= nil then
			R.run(w.header, button, "self,message,button,down", w.post, message, mouseButton, down)
		end
	end

	function R.registerStateDriver(frame, state, values)
		assert(not world.inCombat(), "RegisterStateDriver in combat")
		R.drivers[frame] = { state = state, values = values }
	end

	-- One state-driver update: drivers whose value resolves differently set their state attribute.
	-- Values with macro conditions resolve like SecureCmdOptionParse (only [combat] is emulated).
	function R.tick()
		for frame, d in pairs(R.drivers) do
			local value = d.values
			if value:find("^%[") then value = emulated.SecureCmdOptionParse(value) end
			local attr = "state-" .. d.state
			if frame.attrs[attr] ~= value then R.setAttribute(frame, attr, value, true) end
		end
	end

	function R.setFrameRef(frame, label, ref)
		assert(not world.inCombat(), "SecureHandlerSetFrameRef in combat")
		frame.attrs["frameref-" .. label] = ref
	end

	return R
end

return S
