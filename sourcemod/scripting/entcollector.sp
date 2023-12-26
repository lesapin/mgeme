#pragma semicolon 1

#include <dhooks>

#pragma newdecls required

//#define DEBUG
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
#define ITEMLIST        "gamedata/entcollector.plugin.items.txt"

#define MK_PROJECTILE   "CTFWeaponBaseGun::FireProjectile"
#define SWAP_ITEM       "CTFPlayer::GiveNamedItem"

#define MAXENTS         100
#define ITEM_SLOTS      3

#if !defined DEBUG
    #define PRINT(%1)   0
#else
    #define PRINT(%1)   PrintToChatAll(%1)
#endif

Handle  g_hEntHook,
        g_hItemHooksKv;

int     g_iSlotHooked       [MAXPLAYERS][ITEM_SLOTS],
        g_iEntStore         [MAXPLAYERS][MAXENTS],
        g_iEntStorePtr      [MAXPLAYERS];

bool    g_bEntStoreLoops    [MAXPLAYERS];

public void OnPluginStart()
{
    PrintToServer("====== Entity Collector Init ======");
    PrintToServer("-----------------------------------");

    // load gamedata and itemlist
    
    Handle hGameData = LoadGameConfigFile(GAMEDATA);
    
    if (!hGameData)
        SetFailState("Couldn't load \"gamedata/%s.txt\"", GAMEDATA);
    else
        PrintToServer("Loaded \"gamedata/%s\"", GAMEDATA);

    char path[256];
    BuildPath(Path_SM, path, sizeof(path), ITEMLIST);
    PrintToServer("itemlist path is %s", path);

    g_hItemHooksKv = new KeyValues("HookableItems");

    if (!FileToKeyValues(g_hItemHooksKv, path))
        SetFailState("Couldn't load \"%s.txt", ITEMLIST);
    else
        PrintToServer("Loaded %s KeyValues", ITEMLIST);

    // virtual hook for CTFWeaponBaseGun::FireProjectile

    int offset = GameConfGetOffset(hGameData, MK_PROJECTILE);
    if (offset < 0)
        SetFailState("Failed to get offset. Game might not be supported.");
    else
        PrintToServer("Hooking %s at offset %i", MK_PROJECTILE, offset);

    g_hEntHook = DHookCreate(offset, HookType_Entity, ReturnType_CBaseEntity, 
                             ThisPointer_Ignore, Store_Ent); 
    if (!g_hEntHook)
        SetFailState("DHookCreate for %s failed", MK_PROJECTILE);

    DHookAddParam(g_hEntHook, HookParamType_CBaseEntity);

    PrintToServer("%s dhook success", MK_PROJECTILE);

    // detour GiveNamedItem to re-apply hooks on loadout changes/initial spawns/item pickups 

    Handle hook = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_CBaseEntity,
                                    ThisPointer_CBaseEntity);
    if (!hook)
        SetFailState("Detour setup for %s failed", SWAP_ITEM);

    if (DHookSetFromConf(hook, hGameData, SDKConf_Signature, SWAP_ITEM))
    {
        DHookAddParam(hook, HookParamType_CharPtr);
        DHookAddParam(hook, HookParamType_Int);
        DHookAddParam(hook, HookParamType_ObjectPtr);

        if (!DHookEnableDetour(hook, true, Hook_Weapon))
            SetFailState("Failed to detour %s", SWAP_ITEM);
    }
    else
    {
        SetFailState("Failed to load signature for %s", SWAP_ITEM);
    }

    PrintToServer("%s detour success", SWAP_ITEM);

    delete hook;
    delete hGameData;

    // entities get cleaned up when player dies

    HookEvent("player_death", Clean_Ents, EventHookMode_Post);
    PrintToServer("Hooked generic player_death event with EventHookMode_Post"); 

    PrintToServer("-----------------------------------");

#if defined DEBUG
    DHookAddEntityListener(ListenType_Created, Print_All_Ents);
    //HookUserMessage(GetUserMessageId("PlayerLoadoutUpdated"), UpdateEntHooks, true, UserMsg_Post); 
