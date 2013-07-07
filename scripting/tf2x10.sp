#pragma semicolon 1

// ======= Extensions =========

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <adminmenu>
#include <tf2>
#include <tf2_stocks>
#include <tf2items>
#include <tf2attributes>
#undef REQUIRE_PLUGIN
#tryinclude <updater>
#tryinclude <freak_fortress_2>
#tryinclude <saxtonhale>
#define REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude <steamtools>
#define REQUIRE_EXTENSIONS

// ======== About =============

#define PLUGIN_NAME	"Multiply a Weapon's Stats by 10"
#define PLUGIN_AUTHOR	"Isatis, InvisGhost"
#define PLUGIN_VERSION	"0.44"
#define PLUGIN_CONTACT	"http://www.steamcommunity.com/groups/tf2x10"
#define PLUGIN_DESCRIPTION	"Also known as: TF2x10 or TF20!"

//========= Variables =========

//Where to update from
#define UPDATE_URL	"http://tf2x10.us.to/dl/updater.txt"

//TF2x10-specific variables
new Handle:g_hTopMenu; //Admin Menu Recaching (Mr. Blue)
new Handle:g_hSdkEquipWearable; //For 10 Razorbacks stuff
new Handle:g_hItemInfoTrie; // Item Info Trie
new Handle:g_hHudText; //Caber/Razorback Remaining
new bool:g_bIsEating[MAXPLAYERS + 1] = false; //is eating dalokoh's/fishcake
new bool:g_bHasCaber[MAXPLAYERS + 1] = false; //does client have a caber?
new bool:g_bHasManmelter[MAXPLAYERS + 1] = false; //does client have manmelter?
new bool:g_bTakesHeads[MAXPLAYERS + 1] = false; //can take heads (lowers processing on OnGameFrame)
new bool:steamtools = false; //SteamTools to change description
new g_iRazorbackCount[MAXPLAYERS + 1] = 10; //Number of Razorbacks for Sniper
new g_iCabers[MAXPLAYERS + 1] = 10; //Number of Cabers for Demoman
new g_iBuildingsDestroyed[MAXPLAYERS + 1] = 0; //Crits when a building is destroyed (Frontier Justice)
new g_iRevengeCrits[MAXPLAYERS + 1] = 0; //Since Manmelter has no SourceMod event, keeps track of revenge crits pyro has
new _medPackTraceFilteredEnt = -1; //Candycane full Medipack spawning

//Mod compatibility variables
new bool:vshRunning = false; //is VS Saxton Hale running?
new bool:ff2Running = false; //is Freak Fortress 2 running?
new bool:rndmRunning = false; //is Randomizer running?
new bool:hiddenRunning = false; //is The Hidden running?

//========= Cvars/Handles ============

new bool:enabled = true;
new bool:headScales = false;
new Float:headScalesCap = 6.0;
new String:selectedMod[16] = "default";

new Handle:cvarEnabled;
new Handle:cvarGameDesc;
new Handle:cvarAutoUpdate;
new Handle:cvarHeadScales;
new Handle:cvarHeadScalesCap;
new Handle:cvarHealthCap;
new Handle:cvarBlackBoxHealthCap;
new Handle:cvarFishSlapAngle;
new Handle:cvarCandyCaneMedPackType;
new Handle:cvarMaxSpyHealth;
new Handle:cvarHeavyDalokohOverheal;
new Handle:cvarIncludeBots;
new Handle:cvarCritsPerEvent;
new Handle:fnGetMaxHealth; //thx psychonic

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_CONTACT
}

//===== Primary Functions =====

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	decl String:gameDir[8];
	GetGameFolderName(gameDir, sizeof(gameDir));
	
	if(!StrEqual(gameDir, "tf") && !StrEqual(gameDir, "tf_beta"))
	{
		Format(error, err_max, "This plugin runs on Team Fortress 2, hence why it's TF2x10!");
		return APLRes_Failure;
	}
	
	MarkNativeAsOptional("Steam_SetGameDescription");
	MarkNativeAsOptional("VSH_GetSaxtonHaleUserId");
	MarkNativeAsOptional("FF2_GetBossTeam");
	return APLRes_Success;
}

