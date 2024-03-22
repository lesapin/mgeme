#include <signals>
#include <sourcemod>

#define PLUGIN_VERSION "1.1.0"

public Plugin myinfo = 
{
    name = "ServerMon",
    author = "bezdmn",
    description = "Monitor server usage",
    version = PLUGIN_VERSION,
    url = ""
};

#define MAX_PLAYER_SLOTS    25
#define DUMP_CYCLE          24 // dump stats every x hours

StringMap   UniquePlayers;

int         PlaytimeStore[MAX_PLAYER_SLOTS];

int         MAX_CLIENTS = 0,
            CUR_CLIENTS = 0,
            CONNECTIONS = 0,
            EMPTY_TIME  = 0,
            LAST_PLAYER = 0;

/*** ON FUNCTIONS ***/

public void OnPluginStart() 
{
    UniquePlayers = new StringMap();
    LAST_PLAYER = GetTime();

    RegServerCmd("serverstats", DumpStats_Cmd);

    CreateHandler(USR1, DumpStats_Callback);
    LogMessage("Attached callback for signal USR1");
}

public void OnClientPutInServer(int client)
{
    char steamid[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));

    // Insert a unique player or update their entry
    if (!UniquePlayers.SetValue(steamid, GetTime(), false))
    {
        UniquePlayers.GetValue(steamid, PlaytimeStore[client]);
        UniquePlayers.SetValue(steamid, GetTime(), true);
    }

    if (++CUR_CLIENTS > MAX_CLIENTS)
        MAX_CLIENTS = CUR_CLIENTS;

    if (CUR_CLIENTS == 1)
        EMPTY_TIME += (GetTime() - LAST_PLAYER);

    ++CONNECTIONS;
}

public void OnClientDisconnect(int client)
{
    char steamid[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
    
    int ConnectionTime;
    UniquePlayers.GetValue(steamid, ConnectionTime);
    UniquePlayers.SetValue(steamid, (GetTime() - ConnectionTime) + PlaytimeStore[client]);

    PlaytimeStore[client] = 0;

    if (--CUR_CLIENTS == 0)
        LAST_PLAYER = GetTime();    
}

/*** CALLBACK FUNCTIONS ***/

Action DumpStats_Cmd(int args)
{
    if (!args)
    {
        char tmp[32];
        FormatTime(tmp, sizeof(tmp), "L%G%m%d", GetTime());

        DumpStats(tmp);
    }

    return Plugin_Handled;
}

Action DumpStats_Callback()
{
    char tmp[32];
    FormatTime(tmp, sizeof(tmp), "L%G%m%d", GetTime());
    
    DumpStats(tmp);
    ResetStats();

    return Plugin_Handled;
}

/*** PRIVATE FUNCTIONS ***/

bool DumpStats(const char[] filename)
{
    char FilePath[256];
    BuildPath(Path_SM, FilePath, sizeof(FilePath), "logs/%s.stats", filename);

    File f = OpenFile(FilePath, "w");

    if (f)
    {
        char steamid[64];
        int playtime;
        int totalPlaytime = 0;
        
        StringMapSnapshot snapshot = UniquePlayers.Snapshot();

        for (int i = 0; i < snapshot.Length; i++)
        {
            snapshot.GetKey(i, steamid, sizeof(steamid));
            UniquePlayers.GetValue(steamid, playtime);
        
            if (playtime < DUMP_CYCLE * 60 * 60)
            {
                totalPlaytime += playtime;
                WriteFileLine(f, "PLAYER %s %i", steamid, playtime);
            }
        }

        for (int i = 0; i < MAX_PLAYER_SLOTS; i++)
            totalPlaytime += PlaytimeStore[i];

        WriteFileLine(f, "MANHOURS %i", totalPlaytime);

        if (CUR_CLIENTS == 0)
            WriteFileLine(f, "EMPTYTIME %i", EMPTY_TIME + (GetTime() - LAST_PLAYER));
        else
            WriteFileLine(f, "EMPTYTIME %i", EMPTY_TIME == 0 ? DUMP_CYCLE * 60 * 60 : EMPTY_TIME);

        WriteFileLine(f, "MAXCLIENTS %i", MAX_CLIENTS);
        WriteFileLine(f, "CONNECTIONS %i", CONNECTIONS);
        WriteFileLine(f, "UNIQUECLIENTS %i", snapshot.Length);

        LogMessage("Dumped server stats in %s", FilePath);

        delete snapshot;
    }
    else
    {
        LogError("Unable to open file %s", FilePath);
        return false;
    }

    delete f;
    return true;
}

void ResetStats()
{
    CONNECTIONS = CUR_CLIENTS;
    MAX_CLIENTS = CUR_CLIENTS;

    if (CUR_CLIENTS == 0)
        LAST_PLAYER = GetTime();

    StringMapSnapshot snapshot = UniquePlayers.Snapshot();
    UniquePlayers.Clear();

    char steamid[64]; 

    for (int i = 0; i < snapshot.Length; i++)
    {
        snapshot.GetKey(i, steamid, sizeof(steamid));
        UniquePlayers.SetValue(steamid, GetTime(), true);
    }

    delete snapshot;
}
