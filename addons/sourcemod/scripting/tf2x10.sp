/*
TF2x10

Current developer: Wliu
Original developers: Isatis and Invisighost
Config updates: Mr. Blue and Ultimario

Alliedmodders thread: https://forums.alliedmods.net/showthread.php?p=2338136
Github: https://github.com/50DKP/TF2x10
Bitbucket: https://bitbucket.org/umario/tf2x10/src
*/

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <adminmenu>
#include <sdkhooks>
//#include <morecolors>  //Next version
#include <tf2_stocks>
#include <tf2items>
#include <tf2attributes>
#include <steamtools>
#include <updater>
#undef REQUIRE_PLUGIN
#tryinclude <freak_fortress_2>
#tryinclude <saxtonhale>
#define REQUIRE_PLUGIN

#define PLUGIN_NAME			"Multiply a Weapon's Stats by 10"
#define PLUGIN_AUTHOR		"The TF2x10 group"
#define PLUGIN_VERSION		"1.5.0"
#define PLUGIN_CONTACT		"http://steamcommunity.com/group/tf2x10/"
#define PLUGIN_DESCRIPTION	"It's in the name! Also known as TF2x10 or TF20."

#define UPDATE_URL			"http://ff2.50dkp.com/updater/tf2x10/update.txt"

#define KUNAI_DAMAGE			2100
#define DALOKOH_MAXHEALTH		800
#define DALOKOH_HEALTHPERSEC	150
#define DALOKOH_LASTHEALTH		50
#define MAX_CURRENCY			30000

static const Float:g_fBazaarRates[] =
{
	16.5, //seconds for 0 heads
	8.25, //seconds for 1 head
	3.3, //seconds for 2 heads
	1.32, //seconds for 3 heads
	0.66, //seconds for 4 heads
	0.44, //seconds for 5 heads
	0.33 //seconds for 6+ heads
};

//new g_iHeadCap = 40;
new bool:g_bAprilFools;
new bool:g_bFF2Running;
new bool:g_bHasCaber[MAXPLAYERS + 1];
new bool:g_bHasManmelter[MAXPLAYERS + 1];
new bool:g_bHasBazooka[MAXPLAYERS + 1];
new bool:g_bHeadScaling;
new bool:g_bHiddenRunning;
new bool:g_bTakesHeads[MAXPLAYERS + 1];
new bool:g_bChargingClassic[MAXPLAYERS + 1];
new bool:dalokohs[MAXPLAYERS + 1];
new bool:g_bVSHRunning;

new Float:g_fChargeBegin[MAXPLAYERS + 1];
new Float:g_fHeadScalingCap;

new Handle:g_hHudText;
new Handle:g_hItemInfoTrie;
new Handle:g_hSdkGetMaxHealth;
new Handle:g_hSdkEquipWearable;
new Handle:g_hTopMenu;

new Handle:dalokohsTimer[MAXPLAYERS + 1];

new g_iBuildingsDestroyed[MAXPLAYERS + 1];
new g_iCabers[MAXPLAYERS + 1];
new g_iDalokohSecs[MAXPLAYERS + 1];
new g_iRazorbackCount[MAXPLAYERS + 1];
new g_iRevengeCrits[MAXPLAYERS + 1];

new String:g_sSelectedMod[16] = "default";

new Handle:g_cvarEnabled;
new Handle:g_cvarGameDesc;
new Handle:g_cvarAutoUpdate;
//new Handle:g_cvarHeadCap;
new Handle:g_cvarHeadScaling;
new Handle:g_cvarHeadScalingCap;
new Handle:g_cvarHealthCap;
new Handle:g_cvarIncludeBots;
new Handle:g_cvarCritsFJ;
new Handle:g_cvarCritsDiamondback;
new Handle:g_cvarCritsManmelter;

new tf_feign_death_duration;

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_CONTACT
}

/******************************************************************

Plugin Initialization

******************************************************************/

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	decl String:sGameDir[8];
	GetGameFolderName(sGameDir, sizeof(sGameDir));

	if(StrContains(sGameDir, "tf") < 0)
	{
		strcopy(error, err_max, "This plugin can only run on Team Fortress 2... hence TF2x10!");
		return APLRes_Failure;
	}

	MarkNativeAsOptional("Steam_SetGameDescription");
	MarkNativeAsOptional("VSH_IsSaxtonHaleModeEnabled");
	MarkNativeAsOptional("VSH_GetSaxtonHaleUserId");
	MarkNativeAsOptional("FF2_IsFF2Enabled");
	MarkNativeAsOptional("FF2_GetBossCharge");
	MarkNativeAsOptional("FF2_GetBossIndex");
	MarkNativeAsOptional("FF2_GetBossTeam");
	MarkNativeAsOptional("FF2_SetBossCharge");

	return APLRes_Success;
}

public OnPluginStart()
{
	new Handle:hTopMenu;

	g_hHudText = CreateHudSynchronizer();
	g_hItemInfoTrie = CreateTrie();

	PrepSDKCalls();
	CreateConVars();
	AutoExecConfig(true, "plugin.tf2x10");

	RegAdminCmd("sm_tf2x10_disable", Command_Disable, ADMFLAG_CONVARS);
	RegAdminCmd("sm_tf2x10_enable", Command_Enable, ADMFLAG_CONVARS);
	RegAdminCmd("sm_tf2x10_getmod", Command_GetMod, ADMFLAG_GENERIC);
	RegAdminCmd("sm_tf2x10_recache", Command_Recache, ADMFLAG_GENERIC);
	RegAdminCmd("sm_tf2x10_setmod", Command_SetMod, ADMFLAG_CHEATS);
	RegConsoleCmd("sm_x10group", Command_Group);

	HookAllEvents();

	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsValidClient(client) && IsClientInGame(client))
		{
			UpdateVariables(client);
		}
	}

	if (LibraryExists("adminmenu") && (hTopMenu = GetAdminTopMenu()))
	{
		OnAdminMenuReady(hTopMenu);
	}
}