public OnPluginStart()
{
	g_hHudText = CreateHudSynchronizer();
	g_hItemInfoTrie = CreateTrie();
	
	PrepSDKCalls();
	
	RegAdminCmd("sm_tf2x10_recache", Command_Recache, ADMFLAG_GENERIC);
	RegAdminCmd("sm_tf2x10_loadmod", Command_LoadMod, ADMFLAG_GENERIC);
	
	CreateConVar("tf2x10_version", PLUGIN_VERSION, "Version of TF2x10", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	cvarEnabled = CreateConVar("tf2x10_enabled", "1", "Toggle TF2x10. 0 = disable, 1 = enable", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarGameDesc = CreateConVar("tf2x10_gamedesc", "1", "Toggle setting game description. 0 = disable, 1 = enable. Needs SteamTools.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarIncludeBots = CreateConVar("tf2x10_includebots", "0", "1 allows bots to receive TF2x10 weapons, 0 disables this.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarAutoUpdate = CreateConVar("tf2x10_autoupdate", "1", "Tells updater.smx to automatically update this plugin. 0 = off, 1 = on.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarHeadScales = CreateConVar("tf2x10_headscales", "0", "Enable Resize Heads. 0 = off, 1 = on.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	cvarHeadScalesCap = CreateConVar("tf2x10_headscalescap", "6.0", "Max Head Scale. -1 to disable.", FCVAR_PLUGIN, true, -1.0, false, 100.0);
	cvarHealthCap = CreateConVar("tf2x10_healthcap", "2000", "The max health a player can have. -1 to disable.", FCVAR_PLUGIN, true, -1.0, false, 10000.0);
	cvarBlackBoxHealthCap = CreateConVar("tf2x10_blackboxhealthcap", "2000", "The max health a soldier can have with the black box. -1 to disable.", FCVAR_PLUGIN, true, -1.0, false, 10000.0);
	cvarFishSlapAngle = CreateConVar("tf2x10_fishslapangle", "120", "Fish slap rotation angle. Change is instant so 360 is unnoticible.", FCVAR_PLUGIN);
	cvarCandyCaneMedPackType = CreateConVar("tf2x10_candycanemedpacktype", "2.0", "The type of medpack that is dropped from killing someone while having a candy cane. -1 to disable, 0 small, 1 medium, 2 full.", FCVAR_PLUGIN, true, -1.0, true, 2.0);
	cvarMaxSpyHealth = CreateConVar("tf2x10_maxspyhealth", "185", "Max health a spy can have. -1 to disable.", FCVAR_PLUGIN, true, -1.0, false, 1000.0);
	cvarHeavyDalokohOverheal = CreateConVar("tf2x10_dalokohhealth", "500", "Health a Heavy gets after eating a Dalokoh's/Fishcake. -1 to disable.", FCVAR_PLUGIN, true, -1.0, false, 10000.0);
	cvarCritsPerEvent = CreateConVar("tf2x10_critsperevent", "10", "Number of crits after Frontier kill or Diamondback sap", FCVAR_PLUGIN, true, -1.0, false, 100.0);

	HookConVarChange(cvarEnabled, CVarChange_Enable);
	HookConVarChange(cvarHeadScales, CVarChange_HeadScales);
	HookConVarChange(cvarHeadScalesCap, CVarChange_HeadScales);
		
	AutoExecConfig(true, "plugin.tf2x10");

	HookEvent("arena_win_panel", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("object_destroyed", Event_Object_Destroyed, EventHookMode_Post);
	HookEvent("object_removed", Event_Object_Remove, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath,  EventHookMode_Post);
	HookUserMessage(GetUserMessageId("PlayerShieldBlocked"), Event_PlayerShieldBlocked); 
	HookEvent("post_inventory_application", Event_PostInventoryApplication, EventHookMode_Post);
	HookEvent("teamplay_restart_round", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("teamplay_win_panel", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
	HookEvent("object_deflected", Event_Deflected, EventHookMode_Post);
	
	steamtools = LibraryExists("SteamTools");

	for (new client=1; client < MaxClients; client++)
	{
		if (IsValidClient(client) && IsClientInGame(client))
		{
			UpdateVariables(client);
		}
	}
	
	if (LibraryExists("updater") && GetConVarBool(cvarAutoUpdate) == true)
		Updater_AddPlugin(UPDATE_URL);
	
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
		OnAdminMenuReady(topmenu);

	new loaded = LoadFileIntoTrie("default", "tf2x10_base_items");
	if (loaded == 1)
		CreateTimer(330.0, Timer_Ads, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	else if (loaded == -1)
		SetFailState("Could not find the file x10.default.txt. Aborting.");
	else if (loaded == -2)
		SetFailState("Text file found, but it is the wrong one. Aborting.");
	
}

PrepSDKCalls()
{
	new Handle:hConf = LoadGameConfigFile("sdkhooks.games");
	if (hConf == INVALID_HANDLE)
		SetFailState("Cannot find sdkhooks.games gamedata.");

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "GetMaxHealth");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	fnGetMaxHealth = EndPrepSDKCall();
	CloseHandle(hConf);

	if (fnGetMaxHealth == INVALID_HANDLE)
		SetFailState("Failed to set up GetMaxHealth sdkcall. Try updating SourceMod?");
	
	hConf = LoadGameConfigFile("tf2items.randomizer");
	if (hConf == INVALID_HANDLE)
		SetFailState("Cannot find tf2items.randomizer gamedata, get the file from [TF2Items] GiveWeapon.");
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hConf, SDKConf_Virtual, "CTFPlayer::EquipWearable");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSdkEquipWearable = EndPrepSDKCall();
	CloseHandle(hConf);
	
	if (g_hSdkEquipWearable == INVALID_HANDLE)
		SetFailState("Failed to set up EquipWearable sdkcall, get a new tf2items.randomizer.txt from [TF2Items] GiveWeapon.");
}

public Action:Timer_Ads(Handle:hTimer)
{
	if (!enabled)
		return Plugin_Continue;
	
	PrintToChatAll("\x05[TF2x10]\x01 Multiply By 10 mod by \x05UltiMario\x01 and \x05Mr. Blue\x01, coding done by \x05Isatis\x01 and \x05InvisGhost\x01. Like playing x10? Check out the group for more game mods x10:");
	PrintToChatAll("\x05http://www.steamcommunity.com/groups/tf2x10\x01");
	return Plugin_Continue;
}

public Action:Command_Recache(client, args)
{
	if (enabled && LoadFileIntoTrie("default", "tf2x10_base_items") == 1)
		ReplyToCommand(client, "[TF2x10] Weapons recached.");

	return Plugin_Handled;
}

public AdminMenu_Recache(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayOption:
			Format(buffer, maxlength, "TF2x10 Recache Weapons");

		case TopMenuAction_SelectOption:
		{
			if(enabled && LoadFileIntoTrie("default", "tf2x10_base_items") == 1)
				PrintToChat(param, "[TF2x10] Weapons recached.");
		}
	}
}

public Action:Command_LoadMod(client, args)
{
	if (!enabled)
		return Plugin_Handled;
	
	if (args != 1)
	{
		ReplyToCommand(client, "[TF2x10] Please specify a mod. Usage: sm_tf2x10_loadmod <modname>");
		return Plugin_Handled;
	}
	
	new i = 0;
	GetCmdArg(1, selectedMod, sizeof(selectedMod));
	
	if (!StrEqual(selectedMod, "default") && !GetTrieValue(g_hItemInfoTrie, selectedMod, i))
	{
		new loaded = LoadFileIntoTrie(selectedMod);
		if (loaded == -1)
		{
			ReplyToCommand(client, "[TF2x10] File not found: configs/x10.%s.txt, please try re-checking that it's there.", selectedMod);
			return Plugin_Handled;
		}
		if (loaded == -2)
		{
			ReplyToCommand(client, "[TF2x10] Error: please check that the first line of configs/x10.%s.txt is \"%s\".", selectedMod);
			return Plugin_Handled;
		}
	}
	
	ReplyToCommand(client, "[TF2x10] Now loading from the configs/x10.%s.txt file.", selectedMod);
	return Plugin_Handled;
}

// ====== SourceMod Events ========

public OnLibraryAdded(const String:name[])
{
	if (strcmp(name, "SteamTools", false) == 0)
		steamtools = true;
	else if (StrEqual(name, "updater") && GetConVarBool(cvarAutoUpdate) == true)
		Updater_AddPlugin(UPDATE_URL);
}

public OnLibraryRemoved(const String:name[])
{
	if (strcmp(name, "SteamTools", false) == 0)
		steamtools = false;
}

public OnMapStart()
{
	if (enabled)
	{
		vshRunning = CheckConVar("hale_enabled") == 1;
		ff2Running = CheckConVar("ff2_enabled") == 1;
		rndmRunning = CheckConVar("tf2items_rnd_enabled") == 1;
		hiddenRunning = CheckConVar("sm_hidden_enabled") == 1;
		
		if (vshRunning || ff2Running)
		{
			strcopy(selectedMod, sizeof(selectedMod), "vshff2");
			LoadFileIntoTrie("vshff2");
		}
		
		if (steamtools && GetConVarBool(cvarGameDesc))
		{
			decl String:locDesc[16];
			Format(locDesc, sizeof(locDesc), "TF2x10 %s", PLUGIN_VERSION);
			ReplaceString(locDesc, sizeof(locDesc), "0.", "r");
			Steam_SetGameDescription(locDesc);
		}
	}
}

public OnMapEnd()
{
	decl String:locDesc[16];
	GetGameDescription(locDesc, sizeof(locDesc));
		
	if (enabled && steamtools && StrContains(locDesc, "TF2x10") != 0)
		Steam_SetGameDescription("Team Fortress");
}

public OnClientPutInServer(client)
{
	if (enabled)
	{
		ResetVariables(client);
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
	}
}

public OnClientDisconnect(client)
{
	if (enabled)
	{
		ResetVariables(client);
		SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		SDKUnhook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
	}
}

public OnAdminMenuReady(Handle:topmenu)
{
	if (topmenu == g_hTopMenu)
		return;
	
	g_hTopMenu = topmenu;
	
	new TopMenuObject:player_commands = FindTopMenuCategory(g_hTopMenu, ADMINMENU_SERVERCOMMANDS);
	
	if (player_commands != INVALID_TOPMENUOBJECT)
		AddToTopMenu(g_hTopMenu,
			"TF2x10 Recache Weapons",
			TopMenuObject_Item,
			AdminMenu_Recache,
			player_commands,
			"sm_tf2x10_recache",
			ADMFLAG_GENERIC);
}

// ====== CVar Changing ========

public CVarChange_Enable(Handle:convar, const String:oldValue[], const String:newValue[])
{
	enabled = GetConVarBool(cvarEnabled);
	
	if (enabled)
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
		
		vshRunning = CheckConVar("hale_enabled") == 1;
		ff2Running = CheckConVar("ff2_enabled") == 1;
		rndmRunning = CheckConVar("tf2items_rnd_enabled") == 1;
		hiddenRunning = CheckConVar("sm_hidden_enabled") == 1;
		
		LoadFileIntoTrie("default", "tf2x10_base_items");
		
		if (vshRunning || ff2Running)
		{
			strcopy(selectedMod, sizeof(selectedMod), "vshff2");
			LoadFileIntoTrie("vshff2");
		}
		
		if (steamtools && GetConVarBool(cvarGameDesc))
		{
			decl String:locDesc[16];
			Format(locDesc, sizeof(locDesc), "TF2x10 %s", PLUGIN_VERSION);
			ReplaceString(locDesc, sizeof(locDesc), "0.", "r");
			Steam_SetGameDescription(locDesc);
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
		
		decl String:locDesc[16];
		GetGameDescription(locDesc, sizeof(locDesc));
		
		if(steamtools && StrContains(locDesc, "TF2x10") == 0)
			Steam_SetGameDescription("Team Fortress");
		
		ClearTrie(g_hItemInfoTrie);
	}
}

public CVarChange_HeadScales(Handle:convar, const String:oldValue[], const String:newValue[])
{
	headScales = GetConVarBool(cvarHeadScales);
	headScalesCap = GetConVarFloat(cvarHeadScalesCap);
}

// ======= Event Hooks ===========

public OnGameFrame()
{
	for(new client=1; client <= MaxClients; client++)
	{
		if (headScales && IsValidClient(client) && IsPlayerAlive(client) && g_bTakesHeads[client])
		{
			new Float:playerHeads = 1.0 + (TF2_GetCTFPlayerInfo(client, "m_iDecapitations") / 4.0);
			
			if (playerHeads <= headScalesCap)
				SetEntPropFloat(client, Prop_Send, "m_flHeadScale", playerHeads);
			else
				SetEntPropFloat(client, Prop_Send, "m_flHeadScale", headScalesCap);
		}
	}
}

public Action:Event_RoundEnd(Handle:event,const String:name[],bool:dontBroadcast)
{
	if (!enabled)
		return Plugin_Continue;
	
	for(new client=1; client < MaxClients; client++)
	{
		ResetVariables(client);
    }
	return Plugin_Continue;
}

public Action:Event_Deflected(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!enabled || !ff2Running) return Plugin_Continue;
	
	new index = FF2_GetBossIndex(GetClientOfUserId(GetEventInt(event, "ownerid")));
	
	if (index != -1 && GetEventInt(event, "weaponid") == 40)
	{
		new Float:bossCharge = FF2_GetBossCharge(index, 0) + 63.0;
		//work with FF2's deflect to set to 70 in total instead of  7
		
		if(bossCharge > 100)
			FF2_SetBossCharge(index, 0, 100.0);
		else
			FF2_SetBossCharge(index, 0, bossCharge);
	}
	
	return Plugin_Continue;
}

public Action:Event_Object_Destroyed(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!enabled) return Plugin_Continue;
	
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new primaryWep = TF2_GetWeaponSlotID(attacker, TFWeaponSlot_Primary);
	new critsPerEvent = GetConVarInt(cvarCritsPerEvent);
	
	if (IsValidClient(attacker) && IsPlayerAlive(attacker) && critsPerEvent != -1 && primaryWep == 525)
	{
		decl String:weapon[32];
		GetEventString(event, "weapon", weapon, sizeof(weapon));
		
		if(StrContains(weapon, "sapper") != -1 || StrEqual(weapon, "recorder"))
		{
			new currentCrits = GetEntProp(attacker, Prop_Send, "m_iRevengeCrits");
			SetEntProp(attacker, Prop_Send, "m_iRevengeCrits", currentCrits+critsPerEvent-1);
		}
	}
	
	return Plugin_Continue;
}

public Action:Event_Object_Remove(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new entity = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	
	if (!IsValidEntity(entity)) return Plugin_Continue;
	
	decl String:classname[32];
	GetEdictClassname(entity, classname, sizeof(classname));

	if(StrEqual(classname, "tf_weapon_sentry_revenge") && GetEventInt(event, "objecttype") == 2)
	{
		new currentCrits = GetEntProp(client, Prop_Send, "m_iRevengeCrits");
		SetEntProp(client, Prop_Send, "m_iRevengeCrits", currentCrits+g_iBuildingsDestroyed[client]);
		
		g_iBuildingsDestroyed[client] = 0;
	}
	
	return Plugin_Continue;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!enabled)
		return Plugin_Continue;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new activeWep = GetActiveWeaponID(attacker);
	new customKill = GetEventInt(event, "customkill");
	new candyCaneMedPackType = GetConVarBool(cvarCandyCaneMedPackType);

	if (candyCaneMedPackType != -1 && activeWep == 317)
	{
		TF2_SpawnMedipack(client, candyCaneMedPackType, false);
	}
	else if (activeWep == 356 && customKill == TF_CUSTOM_BACKSTAB && !ff2Running && !vshRunning && !hiddenRunning)
	{
		new health = GetEntProp(attacker, Prop_Send, "m_iHealth");
		TF2_SetHealth(attacker, health * 10);
	}
	
	new inflictor_entindex = GetEventInt(event, "inflictor_entindex");
		
	if(IsValidEntity(inflictor_entindex))
	{
		decl String:inflictorName[32];
		GetEdictClassname(inflictor_entindex, inflictorName, sizeof(inflictorName));
		
		if(StrContains(inflictorName, "sentry") >= 0)
		{
			if(GetEventInt(event, "assister") < 1)
			{
				g_iBuildingsDestroyed[attacker] = g_iBuildingsDestroyed[attacker] + GetConVarInt(cvarCritsPerEvent) - 2;
			}
			else
			{
				g_iBuildingsDestroyed[attacker] = g_iBuildingsDestroyed[attacker] + RoundToNearest(GetConVarFloat(cvarCritsPerEvent) / 2.0) - 2;
			}
		}
	}

	ResetVariables(client);
	
	return Plugin_Continue;
}

public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3], damagecustom)
{
	if (!enabled) return Plugin_Continue;
	
	if (damagecustom == TF_CUSTOM_BOOTS_STOMP) 
	{
		damage *= 10;
		return Plugin_Changed;
	}
	
	new weaponID = GetActiveWeaponID(attacker);
	
	if (damagecustom != TF_CUSTOM_BLEEDING && damagecustom != TF_CUSTOM_BURNING &&
		damagecustom != TF_CUSTOM_BURNING_ARROW && damagecustom != TF_CUSTOM_BURNING_FLARE &&
		(weaponID == 221 || weaponID == 999) && attacker != client && IsPlayerAlive(client))
	{
		decl Float:ang[3];
		GetClientEyeAngles(client, ang);
		ang[1] = ang[1] + GetConVarFloat(cvarFishSlapAngle);
		
		TeleportEntity(client, NULL_VECTOR, ang, NULL_VECTOR);
	}
	
	return Plugin_Continue;
}

