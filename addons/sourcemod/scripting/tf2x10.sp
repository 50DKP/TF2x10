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
#include <tf2_stocks>
#include <tf2items>
#include <tf2attributes>
#include <steamtools>
#include <updater>
#undef REQUIRE_PLUGIN
#tryinclude <freak_fortress_2>
#tryinclude <saxtonhale>
#define REQUIRE_PLUGIN

#pragma newdecls required  //Put this after the include files since some don't use newdecls

#define PLUGIN_NAME			"Multiply a Weapon's Stats by 10"
#define PLUGIN_AUTHOR		"The TF2x10 group"
#define PLUGIN_VERSION		"1.6.0"
#define PLUGIN_CONTACT		"http://steamcommunity.com/group/tf2x10/"
#define PLUGIN_DESCRIPTION	"It's in the name! Also known as TF2x10 or TF20."

#define UPDATE_URL			"http://ff2.50dkp.com/updater/tf2x10/update.txt"

#define KUNAI_DAMAGE			2100
#define DALOKOH_MAXHEALTH		800
#define DALOKOH_HEALTHPERSEC	150
#define DALOKOH_LASTHEALTH		50
#define MAX_CURRENCY			30000

static const float g_fBazaarRates[] =
{
	16.5, //seconds for 0 heads
	8.25, //seconds for 1 head
	3.3, //seconds for 2 heads
	1.32, //seconds for 3 heads
	0.66, //seconds for 4 heads
	0.44, //seconds for 5 heads
	0.33 //seconds for 6+ heads
};

bool g_bAprilFools;
bool g_bFF2Running;
bool g_bHasCaber[MAXPLAYERS + 1];
bool g_bHasManmelter[MAXPLAYERS + 1];
bool g_bHasBazooka[MAXPLAYERS + 1];
bool g_bHeadScaling;
bool g_bHiddenRunning;
bool g_bTakesHeads[MAXPLAYERS + 1];
bool g_bChargingClassic[MAXPLAYERS + 1];
bool g_bVSHRunning;

float g_fChargeBegin[MAXPLAYERS + 1];
float g_fHeadScalingCap;

int g_iHeadCap;

Handle g_hHudText;
Handle g_hSdkGetMaxHealth;
Handle g_hSdkEquipWearable;
StringMap g_hItemInfoTrie;
TopMenu g_hTopMenu;

Handle dalokohsTimer[MAXPLAYERS + 1];

int g_iBuildingsDestroyed[MAXPLAYERS + 1];
int g_iCabers[MAXPLAYERS + 1];
int g_iDalokohSecs[MAXPLAYERS + 1];
int dalokohs[MAXPLAYERS + 1];
int g_iRazorbackCount[MAXPLAYERS + 1];
int g_iRevengeCrits[MAXPLAYERS + 1];

char g_sSelectedMod[16] = "default";

ConVar g_cvarEnabled;
ConVar g_cvarGameDesc;
ConVar g_cvarAutoUpdate;
ConVar g_cvarHeadCap;
ConVar g_cvarHeadScaling;
ConVar g_cvarHeadScalingCap;
ConVar g_cvarHealthCap;
ConVar g_cvarIncludeBots;
ConVar g_cvarCritsFJ;
ConVar g_cvarCritsDiamondback;
ConVar g_cvarCritsManmelter;

int tf_feign_death_duration;

public Plugin myinfo =
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

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char sGameDir[8];
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

public void OnPluginStart()
{
	CreateConVar("tf2x10_version", PLUGIN_VERSION, "TF2x10 version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	g_cvarAutoUpdate = CreateConVar("tf2x10_autoupdate", "1", "Tells Updater to automatically update this plugin.  0 = off, 1 = on.", _, true, 0.0, true, 1.0);
	g_cvarCritsDiamondback = CreateConVar("tf2x10_crits_diamondback", "10", "Number of crits after successful sap with Diamondback equipped.", _, true, 0.0, false);
	g_cvarCritsFJ = CreateConVar("tf2x10_crits_fj", "10", "Number of crits after Frontier kill or for buildings. Half this for assists.", _, true, 0.0, false);
	g_cvarCritsManmelter = CreateConVar("tf2x10_crits_manmelter", "10", "Number of crits after Manmelter extinguishes player.", _, true, 0.0, false);
	g_cvarEnabled = CreateConVar("tf2x10_enabled", "1", "Toggle TF2x10. 0 = disable, 1 = enable", _, true, 0.0, true, 1.0);
	g_cvarGameDesc = CreateConVar("tf2x10_gamedesc", "1", "Toggle setting game description. 0 = disable, 1 = enable.", _, true, 0.0, true, 1.0);
	g_cvarHeadCap = CreateConVar("tf2x10_headcap", "40", "The number of heads before the wielder stops gaining health and speed bonuses", _, true, 4.0);
	g_cvarHeadScaling = CreateConVar("tf2x10_headscaling", "1", "Enable any decapitation weapon (eyelander etc) to grow their head as they gain heads. 0 = off, 1 = on.", _, true, 0.0, true, 1.0);
	g_cvarHeadScalingCap = CreateConVar("tf2x10_headscalingcap", "6.0", "The number of heads before head scaling stops growing their head. 6.0 = 24 heads.", _, true, 0.0, false);
	g_cvarHealthCap = CreateConVar("tf2x10_healthcap", "2100", "The max health a player can have. -1 to disable.", _, true, -1.0, false);
	g_cvarIncludeBots = CreateConVar("tf2x10_includebots", "0", "1 allows bots to receive TF2x10 weapons, 0 disables this.", _, true, 0.0, true, 1.0);

	g_cvarEnabled.AddChangeHook(OnConVarChanged);
	g_cvarHeadCap.AddChangeHook(OnConVarChanged);
	g_cvarHeadScaling.AddChangeHook(OnConVarChanged);
	g_cvarHeadScalingCap.AddChangeHook(OnConVarChanged);
	FindConVar("tf_feign_death_duration").AddChangeHook(OnConVarChanged);

	AutoExecConfig(true, "plugin.tf2x10");

	RegAdminCmd("sm_tf2x10_disable", Command_Disable, ADMFLAG_CONVARS);
	RegAdminCmd("sm_tf2x10_enable", Command_Enable, ADMFLAG_CONVARS);
	RegAdminCmd("sm_tf2x10_getmod", Command_GetMod, ADMFLAG_GENERIC);
	RegAdminCmd("sm_tf2x10_recache", Command_Recache, ADMFLAG_GENERIC);
	RegAdminCmd("sm_tf2x10_setmod", Command_SetMod, ADMFLAG_CHEATS);
	RegConsoleCmd("sm_x10group", Command_Group);

	HookEvent("arena_win_panel", OnRoundEnd, EventHookMode_PostNoCopy);
	HookEvent("object_destroyed", OnObjectDestroyed, EventHookMode_Post);
	HookEvent("object_removed", OnObjectRemoved, EventHookMode_Post);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	HookEvent("post_inventory_application", OnPostInventoryApplication, EventHookMode_Post);
	HookEvent("teamplay_restart_round", OnRoundEnd, EventHookMode_PostNoCopy);
	HookEvent("teamplay_win_panel", OnRoundEnd, EventHookMode_PostNoCopy);
	HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);
	HookEvent("object_deflected", OnObjectDeflected, EventHookMode_Post);
	HookEvent("mvm_pickup_currency", OnPickupMVMCurrency, EventHookMode_Pre);

	HookUserMessage(GetUserMessageId("PlayerShieldBlocked"), OnPlayerShieldBlocked);

	Handle config = LoadGameConfigFile("sdkhooks.games");
	if(config == INVALID_HANDLE)
	{
		SetFailState("Cannot find sdkhooks.games gamedata.");
	}

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "GetMaxHealth");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hSdkGetMaxHealth = EndPrepSDKCall();
	config.Close();

	if(g_hSdkGetMaxHealth == INVALID_HANDLE)
	{
		SetFailState("Failed to set up GetMaxHealth sdkcall. Your SDKHooks is probably outdated.");
	}

	config = LoadGameConfigFile("tf2items.randomizer");
	if(config == INVALID_HANDLE)
	{
		SetFailState("Cannot find gamedata/tf2.randomizer.txt. Get the file from [TF2Items] GiveWeapon.");
	}

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(config, SDKConf_Virtual, "CTFPlayer::EquipWearable");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSdkEquipWearable = EndPrepSDKCall();
	config.Close();

	if(g_hSdkEquipWearable == INVALID_HANDLE)
	{
		SetFailState("Failed to set up EquipWearable sdkcall. Get a int gamedata/tf2items.randomizer.txt from [TF2Items] GiveWeapon.");
	}

	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsValidClient(client) && IsClientInGame(client))
		{
			UpdateVariables(client);
		}
	}

	TopMenu hTopMenu = GetAdminTopMenu();
	if(LibraryExists("adminmenu") && hTopMenu != INVALID_HANDLE)
	{
		OnAdminMenuReady(hTopMenu);
	}

	g_hHudText = CreateHudSynchronizer();
	g_hItemInfoTrie = CreateTrie();
}

