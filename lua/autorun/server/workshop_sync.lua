--[[
Copyright (c) 2023 Jai "Choccy" Fox

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
--]]


-- Prevent WorkshopSync from running in single-player!
if (game.SinglePlayer()) then return; end;

-- Workshop Memory
-- Used to store IDs and other information
local WORKSHOP_MEMORY = WORKSHOP_MEMORY or {
	["DYNAMIC_ID"] = {},
	["MOUNTED_ID"] = {}
};

-- Network Library IDs
local NET_MEMORY = NET_MEMORY or {
	["DynamicIDTable"] = util.AddNetworkString("WNET_DynamicIDTable")
};

-- Dynamic Downloads CVAR
-- Enable/disable the Dynamic Downloads system on-the-fly!
local CVAR_DYNDL = CVAR_DYNDL or CreateConVar("wsync_dynamic_downloads", 1, {FCVAR_GAMEDLL, FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enable WorkshopSync's Dynamic Downloads system. Takes effect upon loading a map.", 0, 1);

-- Override print() function with our own
local VERBOSE_PRINT = VERBOSE_PRINT or true;
local function print(...)
	if (not VERBOSE_PRINT) then return; end;

	local args = {...};

	local sMessage = "";
	for _, arg in ipairs(args) do
		sMessage = sMessage .. tostring(arg) .. '\t';
	end;
	sMessage = sMessage .. '\n';

	MsgC(Color(200, 200, 200), "[", Color(128, 255, 255), "WorkshopSync", Color(200, 200, 200), "]", Color(255, 255, 255), " ", sMessage);
end;

-- Function to add Workshop IDs via both systems
local function AddWorkshopID(id)
	local wsid = tostring(id);

	if (WORKSHOP_MEMORY.MOUNTED_ID[wsid]) then print(string.format("@AddWorkshopID() skipping Workshop ID: %s", wsid)); return; end;
	WORKSHOP_MEMORY.MOUNTED_ID[wsid] = true;

	if (WORKSHOP_MEMORY.DYNAMIC_ID[wsid]) then
		print(string.format("@AddWorkshopID() added {DYNAMIC} Workshop ID: %s", wsid));    -- we do not have to do anything here, it is already handled
	else
		resource.AddWorkshop(wsid);
		print(string.format("@AddWorkshopID() added {RESOURCE} Workshop ID: %s", wsid));
	end;
end;

-- Validates the add-on tags
local function ValidateTags(tab)
	if (table.IsEmpty(tab)) then print("@ValidateTags() received empty table!"); return false; end;

	if (table.HasValue(tab, "save") or table.HasValue(tab, "dupe") or table.HasValue(tab, "demo")) then
		print("@ValidateTags() found a blacklisted tag!");
		return false;
	end;

	print("@ValidateTags() passed.");
	return true;
end;

-- Enum IDs for GMA validation failure
local GMA_VALIDATION = GMA_VALIDATION or {
	["VALIDATE_OK"] = 0,
	["VALIDATE_ERR_EMPTY_TABLE"] = 1,
	["VALIDATE_ERR_LUA_ONLY"] = 2,
	["VALIDATE_ERR_BSP_FOUND"] = 3,
	["VALIDATE_ERR_MDL_FOUND"] = 4,
	["VALIDATE_ERR_FNT_FOUND"] = 5,
	["VALIDATE_ERR_SND_FOUND"] = 6
};

-- Validates file paths in GMA
local function ValidateGMAFilePaths(tab)
	if (table.IsEmpty(tab)) then print("@ValidateGMAFilePaths() received empty table!"); return false, GMA_VALIDATION.VALIDATE_ERR_EMPTY_TABLE; end;

	-- If an add-on only has Lua scripts in it, why would a client want to download it?
	local luaFilesOnly = true;

	for _, path in ipairs(tab) do
		-- Check every path for a .lua ending and set luaFilesOnly to false if we have a file that does not!
		if (not string.EndsWith(path, ".lua")) then luaFilesOnly = false; end;

		-- Find specific file extensions in the GMA, these could be problematic with the dynamic downloads system!
		if (string.StartWith(path, "maps/") and string.EndsWith(path, ".bsp")) then
			print("@ValidateGMAFilePaths() found a map BSP!");
			return false, GMA_VALIDATION.VALIDATE_ERR_BSP_FOUND;
		elseif (string.StartWith(path, "models/") and string.EndsWith(path, ".mdl") and (file.Exists(path, 'MOD') or file.Exists(path, 'hl2') or file.Exists(path, 'episodic'))) then
			print("@ValidateGMAFilePaths() found an overriding MDL!");
			return false, GMA_VALIDATION.VALIDATE_ERR_MDL_FOUND;
		elseif (string.StartWith(path, "resource/") and (string.EndsWith(path, ".otc") or string.EndsWith(path, ".otf") or string.EndsWith(path, ".ttc") or string.EndsWith(path, ".ttf"))) then
			print("@ValidateGMAFilePaths() found a font OTC/OTF/TTC/TTF!");
			return false, GMA_VALIDATION.VALIDATE_ERR_FNT_FOUND;
		elseif (string.StartWith(path, "sound/") and (string.EndsWith(path, ".wav") or string.EndsWith(path, ".mp3") or string.EndsWith(path, ".ogg"))) then
			print("@ValidateGMAFilePaths() found a sound WAV/MP3/OGG!");
			return false, GMA_VALIDATION.VALIDATE_ERR_SND_FOUND;
		end;
	end;

	-- Oops! Lua files only, skip it!
	if (luaFilesOnly) then
		print("@ValidateGMAFilePaths() found Lua scripts only!");
		return false, GMA_VALIDATION.VALIDATE_ERR_LUA_ONLY;
	end;

	print("@ValidateGMAFilePaths() passed.");
	return true, GMA_VALIDATION.VALIDATE_OK;
end;

-- Server is initializing
local function WInitialize()
	-- Parse resource JSON data in the DATA folder
	if (file.Exists("workshop_sync/resource", 'DATA') and file.IsDir("workshop_sync/resource", 'DATA')) then
		local jsonFiles = file.Find("workshop_sync/resource/*.json", 'DATA');
		for _, jFile in ipairs(jsonFiles) do
			local f = file.Open(string.format("workshop_sync/resource/%s", jFile), 'r', 'DATA');
			if (f) then
				local json = {};
				json.data = f:Read(f:Size());
				f:Close();

				json.table = util.JSONToTable(json.data);
				for key, val in ipairs(json.table) do
					AddWorkshopID(val);
				end;
				json = nil;
			end;
		end;
	end;

	-- Parse dynamic JSON data in the DATA folder
	if (CVAR_DYNDL:GetBool() and file.Exists("workshop_sync/dynamic", 'DATA') and file.IsDir("workshop_sync/dynamic", 'DATA')) then
		local jsonFiles = file.Find("workshop_sync/dynamic/*.json", 'DATA');
		for _, jFile in ipairs(jsonFiles) do
			local f = file.Open(string.format("workshop_sync/dynamic/%s", jFile), 'r', 'DATA');
			if (f) then
				local json = {};
				json.data = f:Read(f:Size());
				f:Close();

				json.table = util.JSONToTable(json.data);
				for key, val in ipairs(json.table) do
					WORKSHOP_MEMORY.DYNAMIC_ID[tostring(val)] = true;
					AddWorkshopID(val);
				end;
				json = nil;
			end;
		end;
	end;

	-- Parse engine.GetAddons for Workshop IDs
	for _, addon in ipairs(engine.GetAddons()) do
		local addonTags = string.lower(addon.tags);
		local addonTagsT = string.Explode(',', addonTags);
		print(string.format("@WInitialize() processing add-on: %q", addon.title));
		if (tobool(addon.downloaded) and tobool(addon.mounted) and ValidateTags(addonTagsT)) then
			-- Ideally, we should not use game.MountGMA, but due to the UGC format we cannot use file.Open (the GMA files are outside the root folder)
			-- So you just have to deal with this insanity, sorry
			local gmaData = {};
			if (CVAR_DYNDL:GetBool()) then print(string.format("@WInitialize() mounting GMA: %q", addon.file)); gmaData.mounted, gmaData.files = game.MountGMA(addon.file); end;

			if (not table.IsEmpty(gmaData) and gmaData.mounted) then
				gmaData.validated, gmaData.validationID = ValidateGMAFilePaths(gmaData.files);
				if (gmaData.validated) then
					-- Passed, so it becomes a dynamic download add-on instead!
					WORKSHOP_MEMORY.DYNAMIC_ID[addon.wsid] = true;
					AddWorkshopID(addon.wsid);
				elseif (gmaData.validationID != GMA_VALIDATION.VALIDATE_ERR_LUA_ONLY and gmaData.validationID != GMA_VALIDATION.VALIDATE_ERR_BSP_FOUND) then
					AddWorkshopID(addon.wsid);
				else
					-- Weird situation here, I know...
					-- What is happening here is we DO NOT want maps to be included in the downloads at all!
					-- Workshop maps are generally handled automatically by the server, so it is better we do not make every map download while a client is connecting.
					-- BONUS: we can also skip out on Lua-only add-ons!
					print(string.format("@WInitialize() skipped processing add-on: %q", addon.title));
				end
			else
				-- Either ConVar is set or we somehow failed to check the GMA file contents, either way we will add the add-on to downloads
				AddWorkshopID(addon.wsid);
			end;
		end;
	end;

	-- Print a pretty message
	MsgC(Color(128, 255, 255), "WorkshopSync", Color(255, 255, 255), " is fully initialized!\n");
end;
hook.Add("Initialize", "WSYNC_Initialize", WInitialize);

-- Hooked function for player activation
gameevent.Listen("player_activate");
local function WPlayerActivate(data)
	if (not CVAR_DYNDL:GetBool()) then return; end;

	-- Grab the Player entity
	local ply = Player(data.userid);
	if (ply:IsListenServerHost()) then print("@WPlayerActivate() attempted to send network data to host!"); return; end;

	-- Turn the Dynamic ID table into a compressed JSON
	local json = {};
	json.table = {};
	for idx, val in pairs(WORKSHOP_MEMORY.DYNAMIC_ID) do
		table.insert(json.table, string.format("{%s}", idx));
		table.sort(json.table);
	end;
	json.data = util.Compress(util.TableToJSON(json.table, false));
	json.bytes = #json.data;
	json.table = nil;

	-- If the player still exists, send a network message
	if (IsValid(ply)) then
		local filter = RecipientFilter();
		filter:AddPlayer(ply);
		net.Start("WNET_DynamicIDTable");
		net.WriteUInt(json.bytes, 16);
		net.WriteData(json.data, json.bytes);
		net.Send(filter);
	end;
end;
hook.Add("player_activate", "WSYNC_PlayerActivate", WPlayerActivate);

-- Console command to force re-synchronization of the dynamic list
local function PlayerDynamicResync(ply)
	if (not IsValid(ply)) then return; end;

	local data = {};
	data.userid = ply:UserID();
	WPlayerActivate(data);
end;
concommand.Add("wsync_resynchronize", PlayerDynamicResync, nil, "Re-synchronize WorkshopSync's Dynamic Downloads system.");
