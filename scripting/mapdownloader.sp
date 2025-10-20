#pragma semicolon 1
#include <sourcemod>
#include <cURL>
#include <tf2>

public Plugin myinfo =
{
	name = "Map Downloader (Modified)",
	author = "Icewind - Modified by avan",
	description = "Automatically download missing maps (with md5sum checking)",
	version = "0.2.1",
	url = "https://discord.gg/8ysCuREbWQ"
};

int CURL_Default_opt[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,0},
	{_:CURLOPT_TIMEOUT,60},
	{_:CURLOPT_CONNECTTIMEOUT,120},
	{_:CURLOPT_USE_SSL,CURLUSESSL_TRY},
	{_:CURLOPT_SSL_VERIFYPEER,0},
	{_:CURLOPT_SSL_VERIFYHOST,0},
	{_:CURLOPT_VERBOSE,0}
};

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

Handle g_hCvarUrl = INVALID_HANDLE;
bool g_bDownloadInProgress = false;
float g_fLastProgressUpdate = 0.0;
int g_iLastProgressPercent = -1;

public OnPluginStart() {
	g_hCvarUrl = CreateConVar("sm_map_download_base", "https://fastdl.avanlcy.hk/maps", "map download url", FCVAR_PROTECTED);

	RegServerCmd("changelevel", HandleChangeLevelAction);
}

public Action HandleChangeLevelAction(args) {
	// Check if a download is already in progress
	if (g_bDownloadInProgress) {
		PrintToChatAll("[Matcha] Cannot change level: Map download in progress, please wait...");
		PrintToServer("[Matcha] Cannot change level: Map download in progress");
		return Plugin_Handled;
	}

	char part[128];
	char arg[128];
	int argpos = 0;

	for (int i = 1; i <= args; i++) {
		GetCmdArg(i, part, sizeof(part));
		strcopy(arg[argpos], sizeof(arg) - argpos, part);
		argpos += strlen(part);
	}

	if (arg[strlen(arg) - 1] == ':') {
		PrintToChatAll("[Matcha] Invalid input, to input urls, replace '://' with ':/'");
		return Plugin_Handled;
	}

	PrintToServer("[Matcha] Changing map to %s", arg);

	char path[128];
	Format(path, sizeof(path), "maps/%s.bsp", arg);

	if (FileExists(path)) {
		return Plugin_Continue;
	} else {
		PrintToChatAll("[Matcha] Map %s not found, trying to download", path);
		PrintToServer("[Matcha] Map %s not found, trying to download", path);
		g_bDownloadInProgress = true;
		DownloadMap(arg, path);
		return Plugin_Handled;
	}
}

// For now, we will need to retrieve the md5sum from our server to verify the integrity of the map
/*
Hopps — 00:01
	Its impossible to have the map file and the checksum file to corrupt and lead to a different yet same checksum
	If that happens we should question if we live in a matrix
	Lol
*/
public void OnMD5Complete(const bool success, const char[] md5Hash, any hDLPack) {
	char map[128];
	char targetPath[128];
	
	ResetPack(Handle:hDLPack);
	ReadPackString(Handle:hDLPack, map, sizeof(map));
	ReadPackString(Handle:hDLPack, targetPath, sizeof(targetPath));
	CloseHandle(Handle:hDLPack);
	
	if (!success) {
		PrintToChatAll("[Matcha] MD5 calculation failed, please try again or try another map.");
		PrintToServer("[Matcha] MD5 calculation failed, please try again or try another map.");
		DeleteFile(targetPath);
		g_bDownloadInProgress = false;
		return;
	}
	
	// Log the MD5 hash for verification and debugging
	PrintToServer("[Matcha] Downloaded map %s MD5: %s", map, md5Hash);
	
	// Now download the MD5 checksum file to verify integrity
	DownloadMD5Checksum(map, targetPath, md5Hash);
}

public void ValidateBSPWithMD5(char map[128], char targetPath[128]) {
	Handle hDLPack = CreateDataPack();
	WritePackString(hDLPack, map);
	WritePackString(hDLPack, targetPath);
	
	// calculate
	curl_hash_file(targetPath, Openssl_Hash_MD5, OnMD5Complete, hDLPack);
}

