#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required

int IceRef[MAXPLAYERS + 1];
int SnowRef[MAXPLAYERS + 1];
char g_FreezeSound[PLATFORM_MAX_PATH];
bool bAdminFreeze[MAXPLAYERS + 1];

Handle hIcetimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
Handle hSoundtimer[MAXPLAYERS + 1] = {INVALID_HANDLE, ...};
Handle g_hOnClientFreeze;
Handle g_hOnClientUnFreeze;

bool bWarmUp;

// Cvar
ConVar Cvar_Snow;
ConVar Cvar_Freeze;
ConVar Cvar_Volume;
bool bSnow;
bool bFreeze;
float fVolume;

#define IceModel "models/weapons/eminem/ice_cube/ice_cube.mdl"

public Plugin myinfo =
{
	name = "[CS:GO] Ice Freeze",
	author = "Kento",
	version = "1.0",
	description = "Give player an ice",
	url = "http://steamcommunity.com/id/kentomatoryoshika/"
};

public void OnPluginStart() 
{
	RegAdminCmd("sm_ice", CMD_Ice, ADMFLAG_GENERIC, "Freeze player in ice");
	RegAdminCmd("sm_unice", CMD_UnIce, ADMFLAG_GENERIC, "UnFreeze player in ice");
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_freeze_end", Event_RoundFreezeEnd);
	
	LoadTranslations("common.phrases");
	LoadTranslations("funcommands.phrases");
	
	Cvar_Snow = CreateConVar("sm_ice_snow", "1", "Spawn snow effect when freeze?");
	Cvar_Snow.AddChangeHook(OnConVarChanged);
	
	Cvar_Freeze = CreateConVar("sm_ice_freezetime", "1", "Make player in ice when freezetime?");
	Cvar_Freeze.AddChangeHook(OnConVarChanged);
	
	Cvar_Volume = CreateConVar("sm_ice_volume", "0.5", "How loud should the ice sound?");
	Cvar_Volume.AddChangeHook(OnConVarChanged);
	
	AutoExecConfig(true, "kento_ice");
}

public void OnConfigsExecuted()
{
	bSnow = Cvar_Snow.BoolValue;
	bFreeze = Cvar_Freeze.BoolValue;
	fVolume = Cvar_Volume.FloatValue;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("kento_ice_SetClientFreeze", Native_SetClientFreeze);
	CreateNative("kento_ice_RemoveClientFreeze", Native_RemoveClientFreeze);
	CreateNative("kento_ice_IsClientFreeze", Native_IsClientFreeze);
	
	
	g_hOnClientFreeze = CreateGlobalForward("kento_ice_OnClientFreeze_Post", ET_Event, Param_Cell, Param_Cell);
	g_hOnClientUnFreeze = CreateGlobalForward("kento_ice_OnClientUnFreeze_Post", ET_Event, Param_Cell, Param_Cell);

	RegPluginLibrary("kento_ice");
	
	return APLRes_Success;
}

public int Native_SetClientFreeze(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClient(client))
	{
		PrintToServer("Invalid client (%d)", client);
		return;
	}
	if(!IsPlayerAlive(client))
	{
		PrintToServer("client not Alive (%d)", client);
		return;
	}
	int seconds = GetNativeCell(2);
	FreezeOrUnFreezeClient(client,true ,seconds);
	
}


public int Native_RemoveClientFreeze(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClient(client))
	{
		PrintToServer("Invalid client (%d)", client);
		return;
	}
	FreezeOrUnFreezeClient(client,false,-1);
}


void FreezeOrUnFreezeClient(int client,bool freeze ,int seconds)
{
	if(freeze)
	{
		if(seconds <= 1) seconds = 1;
		
		CreateIce(client, seconds);
		CreateSnow(client);
		bAdminFreeze[client] = true;
		
		Call_StartForward(g_hOnClientFreeze);
		Call_PushCell(client);
		Call_PushCell(seconds);
		Call_Finish();
	}
	else 
	{
		bAdminFreeze[client] = false;
		UnFreeze(client);
		SnowOff(client);
		
		Call_StartForward(g_hOnClientUnFreeze);
		Call_PushCell(client);
		Call_Finish();
	}
	
}

public int Native_IsClientFreeze(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClient(client))
	{
		PrintToServer("Invalid client (%d)", client);
		return false;
	}
	return view_as<bool>(bAdminFreeze[client]);
}


public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(convar == Cvar_Snow)	bSnow = Cvar_Snow.BoolValue;
	else if(convar == Cvar_Freeze)	bFreeze = Cvar_Freeze.BoolValue;
	else if(convar == Cvar_Volume)	fVolume = Cvar_Volume.FloatValue;
}

public void OnClientPutInServer(int client)
{
	if(IsValidClient(client))
	{
		bAdminFreeze[client] = false;
		
		if (hIcetimer[client] != INVALID_HANDLE)
		{
			KillTimer(hIcetimer[client]);
		}
		hIcetimer[client] = INVALID_HANDLE;
		
		if (hSoundtimer[client] != INVALID_HANDLE)
		{
			KillTimer(hSoundtimer[client]);
		}
		hSoundtimer[client] = INVALID_HANDLE;
	}
}