public OnTakeDamagePost(client, attacker, inflictor, Float:damage, damagetype)
{
	if (!enabled || !IsValidClient(client) || !IsValidClient(attacker))
		return;

	if (IsPlayerAlive(client) && !ShouldDisableWeapons(client))
		CheckHealthCaps(client);
	
	if (attacker != client && !ShouldDisableWeapons(attacker) && IsPlayerAlive(attacker))
		CheckHealthCaps(attacker);
}

public TF2Items_OnGiveNamedItem_Post(client, String:classname[], itemDefinitionIndex, itemLevel, itemQuality, entityIndex)
{
	if (!enabled || (!GetConVarBool(cvarIncludeBots) && IsFakeClient(client))
	   || ShouldDisableWeapons(client)
	   || !isCompatibleItem(classname, itemDefinitionIndex)
	   || itemDefinitionIndex > 2000
	   || (itemQuality == 5 && itemDefinitionIndex != 266)
	   || itemQuality == 8 || itemQuality == 10)
		return;
	
	ModifyAttribs(client, classname, itemDefinitionIndex, entityIndex);
}

public Action:Event_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!enabled)
		return Plugin_Continue;

	new userid = GetEventInt(event, "userid");
	TF2_AddCondition(GetClientOfUserId(userid), TFCond_SpeedBuffAlly, 0.01);

	return Plugin_Continue;
}