public OnConfigsExecuted()
{
	if(!GetConVarBool(g_cvarEnabled))
	{
		return;
	}

	if(FindConVar("aw2_version") != INVALID_HANDLE)
	{
		SetFailState("TF2x10 is incompatible with Advanced Weaponiser.");
	}

	switch (LoadFileIntoTrie("default", "tf2x10_base_items"))
	{
		case -1:
		{
			SetFailState("Could not find configs/x10.default.txt. Aborting.");
		}
		case -2:
		{
			SetFailState("Your configs/x10.default.txt seems to be corrupt. Aborting.");
		}
		default:
		{
			//g_iHeadCap = GetConVarInt(g_cvarHeadCap);
			g_bHeadScaling = GetConVarBool(g_cvarHeadScaling);
			g_fHeadScalingCap = GetConVarFloat(g_cvarHeadScalingCap);
			tf_feign_death_duration = GetConVarInt(FindConVar("tf_feign_death_duration"));

			CreateTimer(330.0, Timer_ServerRunningX10, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	if(GetConVarBool(g_cvarAutoUpdate) && LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
}

PrepSDKCalls()
{
	new Handle:hConf = LoadGameConfigFile("sdkhooks.games");
	if (hConf == INVALID_HANDLE)
	{
		SetFailState("Cannot find sdkhooks.games gamedata.");
	}

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "GetMaxHealth");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hSdkGetMaxHealth = EndPrepSDKCall();
	CloseHandle(hConf);

	if (g_hSdkGetMaxHealth == INVALID_HANDLE)
	{
		SetFailState("Failed to set up GetMaxHealth sdkcall. Your SDKHooks is probably outdated.");
	}

	hConf = LoadGameConfigFile("tf2items.randomizer");
	if (hConf == INVALID_HANDLE)
	{
		SetFailState("Cannot find gamedata/tf2.randomizer.txt. Get the file from [TF2Items] GiveWeapon.");
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CTFPlayer::EquipWearable");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSdkEquipWearable = EndPrepSDKCall();
	CloseHandle(hConf);

	if (g_hSdkEquipWearable == INVALID_HANDLE)
	{
		SetFailState("Failed to set up EquipWearable sdkcall. Get a new gamedata/tf2items.randomizer.txt from [TF2Items] GiveWeapon.");
	}
}

CreateConVars()
{
	CreateConVar("tf2x10_version", PLUGIN_VERSION, "Version of TF2x10", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_cvarAutoUpdate = CreateConVar("tf2x10_autoupdate", "1", "Tells Updater to automatically update this plugin.  0 = off, 1 = on.", _, true, 0.0, true, 1.0);
	g_cvarCritsDiamondback = CreateConVar("tf2x10_crits_diamondback", "10", "Number of crits after successful sap with Diamondback equipped.", _, true, 0.0, false);
	g_cvarCritsFJ = CreateConVar("tf2x10_crits_fj", "10", "Number of crits after Frontier kill or for buildings. Half this for assists.", _, true, 0.0, false);
	g_cvarCritsManmelter = CreateConVar("tf2x10_crits_manmelter", "10", "Number of crits after Manmelter extinguishes player.", _, true, 0.0, false);
	g_cvarEnabled = CreateConVar("tf2x10_enabled", "1", "Toggle TF2x10. 0 = disable, 1 = enable", _, true, 0.0, true, 1.0);
	g_cvarGameDesc = CreateConVar("tf2x10_gamedesc", "1", "Toggle setting game description. 0 = disable, 1 = enable.", _, true, 0.0, true, 1.0);
	//g_cvarHeadCap = CreateConVar("tf2x10_headcap", "40", "The number of heads before the wielder stops gaining health and speed bonuses", _, true, 4.0);
	g_cvarHeadScaling = CreateConVar("tf2x10_headscaling", "1", "Enable any decapitation weapon (eyelander etc) to grow their head as they gain heads. 0 = off, 1 = on.", _, true, 0.0, true, 1.0);
	g_cvarHeadScalingCap = CreateConVar("tf2x10_headscalingcap", "6.0", "The number of heads before head scaling stops growing their head. 6.0 = 24 heads.", _, true, 0.0, false);
	g_cvarHealthCap = CreateConVar("tf2x10_healthcap", "2100", "The max health a player can have. -1 to disable.", _, true, -1.0, false);
	g_cvarIncludeBots = CreateConVar("tf2x10_includebots", "0", "1 allows bots to receive TF2x10 weapons, 0 disables this.", _, true, 0.0, true, 1.0);

	HookConVarChange(g_cvarEnabled, OnConVarChanged_tf2x10_enable);
	HookConVarChange(g_cvarHeadScaling, OnConVarChanged);
	HookConVarChange(g_cvarHeadScalingCap, OnConVarChanged);
	HookConVarChange(FindConVar("tf_feign_death_duration"), OnConVarChanged);
}

public OnConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	//g_iHeadCap = GetConVarInt(g_cvarHeadCap);
	if(convar == g_bHeadScaling)
	{
		g_bHeadScaling = GetConVarBool(g_cvarHeadScaling);
	}
	else if(convar == g_fHeadScalingCap)
	{
		g_fHeadScalingCap = GetConVarFloat(g_cvarHeadScalingCap);
	}
	else if(convar == FindConVar("tf_feign_death_duration"))
	{
		tf_feign_death_duration = GetConVarInt(FindConVar("tf_feign_death_duration"));
	}
	else if(convar == g_cvarAutoUpdate)
	{
		GetConVarInt(g_cvarAutoUpdate) ? Updater_AddPlugin(UPDATE_URL) : Updater_RemovePlugin();
	}
}

public OnConVarChanged_tf2x10_enable(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if (GetConVarBool(g_cvarEnabled))
	{
		for (new client=1; client < MaxClients; client++)
		{
			if(IsValidClient(client))
			{
				ResetVariables(client);
				SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
				SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
			}
		}

		g_bHiddenRunning = GetConVarValue("sm_hidden_enabled") == 1;
		#if defined _freak_fortress_2_included
			g_bFF2Running = LibraryExists("freak_fortress_2") ? FF2_IsFF2Enabled() : false;
		#else
			g_bFF2Running = false;
		#endif

		#if defined _saxtonhale_included
			g_bVSHRunning = LibraryExists("saxtonhale") ? VSH_IsSaxtonHaleModeEnabled() : false;
		#else
			g_bVSHRunning = false;
		#endif

		ClearTrie(g_hItemInfoTrie);
		LoadFileIntoTrie("default", "tf2x10_base_items");

		if(g_bFF2Running || g_bVSHRunning)
		{
			g_sSelectedMod = "vshff2";
			LoadFileIntoTrie(g_sSelectedMod);
		}

		if(g_bAprilFools)
		{
			g_sSelectedMod = "aprilfools";
			LoadFileIntoTrie(g_sSelectedMod);
		}
	}
	else
	{
		for (new client=1; client < MaxClients; client++)
		{
			if(IsValidClient(client))
			{
				ResetVariables(client);
				SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
				SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
			}
		}

		ClearTrie(g_hItemInfoTrie);
	}
	DetectGameDescSetting();
}

DetectGameDescSetting()
{
	new bool:bGameDesc = GetConVarBool(g_cvarGameDesc);

	decl String:sDescription[16];
	GetGameDescription(sDescription, sizeof(sDescription));

	if(GetConVarBool(g_cvarEnabled) && bGameDesc && StrEqual(sDescription, "Team Fortress"))
	{
		Format(sDescription, sizeof(sDescription), "TF2x10 v%s", PLUGIN_VERSION);
		Steam_SetGameDescription(sDescription);
	}
	else if((!GetConVarBool(g_cvarEnabled) || !bGameDesc) && StrContains(sDescription, "TF2x10 ") != -1)
	{
		Steam_SetGameDescription("Team Fortress");
	}
}

HookAllEvents()
{
	HookEvent("arena_win_panel", event_round_end, EventHookMode_PostNoCopy);
	HookEvent("object_destroyed", event_object_destroyed, EventHookMode_Post);
	HookEvent("object_removed", event_object_remove, EventHookMode_Post);
	HookEvent("player_death", event_player_death, EventHookMode_Post);
	HookUserMessage(GetUserMessageId("PlayerShieldBlocked"), Event_PlayerShieldBlocked);
	HookEvent("post_inventory_application", event_postinventory, EventHookMode_Post);
	HookEvent("teamplay_restart_round", event_round_end, EventHookMode_PostNoCopy);
	HookEvent("teamplay_win_panel", event_round_end, EventHookMode_PostNoCopy);
	HookEvent("round_end", event_round_end, EventHookMode_PostNoCopy);
	HookEvent("object_deflected", event_deflected, EventHookMode_Post);
	HookEvent("mvm_pickup_currency", event_pickup_currency, EventHookMode_Pre);
}

public OnAdminMenuReady(Handle:topmenu)
{
	if (topmenu == g_hTopMenu)
	{
		return;
	}

	g_hTopMenu = topmenu;

	new TopMenuObject:player_commands = FindTopMenuCategory(g_hTopMenu, ADMINMENU_SERVERCOMMANDS);

	if (player_commands != INVALID_TOPMENUOBJECT)
	{
		AddToTopMenu(g_hTopMenu,
		"TF2x10 Recache Weapons",
		TopMenuObject_Item,
		AdminMenu_Recache,
		player_commands,
		"sm_tf2x10_recache",
		ADMFLAG_GENERIC);
	}
}

LoadFileIntoTrie(const String:rawname[], const String:basename[] = "")
{
	decl String:strBuffer[64];
	decl String:strBuffer2[64];
	decl String:strBuffer3[64];
	BuildPath(Path_SM, strBuffer, sizeof(strBuffer), "configs/x10.%s.txt", rawname);
	decl String:tmpID[32];
	decl String:finalbasename[32];
	new i;

	strcopy(finalbasename, sizeof(finalbasename), StrEqual(basename, "") ? rawname : basename);

	new Handle:hKeyValues = CreateKeyValues(finalbasename);
	if (FileToKeyValues(hKeyValues, strBuffer) == true)
	{
		KvGetSectionName(hKeyValues, strBuffer, sizeof(strBuffer));
		if (StrEqual(strBuffer, finalbasename) == true)
		{
			if (KvGotoFirstSubKey(hKeyValues))
			{
				do
				{
					i = 0;

					KvGetSectionName(hKeyValues, strBuffer, sizeof(strBuffer));
					KvGotoFirstSubKey(hKeyValues, false);

					do
					{
						KvGetSectionName(hKeyValues, strBuffer2, sizeof(strBuffer2));
						Format(tmpID, sizeof(tmpID), "%s__%s_%d_name", rawname, strBuffer, i);
						SetTrieString(g_hItemInfoTrie, tmpID, strBuffer2);

						KvGetString(hKeyValues, NULL_STRING, strBuffer3, sizeof(strBuffer3));
						Format(tmpID, sizeof(tmpID), "%s__%s_%d_val", rawname, strBuffer, i);
						SetTrieString(g_hItemInfoTrie, tmpID, strBuffer3);

						i++;
					}
					while(KvGotoNextKey(hKeyValues, false));
					KvGoBack(hKeyValues);

					Format(tmpID, sizeof(tmpID), "%s__%s_size", rawname, strBuffer);
					SetTrieValue(g_hItemInfoTrie, tmpID, i);
				}
				while(KvGotoNextKey(hKeyValues));
				KvGoBack(hKeyValues);

				SetTrieValue(g_hItemInfoTrie, strBuffer, 1);
			}
		}
		else
		{
			CloseHandle(hKeyValues);
			return -2;
		}
	}
	else
	{
		CloseHandle(hKeyValues);
		return -1;
	}
	CloseHandle(hKeyValues);
	return 1;
}

public Action:Timer_ServerRunningX10(Handle:hTimer)
{
	if (!GetConVarBool(g_cvarEnabled))
	{
		return Plugin_Stop;
	}

	DetectGameDescSetting();

	PrintToChatAll("\x01[\x07FF0000TF2\x070000FFx10\x01] Mod by \x07FF5C33UltiMario\x01 and \x073399FFMr. Blue\x01. Plugin development by \x07008800Wliu\x01 (based off of \x0794DBFFI\x01s\x0794DBFFa\x01t\x0794DBFFi\x01s's and \x075C5C8AInvisGhost\x01's code).");
	PrintToChatAll("\x01Join our Steam group for Hale x10, Randomizer x10 and more by typing \x05/x10group\x01!");

	return Plugin_Continue;
}

/******************************************************************

SourceMod Admin Commands

******************************************************************/

public AdminMenu_Recache(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if (!GetConVarBool(g_cvarEnabled))
	{
		return;
	}

	switch (action)
	{
		case TopMenuAction_DisplayOption:
		{
			Format(buffer, maxlength, "TF2x10 Recache Weapons");
		}

		case TopMenuAction_SelectOption:
		{
			Command_Recache(param, 0);
		}
	}
}

public Action:Command_Enable(client, args)
{
	if (!GetConVarBool(g_cvarEnabled))
	{
		ServerCommand("tf2x10_enabled 1");
		ReplyToCommand(client, "[TF2x10] Multiply A Weapon's Stats by 10 Plugin is now enabled.");
	}
	else
	{
		ReplyToCommand(client, "[TF2x10] Multiply A Weapon's Stats by 10 Plugin is already enabled.");
	}
	return Plugin_Handled;
}

public Action:Command_Disable(client, args)
{
	if (GetConVarBool(g_cvarEnabled))
	{
		ServerCommand("tf2x10_enabled 0");
		ReplyToCommand(client, "[TF2x10] Multiply A Weapon's Stats by 10 Plugin is now disabled.");
	}
	else
	{
		ReplyToCommand(client, "[TF2x10] Multiply A Weapon's Stats by 10 Plugin is already disabled.");
	}
	return Plugin_Handled;
}

public Action:Command_GetMod(client, args)
{
	if (GetConVarBool(g_cvarEnabled))
	{
		ReplyToCommand(client, "[TF2x10] This mod is loading from configs/x10.%s.txt primarily.", g_sSelectedMod);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action:Command_Group(client, args)
{
	new Handle:kv = CreateKeyValues("data");
	KvSetString(kv, "title", "TF2x10 Steam Group");
	KvSetString(kv, "msg", "http://www.steamcommunity.com/groups/tf2x10");
	KvSetNum(kv, "customsvr", 1);
	KvSetNum(kv, "type", MOTDPANEL_TYPE_URL);
	ShowVGUIPanel(client, "info", kv, true);
	CloseHandle(kv);

	return Plugin_Handled;
}

public Action:Command_Recache(client, args)
{
	if (GetConVarBool(g_cvarEnabled))
	{
		switch(LoadFileIntoTrie("default", "tf2x10_base_items"))
		{
			case -1:
			{
				ReplyToCommand(client, "[TF2x10] Could not find configs/x10.default.txt. Please check and try again.");
			}
			case -2:
			{
				ReplyToCommand(client, "[TF2x10] Your configs/x10.default.txt seems to be corrupt. Please check and try again.");
			}
			default:
			{
				ReplyToCommand(client, "[TF2x10] Weapons recached.");
			}
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action:Command_SetMod(client, args)
{
	if(GetConVarBool(g_cvarEnabled))
	{
		if(args != 1)
		{
			ReplyToCommand(client, "[TF2x10] Please specify a mod name to load. Usage: sm_tf2x10_setmod <name>");
			return Plugin_Handled;
		}

		new uselessVar;
		GetCmdArg(1, g_sSelectedMod, sizeof(g_sSelectedMod));

		if (!StrEqual(g_sSelectedMod, "default") && !GetTrieValue(g_hItemInfoTrie, g_sSelectedMod, uselessVar))
		{
			switch(LoadFileIntoTrie(g_sSelectedMod))
			{
				case -1:
				{
					ReplyToCommand(client, "[TF2x10] Could not find configs/x10.%s.txt. Please check and try again.", g_sSelectedMod);
					g_sSelectedMod = "default";
					return Plugin_Handled;
				}
				case -2:
				{
					ReplyToCommand(client, "[TF2x10] Your configs/x10.%s.txt seems to be corrupt: first line does not match filename.", g_sSelectedMod);
					g_sSelectedMod = "default";
					return Plugin_Handled;
				}
			}
		}

		if(!StrEqual(g_sSelectedMod, "default"))
		{
			ReplyToCommand(client, "[TF2x10] Now loading from configs/x10.%s.txt, defaulting to configs/x10.default.txt.", g_sSelectedMod);
		}
		else
		{
			ReplyToCommand(client, "[TF2x10] Now loading from configs/x10.default.txt.");
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

/******************************************************************

SourceMod Map/Library Events

******************************************************************/

public OnAllPluginsLoaded()
{
	g_bHiddenRunning = GetConVarValue("sm_hidden_enabled") == 1;
	#if defined _freak_fortress_2_included
		g_bFF2Running = LibraryExists("freak_fortress_2") ? FF2_IsFF2Enabled() : false;
	#else
		g_bFF2Running = false;
	#endif

	#if defined _saxtonhale_included
		g_bVSHRunning = LibraryExists("saxtonhale") ? VSH_IsSaxtonHaleModeEnabled() : false;
	#else
		g_bVSHRunning = false;
	#endif

	if(g_bFF2Running || g_bVSHRunning)
	{
		g_sSelectedMod = "vshff2";
		LoadFileIntoTrie(g_sSelectedMod);
	}

	if(g_bAprilFools)
	{
		g_sSelectedMod = "aprilfools";
		LoadFileIntoTrie(g_sSelectedMod);
	}
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "updater") && GetConVarBool(g_cvarAutoUpdate))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	else if(StrEqual(name, "freak_fortress_2"))
	{
		#if defined _freak_fortress_2_included
			g_bFF2Running = FF2_IsFF2Enabled();
		#endif
	}
	else if(StrEqual(name, "saxtonhale"))
	{
		#if defined _saxtonhale_included
			g_bVSHRunning = VSH_IsSaxtonHaleModeEnabled();
		#endif
	}
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "freak_fortress_2"))
	{
		g_bFF2Running = false;
	}
	else if(StrEqual(name, "saxtonhale"))
	{
		g_bVSHRunning = false;
	}
	else if(StrEqual(name, "updater"))
	{
		Updater_RemovePlugin();
	}
}

public OnMapStart()
{
	if (GetConVarBool(g_cvarEnabled))
	{
		DetectGameDescSetting();
	}
}

public OnMapEnd()
{
	decl String:sDescription[16];
	GetGameDescription(sDescription, sizeof(sDescription));

	if (GetConVarBool(g_cvarEnabled) && GetConVarBool(g_cvarGameDesc) && StrContains(sDescription, "TF2x10 ") != -1)
	{
		Steam_SetGameDescription("Team Fortress");
	}
}

/******************************************************************

Player Connect/Disconnect & Round End

******************************************************************/

public OnClientPutInServer(client)
{
	if (GetConVarBool(g_cvarEnabled))
	{
		ResetVariables(client);
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
		SDKHook(client, SDKHook_PreThink, OnPreThink);
	}
}

public OnClientDisconnect(client)
{
	if (GetConVarBool(g_cvarEnabled))
	{
		ResetVariables(client);
		SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
		SDKUnhook(client, SDKHook_PreThink, OnPreThink);
	}
}

public Action:event_round_end(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GetConVarBool(g_cvarEnabled))
	{
		for(new client=1; client <= MaxClients; client++)
		{
			ResetVariables(client);
		}
	}
	return Plugin_Continue;
}

/******************************************************************

Gameplay: Event-Specific

******************************************************************/

public TF2_OnConditionAdded(client, TFCond:condition)
{
	if(!GetConVarBool(g_cvarEnabled))
	{
		return;
	}

	new weapon = IsValidClient(client) ? GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") : -1;
	new index = IsValidEntity(weapon) ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") : -1;

	if(condition == TFCond_Zoomed && index == 402)
	{
		g_fChargeBegin[client] = GetGameTime();
		CreateTimer(0.0, Timer_BazaarCharge, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}

	if(condition == TFCond_Taunting && (index == 159 || index == 433) && !g_bVSHRunning && !g_bFF2Running && !g_bHiddenRunning)
	{
		CreateTimer(1.0, Timer_DalokohX10, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public TF2_OnConditionRemoved(client, TFCond:condition)
{
	if(GetConVarBool(g_cvarEnabled))
	{
		if(condition == TFCond_Zoomed && g_fChargeBegin[client])
		{
			g_fChargeBegin[client] = 0.0;
		}

		if(condition == TFCond_Taunting && g_iDalokohSecs[client])
		{
			g_iDalokohSecs[client] = 0;
		}
	}
}

public Action:Timer_BazaarCharge(Handle:hTimer, any:userid)
{
	new client = GetClientOfUserId(userid);

	if(!IsValidClient(client) || !IsPlayerAlive(client) || !TF2_IsPlayerInCondition(client, TFCond_Zoomed))
	{
		return Plugin_Stop;
	}

	new activeWep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	if(!IsValidEntity(activeWep))
	{
		return Plugin_Stop;
	}

	new index = GetEntProp(activeWep, Prop_Send, "m_iItemDefinitionIndex");

	if(index != 402)
	{
		return Plugin_Stop;
	}

	new heads = GetEntProp(client, Prop_Send, "m_iDecapitations");

	if(heads > sizeof(g_fBazaarRates) - 1)
	{
		heads = sizeof(g_fBazaarRates) - 1;
	}

	new Float:charge = ((GetGameTime() - g_fChargeBegin[client]) / g_fBazaarRates[heads]) * 150;

	if(charge > 150)
	{
		charge = 150.0;
	}

	SetEntPropFloat(activeWep, Prop_Send, "m_flChargedDamage", charge);

	return Plugin_Continue;
}

public Action:Timer_DalokohX10(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(!IsValidClient(client) || !IsPlayerAlive(client) || !TF2_IsPlayerInCondition(client, TFCond_Taunting))
	{
		return Plugin_Stop;
	}

	new weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	if(!IsValidEntity(weapon))
	{
		return Plugin_Stop;
	}

	new secondary = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	if(secondary != 159 && secondary != 433)  //Dalokohs Bar, Fishcake
	{
		return Plugin_Stop;
	}

	weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if(!IsValidEntity(weapon))
	{
		return Plugin_Stop;
	}

	new melee = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

	new health = GetClientHealth(client);
	new newHealth;

	g_iDalokohSecs[client]++;
	if(g_iDalokohSecs[client] == 1)
	{
		if(!dalokohs[client])
		{
			dalokohs[client] = true;
			SDKHook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
		}

		if(dalokohsTimer[client] != INVALID_HANDLE)
		{
			KillTimer(dalokohsTimer[client]);
			dalokohsTimer[client] = INVALID_HANDLE;
		}
		dalokohsTimer[client] = CreateTimer(30.0, Timer_DalokohsEnd, userid, TIMER_FLAG_NO_MAPCHANGE);
		//TF2Attrib_SetByName(secondary, "hidden maxhealth non buffed", float(DALOKOH_MAXHEALTH - 300));  //Disabled due to Invasion crashes
	}
	else if(g_iDalokohSecs[client] == 4)
	{
		newHealth = health + DALOKOH_LASTHEALTH;

		if(newHealth > DALOKOH_MAXHEALTH)
		{
			newHealth = DALOKOH_MAXHEALTH;
		}

		if(melee == 310)
		{
			newHealth = 650;
		}

		TF2_SetHealth(client, newHealth);
	}

	if(health < DALOKOH_MAXHEALTH && g_iDalokohSecs[client] >= 1 && g_iDalokohSecs[client] <= 3)
	{
		newHealth = g_iDalokohSecs[client] == 3 ? health + DALOKOH_HEALTHPERSEC : health + DALOKOH_HEALTHPERSEC - 50;

		if(newHealth > DALOKOH_MAXHEALTH)
		{
			newHealth = DALOKOH_MAXHEALTH;
		}

		if(melee == 310)
		{
			newHealth = 650;
		}

		TF2_SetHealth(client, newHealth);
	}

	return Plugin_Continue;
}

public Action:Timer_DalokohsEnd(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if(client)
	{
		dalokohs[client] = false;
		SDKUnhook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
		dalokohsTimer[client] = INVALID_HANDLE;
	}
	return Plugin_Continue;
}

public OnGameFrame()
{
	for(new client=1; client <= MaxClients; client++)
	{
		if (!IsValidClient(client) || !IsPlayerAlive(client))
		{
			continue;
		}

		if(g_bTakesHeads[client])
		{
			new heads = GetEntProp(client, Prop_Send, "m_iDecapitations");
			/*if(heads > 4)
			{
				new Float:speed = GetEntPropFloat(client, Prop_Data, "m_flMaxspeed");
				new Float:newSpeed = heads < g_iHeadCap ? speed + 20.0 : speed;
				SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", newSpeed > 520.0 ? 520.0 : newSpeed);
				PrintToChatAll("[TF2x10] %N %i heads %f speed", client, heads, newSpeed);
			}*/

			if(g_bHeadScaling)
			{
				new Float:fPlayerHeadScale = 1.0 + heads / 4.0;

				if (fPlayerHeadScale <= (g_bAprilFools ? 9999.0 : g_fHeadScalingCap))  //April Fool's 2015: Heads keep getting bigger!
				{
					SetEntPropFloat(client, Prop_Send, "m_flHeadScale", fPlayerHeadScale);
				}
				else
				{
					SetEntPropFloat(client, Prop_Send, "m_flHeadScale", g_fHeadScalingCap);
				}
			}
		}
	}
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (!GetConVarBool(g_cvarEnabled) || !IsValidClient(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	new activeWep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	new index = IsValidEntity(activeWep) ? GetEntProp(activeWep, Prop_Send, "m_iItemDefinitionIndex") : -1;

	if(buttons & IN_ATTACK && index == 1098)
	{
		g_bChargingClassic[client] = true;
	} else
	{
		g_bChargingClassic[client] = false;
	}

	if (index == 307)
	{
		new detonated = GetEntProp(activeWep, Prop_Send, "m_iDetonated");

		if (detonated == 0)
		{
			SetHudTextParams(0.0, 0.0, 0.5, 255, 255, 255, 255, 0, 0.1, 0.1, 0.2);
			ShowSyncHudText(client, g_hHudText, "Cabers: %d", g_iCabers[client]);
		}

		if (g_iCabers[client] > 1 && detonated == 1)
		{
			SetEntProp(activeWep, Prop_Send, "m_iDetonated", 0);
			g_iCabers[client]--;
		}
	}

	else if (index == 19 || index == 206 || index == 1007)
	{
		new iClip = GetEntProp(activeWep, Prop_Send, "m_iClip1");
		if (iClip >= 10)
		{
			buttons &= ~IN_ATTACK;
		}
	}

	if (g_iRazorbackCount[client] > 1)
	{
		SetHudTextParams(0.0, 0.0, 0.5, 255, 255, 255, 255, 0, 0.1, 0.1, 0.2);
		ShowSyncHudText(client, g_hHudText, "Razorbacks: %d", g_iRazorbackCount[client]);
	}

	if (g_bHasManmelter[client])
	{
		new revengeCrits = GetEntProp(client, Prop_Send, "m_iRevengeCrits");

		if (revengeCrits > g_iRevengeCrits[client])
		{
			new newCrits = ((revengeCrits - g_iRevengeCrits[client]) * GetConVarInt(g_cvarCritsManmelter)) + revengeCrits - 1;
			SetEntProp(client, Prop_Send, "m_iRevengeCrits", newCrits);

			g_iRevengeCrits[client] = newCrits;
		}
		else
		{
			g_iRevengeCrits[client] = revengeCrits;
		}
	}

	return Plugin_Continue;
}

public Action:OnGetMaxHealth(client, &maxHealth)
{
	if(GetConVarBool(g_cvarEnabled))
	{
		if(dalokohs[client])
		{
			maxHealth = DALOKOH_MAXHEALTH;
			return Plugin_Changed;
		}

		/*new heads = GetEntProp(client, Prop_Data, "m_iDecapitations");
		if(heads < g_iHeadCap)
		{
			maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth") + heads * 15;
			return Plugin_Changed;
		}*/
	}
	return Plugin_Continue;
}

public Action:event_deflected(Handle:event, const String:name[], bool:dontBroadcast)
{
	#if defined _freak_fortress_2_included
	if(GetConVarBool(g_cvarEnabled) && g_bFF2Running && !GetEventInt(event, "weaponid"))  //A non-0 weaponid indicates that a projectile got deflected and not a client
	{
		new iBossIndex = FF2_GetBossIndex(GetClientOfUserId(GetEventInt(event, "ownerid")));

		new activeWep = GetEntPropEnt(GetClientOfUserId(GetEventInt(event, "userid")), Prop_Send, "m_hActiveWeapon");
		new index = IsValidEntity(activeWep) ? GetEntProp(activeWep, Prop_Send, "m_iItemDefinitionIndex") : -1;

		if (iBossIndex != -1 && (index == 40 || index == 1146)) //backburner
		{
			new Float:fBossCharge = FF2_GetBossCharge(iBossIndex, 0) + 63.0; //work with FF2's deflect to set to 70 in total instead of 7

			if(fBossCharge > 100.0)
			{
				FF2_SetBossCharge(iBossIndex, 0, 100.0);
			}
			else
			{
				FF2_SetBossCharge(iBossIndex, 0, fBossCharge);
			}
		}
	}
	#endif
	return Plugin_Continue;
}

public Action:event_object_destroyed(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!GetConVarBool(g_cvarEnabled))
	{
		return Plugin_Continue;
	}

	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new primaryWep = GetPlayerWeaponSlot(attacker, TFWeaponSlot_Primary);
	new critsDiamondback = GetConVarInt(g_cvarCritsDiamondback);

	if (IsValidClient(attacker) && IsPlayerAlive(attacker) && critsDiamondback > 0 && IsValidEntity(primaryWep) && WeaponHasAttribute(attacker, primaryWep, "sapper kills collect crits"))
	{
		decl String:weapon[32];
		GetEventString(event, "weapon", weapon, sizeof(weapon));

		if(StrContains(weapon, "sapper") != -1 || StrEqual(weapon, "recorder"))
		{
			new crits = GetEntProp(attacker, Prop_Send, "m_iRevengeCrits") + critsDiamondback - 1;
			SetEntProp(attacker, Prop_Send, "m_iRevengeCrits", crits);
		}
	}
	return Plugin_Continue;
}

public Action:event_object_remove(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!GetConVarBool(g_cvarEnabled))
	{
		return Plugin_Continue;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	new weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if (!IsValidEntity(weapon))
	{
		return Plugin_Continue;
	}

	if(WeaponHasAttribute(client, weapon, "mod sentry killed revenge") && GetEventInt(event, "objecttype") == 2)
	{
		new crits = GetEntProp(client, Prop_Send, "m_iRevengeCrits") + g_iBuildingsDestroyed[client];
		SetEntProp(client, Prop_Send, "m_iRevengeCrits", crits);
		g_iBuildingsDestroyed[client] = 0;
	}
	return Plugin_Continue;
}

public Action:event_pickup_currency(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetEventInt(event, "player");
	new dollars = GetEventInt(event, "currency");
	new newDollahs = 0;

	if(GetEntProp(client, Prop_Send, "m_nCurrency") < MAX_CURRENCY)
	{
		newDollahs = RoundToNearest(float(dollars) / 3.16);
	}

	SetEventInt(event, "currency", newDollahs);

	return Plugin_Continue;
}

public Action:TF2_OnIsHolidayActive(TFHoliday:holiday, &bool:result)
{
	if(holiday == TFHoliday_AprilFools && result)
	{
		g_bAprilFools=true;
	}
	return Plugin_Continue;
}

/******************************************************************

Gameplay: Damage and Death Only

******************************************************************/

public Action:event_player_death(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!GetConVarBool(g_cvarEnabled))
	{
		return Plugin_Continue;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new inflictor_entindex = GetEventInt(event, "inflictor_entindex");
	new activewep = IsValidClient(attacker) ? GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon") : -1;
	new weaponid = IsValidEntity(activewep) ? GetEntProp(activewep, Prop_Send, "m_iItemDefinitionIndex") : -1;
	new customKill = GetEventInt(event, "customkill");

	if(g_bAprilFools && weaponid == 356)  //April Fool's 2015: Kunai gives health on ALL kills
	{
		TF2_SetHealth(attacker, KUNAI_DAMAGE);
	}
	else if(weaponid == 317)
	{
		TF2_SpawnMedipack(client);
	}
	else if(customKill == TF_CUSTOM_BACKSTAB && !g_bHiddenRunning)
	{
		if(weaponid == 356)
		{
			TF2_SetHealth(attacker, KUNAI_DAMAGE);
		}
		if(IsValidClient(attacker))
		{
			new primWep = GetPlayerWeaponSlot(attacker, TFWeaponSlot_Primary);
			if(IsValidEntity(primWep) && WeaponHasAttribute(attacker, primWep, "sapper kills collect crits"))
			{
				new crits = GetEntProp(attacker, Prop_Send, "m_iRevengeCrits") + GetConVarInt(g_cvarCritsDiamondback) - 1;
				SetEntProp(attacker, Prop_Send, "m_iRevengeCrits", crits);
			}
		}
	}
	/*else if(IsValidClient(attacker) && g_bTakesHeads[attacker])
	{
		new heads = GetEntProp(attacker, Prop_Send, "m_iDecapitations");
		if(heads > 4)
		{
			SDKHook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
		}
	}*/

	if(GetEventInt(event, "death_flags") & TF_DEATHFLAG_DEADRINGER)
	{
		TF2_AddCondition(client, TFCond_SpeedBuffAlly, tf_feign_death_duration * 10.0);  //Speed boost * 10
	}

	if(IsValidEntity(inflictor_entindex))
	{
		decl String:inflictorName[32];
		GetEdictClassname(inflictor_entindex, inflictorName, sizeof(inflictorName));

		if(StrContains(inflictorName, "sentry") >= 0)
		{
			new critsFJ = GetConVarInt(g_cvarCritsFJ);

			if(GetEventInt(event, "assister") < 1)
			{
				g_iBuildingsDestroyed[attacker] = g_iBuildingsDestroyed[attacker] + critsFJ - 2;
			}
			else
			{
				g_iBuildingsDestroyed[attacker] = g_iBuildingsDestroyed[attacker] + RoundToNearest(critsFJ / 2.0) - 2;
			}
		}
	}

	if(dalokohs[client])
	{
		SDKUnhook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
		if(dalokohsTimer[client] != INVALID_HANDLE)
		{
			KillTimer(dalokohsTimer[client]);
			dalokohsTimer[client] = INVALID_HANDLE;
		}
	}

	ResetVariables(client);
	return Plugin_Continue;
}

new _medPackTraceFilteredEnt = 0;

TF2_SpawnMedipack(client, bool:cmd = false)
{
	decl Float:fPlayerPosition[3];
	GetClientAbsOrigin(client, fPlayerPosition);

	if (fPlayerPosition[0] != 0.0 && fPlayerPosition[1] != 0.0 && fPlayerPosition[2] != 0.0)
	{
		fPlayerPosition[2] += 4;

		if (cmd)
		{
			new Float:PlayerPosEx[3], Float:PlayerAngle[3], Float:PlayerPosAway[3];
			GetClientEyeAngles(client, PlayerAngle);
			PlayerPosEx[0] = Cosine((PlayerAngle[1]/180)*FLOAT_PI);
			PlayerPosEx[1] = Sine((PlayerAngle[1]/180)*FLOAT_PI);
			PlayerPosEx[2] = 0.0;
			ScaleVector(PlayerPosEx, 75.0);
			AddVectors(fPlayerPosition, PlayerPosEx, PlayerPosAway);

			_medPackTraceFilteredEnt = client;
			new Handle:TraceEx = TR_TraceRayFilterEx(fPlayerPosition, PlayerPosAway, MASK_SOLID, RayType_EndPoint, MedipackTraceFilter);
			TR_GetEndPosition(fPlayerPosition, TraceEx);
			CloseHandle(TraceEx);
		}

		new Float:Direction[3];
		Direction[0] = fPlayerPosition[0];
		Direction[1] = fPlayerPosition[1];
		Direction[2] = fPlayerPosition[2]-1024;
		new Handle:Trace = TR_TraceRayFilterEx(fPlayerPosition, Direction, MASK_SOLID, RayType_EndPoint, MedipackTraceFilter);

		new Float:MediPos[3];
		TR_GetEndPosition(MediPos, Trace);
		CloseHandle(Trace);
		MediPos[2] += 4;

		new Medipack = CreateEntityByName("item_healthkit_full");
		DispatchKeyValue(Medipack, "OnPlayerTouch", "!self,Kill,,0,-1");
		if (DispatchSpawn(Medipack))
		{
			SetEntProp(Medipack, Prop_Send, "m_iTeamNum", 0, 4);
			TeleportEntity(Medipack, MediPos, NULL_VECTOR, NULL_VECTOR);
			EmitSoundToAll("items/spawn_item.wav", Medipack, _, _, _, 0.75);
		}
	}
}

public bool:MedipackTraceFilter(ent, contentMask)
{
	return (ent != _medPackTraceFilteredEnt);
}

public OnPreThink(client)
{
	if(g_bChargingClassic[client])
	{
		new activeWep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		new index = IsValidEntity(activeWep) ? GetEntProp(activeWep, Prop_Send, "m_iItemDefinitionIndex") : -1;

		if(IsValidEntity(activeWep) && index == 1098)
		{
			SetEntPropFloat(activeWep, Prop_Send, "m_flChargedDamage", GetEntPropFloat(activeWep, Prop_Send, "m_flChargedDamage") * 10);
		}
	}
}

public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	if (!GetConVarBool(g_cvarEnabled))
	{
		return Plugin_Continue;
	}

	if (damagecustom == TF_CUSTOM_BOOTS_STOMP)
	{
		damage *= 10;
		return Plugin_Changed;
	}

	decl String:classname[64];
	if (!IsValidEntity(weapon) || !GetEdictClassname(weapon, classname, sizeof(classname)))
	{
		return Plugin_Continue;
	}

	if (StrEqual(classname, "tf_weapon_bat_fish") && damagecustom != TF_CUSTOM_BLEEDING &&
		damagecustom != TF_CUSTOM_BURNING && damagecustom != TF_CUSTOM_BURNING_ARROW &&
		damagecustom != TF_CUSTOM_BURNING_FLARE && attacker != client && IsPlayerAlive(client))
	{
		decl Float:ang[3];
		GetClientEyeAngles(client, ang);
		ang[1] = ang[1] + 120.0;

		TeleportEntity(client, NULL_VECTOR, ang, NULL_VECTOR);
	}

	//Alien Isolation bonuses
	new bool:validWeapon = !StrContains(classname, "tf_weapon", false);
	if (validWeapon && GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 30474 &&
		TF2Attrib_GetByDefIndex(client, 694) &&
		TF2Attrib_GetByDefIndex(attacker, 695))
	{
		damage*=10;
		return Plugin_Changed;
	}
	else if (validWeapon && weapon == GetPlayerWeaponSlot(attacker, TFWeaponSlot_Melee) &&
		TF2Attrib_GetByDefIndex(client, 696) &&
		TF2Attrib_GetByDefIndex(attacker, 693))
	{
		damage*=10;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public OnTakeDamagePost(client, attacker, inflictor, Float:damage, damagetype)
{
	if (!GetConVarBool(g_cvarEnabled))
	{
		return;
	}

	if (IsValidClient(client) && IsPlayerAlive(client) && !ShouldDisableWeapons(client))
	{
		CheckHealthCaps(client);
	}

	if (IsValidClient(attacker) && attacker != client && !ShouldDisableWeapons(attacker) && IsPlayerAlive(attacker))
	{
		CheckHealthCaps(attacker);
	}
}

ShouldDisableWeapons(client)
{
	//in case vsh/ff2 and other mods are running, disable x10 effects and checks
	//this list may get extended as I check out more game mods

	#if defined _freak_fortress_2_included
		if(g_bFF2Running && FF2_GetBossTeam() == GetClientTeam(client))
		{
			return true;
		}
	#endif

	#if defined _saxtonhale_included
		if(g_bVSHRunning && VSH_GetSaxtonHaleUserId() == GetClientUserId(client))
		{
			return true;
		}
	#endif

	return (g_bHiddenRunning && GetClientTeam(client) == _:TFTeam_Blue);
}

CheckHealthCaps(client)
{
	if(!g_bAprilFools)  //April Fool's 2015: Unlimited health!
	{
		new cap = GetConVarInt(g_cvarHealthCap);

		if (cap > 0 && GetClientHealth(client) > cap)
		{
			TF2_SetHealth(client, cap);
		}
	}
}

public Action:Event_PlayerShieldBlocked(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
	if (!GetConVarBool(g_cvarEnabled) || playersNum < 2)
	{
		return Plugin_Continue;
	}

	new victim = players[0];

	if (g_iRazorbackCount[victim] > 1)
	{
		g_iRazorbackCount[victim]--;

		new loopBreak = 0;
		new slotEntity = -1;

		while ((slotEntity = GetPlayerWeaponSlot_Wearable(victim, TFWeaponSlot_Secondary)) != -1 && loopBreak < 20)
		{
			RemoveEdict(slotEntity);
			loopBreak++;
		}

		RemovePlayerBack(victim);

		new Handle:hWeapon = TF2Items_CreateItem(OVERRIDE_CLASSNAME | OVERRIDE_ITEM_DEF | OVERRIDE_ITEM_LEVEL | OVERRIDE_ITEM_QUALITY | OVERRIDE_ATTRIBUTES);
		TF2Items_SetClassname(hWeapon, "tf_wearable");
		TF2Items_SetItemIndex(hWeapon, 57);
		TF2Items_SetLevel(hWeapon, 10);
		TF2Items_SetQuality(hWeapon, 6);
		TF2Items_SetAttribute(hWeapon, 0, 52, 1.0);
		TF2Items_SetAttribute(hWeapon, 1, 292, 5.0);
		TF2Items_SetNumAttributes(hWeapon, 2);

		new entity = TF2Items_GiveNamedItem(victim, hWeapon);
		CloseHandle(hWeapon);
		SDKCall(g_hSdkEquipWearable, victim, entity);
	}

	return Plugin_Continue;
}

/******************************************************************

Gameplay: Player & Item Spawn

******************************************************************/

public TF2Items_OnGiveNamedItem_Post(client, String:classname[], itemDefinitionIndex, itemLevel, itemQuality, entityIndex)
{
	if (!GetConVarBool(g_cvarEnabled)
		|| (!GetConVarBool(g_cvarIncludeBots) && IsFakeClient(client))
		|| ShouldDisableWeapons(client)
		|| !isCompatibleItem(classname, itemDefinitionIndex)
		|| (itemQuality == 5 && itemDefinitionIndex != 266)
		|| itemQuality == 8 || itemQuality == 10)
	{
		return;
	}

	new size = 0;

	decl String:attribName[64];
	decl String:attribValue[8];
	decl String:selectedMod[16];
	decl String:tmpID[32];

	Format(tmpID, sizeof(tmpID), "%s__%d_size", g_sSelectedMod, itemDefinitionIndex);
	if (!GetTrieValue(g_hItemInfoTrie, tmpID, size))
	{
		Format(tmpID, sizeof(tmpID), "default__%d_size", itemDefinitionIndex);
		if (!GetTrieValue(g_hItemInfoTrie, tmpID, size))
		{
			return;
		}
		else
		{
			strcopy(selectedMod, sizeof(selectedMod), "default");
		}
	}
	else
	{
		strcopy(selectedMod, sizeof(selectedMod), g_sSelectedMod);
	}

	for(new i=0; i < size; i++)
	{
		Format(tmpID, sizeof(tmpID), "%s__%d_%d_name", selectedMod, itemDefinitionIndex, i);
		GetTrieString(g_hItemInfoTrie, tmpID, attribName, sizeof(attribName));

		Format(tmpID, sizeof(tmpID), "%s__%d_%d_val", selectedMod, itemDefinitionIndex, i);
		GetTrieString(g_hItemInfoTrie, tmpID, attribValue, sizeof(attribValue));

		if(StrEqual(attribValue, "remove"))
		{
			TF2Attrib_RemoveByName(entityIndex, attribName);
		}
		else
		{
			TF2Attrib_SetByName(entityIndex, attribName, StringToFloat(attribValue));
		}

		if(itemDefinitionIndex==1153 && TF2_GetPlayerClass(client)==TFClass_Engineer)  //Engineer has the Panic Attack in the primary slot
		{
			TF2Attrib_RemoveByName(entityIndex, "maxammo secondary increased");
			TF2Attrib_SetByName(entityIndex, "maxammo primary increased", StringToFloat(attribValue));
		}
	}
}

bool:isCompatibleItem(String:classname[], iItemDefinitionIndex)
{
	return StrContains(classname, "tf_weapon") != -1 ||
		StrEqual(classname, "saxxy") ||
		StrEqual(classname, "tf_wearable_demoshield") ||
		(StrEqual(classname, "tf_wearable") &&
		(iItemDefinitionIndex == 133 ||
		iItemDefinitionIndex == 444 ||
		iItemDefinitionIndex == 405 ||
		iItemDefinitionIndex == 608 ||
		iItemDefinitionIndex == 57 ||
		iItemDefinitionIndex == 231 ||
		iItemDefinitionIndex == 642));
}

public Action:event_postinventory(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!GetConVarBool(g_cvarEnabled))
	{
		return Plugin_Continue;
	}

	new userid = GetEventInt(event, "userid");
	new Float:delay = GetConVarValue("tf2items_rnd_enabled") == 1 ? 0.3 : 0.1;

	UpdateVariables(GetClientOfUserId(userid));
	CreateTimer(delay, Timer_FixClips, userid, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action:Timer_FixClips(Handle:hTimer, any:userid)
{
	new client = GetClientOfUserId(userid);

	if (!GetConVarBool(g_cvarEnabled) || !IsValidClient(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	for(new slot=0; slot < 2; slot++)
	{
		new wepEntity = GetPlayerWeaponSlot(client, slot);

		if(IsValidEntity(wepEntity))
		{
			CheckClips(wepEntity);

			if(GetConVarValue("tf2items_rnd_enabled") == 1)
			{
				Randomizer_CheckAmmo(client, wepEntity);
			}
		}
	}

	new maxhealth = SDKCall(g_hSdkGetMaxHealth, client);

	if(GetClientHealth(client) != maxhealth)
	{
		TF2_SetHealth(client, maxhealth);
	}

	UpdateVariables(client);
	TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.01); //recalc speed - thx sarge

	return Plugin_Continue;
}

CheckClips(entityIndex)
{
	new Address:attribAddress;

	if ((attribAddress = TF2Attrib_GetByName(entityIndex, "clip size penalty")) != Address_Null ||
		(attribAddress = TF2Attrib_GetByName(entityIndex, "clip size bonus")) != Address_Null ||
		(attribAddress = TF2Attrib_GetByName(entityIndex, "clip size penalty HIDDEN")) != Address_Null)
	{
		new ammoCount = GetEntProp(entityIndex, Prop_Data, "m_iClip1");
		new Float:clipSize = TF2Attrib_GetValue(attribAddress);
		ammoCount = (TF2Attrib_GetByName(entityIndex, "can overload") != Address_Null) ? 0 : RoundToCeil(ammoCount * clipSize);

		SetEntProp(entityIndex, Prop_Send, "m_iClip1", ammoCount);
	}
	else if((attribAddress = TF2Attrib_GetByName(entityIndex, "mod max primary clip override")) != Address_Null)
	{
		SetEntProp(entityIndex, Prop_Send, "m_iClip1", RoundToNearest(TF2Attrib_GetValue(attribAddress)));
	}
}

Randomizer_CheckAmmo(client, entityIndex)
{
	//Canceling out Randomizer's own "give ammo" function to the right amount

	new ammoCount = -1;
	new iOffset = GetEntProp(entityIndex, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
	new iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
	new Address:attribAddress;

	if ((attribAddress = TF2Attrib_GetByName(entityIndex, "maxammo primary increased")) != Address_Null ||
		(attribAddress = TF2Attrib_GetByName(entityIndex, "maxammo secondary increased")) != Address_Null ||
		(attribAddress = TF2Attrib_GetByName(entityIndex, "maxammo primary reduced")) != Address_Null ||
		(attribAddress = TF2Attrib_GetByName(entityIndex, "maxammo secondary reduced")) != Address_Null)
	{
		ammoCount = RoundToCeil(GetEntData(client, iAmmoTable+iOffset) * TF2Attrib_GetValue(attribAddress));
	}
	else if((attribAddress = TF2Attrib_GetByName(entityIndex, "maxammo grenades1 increased")) != Address_Null)
	{
		ammoCount = RoundToCeil(TF2Attrib_GetValue(attribAddress));
	}
	else
	{
		return;
	}

	SetEntData(client, iAmmoTable+iOffset, ammoCount, 4, true);
}

public OnEntityCreated(entity, const String:classname[])
{
	if(StrContains(classname, "item_ammopack")!=-1 || StrEqual(classname, "tf_ammo_pack"))
	{
		SDKHook(entity, SDKHook_Spawn, OnItemSpawned);
	}
}

public OnItemSpawned(entity)
{
	SDKHook(entity, SDKHook_StartTouch, OnPickup);
	SDKHook(entity, SDKHook_Touch, OnPickup);
}

public Action:OnPickup(entity, client)
{
	if(g_bAprilFools && IsValidClient(client) && g_bHasBazooka[client])
	{
		return Plugin_Stop;
	}
	return Plugin_Continue;
}
/******************************************************************

Stock Functions In Gameplay

******************************************************************/

bool:IsValidClient(client)
{
	return client > 0 && client <= MaxClients && IsClientConnected(client)
	&& !IsFakeClient(client) && IsClientInGame(client)
	&& !GetEntProp(client, Prop_Send, "m_bIsCoaching")
	&& !IsClientSourceTV(client) && !IsClientReplay(client);
}

ResetVariables(client)
{
	g_iRazorbackCount[client] = 0;
	g_iCabers[client] = 0;
	g_iDalokohSecs[client] = 0;
	g_iRevengeCrits[client] = 0;
	g_bHasCaber[client] = false;
	g_bHasManmelter[client] = false;
	g_bTakesHeads[client] = false;
	g_bHasBazooka[client] = false;
	dalokohs[client] = false;
	g_fChargeBegin[client] = 0.0;
}

UpdateVariables(client)
{
	new primyWep = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	new secndWep = GetPlayerWeaponSlot_Wearable(client, TFWeaponSlot_Secondary);
	new meleeWep = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);

	if(!IsValidEntity(secndWep))
	{
		secndWep = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	}

	if(IsValidEntity(primyWep))
	{
		g_bHasBazooka[client] = GetEntProp(primyWep, Prop_Send, "m_iItemDefinitionIndex") == 730;
	}
	else
	{
		g_bHasBazooka[client] = false;
	}

	if(IsValidEntity(secndWep))
	{
		g_iRazorbackCount[client] = WeaponHasAttribute(client, secndWep, "backstab shield") ? 10 : 0;
		g_bHasManmelter[client] = WeaponHasAttribute(client, secndWep, "extinguish earns revenge crits");
	}
	else
	{
		g_iRazorbackCount[client] = 0;
		g_bHasManmelter[client] = false;
	}

	if(IsValidEntity(meleeWep))
	{
		g_bHasCaber[client] = GetEntProp(meleeWep, Prop_Send, "m_iItemDefinitionIndex") == 307;
		g_bTakesHeads[client] = WeaponHasAttribute(client, meleeWep, "decapitate type");
	}
	else
	{
		g_bHasCaber[client] = g_bHasManmelter[client] = g_bHasBazooka[client] = g_bTakesHeads[client] = false;
	}

	g_iCabers[client] = g_bHasCaber[client] ? 10 : 0;
}

stock TF2_SetHealth(client, NewHealth)
{
	if (IsValidClient(client))
	{
		SetEntProp(client, Prop_Send, "m_iHealth", NewHealth);
		SetEntProp(client, Prop_Data, "m_iHealth", NewHealth);
	}
}

stock GetPlayerWeaponSlot_Wearable(client, slot)
{
	new edict = MaxClients + 1;
	if (slot == TFWeaponSlot_Secondary)
	{
		while((edict = FindEntityByClassname2(edict, "tf_wearable_demoshield")) != -1)
		{
			new idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
			if ((idx == 131 || idx == 406) && GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
			{
				return edict;
			}
		}
	}

	edict = MaxClients+1;
	while((edict = FindEntityByClassname2(edict, "tf_wearable")) != -1)
	{
		decl String:netclass[32];
		if (GetEntityNetClass(edict, netclass, sizeof(netclass)) && StrEqual(netclass, "CTFWearable"))
		{
			new idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
			if (((slot == TFWeaponSlot_Primary && (idx == 405 || idx == 608)) || (slot == TFWeaponSlot_Secondary && (idx == 57 || idx == 133 || idx == 231 || idx == 444 || idx == 642))) && GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
			{
				return edict;
			}
		}
	}
	return -1;
}

stock FindEntityByClassname2(startEnt, const String:classname[])
{
	while (startEnt > -1 && !IsValidEntity(startEnt))
	{
		startEnt--;
	}
	return FindEntityByClassname(startEnt, classname);
}

stock RemovePlayerBack(client)
{
	new edict = MaxClients+1;
	while((edict = FindEntityByClassname2(edict, "tf_wearable")) != -1)
	{
		decl String:netclass[32];
		if (GetEntityNetClass(edict, netclass, sizeof(netclass)) && StrEqual(netclass, "CTFWearable"))
		{
			new idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
			if ((idx == 57 || idx == 133 || idx == 231 || idx == 444 || idx == 642) && GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
			{
				AcceptEntityInput(edict, "Kill");
			}
		}
	}
}

//I have this in case TF2Attrib_GetByName acts up
stock bool:WeaponHasAttribute(client, entity, String:name[])
{
	if(TF2Attrib_GetByName(entity, name) != Address_Null)
	{
		return true;
	}

	if(StrEqual(name, "backstab shield") && (GetPlayerWeaponSlot_Wearable(client, TFWeaponSlot_Secondary) == 57))
	{
		return true;
	}

	new itemIndex = GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");

	return (StrEqual(name, "sapper kills collect crits") && (itemIndex == 525))
		|| (StrEqual(name, "mod sentry killed revenge") &&
		(itemIndex == 141 || itemIndex == 1004))
		|| (StrEqual(name, "decapitate type") &&
		(itemIndex == 132 || itemIndex == 266 || itemIndex == 482 || itemIndex == 1082))
		|| (StrEqual(name, "ullapool caber") && (itemIndex == 307))
		|| (StrEqual(name, "extinguish earns revenge crits") && (itemIndex == 595));
}

stock GetConVarValue(const String:cvarname[])
{
	new Handle:cvar = FindConVar(cvarname);

	if(cvar == INVALID_HANDLE)
	{
		return 0;
	}

	new value = GetConVarInt(cvar);
	CloseHandle(cvar);

	return value;
}