#endif
}

public MRESReturn Hook_Weapon(Address pThis, Handle hReturn, Handle hParams)
{
    //PRINT("Hook_Weapon pThis: %i", pThis);

    char weapon_name[64];
    DHookGetParamString(hParams, 1, weapon_name, sizeof(weapon_name));

    // hook weapon if it's allowed (=1) by the itemlist
    // weapons that aren't on the list don't get hooked
    if (KvGetNum(g_hItemHooksKv, weapon_name, 0))
    {
        int weapon_ent = DHookGetReturn(hReturn); //:CBaseEntity

        PRINT("Entity %i of class %s, hooking..", weapon_ent, weapon_name);

        int hookid = DHookEntity(g_hEntHook, true, weapon_ent);
        if (hookid == INVALID_HOOK_ID)
        {
            PRINT("Hooking entity %i failed", weapon_ent);
        }
        else
        {
            PRINT("Hook success! (%i)", hookid);

            // pThis == client id/entity
            g_iSlotHooked[pThis][0] = hookid;
        }
    }

    return MRES_Ignored;
}

/*
 * Store entity references of player-spawned projectiles
 * in a cyclical array for garbage collection later on
 */
public MRESReturn Store_Ent(Handle hReturn, Handle hParams)
{
    int entref = EntIndexToEntRef(DHookGetReturn(hReturn)); //:CBaseEntity
    int client = DHookGetParam(hParams, 1);

    PRINT("EntStorePtr = %i", g_iEntStorePtr[client]);

    if (g_iEntStore[client][g_iEntStorePtr[client]] != 0)
    {
        // make space for a new entity
        // erase previous entity here... 
        Erase_EntRef(g_iEntStore[client][g_iEntStorePtr[client]]);
    }
    
    g_iEntStore[client][g_iEntStorePtr[client]] = entref;
    g_iEntStorePtr[client] += 1;

    if (g_iEntStorePtr[client] >= MAXENTS) //make a loop
    {
        g_bEntStoreLoops[client] = true;
        g_iEntStorePtr[client] = 0;
        PRINT("EntStore looped");
    }

    PRINT("Stored entity reference %i for client %i", entref, client);

    return MRES_Ignored;
}

public Action Clean_Ents(Event ev, const char[] name, bool dontBroadcast)
{
    if (ev == INVALID_HANDLE)
       SetFailState("Hooking player_death event failed. Another plugin might \
                     be setting a hook in the EventHookMode_PostNoCopy mode"); 

    int client = GetClientOfUserId(GetEventInt(ev, "userid"));

    PRINT("Cleaning client %i entities", client);

    while (g_iEntStorePtr[client] > 0)
    {
        g_iEntStorePtr[client] -= 1;
        
        if (g_iEntStore[client][g_iEntStorePtr[client]] != 0)
        {
            Erase_EntRef(g_iEntStore[client][g_iEntStorePtr[client]]);
            g_iEntStore[client][g_iEntStorePtr[client]] = 0;
        }
    }

    // Data looped, start from the end again
    if (g_bEntStoreLoops[client])
    {
        // dont necessarily need to loop over the
        // entire store, but it doesn't hurt
        g_bEntStoreLoops[client] = false;
        g_iEntStorePtr[client] = MAXENTS;
        
        PRINT("Cleaning the second loop"); 
        Clean_Ents(ev, name, dontBroadcast);
    }

    return Plugin_Continue;
}

void Erase_EntRef(int entref)
{
    int entity = EntRefToEntIndex(entref);
    if (entity != INVALID_ENT_REFERENCE) // does entity still exists in game?
    {
        RemoveEntity(entity);
        PRINT("Erased previous entity at StorePtr");
    }
}

void Client_Setup()
{

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
public void Print_All_Ents(int entity, const char[] classname)
{
    PrintToChatAll("entity %i of class %s created", entity, classname);
}
