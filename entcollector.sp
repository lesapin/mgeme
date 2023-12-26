#pragma semicolon 1

#include <dhooks>
#include <usermessages>
#include <bitbuffer>

#pragma newdecls required

#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo = 
{
    name = "Entity Collector",
    author = "bezdmn",
    description = "Clean up orphaned entities (e.g. projectiles) after their owner dies.",
    version = PLUGIN_VERSION,
    url = "http://mge.me"
};

#define GAMEDATA        "entcollector.plugin"

#define MK_PROJECTILE   "CTFWeaponBaseGun::FireProjectile"
#define SWAP_ITEM       "CTFPlayer::GiveNamedItem"

Handle g_hEntHook;

public void OnPluginStart()
{
    Handle hGameData = LoadGameConfigFile(GAMEDATA);
    
    if (!hGameData)
        SetFailState("Couldn't load \"gamedata/%s.txt\"", GAMEDATA);
    else
        PrintToServer("Loaded gamedata from %s", GAMEDATA);

    // virtual hook for CTFWeaponBaseGun::FireProjectile

    int offset = GameConfGetOffset(hGameData, MK_PROJECTILE);
    if (offset < 0)
        SetFailState("Failed to get offset");
    else
        PrintToServer("Found offset %i for %s", offset, MK_PROJECTILE);

    g_hEntHook = DHookCreate(offset, HookType_Entity, ReturnType_CBaseEntity, 
                             ThisPointer_Ignore, CountEntity); 
    if (!g_hEntHook)
        SetFailState("DHookCreate for %s failed", MK_PROJECTILE);

    DHookAddParam(g_hEntHook, HookParamType_CBaseEntity);

    PrintToServer("%s dhook success", MK_PROJECTILE);

    // detour GiveNamedItem to re-apply hooks on loadout changes/player spawns/item pickups 

    Handle hook = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_CBaseEntity,
                                    ThisPointer_CBaseEntity);
    if (!hook)
        SetFailState("Detour setup for %s failed", SWAP_ITEM);

    if (DHookSetFromConf(hook, hGameData, SDKConf_Signature, SWAP_ITEM))
    {
        DHookAddParam(hook, HookParamType_CharPtr);
        DHookAddParam(hook, HookParamType_Int);
        DHookAddParam(hook, HookParamType_ObjectPtr);

        if (!DHookEnableDetour(hook, true, Hook_Weapons))
            SetFailState("Failed to detour %s", SWAP_ITEM);
    }
    else
    {
        SetFailState("Failed to load signature for %s", SWAP_ITEM);
    }

    PrintToServer("%s detour success", SWAP_ITEM);

    delete hook;
    delete hGameData;

    DHookAddEntityListener(ListenType_Created, Print_Created_Ents);
    
    //HookUserMessage(GetUserMessageId("PlayerLoadoutUpdated"), UpdateEntHooks, true, UserMsg_Post); 
}

public MRESReturn Hook_Weapons(Address pThis, Handle hReturn, Handle hParams)
{
    // pThis == client id/entity

    char buf[512];
    DHookGetParamString(hParams, 1, buf, sizeof(buf));
    
    if (StrEqual(buf, "tf_weapon_rocketlauncher"))
    {
        PrintToChatAll("HookWeapon %s", buf);
        
        int weapon_ent = DHookGetReturn(hReturn);
        PrintToChatAll("weapon_ent: %i", weapon_ent);
    }

    return MRES_Ignored;
}

public MRESReturn CountEntity(Handle hReturn, Handle hParams)
{
    PrintToChatAll("CountEntity called");
    return MRES_Ignored;
}

/*
void UserMsg_Post(UserMsg msg, bool sent)
{
    PrintToChatAll("UserMsg_Post, sent: %b", sent);
}

public Action UpdateEntHooks(UserMsg msg_id, BfRead msg, const int[] players, 
                             int num_players, bool reliable, bool init)
{
    PrintToServer("UpdateEntHooks called for %i player", num_players);
    return Plugin_Continue;
}
*/

public void Print_Created_Ents(int entity, const char[] classname)
{
    PrintToChatAll("entity %i of class %s created", entity, classname);

    if (!strcmp(classname, "tf_weapon_rocketlauncher"))
    //if (classname[3] == 'p') // tf_projectile...
    {
        PrintToChatAll("Entity %i of class %s created, hooking..", entity, classname);
        int hookid = DHookEntity(g_hEntHook, true, entity);

        if (hookid == INVALID_HOOK_ID)
        {
            PrintToChatAll("Hooking failed");
        }
        else
        {
            PrintToChatAll("Hook ID %i success!", hookid);
        }
    }
}

/*
public void OnPluginStart()
{
    // CBaseEntity *CTFWeaponBaseGun::FireProjectile( CTFPlayer *pPlayer)
    //char[] FuncName = "FireProjectile"; doesn't get called
    // *CBaseEntity::CreateNoSpawn( const char *szName, const Vector &vecOrigin, const QAngle
    //&vecAngles, CBaseEntity *pOwner )
    char[] FuncName = "CreateNoSpawn";

    GameData hGameData = LoadGameConfigFile("entcollector");
    if (!hGameData)
        SetFailState("Couldn't load \"gamedata/entcollector.txt\", does the file exist?");

    g_hProjectileHook = DHookCreateFromConf(hGameData, FuncName);
    if (!g_hProjectileHook)
        SetFailState("DHookCreateFromConf \"%s\" setup failed, bad signature", FuncName);

    delete hGameData;

    if (!DHookEnableDetour(g_hProjectileHook, false, Detour_Projectile))
        SetFailState("Failed to detour %s", FuncName);
 
    if (!DHookEnableDetour(g_hProjectileHook, true, Detour_Projectile_Post))
        SetFailState("Failed to detour %s post", FuncName);

    PrintToServer("%s detoured successfully", FuncName);
}

public MRESReturn Detour_Projectile(int pThis, Handle hParams)
{
    PrintToChatAll("Projectile detour called");
    return MRES_Ignored;
}

public MRESReturn Detour_Projectile_Post(int pThis, Handle hParams)
{
    PrintToChatAll("Projectile detour post called");
    return MRES_Ignored; 
}
*/

/*
DHookSetup g_hCreateProjectile; // CTFBaseProjectile::Create

public void OnPluginStart() 
{
    GameData hGameData = LoadGameConfigFile("entcollector.txt");
    if (!hGameData)
        SetFailState("Couldn't load \"gamedata/entcollerctor.txt\", does the file exist?");

    g_hCreateProjectile = DHookCreateFromConf(hGameData, "CreateProjectile");
    if (!g_hCreateProjectile)
        SetFailState("DHookCreateFromConf signature for \"CreateProjectile\" not found");

    delete hGameData;

    if (!DHookEnableDetour(g_hCreateprojectile, true, Detour_CreateProjectile_Post))
        SetFailState("Failed to detour CTFBaseProjectile::Create");

    PrintToServer("CTFBaseProjectile::Create detoured successfully");
}

public MRESReturn Detour_CreateProjectile_Post(Handle hParams)
{
    PrintToChatAll("CreateProjectile post called");
    return MRES_Handled; // detour success, return to the real function
}
*/