public void OnConfigsExecuted()
{
	if(!g_cvarEnabled.BoolValue)
	{
		return;
	}

	if(FindConVar("aw2_version") != INVALID_HANDLE)
	{
		SetFailState("TF2x10 is incompatible with Advanced Weaponiser.");
	}

	switch(LoadFileIntoTrie("default", "tf2x10_base_items"))
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
			g_iHeadCap = g_cvarHeadCap.IntValue;
			g_bHeadScaling = g_cvarHeadScaling.BoolValue;
			g_fHeadScalingCap = g_cvarHeadScalingCap.FloatValue;
			tf_feign_death_duration = FindConVar("tf_feign_death_duration").IntValue;

			CreateTimer(330.0, Timer_ServerRunningX10, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	if(LibraryExists("updater"))
	{
		g_cvarAutoUpdate.BoolValue ? Updater_AddPlugin(UPDATE_URL) : Updater_RemovePlugin();
	}
}

public void OnConVarChanged(Handle convar, const char[] oldValue, const char[] newValue)
{
	if(convar == g_cvarEnabled)
	{
		if(g_cvarEnabled.BoolValue)
		{
			for(int client = 1; client <= MaxClients; client++)
			{
				if(IsValidClient(client))
				{
					ResetVariables(client);
					SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
					SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
				}
			}

			if(FindConVar("sm_hidden_enabled"))
			{
				g_bHiddenRunning = FindConVar("sm_hidden_enabled").BoolValue;
			}
			else
			{
				g_bHiddenRunning = false;
			}

			#if defined _FF2_included
			g_bFF2Running = LibraryExists("freak_fortress_2") ? FF2_IsFF2Enabled() : false;
			#else
			g_bFF2Running = false;
			#endif

			#if defined _saxtonhale_included
			g_bVSHRunning = LibraryExists("saxtonhale") ? VSH_IsSaxtonHaleModeEnabled() : false;
			#else
			g_bVSHRunning = false;
			#endif

			g_hItemInfoTrie.Clear();
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
			for(int client = 1; client <= MaxClients; client++)
			{
				if(IsValidClient(client))
				{
					ResetVariables(client);
					SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
					SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
					SDKUnhook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
				}
			}
			g_hItemInfoTrie.Clear();
		}
		SetGameDescription();
	}
	else if(convar == g_cvarHeadCap)
	{
		g_iHeadCap = g_cvarHeadCap.IntValue;
	}
	else if(convar == g_cvarHeadScaling)
	{
		g_bHeadScaling = g_cvarHeadScaling.BoolValue;
	}
	else if(convar == g_cvarHeadScalingCap)
	{
		g_fHeadScalingCap = g_cvarHeadScalingCap.FloatValue;
	}
	else if(convar == FindConVar("tf_feign_death_duration"))
	{
		tf_feign_death_duration = FindConVar("tf_feign_death_duration").IntValue;
	}
	else if(convar == g_cvarAutoUpdate)
	{
		g_cvarAutoUpdate.BoolValue ? Updater_AddPlugin(UPDATE_URL) : Updater_RemovePlugin();
	}
}

void SetGameDescription()
{
	char description[16];
	GetGameDescription(description, sizeof(description));

	if(g_cvarEnabled.BoolValue && g_cvarGameDesc.BoolValue && StrEqual(description, "Team Fortress"))
	{
		Format(description, sizeof(description), "TF2x10 v%s", PLUGIN_VERSION);
		Steam_SetGameDescription(description);
	}
	else if(!g_cvarEnabled.BoolValue || !g_cvarGameDesc.BoolValue && StrContains(description, "TF2x10 ") != -1)
	{
		Steam_SetGameDescription("Team Fortress");
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	if(topmenu == g_hTopMenu)
	{
		return;
	}

	g_hTopMenu = TopMenu.FromHandle(topmenu);

	TopMenuObject player_commands = g_hTopMenu.FindCategory(ADMINMENU_SERVERCOMMANDS);

	if(player_commands != INVALID_TOPMENUOBJECT)
	{
		g_hTopMenu.AddItem("TF2x10: Recache Weapons", AdminMenu_Recache, player_commands, "sm_tf2x10_recache", ADMFLAG_GENERIC);
	}
}

int LoadFileIntoTrie(const char[] rawname, const char[] basename = "")
{
	char strBuffer[64];
	char strBuffer2[64];
	char strBuffer3[64];
	BuildPath(Path_SM, strBuffer, sizeof(strBuffer), "configs/x10.%s.txt", rawname);
	char tmpID[32];
	char finalbasename[32];
	int i;

	strcopy(finalbasename, sizeof(finalbasename), StrEqual(basename, "") ? rawname : basename);

	KeyValues hKeyValues = CreateKeyValues(finalbasename);
	if(hKeyValues.ImportFromFile(strBuffer))
	{
		hKeyValues.GetSectionName(strBuffer, sizeof(strBuffer));
		if(StrEqual(strBuffer, finalbasename))
		{
			if(hKeyValues.GotoFirstSubKey())
			{
				do
				{
					i = 0;

					hKeyValues.GetSectionName(strBuffer, sizeof(strBuffer));
					hKeyValues.GotoFirstSubKey(false);

					do
					{
						hKeyValues.GetSectionName(strBuffer2, sizeof(strBuffer2));
						Format(tmpID, sizeof(tmpID), "%s__%s_%i_name", rawname, strBuffer, i);
						g_hItemInfoTrie.SetString(tmpID, strBuffer2);

						hKeyValues.GetString(NULL_STRING, strBuffer3, sizeof(strBuffer3));
						Format(tmpID, sizeof(tmpID), "%s__%s_%i_val", rawname, strBuffer, i);
						g_hItemInfoTrie.SetString(tmpID, strBuffer3);

						i++;
					}
					while(hKeyValues.GotoNextKey(false));
					hKeyValues.GoBack();

					Format(tmpID, sizeof(tmpID), "%s__%s_size", rawname, strBuffer);
					g_hItemInfoTrie.SetValue(tmpID, i);
				}
				while(hKeyValues.GotoNextKey());
				hKeyValues.GoBack();

				g_hItemInfoTrie.SetValue(strBuffer, 1);
			}
		}
		else
		{
			hKeyValues.Close();
			return -2;
		}
	}
	else
	{
		hKeyValues.Close();
		return -1;
	}
	hKeyValues.Close();
	return 1;
}

public Action Timer_ServerRunningX10(Handle hTimer)
{
	if(!g_cvarEnabled.BoolValue)
	{
		return Plugin_Stop;
	}

	PrintToChatAll("\x01[\x07FF0000TF2\x070000FFx10\x01] Mod by \x07FF5C33UltiMario\x01 and \x073399FFMr. Blue\x01. Plugin development by \x079EC34FWliu\x01 (based off of \x0794DBFFI\x01s\x0794DBFFa\x01t\x0794DBFFi\x01s's and \x075C5C8AInvisGhost\x01's code).");
	PrintToChatAll("\x01Join our Steam group for Hale x10, Randomizer x10 and more by typing \x05/x10group\x01!");
	return Plugin_Continue;
}

/******************************************************************

SourceMod Admin Commands

******************************************************************/

public void AdminMenu_Recache(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(g_cvarEnabled.BoolValue)
	{
		switch(action)
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
}

public Action Command_Enable(int client, int args)
{
	if(!g_cvarEnabled.BoolValue)
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

public Action Command_Disable(int client, int args)
{
	if(g_cvarEnabled.BoolValue)
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

public Action Command_GetMod(int client, int args)
{
	if(g_cvarEnabled.BoolValue)
	{
		ReplyToCommand(client, "[TF2x10] This mod is loading primarily from configs/x10.%s.txt.", g_sSelectedMod);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action Command_Group(int client, int args)
{
	KeyValues kv = CreateKeyValues("data");
	kv.SetString("title", "TF2x10 Steam Group");
	kv.SetString("msg", "http://www.steamcommunity.com/groups/tf2x10");
	kv.SetNum("customsvr", 1);
	kv.SetNum("type", MOTDPANEL_TYPE_URL);
	ShowVGUIPanel(client, "info", kv, true);
	kv.Close();

	return Plugin_Handled;
}

public Action Command_Recache(int client, int args)
{
	if(g_cvarEnabled.BoolValue)
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

public Action Command_SetMod(int client, int args)
{
	if(g_cvarEnabled.BoolValue)
	{
		if(args != 1)
		{
			ReplyToCommand(client, "[TF2x10] Please specify a mod name to load. Usage: sm_tf2x10_setmod <name>");
			return Plugin_Handled;
		}

		int uselessVar;
		GetCmdArg(1, g_sSelectedMod, sizeof(g_sSelectedMod));

		if(!StrEqual(g_sSelectedMod, "default") && !g_hItemInfoTrie.GetValue(g_sSelectedMod, uselessVar))
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

public void OnAllPluginsLoaded()
{
	if(FindConVar("sm_hidden_enabled"))
	{
		g_bHiddenRunning = FindConVar("sm_hidden_enabled").BoolValue;
	}
	else
	{
		g_bHiddenRunning = false;
	}

	#if defined _FF2_included
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
		selectedMod = "vshff2";
		LoadFileIntoTrie(selectedMod);
	}

	if(g_bAprilFools)
	{
		selectedMod = "aprilfools";
		LoadFileIntoTrie(selectedMod);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "updater") && g_cvarAutoUpdate.BoolValue)
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	else if(StrEqual(name, "freak_fortress_2"))
	{
		#if defined _FF2_included
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

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "freak_fortress_2"))
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

public void OnMapStart()
{
	if(g_cvarEnabled.BoolValue)
	{
		SetGameDescription();
	}
}

public void OnMapEnd()
{
	char description[16];
	GetGameDescription(description, sizeof(description));

	if(g_cvarEnabled.BoolValue && g_cvarGameDesc.BoolValue && StrContains(description, "TF2x10 ") != -1)
	{
		Steam_SetGameDescription("Team Fortress");
	}
}

/******************************************************************

Player Connect/Disconnect & Round End

******************************************************************/

public void OnClientPutInServer(int client)
{
	if(g_cvarEnabled.BoolValue)
	{
		ResetVariables(client);
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
		SDKHook(client, SDKHook_PreThink, OnPreThink);
	}
}

public void OnClientDisconnect(int client)
{
	if(g_cvarEnabled.BoolValue)
	{
		ResetVariables(client);
		SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
		SDKUnhook(client, SDKHook_PreThink, OnPreThink);
	}
}

public Action OnRoundEnd(Handle event, const char[] name, bool dontBroadcast)
{
	if(g_cvarEnabled.BoolValue)
	{
		for(int client = 1; client <= MaxClients; client++)
		{
			ResetVariables(client);
		}
	}
	return Plugin_Continue;
}

/******************************************************************

Gameplay: Event-Specific

******************************************************************/

public void TF2_OnConditionAdded(int client, TFCond condition)
{
	if(!g_cvarEnabled.BoolValue)
	{
		return;
	}

	int weapon = IsValidClient(client) ? GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") : -1;
	int index = IsValidEntity(weapon) ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") : -1;

	if(condition == TFCond_Zoomed && index == 402)  //Bazaar Bargain
	{
		g_fChargeBegin[client] = GetGameTime();
		CreateTimer(0.0, Timer_BazaarCharge, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}

	if(condition == TFCond_Taunting && (index == 159 || index == 433) && !g_bVSHRunning && !g_bFF2Running && !g_bHiddenRunning)  //Dalokohs Bar, Fishcake
	{
		CreateTimer(1.0, Timer_DalokohX10, GetClientUserId(client), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if(g_cvarEnabled.BoolValue)
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

public Action Timer_BazaarCharge(Handle hTimer, any userid)
{
	int client = GetClientOfUserId(userid);

	if(!IsValidClient(client) || !IsPlayerAlive(client) || !TF2_IsPlayerInCondition(client, TFCond_Zoomed))
	{
		return Plugin_Stop;
	}

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(!IsValidEntity(weapon))
	{
		return Plugin_Stop;
	}

	int index = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	if(index != 402)  //Bazaar Bargain
	{
		return Plugin_Stop;
	}

	int heads = GetEntProp(client, Prop_Send, "m_iDecapitations");
	if(heads > sizeof(g_fBazaarRates) - 1)
	{
		heads = sizeof(g_fBazaarRates) - 1;
	}

	float charge = 150 * (GetGameTime() - g_fChargeBegin[client]) / g_fBazaarRates[heads];
	if(charge > 150)
	{
		charge = 150.0;
	}

	SetEntPropFloat(activeWep, Prop_Send, "m_flChargedDamage", charge);
	return Plugin_Continue;
}

public Action Timer_DalokohX10(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if(!IsValidClient(client) || !IsPlayerAlive(client) || !TF2_IsPlayerInCondition(client, TFCond_Taunting))
	{
		return Plugin_Stop;
	}

	int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	if(!IsValidEntity(weapon))
	{
		return Plugin_Stop;
	}

	int index = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	if(index != 159 && index != 433)  //Dalokohs Bar, Fishcake
	{
		return Plugin_Stop;
	}

	weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);
	if(!IsValidEntity(weapon))
	{
		return Plugin_Stop;
	}

	index = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");

	int health = GetClientHealth(client);
	int newHealth, maxHealth;
	if(index == 310)  //Warrior's Spirit
	{
		maxHealth = DALOKOH_MAXHEALTH - 200;  //Warrior's Spirit subtracts 200 health
	}
	else
	{
		maxHealth = DALOKOH_MAXHEALTH;
	}

	g_iDalokohSecs[client]++;
	if(g_iDalokohSecs[client] == 1)
	{
		if(!dalokohs[client])
		{
			dalokohs[client] = maxHealth;
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
		if(newHealth > maxHealth)
		{
			newHealth = maxHealth;
		}
		TF2_SetHealth(client, newHealth);
	}

	if(health < DALOKOH_MAXHEALTH && g_iDalokohSecs[client] >= 1 && g_iDalokohSecs[client] <= 3)
	{
		newHealth = g_iDalokohSecs[client] == 3 ? health + DALOKOH_HEALTHPERSEC : health + DALOKOH_HEALTHPERSEC - 50;
		if(newHealth > maxHealth)
		{
			newHealth = maxHealth;
		}
		TF2_SetHealth(client, newHealth);
	}
	return Plugin_Continue;
}

public Action Timer_DalokohsEnd(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	if(IsValidClient(client))
	{
		dalokohs[client] = 0;
		SDKUnhook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
		dalokohsTimer[client] = INVALID_HANDLE;
	}
	return Plugin_Continue;
}

public void OnGameFrame()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(!IsValidClient(client) || !IsPlayerAlive(client))
		{
			continue;
		}

		if(g_bTakesHeads[client])
		{
			int heads = GetEntProp(client, Prop_Send, "m_iDecapitations");
			/*if(heads > 4)
			{
				float speed = GetEntPropFloat(client, Prop_Data, "m_flMaxspeed");
				float newSpeed = heads < g_iHeadCap ? speed + 20.0 : speed;
				SetEntPropFloat(client, Prop_Data, "m_flMaxspeed", newSpeed > 520.0 ? 520.0 : newSpeed);
				PrintToChatAll("[TF2x10] %N %i heads %f speed", client, heads, newSpeed > 520.0 ? 520.0 : newSpeed);
			}*/

			if(g_bHeadScaling)
			{
				float fPlayerHeadScale = 1.0 + heads / 4.0;
				if(fPlayerHeadScale <= (g_bAprilFools ? 9999.0 : g_fHeadScalingCap))  //April Fool's 2015: Heads keep getting bigger!
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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if(!g_cvarEnabled.BoolValue || !IsValidClient(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	int activeWep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int index = IsValidEntity(activeWep) ? GetEntProp(activeWep, Prop_Send, "m_iItemDefinitionIndex") : -1;

	if(buttons & IN_ATTACK && index == 1098)  //Classic
	{
		g_bChargingClassic[client] = true;
	}
	else
	{
		g_bChargingClassic[client] = false;
	}

	if(index == 307)  //Ullapool Caber
	{
		int detonated = GetEntProp(activeWep, Prop_Send, "m_iDetonated");
		if(!detonated)
		{
			SetHudTextParams(0.0, 0.0, 0.5, 255, 255, 255, 255, 0, 0.1, 0.1, 0.2);
			ShowSyncHudText(client, g_hHudText, "Cabers: %i", g_iCabers[client]);
		}

		if(g_iCabers[client] > 1 && detonated == 1)
		{
			SetEntProp(activeWep, Prop_Send, "m_iDetonated", 0);
			g_iCabers[client]--;
		}
	}

	else if(index == 19 || index == 206 || index == 1007) //Grenade Launcher, Strange Grenade Launcher, Festive Grenade Launcher
	{
		if(GetEntProp(activeWep, Prop_Send, "m_iClip1") >= 10)
		{
			buttons &= ~IN_ATTACK;
		}
	}

	if(g_iRazorbackCount[client] > 1)
	{
		SetHudTextParams(0.0, 0.0, 0.5, 255, 255, 255, 255, 0, 0.1, 0.1, 0.2);
		ShowSyncHudText(client, g_hHudText, "Razorbacks: %i", g_iRazorbackCount[client]);
	}

	if(g_bHasManmelter[client])
	{
		int revengeCrits = GetEntProp(client, Prop_Send, "m_iRevengeCrits");
		if(revengeCrits > g_iRevengeCrits[client])
		{
			int newCrits = ((revengeCrits - g_iRevengeCrits[client]) * g_cvarCritsManmelter.IntValue) + revengeCrits - 1;
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

public Action OnGetMaxHealth(int client, int &maxHealth)
{
	if(g_cvarEnabled.BoolValue)
	{
		if(dalokohs[client])
		{
			maxHealth = dalokohs[client];
			return Plugin_Changed;
		}

		int heads = GetEntProp(client, Prop_Send, "m_iDecapitations");
		if(heads > 4 && heads < g_iHeadCap)
		{
			maxHealth = GetEntProp(client, Prop_Data, "m_iMaxHealth") + heads * 15;
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public Action OnObjectDeflected(Handle event, const char[] name, bool dontBroadcast)
{
	#if defined _FF2_included
	if(g_cvarEnabled.BoolValue && g_bFF2Running && !GetEventInt(event, "weaponid"))  //We only want a weaponid of 0 (a client)
	{
		int client = GetClientOfUserId(GetEventInt(event, "ownerid"));
		int boss = FF2_GetBossIndex(client);

		int weapon = GetEntPropEnt(client), Prop_Send, "m_hActiveWeapon");
		int index = IsValidEntity(weapon) ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") : -1;

		if(boss != -1 && (index == 40 || index == 1146)) //Backburner
		{
			float charge = FF2_GetBossCharge(boss, 0) + 63.0; //Work with FF2's deflect to set to 70 in total instead of 7
			if(charge > 100.0)
			{
				FF2_SetBossCharge(boss, 0, 100.0);
			}
			else
			{
				FF2_SetBossCharge(boss, 0, charge);
			}
		}
	}
	#endif
	return Plugin_Continue;
}

public Action OnObjectDestroyed(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_cvarEnabled.BoolValue)
	{
		return Plugin_Continue;
	}

	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int primary = GetPlayerWeaponSlot(attacker, TFWeaponSlot_Primary);
	int critsDiamondback = g_cvarCritsDiamondback.IntValue;

	if(IsValidClient(attacker) && IsPlayerAlive(attacker) && critsDiamondback > 0 && IsValidEntity(primary) && WeaponHasAttribute(attacker, primary, "sapper kills collect crits"))
	{
		char weapon[32];
		GetEventString(event, "weapon", weapon, sizeof(weapon));

		if(StrContains(weapon, "sapper") != -1 || StrEqual(weapon, "recorder"))
		{
			SetEntProp(attacker, Prop_Send, "m_iRevengeCrits", GetEntProp(attacker, Prop_Send, "m_iRevengeCrits") + critsDiamondback - 1);
		}
	}
	return Plugin_Continue;
}

public Action OnObjectRemoved(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_cvarEnabled.BoolValue)
	{
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	int weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if(!IsValidEntity(weapon))
	{
		return Plugin_Continue;
	}

	if(WeaponHasAttribute(client, weapon, "mod sentry killed revenge") && GetEventInt(event, "objecttype") == 2)  //Sentry gun
	{
		int crits = GetEntProp(client, Prop_Send, "m_iRevengeCrits") + g_iBuildingsDestroyed[client];
		SetEntProp(client, Prop_Send, "m_iRevengeCrits", crits);
		g_iBuildingsDestroyed[client] = 0;
	}
	return Plugin_Continue;
}

public Action OnPickupMVMCurrency(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetEventInt(event, "player");
	int dollars = GetEventInt(event, "currency");
	int newDollahs = 0;

	if(GetEntProp(client, Prop_Send, "m_nCurrency") < MAX_CURRENCY)
	{
		newDollahs = RoundToNearest(float(dollars) / 3.16);
	}

	SetEventInt(event, "currency", newDollahs);

	return Plugin_Continue;
}

public Action TF2_OnIsHolidayActive(TFHoliday holiday, bool &result)
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

public Action OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_cvarEnabled.BoolValue)
	{
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int inflictor_entindex = GetEventInt(event, "inflictor_entindex");
	int activewep = IsValidClient(attacker) ? GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon") : -1;
	int weaponid = IsValidEntity(activewep) ? GetEntProp(activewep, Prop_Send, "m_iItemDefinitionIndex") : -1;
	int customKill = GetEventInt(event, "customkill");

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
			int primWep = GetPlayerWeaponSlot(attacker, TFWeaponSlot_Primary);
			if(IsValidEntity(primWep) && WeaponHasAttribute(attacker, primWep, "sapper kills collect crits"))
			{
				int crits = GetEntProp(attacker, Prop_Send, "m_iRevengeCrits") + g_cvarCritsDiamondback.IntValue - 1;
				SetEntProp(attacker, Prop_Send, "m_iRevengeCrits", crits);
			}
		}
	}

	if(GetEventInt(event, "death_flags") & TF_DEATHFLAG_DEADRINGER)
	{
		TF2_AddCondition(client, TFCond_SpeedBuffAlly, tf_feign_death_duration * 10.0);  //Speed boost * 10
	}

	if(IsValidEntity(inflictor_entindex))
	{
		char inflictorName[32];
		GetEdictClassname(inflictor_entindex, inflictorName, sizeof(inflictorName));

		if(StrContains(inflictorName, "sentry") >= 0)
		{
			int critsFJ = g_cvarCritsFJ.IntValue;

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

	if(g_bTakesHeads[client])
	{
		SDKUnhook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
	}

	ResetVariables(client);
	return Plugin_Continue;
}

int _medPackTraceFilteredEnt = 0;

void TF2_SpawnMedipack(int client, bool cmd = false)
{
	float fPlayerPosition[3];
	GetClientAbsOrigin(client, fPlayerPosition);

	if(fPlayerPosition[0] != 0.0 && fPlayerPosition[1] != 0.0 && fPlayerPosition[2] != 0.0)
	{
		fPlayerPosition[2] += 4;

		if(cmd)
		{
			float PlayerPosEx[3], PlayerAngle[3], PlayerPosAway[3];
			GetClientEyeAngles(client, PlayerAngle);
			PlayerPosEx[0] = Cosine((PlayerAngle[1]/180)*FLOAT_PI);
			PlayerPosEx[1] = Sine((PlayerAngle[1]/180)*FLOAT_PI);
			PlayerPosEx[2] = 0.0;
			ScaleVector(PlayerPosEx, 75.0);
			AddVectors(fPlayerPosition, PlayerPosEx, PlayerPosAway);

			_medPackTraceFilteredEnt = client;
			Handle TraceEx = TR_TraceRayFilterEx(fPlayerPosition, PlayerPosAway, MASK_SOLID, RayType_EndPoint, MedipackTraceFilter);
			TR_GetEndPosition(fPlayerPosition, TraceEx);
			TraceEx.Close();
		}

		float Direction[3];
		Direction[0] = fPlayerPosition[0];
		Direction[1] = fPlayerPosition[1];
		Direction[2] = fPlayerPosition[2]-1024;
		Handle Trace = TR_TraceRayFilterEx(fPlayerPosition, Direction, MASK_SOLID, RayType_EndPoint, MedipackTraceFilter);

		float MediPos[3];
		TR_GetEndPosition(MediPos, Trace);
		Trace.Close();
		MediPos[2] += 4;

		int Medipack = CreateEntityByName("item_healthkit_full");
		DispatchKeyValue(Medipack, "OnPlayerTouch", "!self,Kill,,0,-1");
		if(DispatchSpawn(Medipack))
		{
			SetEntProp(Medipack, Prop_Send, "m_iTeamNum", 0, 4);
			TeleportEntity(Medipack, MediPos, NULL_VECTOR, NULL_VECTOR);
			EmitSoundToAll("items/spawn_item.wav", Medipack, _, _, _, 0.75);
		}
	}
}

public bool MedipackTraceFilter(int ent, int contentMask)
{
	return (ent != _medPackTraceFilteredEnt);
}

public void OnPreThink(int client)
{
	if(g_bChargingClassic[client])
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		int index = IsValidEntity(weapon) ? GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") : -1;

		if(IsValidEntity(weapon) && index == 1098)  //Classic
		{
			SetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage", GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage") * 10);
		}
	}
}

public Action OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(!g_cvarEnabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if(damagecustom == TF_CUSTOM_BOOTS_STOMP)
	{
		damage *= 10;
		return Plugin_Changed;
	}

	char classname[64];
	if(!IsValidEntity(weapon) || !GetEdictClassname(weapon, classname, sizeof(classname)))
	{
		return Plugin_Continue;
	}

	if(StrEqual(classname, "tf_weapon_bat_fish") && damagecustom != TF_CUSTOM_BLEEDING &&
		damagecustom != TF_CUSTOM_BURNING && damagecustom != TF_CUSTOM_BURNING_ARROW &&
		damagecustom != TF_CUSTOM_BURNING_FLARE && attacker != client && IsPlayerAlive(client))
	{
		float ang[3];
		GetClientEyeAngles(client, ang);
		ang[1] = ang[1] + 120.0;

		TeleportEntity(client, NULL_VECTOR, ang, NULL_VECTOR);
	}

	//Alien Isolation bonuses
	bool validWeapon = !StrContains(classname, "tf_weapon", false);
	if(validWeapon && GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 30474 &&
		TF2Attrib_GetByDefIndex(client, 694) &&
		TF2Attrib_GetByDefIndex(attacker, 695))
	{
		damage *= 10;
		return Plugin_Changed;
	}
	else if(validWeapon && weapon == GetPlayerWeaponSlot(attacker, TFWeaponSlot_Melee) &&
		TF2Attrib_GetByDefIndex(client, 696) &&
		TF2Attrib_GetByDefIndex(attacker, 693))
	{
		damage *= 10;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void OnTakeDamagePost(int client, int attacker, int inflictor, float damage, int damagetype)
{
	if(!g_cvarEnabled.BoolValue)
	{
		return;
	}

	if(IsValidClient(client) && IsPlayerAlive(client) && !ShouldDisableWeapons(client))
	{
		CheckHealthCaps(client);
	}

	if(IsValidClient(attacker) && attacker != client && !ShouldDisableWeapons(attacker) && IsPlayerAlive(attacker))
	{
		CheckHealthCaps(attacker);
	}
}

bool ShouldDisableWeapons(int client)
{
	//in case vsh/ff2 and other mods are running, disable x10 effects and checks
	//this list may get extended as I check out more game mods

	#if defined _FF2_included
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

	return (g_bHiddenRunning && TF2_GetClientTeam(client) == TFTeam_Blue);
}

void CheckHealthCaps(int client)
{
	if(!g_bAprilFools)  //April Fool's 2015: Unlimited health!
	{
		int cap = g_cvarHealthCap.IntValue;
		if(cap > 0 && GetClientHealth(client) > cap)
		{
			TF2_SetHealth(client, cap);
		}
	}
}

public Action OnPlayerShieldBlocked(UserMsg msg_id, Handle bf, const players[], int playersNum, bool reliable, bool init)
{
	if(!g_cvarEnabled.BoolValue || playersNum < 2)
	{
		return Plugin_Continue;
	}

	int victim = players[0];
	if(g_iRazorbackCount[victim] > 1)
	{
		g_iRazorbackCount[victim]--;

		int loopBreak = 0;
		int slotEntity = -1;

		while((slotEntity = GetPlayerWeaponSlot_Wearable(victim, TFWeaponSlot_Secondary)) != -1 && loopBreak < 20)
		{
			RemoveEdict(slotEntity);
			loopBreak++;
		}

		RemovePlayerBack(victim);

		Handle hWeapon = TF2Items_CreateItem(OVERRIDE_CLASSNAME | OVERRIDE_ITEM_DEF | OVERRIDE_ITEM_LEVEL | OVERRIDE_ITEM_QUALITY | OVERRIDE_ATTRIBUTES);
		TF2Items_SetClassname(hWeapon, "tf_wearable");
		TF2Items_SetItemIndex(hWeapon, 57);
		TF2Items_SetLevel(hWeapon, 10);
		TF2Items_SetQuality(hWeapon, 6);
		TF2Items_SetAttribute(hWeapon, 0, 52, 1.0);
		TF2Items_SetAttribute(hWeapon, 1, 292, 5.0);
		TF2Items_SetNumAttributes(hWeapon, 2);

		int entity = TF2Items_GiveNamedItem(victim, hWeapon);
		hWeapon.Close();
		SDKCall(g_hSdkEquipWearable, victim, entity);
	}

	return Plugin_Continue;
}

/******************************************************************

Gameplay: Player & Item Spawn

******************************************************************/

public int TF2Items_OnGiveNamedItem_Post(int client, char[] classname, int itemDefinitionIndex, int itemLevel, int itemQuality, int entityIndex)
{
	if(!g_cvarEnabled.BoolValue
		|| (!g_cvarIncludeBots.BoolValue && IsFakeClient(client))
		|| ShouldDisableWeapons(client)
		|| !isCompatibleItem(classname, itemDefinitionIndex)
		|| (itemQuality == 5 && itemDefinitionIndex != 266)
		|| itemQuality == 8 || itemQuality == 10)
	{
		return;
	}

	int size = 0;

	char attribName[64];
	char attribValue[8];
	char selectedMod[16];
	char tmpID[32];

	Format(tmpID, sizeof(tmpID), "%s__%i_size", g_sSelectedMod, itemDefinitionIndex);
	if(!g_hItemInfoTrie.GetValue(tmpID, size))
	{
		Format(tmpID, sizeof(tmpID), "default__%i_size", itemDefinitionIndex);
		if(!g_hItemInfoTrie.GetValue(tmpID, size))
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

	for(int i; i < size; i++)
	{
		Format(tmpID, sizeof(tmpID), "%s__%i_%i_name", selectedMod, itemDefinitionIndex, i);
		g_hItemInfoTrie.GetString(tmpID, attribName, sizeof(attribName));

		Format(tmpID, sizeof(tmpID), "%s__%i_%i_val", selectedMod, itemDefinitionIndex, i);
		g_hItemInfoTrie.GetString(tmpID, attribValue, sizeof(attribValue));

		if(StrEqual(attribValue, "remove"))
		{
			TF2Attrib_RemoveByName(entityIndex, attribName);
		}
		else
		{
			TF2Attrib_SetByName(entityIndex, attribName, StringToFloat(attribValue));
		}

		//Engineer has the Panic Attack in the primary slot
		if(itemDefinitionIndex==1153 && TF2_GetPlayerClass(client)==TFClass_Engineer && StrEqual(attribName, "maxammo secondary increased"))
		{
			TF2Attrib_RemoveByName(entityIndex, "maxammo secondary increased");
			TF2Attrib_SetByName(entityIndex, "maxammo primary increased", StringToFloat(attribValue));
		}
	}
}

bool isCompatibleItem(char[] classname, int iItemDefinitionIndex)
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

public Action OnPostInventoryApplication(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_cvarEnabled.BoolValue)
	{
		return Plugin_Continue;
	}

	int userid = GetEventInt(event, "userid");
	float delay;
	if(FindConVar("tf2items_rnd_enabled"))
	{
		delay = FindConVar("tf2items_rnd_enabled").BoolValue ? 0.3 : 0.1;
	}
	else
	{
		delay = 0.1;
	}

	UpdateVariables(GetClientOfUserId(userid));
	CreateTimer(delay, Timer_FixClips, userid, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

public Action Timer_FixClips(Handle hTimer, any userid)
{
	int client = GetClientOfUserId(userid);

	if(!g_cvarEnabled.BoolValue || !IsValidClient(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	for(int slot; slot < 2; slot++)
	{
		int wepEntity = GetPlayerWeaponSlot(client, slot);

		if(IsValidEntity(wepEntity))
		{
			CheckClips(wepEntity);

			if(FindConVar("tf2items_rnd_enabled").BoolValue)
			{
				Randomizer_CheckAmmo(client, wepEntity);
			}
		}
	}

	int maxhealth = SDKCall(g_hSdkGetMaxHealth, client);

	if(GetClientHealth(client) != maxhealth)
	{
		TF2_SetHealth(client, maxhealth);
	}

	UpdateVariables(client);
	TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.01); //recalc speed - thx sarge

	return Plugin_Continue;
}

void CheckClips(int entityIndex)
{
	Address attribAddress;

	if((attribAddress = TF2Attrib_GetByName(entityIndex, "clip size penalty")) != Address_Null ||
		(attribAddress = TF2Attrib_GetByName(entityIndex, "clip size bonus")) != Address_Null ||
		(attribAddress = TF2Attrib_GetByName(entityIndex, "clip size penalty HIDDEN")) != Address_Null)
	{
		int ammoCount = GetEntProp(entityIndex, Prop_Data, "m_iClip1");
		float clipSize = TF2Attrib_GetValue(attribAddress);
		ammoCount = (TF2Attrib_GetByName(entityIndex, "can overload") != Address_Null) ? 0 : RoundToCeil(ammoCount * clipSize);

		SetEntProp(entityIndex, Prop_Send, "m_iClip1", ammoCount);
	}
	else if((attribAddress = TF2Attrib_GetByName(entityIndex, "mod max primary clip override")) != Address_Null)
	{
		SetEntProp(entityIndex, Prop_Send, "m_iClip1", RoundToNearest(TF2Attrib_GetValue(attribAddress)));
	}
}

void Randomizer_CheckAmmo(int client, int entityIndex)
{
	//Canceling out Randomizer's own "give ammo" function to the right amount

	int ammoCount = -1;
	int iOffset = GetEntProp(entityIndex, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
	int iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
	Address attribAddress;

	if((attribAddress = TF2Attrib_GetByName(entityIndex, "maxammo primary increased")) != Address_Null ||
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

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrContains(classname, "item_ammopack")!=-1 || StrEqual(classname, "tf_ammo_pack"))
	{
		SDKHook(entity, SDKHook_Spawn, OnItemSpawned);
	}
}

public void OnItemSpawned(int entity)
{
	SDKHook(entity, SDKHook_StartTouch, OnPickup);
	SDKHook(entity, SDKHook_Touch, OnPickup);
}

public Action OnPickup(int entity, int client)
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

bool IsValidClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientConnected(client)
	&& !IsFakeClient(client) && IsClientInGame(client)
	&& !GetEntProp(client, Prop_Send, "m_bIsCoaching")
	&& !IsClientSourceTV(client) && !IsClientReplay(client);
}

void ResetVariables(int client)
{
	g_iRazorbackCount[client] = 0;
	g_iCabers[client] = 0;
	g_iDalokohSecs[client] = 0;
	dalokohs[client] = 0;
	g_iRevengeCrits[client] = 0;
	g_bHasCaber[client] = false;
	g_bHasManmelter[client] = false;
	g_bTakesHeads[client] = false;
	g_bHasBazooka[client] = false;
	g_fChargeBegin[client] = 0.0;
}

void UpdateVariables(int client)
{
	int primary = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	int secondary = GetPlayerWeaponSlot_Wearable(client, TFWeaponSlot_Secondary);
	int melee = GetPlayerWeaponSlot(client, TFWeaponSlot_Melee);

	if(!IsValidEntity(secondary))
	{
		secondary = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	}

	if(IsValidEntity(primary))
	{
		g_bHasBazooka[client] = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex") == 730;
	}
	else
	{
		g_bHasBazooka[client] = false;
	}

	if(IsValidEntity(secondary))
	{
		g_iRazorbackCount[client] = WeaponHasAttribute(client, secondary, "backstab shield") ? 10 : 0;
		g_bHasManmelter[client] = WeaponHasAttribute(client, secondary, "extinguish earns revenge crits");
	}
	else
	{
		g_iRazorbackCount[client] = 0;
		g_bHasManmelter[client] = false;
	}

	if(IsValidEntity(melee))
	{
		g_bHasCaber[client] = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex") == 307;
		g_bTakesHeads[client] = WeaponHasAttribute(client, melee, "decapitate type");
		if(g_bTakesHeads[client])
		{
			SDKHook(client, SDKHook_GetMaxHealth, OnGetMaxHealth);
		}
	}
	else
	{
		g_bHasCaber[client] = g_bHasManmelter[client] = g_bHasBazooka[client] = g_bTakesHeads[client] = false;
	}

	g_iCabers[client] = g_bHasCaber[client] ? 10 : 0;
}

stock void TF2_SetHealth(int client, int health)
{
	if(IsValidClient(client))
	{
		SetEntProp(client, Prop_Send, "m_iHealth", health);
		SetEntProp(client, Prop_Data, "m_iHealth", health);
	}
}

stock int GetPlayerWeaponSlot_Wearable(int client, int slot)
{
	int edict = MaxClients + 1;
	if(slot == TFWeaponSlot_Secondary)
	{
		while((edict = FindEntityByClassname2(edict, "tf_wearable_demoshield")) != -1)
		{
			int idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
			if((idx == 131 || idx == 406) && GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
			{
				return edict;
			}
		}
	}

	edict = MaxClients+1;
	while((edict = FindEntityByClassname2(edict, "tf_wearable")) != -1)
	{
		char netclass[32];
		if(GetEntityNetClass(edict, netclass, sizeof(netclass)) && StrEqual(netclass, "CTFWearable"))
		{
			int idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
			if(((slot == TFWeaponSlot_Primary && (idx == 405 || idx == 608))
				|| (slot == TFWeaponSlot_Secondary && (idx == 57 || idx == 133 || idx == 231 || idx == 444 || idx == 642)))
				&& GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
			{
				return edict;
			}
		}
	}
	return -1;
}

stock int FindEntityByClassname2(int startEnt, const char[] classname)
{
	while(startEnt > -1 && !IsValidEntity(startEnt))
	{
		startEnt--;
	}
	return FindEntityByClassname(startEnt, classname);
}

stock int RemovePlayerBack(int client)
{
	int edict = MaxClients + 1;
	while((edict = FindEntityByClassname2(edict, "tf_wearable")) != -1)
	{
		char netclass[32];
		if(GetEntityNetClass(edict, netclass, sizeof(netclass)) && StrEqual(netclass, "CTFWearable"))
		{
			int idx = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
			if((idx == 57 || idx == 133 || idx == 231 || idx == 444 || idx == 642)
				&& GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == client && !GetEntProp(edict, Prop_Send, "m_bDisguiseWearable"))
			{
				AcceptEntityInput(edict, "Kill");
			}
		}
	}
}

//I have this in case TF2Attrib_GetByName acts up
stock bool WeaponHasAttribute(int client, int entity, char[] name)
{
	if(TF2Attrib_GetByName(entity, name) != Address_Null)
	{
		return true;
	}

	if(StrEqual(name, "backstab shield") && (GetPlayerWeaponSlot_Wearable(client, TFWeaponSlot_Secondary) == 57))
	{
		return true;
	}

	int itemIndex = GetEntProp(entity, Prop_Send, "m_iItemDefinitionIndex");

	return (StrEqual(name, "sapper kills collect crits") && (itemIndex == 525))
		|| (StrEqual(name, "mod sentry killed revenge") &&
		(itemIndex == 141 || itemIndex == 1004))
		|| (StrEqual(name, "decapitate type") &&
		(itemIndex == 132 || itemIndex == 266 || itemIndex == 482 || itemIndex == 1082))
		|| (StrEqual(name, "ullapool caber") && (itemIndex == 307))
		|| (StrEqual(name, "extinguish earns revenge crits") && (itemIndex == 595));
}