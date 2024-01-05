#pragma semicolon 1

#include <signals>
#include <sdktools>

#pragma newdecls required
#define PLUGIN_VERSION "1.0.0"


public Plugin myinfo = 
{
    name = "Admin interface for MGE.ME",
    author = "bezdmn",
    description = "Server tools",
    version = PLUGIN_VERSION,
    url = "mge.me"
};

#define SHUTDOWNDELAY 60

public void OnPluginStart()
{
    CreateTimer(5.0, SetSignalCallbacks);
    
    // Disable server CVar change announcements
    //HookEvent("server_cvar", Event_ServerCVar, EventHookMode_Pre);
}

public Action Event_ServerCVar(Handle ev, const char[] name, bool dontBroadcast)
{
    return Plugin_Handled;
}

Action SetSignalCallbacks(Handle timer)
{ 
    // Handle SIGINT (Ctrl-C in terminal) gracefully.
    if (CreateHandler(SIGINT, GracefulShutdown) != view_as<int>(NoError))
    {
        LogError("Failed to attach callback for SIGINT. \
                       a handler might already exist for this signal.");
    }
    
    // ... but leave a way to shutdown the server instantly. 
    if (CreateHandler(SIGTERM, InstantShutdown) != view_as<int>(NoError))
    {
        LogError("Failed to attach callback for SIGTERM. \
                       a handler might already exist for this signal.");
    }

    // Start and stop profiling.
    if (CreateHandler(SIGUSR1, StartVProf) != view_as<int>(NoError) ||
        CreateHandler(SIGUSR2, StopVProf) != view_as<int>(NoError))
    {
        LogError("Failed to attach callbacks for SIGUSR: \
                       a handler might already exist for this signal.");
    }

    // Fix jittering issues on long-running maps by reloading the map.
    // SIGWINCH is ignored by default so we can repurpose it. 
    if (CreateHandler(SIGWINCH, ReloadMap) != view_as<int>(NoError))
    {
        LogError("Failed to attach callback for SIGWINCH. \
                       a handler might already exist for this signal.");
    }

    return Plugin_Continue;
}

/****** CALLBACK FUNCTIONS ******/

Action GracefulShutdown()
{
    ForceRoundTimer(SHUTDOWNDELAY);

    CreateTimer(SHUTDOWNDELAY + 1.0, GameEnd);
    CreateTimer(SHUTDOWNDELAY + 10.0, ShutdownServer);

    PrintToChatAll("[SERVER] Shutting down in %i seconds for maintenance", SHUTDOWNDELAY);
    LogMessage("Server shutdown in ~%i seconds", SHUTDOWNDELAY);

    return Plugin_Continue;
}

Action InstantShutdown()
{
    // https://github.com/ValveSoftware/Source-1-Games/issues/1726
    LogMessage("Server shutting down");
    ServerCommand("sv_shutdown");
    //////////////////////////////////

    for (int client = 1; client < MaxClients; client++)
    {
        if (IsClientConnected(client))
        {
            // Send a user-friendly shutdown message
            KickClient(client, "Shutting down for maintenance");
        }
    }

    return Plugin_Continue;
}

Action StartVProf()
{
    ServerCommand("vprof_reset");

    ServerCommand("vprof_on");
    LogMessage("Started VProfiler");

    return Plugin_Continue;
}

Action StopVProf()
{
    char Previous[128];
    Handle ConLog = FindConVar("con_logfile");
    
    if (ConLog == null)
    {
        LogError("Failed to dump vprof log");
    }
    else
    {
        // Logfile gets dumped in the server root folder
        GetConVarString(ConLog, Previous, sizeof(Previous));
        SetConVarString(ConLog, "vprof.txt", false, false);

        //ServerCommand("con_logfile vprof.txt");
        ServerCommand("vprof_generate_report"); 
        ServerCommand("vprof_generate_report_hierarchy");
        ServerCommand("vprof_generate_report_map_load");

        //ServerCommand("con_logfile %s", Previous);
        SetConVarString(ConLog, Previous, false, false);
    }

    ServerCommand("vprof_off");
    LogMessage("Stopped VProfiler");

    delete ConLog;

    return Plugin_Continue;
}

Action ReloadMap()
{
    ForceRoundTimer(SHUTDOWNDELAY);

    CreateTimer(SHUTDOWNDELAY + 1.0, GameEnd);
    CreateTimer(SHUTDOWNDELAY + 10.0, ChangeLevel);

    PrintToChatAll("[SERVER] Reloading the map in %i seconds for maintenance", SHUTDOWNDELAY);
    LogMessage("Reloading map in %i seconds", SHUTDOWNDELAY);

    return Plugin_Continue;
}

/****** HELPER FUNCTIONS ******/

void ForceRoundTimer(int seconds)
{
    if (true)
    {
        int TimerEnt = -1,
            TimerEntKothRed = -1,
            TimerEntKothBlu = -1;

        TimerEnt = FindEntityByClassname(TimerEnt, "team_round_timer");
        TimerEntKothRed = FindEntityByClassname(TimerEntKothRed, "zz_red_koth_timer");
        TimerEntKothBlu = FindEntityByClassname(TimerEntKothBlu, "zz_blue_koth_timer");

        if (TimerEnt >= 1) // Delete all previous round timers
        {
            RemoveEntity(TimerEnt);    
        }
        else if (TimerEntKothBlu >= 1 || TimerEntKothRed >= 1)
        {
            RemoveEntity(TimerEntKothBlu);
            RemoveEntity(TimerEntKothRed);
        }
    
        int NewTimer = CreateEntityByName("team_round_timer");
        if (!IsValidEntity(NewTimer))
            SetFailState("Couldn't create round timer entity");
        
        HookSingleEntityOutput(NewTimer, "OnFinished", EndGame, true);

        DispatchSpawn(NewTimer);

        SetVariantInt(seconds);
        AcceptEntityInput(NewTimer, "SetTime");
        SetVariantInt(seconds);
        AcceptEntityInput(NewTimer, "SetMaxTime");
        SetVariantInt(0);
        AcceptEntityInput(NewTimer, "SetSetupTime");
        SetVariantInt(1);
        AcceptEntityInput(NewTimer, "ShowInHud");
        SetVariantInt(1);
        AcceptEntityInput(NewTimer, "AutoCountdown");
        AcceptEntityInput(NewTimer, "Enable");
    }
}

Action GameEnd(Handle timer)
{
    int EndGameEnt = -1;
    EndGameEnt = FindEntityByClassname(EndGameEnt, "game_end");

    if (EndGameEnt < 1)
        EndGameEnt = CreateEntityByName("game_end");

    if (IsValidEntity(EndGameEnt))
    {
        AcceptEntityInput(EndGameEnt, "EndGame");
    }
    else // just shutdown instantly
    {
        LogError("Couldn't create game_end entity. Shutting down");
    }

    return Plugin_Continue;
}

// TODO
Action EndGame(const char[] output, int caller, int activator, float delay)
{
    LogMessage("EndGame entity output");
    return Plugin_Continue;
}

Action ShutdownServer(Handle timer)
{
    return InstantShutdown(); // compiler warnings
}

Action ChangeLevel(Handle timer)
{
    char CurrentMap[64];
    GetCurrentMap(CurrentMap, sizeof(CurrentMap));
    ForceChangeLevel(CurrentMap, "Map reload for maintenance");
    return Plugin_Continue;
}

