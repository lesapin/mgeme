#pragma semicolon 1

#include <sdktools>
#include <dbi>
#include <signals>
#include <etf2l_query>
#include <morecolors>
#include <tempstats>

#pragma newdecls required

#define PLUGIN_VERSION "1.2.0"

public Plugin myinfo = 
{
    name = "Admin interface for MGE.ME",
    author = "bezdmn",
    description = "Server tools",
    version = PLUGIN_VERSION,
    url = "http://mge.me"
};

#define SHUTDOWNDELAY 60
#define MAXCMDLEN 256

DataPack cmds;

Handle QueryTimers[MAXPLAYERS+1];

public void OnPluginStart()
{
    cmds = CreateDataPack();
    SetSignalCallbacks();

    HookEvent("player_connect_client", Event_PlayerConnect, EventHookMode_Pre);
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

    //RegConsoleCmd("tstats_start", Command_TempStats_Start);
    //RegConsoleCmd("tstats_stop", Command_TempStats_Stop);
    //RegConsoleCmd("tstats_reset", Command_TempStats_Reset);

    RegConsoleCmd("div", Command_Div);
}

public void OnClientAuthorized(int client, const char[] auth)
{
    char steamid[64];

    if (GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid), true))
    {
        ETF2LQuery(steamid);

        DataPack pack;
        QueryTimers[client] = CreateDataTimer(2.0, QueryDb, pack);
        pack.WriteCell(client);
        pack.WriteString(steamid);
    }
}

public void OnClientPutInServer(int client)
{
    CreateTimer(10.0, WelcomeMessage, GetClientSerial(client));
}

public void OnClientDisconnect(int client)
{
    delete QueryTimers[client];

    if (GetClientTime(client) > 4.0) // player wasn't kicked instantly
    {
        char Name[64];
        GetClientName(client, Name, sizeof(Name));
        MC_PrintToChatAll("{lightgreen}%s {default} left the game", Name);
    } 
}

public Action QueryDb(Handle timer, DataPack pack)
{
    char err[255];
    char steamid[64];

    pack.Reset();
    int client = pack.ReadCell();
    pack.ReadString(steamid, sizeof(steamid));
    QueryTimers[client] = null;

    Database db = SQL_Connect(SQL_CONF, true, err, sizeof(err));

    if (db != null)
    {
        DBStatement GetPlayerInfoStmt = SQL_PrepareQuery(db, "SELECT name, team FROM players WHERE steamid=?",
                                             err, sizeof(err));

        DBStatement PlayerExistsStmt = SQL_PrepareQuery(db, "SELECT EXISTS(SELECT 1 FROM players WHERE steamid=?)",
                                             err, sizeof(err));

        if (GetPlayerInfoStmt == null || PlayerExistsStmt == null)
        {
            LogError("SQL prepared statement error");
        }
        else
        {
            SQL_BindParamString(PlayerExistsStmt, 0, steamid, false);
            bool IsRegistered = false;

            if (SQL_Execute(PlayerExistsStmt))
            {
                SQL_FetchRow(PlayerExistsStmt);
                IsRegistered = view_as<bool>(SQL_FetchInt(PlayerExistsStmt, 0));
            }

            if (!IsRegistered)
            { 
                KickClient(client, "Registered ETF2L players only");
            } 	
            else if (!ActiveETF2LParticipant(steamid))
            {
                KickClient(client, "One ETF2L match participation required");
            }
            else if (ActiveETF2LBan(steamid))
            {
                KickClient(client, "Active ETF2L ban");
            }
            else
            {
                SQL_BindParamString(GetPlayerInfoStmt, 0, steamid, false);

                if (SQL_Execute(GetPlayerInfoStmt))
                {
                    char Name[64], Team[64];

                    SQL_FetchRow(GetPlayerInfoStmt); 
                    SQL_FetchString(GetPlayerInfoStmt, 0, Name, sizeof(Name));
                    SQL_FetchString(GetPlayerInfoStmt, 1, Team, sizeof(Team));

                    if (StrEqual(Team, ""))
                    {
                        StrCat(Team, sizeof(Team), "no team");
                    }

                    SetClientName(client, Name);

                    MC_PrintToChatAll("{lightgreen}%s (%s) {default}has joined the game", Name, Team);
                }
            }
        }

        delete PlayerExistsStmt;
        delete GetPlayerInfoStmt;
    }   
    
    delete db;

    return Plugin_Continue;
}

Action SetSignalCallbacks()
{ 
    // Handle SIGINT (Ctrl-C in terminal) gracefully.
    SetSignalCallback(INT, GracefulShutdown);
    
    // ... but leave a way to shutdown the server instantly. 
    SetSignalCallback(TERM, InstantShutdown);

    // Start and stop profiling.
    SetSignalCallback(USR1, StartVProf);
    SetSignalCallback(USR2, StopVProf);

    // Fix jittering issues on long-running maps by reloading the map.
    // SIGWINCH is ignored by default so we can repurpose it. 
    SetSignalCallback(WINCH, ReloadMap);

    return Plugin_Continue;
}