public Action:Event_PostInventoryApplication(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!enabled)
		return Plugin_Continue;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	UpdateVariables(client);
	
	for(new slot=0; slot < 2; slot++)
	{
		new wepEntity = GetPlayerWeaponSlot(client, slot);
		
		if(IsValidEntity(wepEntity))
		{
			CheckClips(wepEntity);
		}
	}
	
	return Plugin_Continue;
}

public Action:Event_PlayerShieldBlocked(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init) 
{
	if (!enabled || playersNum < 2)
		return Plugin_Continue;
		
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

public Action:Command_Taunt(client, args)
{
	if (enabled && (IsValidClient(client) && IsPlayerAlive(client)) &&
	   (GetActiveWeaponID(client) == 159 ||
	    GetActiveWeaponID(client) == 433) &&
		!g_bIsEating[client])
	{
		if(GetConVarInt(cvarHeavyDalokohOverheal) >= 50)
		{
			CreateTimer(4.1, Timer_Dalokoh, any:client);
			g_bIsEating[client] = true;
		}
	}
	return Plugin_Continue;
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon) 
{
	if (!enabled || !IsValidClient(client) || !IsPlayerAlive(client))
		return Plugin_Continue;
	
	if (rndmRunning)
		Randomizer_OnPlayerRunCmd(client, buttons);
	
	if (g_bHasCaber[client])
	{
		new meleeweapon = GetPlayerWeaponSlot(client, 2);
		
		if (IsValidEntity(meleeweapon))
		{
			new detonated = GetEntProp(meleeweapon, Prop_Send, "m_iDetonated");
			
			if (detonated == 0)
			{
				SetHudTextParams(0.0, 0.0, 0.5, 255, 255, 255, 255, 0, 0.1, 0.1, 0.2);
				ShowSyncHudText(client, g_hHudText, "Cabers: %d", g_iCabers[client]);
			}
			
			if (g_iCabers[client] > 1 && detonated == 1)
			{
				SetEntProp(meleeweapon, Prop_Send, "m_iDetonated", 0);
				g_iCabers[client]--;
			}
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
			new newCrits = ((revengeCrits - g_iRevengeCrits[client]) * GetConVarInt(cvarCritsPerEvent)) + revengeCrits - 1;
			SetEntProp(client, Prop_Send, "m_iRevengeCrits", newCrits);
			g_iRevengeCrits[client] = newCrits;
		}
		else
		{
			g_iRevengeCrits[client] = revengeCrits;
		}
	}

	if ((buttons & IN_ATTACK) && (GetActiveWeaponID(client) == 159 || GetActiveWeaponID(client) == 433) &&
	    (GetEntityFlags(client) & FL_ONGROUND) && !g_bIsEating[client] && GetConVarInt(cvarHeavyDalokohOverheal) >= 50)
	{
		CreateTimer(4.1, Timer_Dalokoh, any:client);
		g_bIsEating[client] = true;
	}
	return Plugin_Continue;
}

public Action:Timer_Dalokoh(Handle:timer, any:client)
{
	if (GetClientHealth(client) <= SDKCall(fnGetMaxHealth, client) && TF2_IsPlayerInCondition(client, TFCond_Taunting)
	   && g_bIsEating[client] == true && (GetActiveWeaponID(client) == 159 || GetActiveWeaponID(client) == 433))
	{
		TF2_SetHealth(client, (GetClientHealth(client)+GetConVarInt(cvarHeavyDalokohOverheal)-50));
	}
	g_bIsEating[client] = false;
}

// ==== Required Libraries ====

stock bool:IsValidClient(client)
{
	return client > 0 && client <= MaxClients && IsClientConnected(client)
	    && !IsFakeClient(client) && IsClientInGame(client)
		&& !GetEntProp(client, Prop_Send, "m_bIsCoaching")
		&& !IsClientSourceTV(client) && !IsClientReplay(client);
}

stock LoadFileIntoTrie(const String:rawname[], const String:basename[] = "")
{
	decl String:strBuffer[64];
	decl String:strBuffer2[64];
	decl String:strBuffer3[64];
	BuildPath(Path_SM, strBuffer, sizeof(strBuffer), "configs/x10.%s.txt", rawname);
	decl String:tmpID[32];
	decl String:finalbasename[32];
	new i;
	
	if (StrEqual(basename, ""))
		strcopy(finalbasename, sizeof(finalbasename), rawname);
	else
		strcopy(finalbasename, sizeof(finalbasename), basename);
		
	new Handle:hKeyValues = CreateKeyValues(finalbasename);
	if (FileToKeyValues(hKeyValues, strBuffer) == true)
	{
		KvGetSectionName(hKeyValues, strBuffer, sizeof(strBuffer));
		if (StrEqual(strBuffer, finalbasename) == true)
		{
			if (KvGotoFirstSubKey(hKeyValues))
			{
				do {
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
						
						if (StrContains(strBuffer2, "clip size ") != -1 && !StrEqual(strBuffer3, "remove"))
						{
							Format(tmpID, sizeof(tmpID), "%s__%s_chkclip1", rawname, strBuffer);
							SetTrieString(g_hItemInfoTrie, tmpID, strBuffer3);
						}
						else if (StrContains(strBuffer2, "mod max primary clip override") != -1 && !StrEqual(strBuffer3, "-1") && !StrEqual(strBuffer3, "remove"))
						{
							Format(tmpID, sizeof(tmpID), "%s__%s_chkclip2", rawname, strBuffer);
							SetTrieString(g_hItemInfoTrie, tmpID, strBuffer3);
						}
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
			return -2;
		}
	}
	else
	{
		return -1;
	}
	CloseHandle(hKeyValues);
	
	return 1;
}

stock ResetVariables(client)
{
	g_iRazorbackCount[client] = 0;
	g_iCabers[client] = 0;
	g_iRevengeCrits[client] = 0;
	g_bHasCaber[client] = false;
	g_bHasManmelter[client] = false;
	g_bTakesHeads[client] = false;
}

stock UpdateVariables(client)
{
	new secndWep = GetPlayerWeaponSlot_Wearable(client, TFWeaponSlot_Secondary);
	new secndWepID = IsValidEntity(secndWep) ? GetEntProp(secndWep, Prop_Send, "m_iItemDefinitionIndex") : -1;
	new meleeWep = TF2_GetWeaponSlotID(client, TFWeaponSlot_Melee);
	
	g_iRazorbackCount[client] = secndWepID == 57 ? 10 : 0;
	g_bHasCaber[client] = meleeWep == 307;
	g_bHasManmelter[client] = TF2_GetWeaponSlotID(client, TFWeaponSlot_Secondary) == 595;
	g_iCabers[client] = g_bHasCaber[client] ? 10 : 0;
	g_bTakesHeads[client] = meleeWep == 132 || meleeWep == 266 || meleeWep == 482;
}

stock CheckHealthCaps(client)
{
	new currentHealth = GetClientHealth(client);
	new blackBoxHealthCap = GetConVarInt(cvarBlackBoxHealthCap);
	new maxSpyHealth = GetConVarInt(cvarMaxSpyHealth);
	new healthCap = GetConVarInt(cvarHealthCap);
	
	if (blackBoxHealthCap != -1 && TF2_GetWeaponSlotID(client, TFWeaponSlot_Primary) == 228 && currentHealth > blackBoxHealthCap)
		TF2_SetHealth(client, blackBoxHealthCap);
			
	if (maxSpyHealth != -1 && TF2_GetPlayerClass(client) == TFClass_Spy && TF2_GetWeaponSlotID(client, TFWeaponSlot_Melee) != 356 && currentHealth > maxSpyHealth)
		TF2_SetHealth(client, maxSpyHealth);
	
	if (healthCap != -1 && currentHealth > healthCap)
		TF2_SetHealth(client, healthCap);
}

stock bool:IsEntLimitReached()
{
	if (enabled)
	{
		if (GetEntityCount() >= (GetMaxEntities()-64))
		{
			PrintToChatAll("Warning: Entity limit is nearly reached! Please change the map!");
			LogError("Entity limit is nearly reached: current: %d/max: %d", GetEntityCount(), GetMaxEntities());
			return true;
		}
		else
			return false;
	}
	else
	{
		return false;
	}
}

stock TF2_GetCTFPlayerInfo(client, const String:prop[])
{
	if (!IsValidClient(client)) return 0;
	
	new iOffset = FindSendPropInfo("CTFPlayer", prop);
	return GetEntData(client, iOffset);
}

stock TF2_SetHealth(client, NewHealth)
{
	if (!IsValidClient(client)) return;
	SetEntProp(client, Prop_Send, "m_iHealth", NewHealth);
	SetEntProp(client, Prop_Data, "m_iHealth", NewHealth);
}

stock TF2_GetWeaponSlotID(client, slot)
{
	if (!IsValidClient(client)) return 0;
	new weapon = GetPlayerWeaponSlot(client, slot);
	
	if (weapon == -1)
		return -1;
	
	return GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
}

stock TF2_SpawnMedipack(client, type, bool:cmd)
{
	if (!IsValidClient(client)) return;
	new Float:PlayerPosition[3];
	GetClientAbsOrigin(client, PlayerPosition);
	decl String:name[32];
	
	switch (type)
	{
		case 0:
		{
			name = "item_healthkit_small";
		}
		case 1:
		{
			name = "item_healthkit_medium";
		}
		case 2:
		{
			name = "item_healthkit_full";
		}
		default:
		{
			return;
		}
	}
	
	if (PlayerPosition[0] != 0.0 && PlayerPosition[1] != 0.0 && PlayerPosition[2] != 0.0 && IsEntLimitReached() == false)
	{
		PlayerPosition[2] += 4;
		
		if (cmd)
		{
			new Float:PlayerPosEx[3], Float:PlayerAngle[3], Float:PlayerPosAway[3];
			GetClientEyeAngles(client, PlayerAngle);
			PlayerPosEx[0] = Cosine((PlayerAngle[1]/180)*FLOAT_PI);
			PlayerPosEx[1] = Sine((PlayerAngle[1]/180)*FLOAT_PI);
			PlayerPosEx[2] = 0.0;
			ScaleVector(PlayerPosEx, 75.0);
			AddVectors(PlayerPosition, PlayerPosEx, PlayerPosAway);

			_medPackTraceFilteredEnt = client;
			new Handle:TraceEx = TR_TraceRayFilterEx(PlayerPosition, PlayerPosAway, MASK_SOLID, RayType_EndPoint, MedipackTraceFilter);
			TR_GetEndPosition(PlayerPosition, TraceEx);
			CloseHandle(TraceEx);
		}

		new Float:Direction[3];
		Direction[0] = PlayerPosition[0];
		Direction[1] = PlayerPosition[1];
		Direction[2] = PlayerPosition[2]-1024;
		new Handle:Trace = TR_TraceRayFilterEx(PlayerPosition, Direction, MASK_SOLID, RayType_EndPoint, MedipackTraceFilter);

		new Float:MediPos[3];
		TR_GetEndPosition(MediPos, Trace);
		CloseHandle(Trace);
		MediPos[2] += 4;

		new Medipack = CreateEntityByName(name);
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

stock GetActiveWeaponID(client)
{
	if (!IsValidClient(client))
		return -1;
	
	new weaponEnt = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weaponEnt < 0)
		return -1;
	
	return GetEntProp(weaponEnt, Prop_Send, "m_iItemDefinitionIndex");
}

stock bool:isCompatibleItem(String:classname[], iItemDefinitionIndex)
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

stock ShouldDisableWeapons(client)
{
	//in case vsh/ff2 and other mods are running, disable x10 effects and checks
	//this list may get extended as I check out more game mods
	
	return (ff2Running && FF2_GetBossTeam() == GetClientTeam(client)) ||
		   (vshRunning && VSH_GetSaxtonHaleUserId() == GetClientUserId(client)) ||
		   (hiddenRunning && GetClientTeam(client) == _:TFTeam_Blue);
}

stock ModifyAttribs(client, const String:classname[], itemDefinitionIndex, entityIndex)
{
	new bool:usingdefault = false;
	new size;
	decl String:attribName[64];
	decl String:attribValue[8];
	decl String:tmpID[32];
	
	Format(tmpID, sizeof(tmpID), "%s__%d_size", selectedMod, itemDefinitionIndex);
	if (!GetTrieValue(g_hItemInfoTrie, tmpID, size))
	{
		Format(tmpID, sizeof(tmpID), "default__%d_size", itemDefinitionIndex);
		if (!GetTrieValue(g_hItemInfoTrie, tmpID, size))
			return;
		else
			usingdefault = true;
	}

	for(new i=0; i < size; i++)
	{
		if (usingdefault)
		{
			Format(tmpID, sizeof(tmpID), "%s__%d_%d_name", "default", itemDefinitionIndex, i);
			GetTrieString(g_hItemInfoTrie, tmpID, attribName, sizeof(attribName));
			Format(tmpID, sizeof(tmpID), "%s__%d_%d_val", "default", itemDefinitionIndex, i);
			GetTrieString(g_hItemInfoTrie, tmpID, attribValue, sizeof(attribValue));
		}
		else
		{
			Format(tmpID, sizeof(tmpID), "%s__%d_%d_name", selectedMod, itemDefinitionIndex, i);
			GetTrieString(g_hItemInfoTrie, tmpID, attribName, sizeof(attribName));
			Format(tmpID, sizeof(tmpID), "%s__%d_%d_val", selectedMod, itemDefinitionIndex, i);
			GetTrieString(g_hItemInfoTrie, tmpID, attribValue, sizeof(attribValue));
		}

		if(StrEqual(attribValue, "remove"))
		{
			TF2Attrib_RemoveByName(entityIndex, attribName);
		}
		else
		{
			TF2Attrib_SetByName(entityIndex, attribName, StringToFloat(attribValue));
		}
	}
}

stock CheckClips(entityIndex)
{
	//TF2Attrib apparently doesn't affect clip size penalties, so manually checking here.
	decl String:tmpID[32];
	decl String:attribValue[8];
	
	new itemDefinitionIndex = GetEntProp(entityIndex, Prop_Send, "m_iItemDefinitionIndex");
	
	Format(tmpID, sizeof(tmpID), "%s__%d_chkclip1", selectedMod, itemDefinitionIndex);
	if (GetTrieString(g_hItemInfoTrie, tmpID, attribValue, sizeof(attribValue)))
	{
		new ammoCount = GetEntProp(entityIndex, Prop_Data, "m_iClip1");
		new Float:clipSize = StringToFloat(attribValue);
		ammoCount = (itemDefinitionIndex == 19 || itemDefinitionIndex == 206 || itemDefinitionIndex == 1007) ? 0 : RoundToCeil(ammoCount * clipSize);
		SetEntData(entityIndex, FindSendPropInfo("CTFWeaponBase", "m_iClip1"), ammoCount, 4, true);
	}
	else
	{
		Format(tmpID, sizeof(tmpID), "%s__%d_chkclip2", selectedMod, itemDefinitionIndex);
		if (GetTrieString(g_hItemInfoTrie, tmpID, attribValue, sizeof(attribValue)))
		{
			SetEntData(entityIndex, FindSendPropInfo("CTFWeaponBase", "m_iClip1"), StringToInt(attribValue), 4, true);
		}
	}
}

stock GetPlayerWeaponSlot_Wearable(client, slot)
{
	new edict = MaxClients+1;
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
	/* If startEnt isn't valid shifting it back to the nearest valid one */
	while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
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

stock CheckConVar(const String:cvarname[])
{
	new Handle:p_enabled = FindConVar(cvarname);
	if(p_enabled == INVALID_HANDLE)
		return -1;

	new isenabled = GetConVarInt(p_enabled);
	CloseHandle(p_enabled);
	
	return isenabled;
}

// ==== Randomizer Support ====

stock Randomizer_OnPlayerRunCmd(client, &buttons)
{
}