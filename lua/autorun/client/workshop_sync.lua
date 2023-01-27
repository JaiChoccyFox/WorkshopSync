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
	["MOUNTED_ID"] = {},
	["QUEUED_ID"] = {}
};

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

	MsgC(Color(200, 200, 200), "[", Color(255, 255, 128), "WorkshopSync", Color(200, 200, 200), "]", Color(255, 255, 255), " ", sMessage);
end;

-- Function to mount GMAs and do some extra stuff
local function MountGMA(path)
	local gmaData = {};
	gmaData.mounted, gmaData.files = game.MountGMA(path);
	if (gmaData.mounted) then
		-- Hot reload contents
		for _, fPath in ipairs(gmaData.files) do
			if (string.StartWith(fPath, "materials/") and string.EndsWith(fPath, ".vmt")) then
				local mPath = string.sub(fPath, 11, #fPath - 4);
				local vMaterial = Material(mPath);

				if (vMaterial) then
					vMaterial:Recompute();
					print(string.format("@MountGMA() refreshed material: %q", vMaterial:GetName()));
				end;
			elseif (string.StartWith(fPath, "models/") and string.EndsWith(fPath, ".mdl")) then
				print(string.format("@MountGMA() precaching model: %q", fPath));
				util.PrecacheModel(fPath);
			end;
		end;
		print(string.format("@MountGMA() mounted GMA: %q", path));
	else
		print(string.format("@MountGMA() failed to mount GMA: %q", path));
	end;
	return gmaData.mounted, gmaData.files;
end;

-- Client is initializing
local function WInitialize()
	-- Parse engine.GetAddons for Workshop IDs
	for _, addon in ipairs(engine.GetAddons()) do
		print(string.format("@WInitialize() processing add-on: %q", addon.title));
		if (tobool(addon.downloaded) and tobool(addon.mounted)) then
			WORKSHOP_MEMORY.MOUNTED_ID[addon.wsid] = true;
		end;
	end;

	-- Print a pretty message
	MsgC(Color(255, 255, 128), "WorkshopSync", Color(255, 255, 255), " is fully initialized!\n");
end;
hook.Add("Initialize", "WSYNC_Initialize", WInitialize);

-- Received a network message, do something!
local function WDynamicIDTable(len)
	print(string.format("@WDynamicIDTable() received %d bytes of data!", len / 8));

	-- Decompress JSON and add it into the table
	local json = {};
	json.bytes = net.ReadUInt(16);
	json.data = util.Decompress(net.ReadData(json.bytes));
	json.table = util.JSONToTable(json.data);
	for _, val in ipairs(json.table) do
		if (#val > 2 and string.StartWith(val, "{") and string.EndsWith(val, "}")) then
			local wsid = string.sub(val, 2, #val - 1);
			table.insert(WORKSHOP_MEMORY.QUEUED_ID, wsid);
			table.sort(WORKSHOP_MEMORY.QUEUED_ID);
		end;
	end;
	json = nil;

	-- Process the Workshop queue
	for _, wsid in ipairs(WORKSHOP_MEMORY.QUEUED_ID) do
		-- Steamworks functions
		local function CSteamworksFileInfo(info)
			local wsid = info.id;
			if (tobool(info.installed) and not tobool(info.disabled)) then
				print(string.format("@CSteamworksFileInfo() skipping Workshop ID: %s", wsid));
				WORKSHOP_MEMORY.MOUNTED_ID[wsid] = true;
				return;
			end;

			print(string.format("@CSteamworksFileInfo() processing Workshop ID: %s", wsid));

			local function CSteamworksDownloadUGC(path)
				print(string.format("@CSteamworksDownloadUGC() downloaded Workshop ID: %s", wsid));
				local gmaMounted = MountGMA(path);
				WORKSHOP_MEMORY.MOUNTED_ID[wsid] = gmaMounted;
			end;
			steamworks.DownloadUGC(wsid, CSteamworksDownloadUGC);

			print(string.format("@CSteamworksFileInfo() processed Workshop ID: %s", wsid));
		end;

		-- Declare this variable here because it does not like being placed below!
		local cacheGMA = string.format("cache/workshop/%s.gma", wsid);

		-- Skip already mounted add-ons
		if (WORKSHOP_MEMORY.MOUNTED_ID[wsid]) then
			print(string.format("@WDynamicIDTable() skipping Workshop ID: %s", wsid));
			goto queue_continue;
		end;

		print(string.format("@WDynamicIDTable() processing Workshop ID: %s", wsid));

		-- Parse engine.GetAddons for downloaded but not mounted add-ons
		for _, addon in ipairs(engine.GetAddons()) do
			if (addon.wsid == wsid and tobool(addon.downloaded) and not tobool(addon.mounted)) then
				local gmaMounted = MountGMA(addon.file);
				WORKSHOP_MEMORY.MOUNTED_ID[addon.wsid] = gmaMounted;
				goto queue_continue;
			end;
		end;

		-- Previously downloaded legacy UGC add-ons get stored in the cache folder
		if (file.Exists(cacheGMA, 'GAME')) then
			local gmaMounted = MountGMA(cacheGMA);
			WORKSHOP_MEMORY.MOUNTED_ID[wsid] = gmaMounted;
			goto queue_continue;
		end;

		-- Use the Steamworks library to check and download add-ons
		steamworks.FileInfo(wsid, CSteamworksFileInfo);

		::queue_continue::
		print(string.format("@WDynamicIDTable() processed Workshop ID: %s", wsid));
	end;
	WORKSHOP_MEMORY.QUEUED_ID = {};
end;
net.Receive("WNET_DynamicIDTable", WDynamicIDTable);

-- Console command to force re-synchronization of the dynamic list
concommand.Add("wsync_resynchronize", nil, nil, "Re-synchronize WorkshopSync's Dynamic Downloads system.");