public void DownloadMD5Checksum(char map[128], char targetPath[128], const char[] calculatedMD5) {
	char BaseUrl[128];
	char MD5URL[512];
	char md5FilePath[128];
	
	GetConVarString(g_hCvarUrl, BaseUrl, sizeof(BaseUrl));
	Format(MD5URL, sizeof(MD5URL), "%s/%s.md5sum", BaseUrl, map);
	Format(md5FilePath, sizeof(md5FilePath), "maps/%s.md5sum", map);
	
	Handle curl = curl_easy_init();
	Handle output_file = curl_OpenFile(md5FilePath, "wb");
	CURL_DEFAULT_OPT(curl);
	
	PrintToChatAll("[Matcha] Verifying MD5 checksum...");
	PrintToServer("[Matcha] Verifying MD5 checksum...");
	
	Handle hDLPack = CreateDataPack();
	WritePackCell(hDLPack, _:output_file);
	WritePackString(hDLPack, map);
	WritePackString(hDLPack, targetPath);
	WritePackString(hDLPack, calculatedMD5);
	WritePackString(hDLPack, md5FilePath);
	
	curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, output_file);
	curl_easy_setopt_string(curl, CURLOPT_URL, MD5URL);
	curl_easy_perform_thread(curl, OnMD5DownloadComplete, hDLPack);
}

public void OnMD5DownloadComplete(Handle hndl, CURLcode code, any hDLPack) {
	char map[128];
	char targetPath[128];
	char calculatedMD5[33];
	char md5FilePath[128];
	
	ResetPack(hDLPack);
	CloseHandle(Handle:ReadPackCell(hDLPack)); // output_file
	ReadPackString(hDLPack, map, sizeof(map));
	ReadPackString(hDLPack, targetPath, sizeof(targetPath));
	ReadPackString(hDLPack, calculatedMD5, sizeof(calculatedMD5));
	ReadPackString(hDLPack, md5FilePath, sizeof(md5FilePath));
	CloseHandle(hDLPack);
	CloseHandle(hndl);
	
	if (code != CURLE_OK) {
		PrintToChatAll("[Matcha] Error downloading MD5 checksum");
		PrintToServer("[Matcha] Error downloading MD5 checksum");
		char sError[256];
		curl_easy_strerror(code, sError, sizeof(sError));
		PrintToChatAll("[Matcha] cURL error: %s", sError);
		PrintToServer("[Matcha] cURL error: %s", sError);
		DeleteFile(targetPath);
		DeleteFile(md5FilePath);
		g_bDownloadInProgress = false; // Release lock on MD5 download failure
		return;
	}
	
	// Verify the downloaded MD5 checksum
	VerifyMD5Checksum(map, targetPath, calculatedMD5, md5FilePath);
}

public void VerifyMD5Checksum(char map[128], char targetPath[128], const char[] calculatedMD5, char md5FilePath[128]) {
	Handle file = OpenFile(md5FilePath, "r");
	if (file == INVALID_HANDLE) {
		PrintToChatAll("[Matcha] Failed to open MD5 checksum file, please try again or try another map.");
		PrintToServer("[Matcha] Failed to open MD5 checksum file, please try again or try another map.");
		DeleteFile(targetPath);
		DeleteFile(md5FilePath);
		g_bDownloadInProgress = false; // Release lock on file open failure
		return;
	}
	
	char expectedMD5[33];
	if (!ReadFileString(file, expectedMD5, sizeof(expectedMD5))) {
		PrintToChatAll("[Matcha] Failed to read MD5 checksum, please try again or try another map.");
		PrintToServer("[Matcha] Failed to read MD5 checksum, please try again or try another map.");
		CloseHandle(file);
		DeleteFile(targetPath);
		DeleteFile(md5FilePath);
		g_bDownloadInProgress = false;
		return;
	}
	CloseHandle(file);
	TrimString(expectedMD5);
	
	// only 32 char
	if (strlen(expectedMD5) >= 32) {
		expectedMD5[32] = '\0';
	}
	
	PrintToServer("[Matcha] Expected MD5: %s", expectedMD5);
	PrintToServer("[Matcha] Calculated MD5: %s", calculatedMD5);
	
	// matches the value
	if (StrEqual(expectedMD5, calculatedMD5, true)) {
		PrintToChatAll("[Matcha] MD5 verification successful");
		PrintToChatAll("[Matcha] %s MD5: %s", map, calculatedMD5);

		PrintToServer("[Matcha] MD5 verification successful");
		PrintToServer("[Matcha] %s MD5: %s", map, calculatedMD5);

		DeleteFile(md5FilePath); // delete the md5sum
		g_bDownloadInProgress = false;
		changeLevel(map);
	} else {
		PrintToChatAll("[Matcha] MD5 verification failed, please try again or try another map");
		PrintToChatAll("[Matcha] %s MD5: %s", map, calculatedMD5);
		PrintToChatAll("[Matcha] Expected MD5: %s", expectedMD5);

		PrintToServer("[Matcha] MD5 verification failed, please try again or try another map");
		PrintToServer("[Matcha] %s MD5: %s", map, calculatedMD5);
		PrintToServer("[Matcha] Expected MD5: %s", expectedMD5);

		DeleteFile(targetPath); // Delete both files
		DeleteFile(md5FilePath);
		g_bDownloadInProgress = false;
	}
}