void SetSignalCallback(SIG signal, SignalCallbackType cb)
{
    int err = CreateHandler(signal, cb);
    if (err == view_as<int>(FuncCountError)) // Callback already exists probably because of a plugin reload. 
    {
        LogMessage("Resetting handler for signal %i", signal);

        // Remove the previous handler and try again
        RemoveHandler(signal);
        err = CreateHandler(signal, cb);
    }
    else if (err == view_as<int>(SAHandlerError))
    {
        // Signal handler was set, not neccessarily by this extension but by the process.
        // This error is like a confirmation that we really want to replace the handler.
        LogError("A handler set by another process was replaced");

        // Ignore the previous handler. Someone else should deal with it.
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
    LogMessage("Server shutting down in ~%i seconds", SHUTDOWNDELAY);

    if (!GetClientCount(true)) // zero clients in-game
    {
        LogMessage("No clients in-game, shutting down instantly");
        ServerCommand("exit");
    }
    else
    {
        // sv_shutdown shuts down the server after sv_shutdown_timeout_minutes,
        // or after every player has left/gets kicked from the server.
        // Set it to a whole number that's greater than SHUTDOWNDELAY;
        ServerCommand("sv_shutdown");
    }

    ForceRoundTimer(SHUTDOWNDELAY);

    CreateTimer(SHUTDOWNDELAY + 1.0, GameEnd);
    CreateTimer(SHUTDOWNDELAY + 10.0, ShutdownServer);

    //PrintToChatAll("[SERVER] Shutting down in %i seconds for maintenance", SHUTDOWNDELAY);
    MC_PrintToChatAll("{gold}[SERVER] {default}Shutting down in %i seconds for maintenance", SHUTDOWNDELAY);

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
        if (IsClientConnected(client) || IsClientAuthorized(client))
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
    ServerCommand("vprof_off");
    LogMessage("Stopped VProfiler");

    char PreviousLog[64];
    char RestoreConLogCmd[MAXCMDLEN];

    Handle ConLog = FindConVar("con_logfile");
    if (ConLog == null)
    {
        LogError("Failed to dump vprof report");
    }
    else
    {
        // Dump vprof report in the server root folder
        GetConVarString(ConLog, PreviousLog, sizeof(PreviousLog));
        Format(RestoreConLogCmd, sizeof(RestoreConLogCmd), "con_logfile %s", PreviousLog);

        ServerCommand("con_logfile \"vprof.txt\"");

        cmds.WriteString("vprof_generate_report");
        cmds.WriteString("vprof_generate_report_hierarchy");
        cmds.WriteString(RestoreConLogCmd);
        cmds.Reset();

        // Have to stagger commands into the server cmd buffer to get them to dump
        // stuff into the logfile consecutively. Doesn't seem to work any other way.
        CreateTimer(0.4, ExecuteCmdDelay, cmds);
        CreateTimer(0.8, ExecuteCmdDelay, cmds);
        CreateTimer(1.2, ExecuteCmdDelay, cmds);
    }

    delete ConLog;

    return Plugin_Continue;
}

Action ReloadMap()
{
    LogMessage("Reloading the map in %i seconds", SHUTDOWNDELAY);

    if (!GetClientCount(true)) // Zero players in server
    {
        LogMessage("No clients in-game, reloading instantly");
    
        char CurrentMap[64];
        GetCurrentMap(CurrentMap, sizeof(CurrentMap));
        ForceChangeLevel(CurrentMap, "Map reload for maintenance");

        // Prevent SourceMod from creating the timers unnecessarily.
        return Plugin_Continue;
    }

    ForceRoundTimer(SHUTDOWNDELAY);

    CreateTimer(SHUTDOWNDELAY + 1.0, GameEnd);
    CreateTimer(SHUTDOWNDELAY + 10.0, ChangeLevel);

    //PrintToChatAll("[SERVER] Reloading the map in %i seconds for maintenance", SHUTDOWNDELAY);
    MC_PrintToChatAll("{gold}[SERVER] {default}Refreshing the map in %i seconds", SHUTDOWNDELAY);

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
        if (!IsValidEntity(NewTimer)) // Try to create a new timer entity
        {
            // Doesn't really matter as it's only for user-friendliness
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
    else // Just shutdown instantly
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

// Execute a server command with a delay
Action ExecuteCmdDelay(Handle timer, DataPack data)
{
    char cmd[MAXCMDLEN];
    data.ReadString(cmd, sizeof(cmd));
    ServerCommand(cmd);
    return Plugin_Continue;
}

/** EVENTS **/

public Action Event_PlayerConnect(Event ev, const char[] name, bool dontBroadcast)
{
   SetEventBroadcast(ev, true);
   ev.BroadcastDisabled = true;
   return Plugin_Continue;
}

public Action Event_PlayerDisconnect(Event ev, const char[] name, bool dontBroadcast)
{
   SetEventBroadcast(ev, true);
   ev.BroadcastDisabled = true;
   return Plugin_Continue;
}

/*** CONSOLE COMMANDS ***/

public Action Command_TempStats_Start(int client, int args)
{
    TempStats_Start(client);
    return Plugin_Handled;
}

public Action Command_TempStats_Stop(int client, int args)
{
    TempStats_Stop(client);
    return Plugin_Handled;
}

public Action Command_TempStats_Reset(int client, int args)
{
    TempStats_Reset(client);
    return Plugin_Handled;
}

public Action Command_Div(int client, int args)
{
    int rand = GetRandomInt(0,6);
    char name[32];

    if (args == 0)
        GetClientName(client, name, sizeof(name));
    else if (args == 1)
        GetCmdArgString(name, sizeof(name));  
    else
       Format(name, sizeof(name), "my mother"); 

    if (rand == 0)
        PrintToChatAll("%s is without a doubt a premiership level player!", name);
    else 
        PrintToChatAll("%s is a division %i player", name, rand);

    return Plugin_Handled;
}

/*** TIMERS ***/

public Action WelcomeMessage(Handle timer, int serial)
{
    int client = GetClientFromSerial(serial);

    if (client == 0 || !IsClientInGame(client))
    { 
       return Plugin_Stop;
    } 

    MC_PrintToChat(client, "{olive}View player info using {default}!profile [name]");
    MC_PrintToChat(client, "{olive}Toggle stat tracking with {default}!tstats");

    return Plugin_Continue;
}
