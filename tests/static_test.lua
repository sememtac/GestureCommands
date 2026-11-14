-- Static checks: the TOC and files agree, every file is valid Lua 5.1, and every secure snippet passes
-- Blizzard's snippet compiler and only uses what the restricted environment has.
-- Run: tests/run.ps1 (or luajit tests/static_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
local H = dofile(lib .. "harness.lua")
local S = dofile(lib .. "secure.lua")
local check = H.check

-- ---- TOC ---------------------------------------------------------------------------------------
local toc = H.read(H.root .. "/" .. H.ADDON .. ".toc")
local listed = {}
for _, file in ipairs(H.tocFiles()) do
	listed[file] = true
	check(io.open(H.root .. "/" .. file) ~= nil, "TOC file exists: " .. file)
end
for _, field in ipairs({ "Interface", "Title", "Version", "SavedVariablesPerCharacter", "IconTexture" }) do
	check(toc:match("\n## " .. field .. ": ") or toc:match("^## " .. field .. ": "), "TOC has ## " .. field)
end
check(toc:match("## Interface: 16001"), "TOC targets WoW: Forever (Interface 16001)")
local icon = toc:match("## IconTexture: Interface\\AddOns\\" .. H.ADDON .. "\\([^\r\n]+)")
check(icon and io.open(H.root .. "/" .. icon:gsub("\\", "/") .. ".tga") ~= nil, "TOC icon exists")

-- Every Lua file in the addon is loaded by the TOC (a file missing from it silently does nothing in game).
local function luaFiles()
	local out = {}
	local cmd = H.WINDOWS and ('dir /b /s "' .. H.root:gsub("/", "\\") .. '\\*.lua"') or ('find "' .. H.root .. '" -name "*.lua"')
	local p = io.popen(cmd)
	for line in p:lines() do
		local rel = line:gsub("\\", "/"):sub(#H.root + 2)
		if not rel:match("^tests/") and not rel:match("^%.") and not rel:match("^media/") and not rel:match("^Libs/") then out[#out + 1] = rel end
	end
	p:close()
	table.sort(out)
	return out
end
local files = luaFiles()
check(#files > 0, "found the addon's Lua files")
for _, file in ipairs(files) do
	check(listed[file], "listed in the TOC: " .. file)
end

-- ---- syntax (the game runs Lua 5.1) --------------------------------------------------------------
for _, file in ipairs(files) do
	local ok, err = loadfile(H.root .. "/" .. file)
	check(ok ~= nil, "valid Lua 5.1: " .. file .. (err and (" (" .. err .. ")") or ""))
end

-- ---- secure snippets -----------------------------------------------------------------------------
-- Every long string ([[ ]] / [=[ ]=]) in the addon is a secure snippet, given to ns.Snippet with the name of
-- the attribute or script it is for; the name says the signature Blizzard calls it with.
local function SignatureFor(name)
	if name:match("^_onstate%-") then return "self,stateid,newstate" end
	return ({
		_onattributechanged = "self,name,value",
		["OnClick-pre"] = "self,button,down",
		["OnClick-post"] = "self,message,button,down",
	})[name]
end
local snippets = 0
for _, file in ipairs(files) do
	local src = H.read(H.root .. "/" .. file)
	local pos = 1
	while true do
		local s, e, eq = src:find("%[(=*)%[", pos)
		if not s then break end
		local close = src:find("]" .. eq .. "]", e + 1, true)
		assert(close, file .. ": unterminated long string")
		local body = src:sub(e + 1, close - 1)
		local line = select(2, src:sub(1, s):gsub("\n", "")) + 1
		local name = src:sub(math.max(1, s - 80), s - 1):match('ns%.Snippet%("([^"]+)",%s*$')
		local signature = name and SignatureFor(name)
		snippets = snippets + 1
		if check(signature ~= nil, ("snippet %s:%d goes through ns.Snippet with a known name (%s)"):format(file, line, tostring(name))) then
			local problems = S.staticProblems(body, signature)
			check(#problems == 0, ("snippet %s:%d (%s) is valid restricted code%s"):format(file, line, name,
				#problems > 0 and (": " .. table.concat(problems, "; ")) or ""))
		end
		pos = close + 2 + #eq
	end
end
check(snippets == 5, "found the secure snippets (" .. snippets .. ")")

-- The load-time check in Core reports a snippet the game would refuse.
do
	dofile(lib .. "world.lua").new()
	local ns = {}
	H.loadAddon(ns, function(file) return file == "Core/Core.lua" end)
	check(ns.Snippet("ok", "return;") == "return;" and #ns.snippetErrors == 0, "ns.Snippet passes good code through")
	ns.Snippet("bad", "-- a function word\nreturn;")
	ns.Snippet("braces", "local t = {};")
	check(#ns.snippetErrors == 2 and ns.snippetErrors[1]:find("bad") and ns.snippetErrors[2]:find("brace"), "ns.Snippet reports the word \"function\" and braces")
	check(#ns.snippets == 3, "ns.Snippet keeps every snippet for tests")
end

-- ---- the UI uses only the engine API -------------------------------------------------------------
do
	local allowed = {}
	for _, name in ipairs(dofile(lib .. "engine_api.lua")) do allowed[name] = true end
	for _, name in ipairs({ "OnPublished", "OnPlacingChanged", "ToggleConfig", "CloseConfig", "ToggleMinimapButton" }) do allowed[name] = true end
	local uiFiles = {}
	for _, file in ipairs(files) do
		if file:match("^UI/") or not (file:match("^Core/") or file:match("^Engine/")) then uiFiles[#uiFiles + 1] = file end
	end
	for _, file in ipairs(uiFiles) do -- names the UI defines for itself
		for name in H.read(H.root .. "/" .. file):gmatch("function ns%.([%w_]+)") do allowed[name] = true end
		for name in H.read(H.root .. "/" .. file):gmatch("\nns%.([%w_]+)%s*=") do allowed[name] = true end
	end
	for _, file in ipairs(uiFiles) do
		local bad = {}
		for name in H.read(H.root .. "/" .. file):gmatch("ns%.([%w_]+)") do
			if not allowed[name] and not bad[name] then bad[name] = true; bad[#bad + 1] = name end
		end
		check(#bad == 0, "UI file uses only the engine API: " .. file .. (#bad > 0 and (" (" .. table.concat(bad, ", ") .. ")") or ""))
	end
end

-- The checker itself: what broke binding in 1.0.1, and other things Blizzard refuses.
check(S.compileError("local function F() end") == "The function keyword is not permitted", "checker: a local function is refused")
check(S.compileError("-- no function here\nreturn") == "The function keyword is not permitted", "checker: even the word in a comment is refused")
check(S.compileError("local t = {}") == "Direct table creation is not permitted", "checker: braces are refused")
check(S.compileError("return", "self, ...") == nil and S.compileError("return", "self=1") ~= nil, "checker: signatures")
check(#S.staticProblems("CreateFrame(\"Frame\")", "self") > 0, "checker: CreateFrame isn't in the restricted environment")
check(#S.staticProblems("self:SetScript(\"OnShow\", nil)", "self") > 0, "checker: frame handles have no SetScript")
check(#S.staticProblems("local dial = self:GetFrameRef(\"dial\"); if dial:IsVisible() then dial:Hide(true) end", "self") == 0,
	"checker: real handle methods pass")
check(#S.staticProblems("local kind, id = GetActionInfo(slot)", "self,slot") == 0, "checker: GetActionInfo is allowed")

H.finish()