public int ProgressCallback(Handle hndl, int dltotal, int dlnow, int ultotal, int ulnow) {
	float currentTime = GetGameTime();
	if (dltotal > 0 && dlnow > 0) {
		int percent = RoundToNearest((float(dlnow) / float(dltotal)) * 100.0);
		
		// Update if 2 seconds have passed AND percentage changed, or if it's a significant change (10%)
		if ((currentTime - g_fLastProgressUpdate >= 2.0 && percent != g_iLastProgressPercent) || 
		    (percent - g_iLastProgressPercent >= 10)) {
			PrintToChatAll("[Matcha] Download progress: %d%% (%d KB / %d KB)", 
				percent, dlnow / 1024, dltotal / 1024);
			g_fLastProgressUpdate = currentTime;
			g_iLastProgressPercent = percent;
		}
	}
	return 0;
}

public DownloadMap(char map[128], char targetPath[128]) {
	char MapURL[512];
	char BaseUrl[128];
	GetConVarString(g_hCvarUrl, BaseUrl, sizeof(BaseUrl));

	Format(MapURL, sizeof(MapURL), "%s/%s.bsp", BaseUrl, map);
	DownloadMapUrl(map, MapURL, targetPath);
}

public DownloadMapUrl(char map[128], char fullUrl[512], char targetPath[128]) {
	Handle curl = curl_easy_init();
	Handle output_file = curl_OpenFile(targetPath, "wb");
	CURL_DEFAULT_OPT(curl);

	PrintToChatAll("[Matcha] Trying to download %s from %s", map, fullUrl);
	PrintToServer("[Matcha] Trying to download %s from %s", map, fullUrl);

	// Reset progress tracking
	g_fLastProgressUpdate = 0.0;
	g_iLastProgressPercent = -1;

	Handle hDLPack = CreateDataPack();
	WritePackCell(hDLPack, _:output_file);
	WritePackString(hDLPack, map);
	WritePackString(hDLPack, targetPath);

	curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, output_file);
	curl_easy_setopt_string(curl, CURLOPT_URL, fullUrl);
	curl_easy_setopt_function(curl, CURLOPT_PROGRESSFUNCTION, ProgressCallback);
	curl_easy_perform_thread(curl, onComplete, hDLPack);
}

public onComplete(Handle hndl, CURLcode code, any hDLPack) {
	char map[128];
	char targetPath[128];

	ResetPack(hDLPack);
	CloseHandle(Handle:ReadPackCell(hDLPack)); // output_file
	ReadPackString(hDLPack, map, sizeof(map));
	ReadPackString(hDLPack, targetPath, sizeof(targetPath));
	CloseHandle(hDLPack);
	CloseHandle(hndl);

	if (code != CURLE_OK) {
		PrintToChatAll("[Matcha] Error downloading map %s", map);
		PrintToServer("[Matcha] Error downloading map %s", map);

		char sError[256];
		curl_easy_strerror(code, sError, sizeof(sError));
		PrintToChatAll("[Matcha] cURL error: %s", sError);
		PrintToChatAll("[Matcha] cURL error code: %d", code);

		PrintToServer("[Matcha] cURL error: %s", sError);
		PrintToServer("[Matcha] cURL error code: %d", code);

		DeleteFile(targetPath);
		g_bDownloadInProgress = false;
	} else {
		//PrintToChatAll("map size(%s): %d", targetPath, FileSize(targetPath));
		if (FileSize(targetPath) < 1024) {
			PrintToChatAll("[Matcha] Map file too small, discarding");
			PrintToServer("[Matcha] Map file too small, discarding");
			DeleteFile(targetPath);
			g_bDownloadInProgress = false;
			return;
		}
		
		ValidateBSPWithMD5(map, targetPath); // Check the integrity of the map
	}

	return;
}

public changeLevel(char map[128]) {
	char command[512];
	Format(command, sizeof(command), "changelevel %s", map);
	ServerCommand(command);
}