public void OnClientDisconnect(int client)
{
	if(IsValidClient(client))
	{
		bAdminFreeze[client] = false;
		
		if (hIcetimer[client] != INVALID_HANDLE)
		{
			KillTimer(hIcetimer[client]);
		}
		hIcetimer[client] = INVALID_HANDLE;
		
		if (hSoundtimer[client] != INVALID_HANDLE)
		{
			KillTimer(hSoundtimer[client]);
		}
		hSoundtimer[client] = INVALID_HANDLE;
	}
}

public Action CMD_Ice(int client, int args)
{
	if(IsValidClient(client))
	{
		// from funcommands/ice.sp
		if (args < 1)
		{
			ReplyToCommand(client, "[SM] Usage: sm_ice <#userid|name> [time]");
			return Plugin_Handled;
		}
		
		char arg[65];
		GetCmdArg(1, arg, sizeof(arg));
		
		int seconds = 0;
		
		if (args > 1)
		{
			char time[20];
			GetCmdArg(2, time, sizeof(time));
			if (StringToIntEx(time, seconds) == 0)
			{
				ReplyToCommand(client, "[SM] %t", "Invalid Amount");
				return Plugin_Handled;
			}
		}	
		
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		
		if ((target_count = ProcessTargetString(
		arg,
		client,
		target_list,
		MAXPLAYERS,
		COMMAND_FILTER_ALIVE,
		target_name,
		sizeof(target_name),
		tn_is_ml)) <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		
		for (int i = 0; i < target_count; i++)
		{
			CreateIce(target_list[i], seconds);
			CreateSnow(target_list[i])
			if(seconds > 0)	PrintHintText(target_list[i], "%t", "You will be unfrozen", seconds);
			bAdminFreeze[target_list[i]] = true;
		}
		
		if (tn_is_ml)
		{
			ShowActivity2(client, "[SM] ", "%t", "Froze target", "_s", target_name);
		}
		else
		{
			ShowActivity2(client, "[SM] ", "%t", "Froze target", "_s", target_name);
		}
	}
	
	return Plugin_Handled;
}

public Action CMD_UnIce(int client, int args)
{
	if(IsValidClient(client))
	{
		// from funcommands/ice.sp
		if (args < 1)
		{
			ReplyToCommand(client, "[SM] Usage: sm_ice <#userid|name> [time]");
			return Plugin_Handled;
		}
		
		char arg[65];
		GetCmdArg(1, arg, sizeof(arg));
		
		char target_name[MAX_TARGET_LENGTH];
		int target_list[MAXPLAYERS], target_count;
		bool tn_is_ml;
		
		if ((target_count = ProcessTargetString(
		arg,
		client,
		target_list,
		MAXPLAYERS,
		COMMAND_FILTER_ALIVE,
		target_name,
		sizeof(target_name),
		tn_is_ml)) <= 0)
		{
			ReplyToTargetError(client, target_count);
			return Plugin_Handled;
		}
		
		for (int i = 0; i < target_count; i++)
		{
			bAdminFreeze[target_list[i]] = false;
			UnFreeze(target_list[i]);
			SnowOff(target_list[i]);
		}
	}
	
	return Plugin_Handled;
}

public void OnMapStart() 
{
	// Ice cube model
	AddFileToDownloadsTable("materials/models/weapons/eminem/ice_cube/ice_cube.vtf");
	AddFileToDownloadsTable("materials/models/weapons/eminem/ice_cube/ice_cube_normal.vtf");
	AddFileToDownloadsTable("materials/models/weapons/eminem/ice_cube/ice_cube.vmt");
	AddFileToDownloadsTable("models/weapons/eminem/ice_cube/ice_cube.phy");
	AddFileToDownloadsTable("models/weapons/eminem/ice_cube/ice_cube.vvd");
	AddFileToDownloadsTable("models/weapons/eminem/ice_cube/ice_cube.dx90.vtx");
	AddFileToDownloadsTable("models/weapons/eminem/ice_cube/ice_cube.mdl");
	PrecacheModel(IceModel, true);
	
	// Snow effect
	PrecacheModel("materials/particle/snow.vmt",true);
	PrecacheModel("particle/snow.vmt",true);
	
	// Freeze sound
	Handle gameConfig = LoadGameConfigFile("funcommands.games");
	
	if (GameConfGetKeyValue(gameConfig, "SoundFreeze", g_FreezeSound, sizeof(g_FreezeSound)) && g_FreezeSound[0])
	{
		PrecacheSound(g_FreezeSound, true);
	}
	
}

public Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	// Delay
	if(!bWarmUp && bFreeze)	CreateTimer(0.1, Freeze);
}

public Action Freeze(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			CreateIce(i, 0);
			if(bSnow)	CreateSnow(i);
		}
	}
}

public Action Event_RoundFreezeEnd(Handle event, const char[] name, bool dontBroadcast)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			UnFreeze(i);	SnowOff(i);
		}
	}
}

