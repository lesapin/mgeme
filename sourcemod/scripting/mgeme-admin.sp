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
    url = "http://mge.me"
};

#define SHUTDOWNDELAY 60

public void OnPluginStart()
{
    SetSignalCallbacks();
}

Action SetSignalCallbacks()
{ 
    // Handle SIGINT (Ctrl-C in terminal) gracefully.
    SetSignalCallback(SIGINT, GracefulShutdown);
    
    // ... but leave a way to shutdown the server instantly. 
    SetSignalCallback(SIGTERM, InstantShutdown);

    // Start and stop profiling.
    SetSignalCallback(SIGUSR1, StartVProf);
    SetSignalCallback(SIGUSR2, StopVProf);

    // Fix jittering issues on long-running maps by reloading the map
    // SIGWINCH is ignored by default so we can repurpose it
    SetSignalCallback(SIGWINCH, ReloadMap);

    return Plugin_Continue;
}

void SetSignalCallback(SignalCode signal, SignalCallbackType cb)
{
    int err = CreateHandler(signal, cb);
    if (err == view_as<int>(FuncCountError)) // A callback already exists probably because of a plugin reload. 
    {
        LogMessage("Resetting handler for signal %i", signal);
        // Remove the previous handler and try again
        RemoveHandler(signal);
        err = CreateHandler(signal, cb);
    }
    else if (err == view_as<int>(SAHandlerError))
    {
        // A signal handler was set, not neccessarily by this extension but by the process.
        // This error is like a confirmation that we really want to replace the handler.
        LogError("A handler set by another process was replaced");
        // We ignore the previous handler. someone else should deal with it.
        RemoveHandler(signal);
        err = CreateHandler(signal, cb);
    }

    if (err != view_as<int>(NoError))
    {
        LogError("Critical error, code %i", err);
        SetFailState("ERR: %i. Failed to attach callback for signal %i", err, signal);
    }

    LogMessage("Hooked signal %i", signal);
}

/****** CALLBACK FUNCTIONS ******/

Action GracefulShutdown()
{
    LogMessage("Server shutdown in ~%i seconds", SHUTDOWNDELAY);

    if (!GetClientCount(true)) // zero players in server
    {
        LogMessage("No clients in-game, shutting down instantly");
        ServerCommand("exit");
    }

    ForceRoundTimer(SHUTDOWNDELAY);

    CreateTimer(SHUTDOWNDELAY + 1.0, GameEnd);
    CreateTimer(SHUTDOWNDELAY + 10.0, ShutdownServer);

    PrintToChatAll("[SERVER] Shutting down in %i seconds for maintenance", SHUTDOWNDELAY);

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
    LogMessage("Reloading the map in %i seconds", SHUTDOWNDELAY);

    if (!GetClientCount(true)) // zero players in server
    {
        LogMessage("No clients in-game, reloading instantly");
    
        char CurrentMap[64];
        GetCurrentMap(CurrentMap, sizeof(CurrentMap));
        ForceChangeLevel(CurrentMap, "Map reload for maintenance");
    }

    ForceRoundTimer(SHUTDOWNDELAY);

    CreateTimer(SHUTDOWNDELAY + 1.0, GameEnd);
    CreateTimer(SHUTDOWNDELAY + 10.0, ChangeLevel);

    PrintToChatAll("[SERVER] Reloading the map in %i seconds for maintenance", SHUTDOWNDELAY);

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
        if (!IsValidEntity(NewTimer)) // try to create a new timer entity
        {
            // doesn't really matter as it's only for user-friendliness
            LogError("Couldn't create team_round_timer entity");
        }
        else
        {
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
        InstantShutdown();
    }

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

