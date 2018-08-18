#if defined _kento_ice_included
 #endinput
#endif

#define _kento_ice_included

native void kento_ice_SetClientFreeze(int client,int seconds);
native void kento_ice_RemoveClientFreeze(int client);
native bool kento_ice_IsClientFreeze(int client);

forward void kento_ice_OnClientFreeze_Post(int client);
forward void kento_ice_OnClientUnFreeze_Post(int client);

public SharedPlugin __pl_kento_ice = 
{
	name = "kento_ice",
	file = "kento_ice.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_kento_ice_SetNTVOptional()
{
	MarkNativeAsOptional("kento_ice_SetClientFreeze");
	MarkNativeAsOptional("kento_ice_RemoveClientFreeze");
	MarkNativeAsOptional("kento_ice_IsClientFreeze");
}
#endif