void CreateIce(int client, int time)
{
	SetEntityMoveType(client, MOVETYPE_NONE);
	
	float pos[3];
	GetClientAbsOrigin(client, pos);
	
	int model = CreateEntityByName("prop_dynamic_override");
	
	DispatchKeyValue(model, "model", IceModel);
	DispatchKeyValue(model, "spawnflags", "256");
	DispatchKeyValue(model, "solid", "0");
	SetEntPropEnt(model, Prop_Send, "m_hOwnerEntity", client);
	
	//SetEntProp(model, Prop_Data, "m_CollisionGroup", 0);  
	
	DispatchSpawn(model);	
	TeleportEntity(model, pos, NULL_VECTOR, NULL_VECTOR); 
	
	AcceptEntityInput(model, "TurnOn", model, model, 0);
	
	SetVariantString("!activator");
	AcceptEntityInput(model, "SetParent", client, model, 0);
	
	IceRef[client] = EntIndexToEntRef(model);
	
	// has unfreeze time
	if(time > 0)
	{
		float ftime = IntToFloat(time);
		hIcetimer[client] = CreateTimer(ftime, UnIceTimer, client);
	}
	
	// create sound timer
	if (g_FreezeSound[0])
	{
		hSoundtimer[client] = CreateTimer(1.0, SoundTimer, client, TIMER_REPEAT);
	}
}

public Action UnIceTimer(Handle timer, int client)
{
	if (hIcetimer[client] != INVALID_HANDLE)
	{
		KillTimer(hIcetimer[client]);
	}
	hIcetimer[client] = INVALID_HANDLE;
	
	bAdminFreeze[client] = false;
	
	UnFreeze(client);
	PrintHintText(client, "%t", "Unfrozen");
}

public Action SoundTimer(Handle timer, int client)
{
	float vec[3];
	GetClientEyePosition(client, vec);
	EmitAmbientSound(g_FreezeSound, vec, client, SNDLEVEL_RAIDSIREN, _, fVolume);
}

// Code taken from my friend
// https://forums.alliedmods.net/showthread.php?p=2477157
void CreateSnow(int client)
{
	int ent = CreateEntityByName("env_smokestack");
	if(ent == -1) return;
	
	float eyePosition[3];
	GetClientEyePosition(client, eyePosition);
	
	eyePosition[2] +=25.0
	DispatchKeyValueVector(ent,"Origin", eyePosition);
	DispatchKeyValueFloat(ent,"BaseSpread", 50.0);
	DispatchKeyValue(ent,"SpreadSpeed", "100");
	DispatchKeyValue(ent,"Speed", "25");
	DispatchKeyValueFloat(ent,"StartSize", 1.0);
	DispatchKeyValueFloat(ent,"EndSize", 1.0);
	DispatchKeyValue(ent,"Rate", "125");
	DispatchKeyValue(ent,"JetLength", "300");
	DispatchKeyValueFloat(ent,"Twist", 200.0);
	DispatchKeyValue(ent,"RenderColor", "255 255 255");
	DispatchKeyValue(ent,"RenderAmt", "200");
	DispatchKeyValue(ent,"RenderMode", "18");
	DispatchKeyValue(ent,"SmokeMaterial", "particle/snow");
	DispatchKeyValue(ent,"Angles", "180 0 0");
	
	DispatchSpawn(ent);
	ActivateEntity(ent);
	
	eyePosition[2] += 50;
	TeleportEntity(ent, eyePosition, NULL_VECTOR, NULL_VECTOR);
	
	SetVariantString("!activator");
	AcceptEntityInput(ent, "SetParent", client);
	
	AcceptEntityInput(ent, "TurnOn");
	
	SnowRef[client] = EntIndexToEntRef(ent);
}

void UnFreeze(int client)
{
	// admin freeze
	if(bAdminFreeze[client])	return;
	
	SetEntityMoveType(client, MOVETYPE_WALK);
	
	int entity = EntRefToEntIndex(IceRef[client]);
	if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
	{
		AcceptEntityInput(entity, "Kill");
		IceRef[client] = INVALID_ENT_REFERENCE;
	}
	
	if (hSoundtimer[client] != INVALID_HANDLE)
	{
		KillTimer(hSoundtimer[client]);
	}
	hSoundtimer[client] = INVALID_HANDLE;
	
	SnowOff(client);
}

void SnowOff(int client)
{ 
	int entity = EntRefToEntIndex(SnowRef[client]);
	if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
	{
		AcceptEntityInput(entity, "TurnOff"); 
		AcceptEntityInput(entity, "Kill"); 
		SnowRef[client] = INVALID_ENT_REFERENCE;
	}
}

public void OnGameFrame()
{
	if(GameRules_GetProp("m_bWarmupPeriod") == 1)	bWarmUp = true;
	else bWarmUp = false;
}

public float IntToFloat(int integer)
{
	char s[300];
	IntToString(integer,s,sizeof(s));
	return StringToFloat(s);
}

stock bool IsValidClient(int client)
{
	if (client <= 0) return false;
	if (client > MaxClients) return false;
	if (!IsClientConnected(client)) return false;
	return IsClientInGame(client);
}
