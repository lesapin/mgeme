#include <signals>
#include <sourcemod>

#define PLUGIN_VERSION "1.2.3"

public Plugin myinfo = 
{
    name = "ServerMon",
    author = "bezdmn",
    description = "Monitor server usage",
    version = PLUGIN_VERSION,
    url = ""
};

#define MAX_PLAYER_SLOTS 25
#define DUMP_CYCLE       24 // dump stats every x hours

#define TMPPLAYERS "data/uniqueplayers.tmp"
#define TMPSTATS   "data/serverstats.tmp"

StringMap   UniquePlayers;

int         PlaytimeStore[MAX_PLAYER_SLOTS];

int         MAX_CLIENTS  = 0,
            CUR_CLIENTS  = 0,
            CONNECTIONS  = 0,
            ACTIVE_TIME  = 0,
            FIRST_PLAYER = 0;

/*** ONPLUGIN FUNCTIONS ***/

public void OnPluginStart() 
{
    UniquePlayers = new StringMap();

    char FilePath[256];

    // import UniquePlayers from tmpfile
    BuildPath(Path_SM, FilePath, sizeof(FilePath), TMPPLAYERS);
    
    if (FileExists(FilePath))
    {
        File tmpfile = OpenFile(FilePath, "r");

        if (tmpfile)
        {
            char steamid[18]; //ignore newline
            int timestamp, playtime;

            tmpfile.ReadInt32(timestamp);

            if ((GetTime() - timestamp) < DUMP_CYCLE * 60 * 60)
            {
                while (!tmpfile.EndOfFile())
                {
                    tmpfile.ReadInt32(playtime);
                    tmpfile.ReadLine(steamid, sizeof(steamid));

                    if (playtime > 0)
                        UniquePlayers.SetValue(steamid, playtime, true);
                }

                LogMessage("Imported UniquePlayers from %s", FilePath);
            }
            else
                LogMessage("%s is old, not importing", FilePath);
        }
        else
            LogError("Couldn't import UniquePlayers from %s", FilePath);

        delete tmpfile;
        DeleteFile(FilePath);
    }

    // import serverstats from tmpfile
    BuildPath(Path_SM, FilePath, sizeof(FilePath), TMPSTATS);

    if (FileExists(FilePath))
    {
        File tmpfile = OpenFile(FilePath, "r");

        if (tmpfile)
        {
            int timestamp;
            tmpfile.ReadInt32(timestamp);

            if ((GetTime() - timestamp) < DUMP_CYCLE * 60 * 60)
            {
                tmpfile.ReadInt32(MAX_CLIENTS);
                tmpfile.ReadInt32(CONNECTIONS);
                tmpfile.ReadInt32(ACTIVE_TIME);
    
                LogMessage("Imported server stats from %s", FilePath);
            }
            else
                LogMessage("%s is old, not importing", FilePath);

        }
        else
            LogError("Couldn't import serverstats from %s", FilePath);

        delete tmpfile;
        DeleteFile(FilePath);
    }

    RegServerCmd("serverstats", DumpStats_Cmd);

    CreateHandler(USR1, DumpStats_Callback);
    LogMessage("Attached callback for signal USR1");

    CUR_CLIENTS = GetClientCount(true);

    if (CUR_CLIENTS)
        FIRST_PLAYER = GetTime();
}

public void OnPluginEnd()
{
    // plugin is (re/un)loaded during a dump cycle, export UniquePlayers 
    char FilePath[256];
    BuildPath(Path_SM, FilePath, sizeof(FilePath), TMPPLAYERS);

    File tmpfile = OpenFile(FilePath, "w");

    if (tmpfile)
    {
        StringMapSnapshot snapshot = UniquePlayers.Snapshot();
        char steamid[64];
        int playtime;

        tmpfile.WriteInt32(GetTime()); //timestamp

        for (int i = 0; i < snapshot.Length; i++)
        {
            snapshot.GetKey(i, steamid, sizeof(steamid));
            UniquePlayers.GetValue(steamid, playtime);
        
            tmpfile.WriteInt32(playtime);
            tmpfile.WriteLine(steamid);
        }

        delete snapshot;
    }
    else
        LogError("Couldn't export UniquePlayers to %s", FilePath);

    tmpfile.Close();

    // export serverstats to tmpfile
    BuildPath(Path_SM, FilePath, sizeof(FilePath), TMPSTATS);

    tmpfile = OpenFile(FilePath, "w");

    if (tmpfile)
    {
        tmpfile.WriteInt32(GetTime()); //timestamp

        tmpfile.WriteInt32(MAX_CLIENTS);
        tmpfile.WriteInt32(CONNECTIONS);
        tmpfile.WriteInt32(ACTIVE_TIME);
    }
    else
        LogError("Couldn't export serverstats to %s", FilePath);

    delete tmpfile;
}

/*** ONCLIENT FUNCTIONS ***/

public void OnClientPutInServer(int client)
{
    CreateTimer(5.0, Timer_PostConnect, client);
}

public void OnClientDisconnect(int client)
{
    char steamid[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
    
    int ConnectionTime;
    UniquePlayers.GetValue(steamid, ConnectionTime);
    UniquePlayers.SetValue(steamid, (GetTime() - ConnectionTime) + PlaytimeStore[client]);

    PlaytimeStore[client] = 0;

    CUR_CLIENTS--;

    if (!CUR_CLIENTS)
        ACTIVE_TIME += GetTime() - FIRST_PLAYER;
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

        //for (int i = 0; i < MAX_PLAYER_SLOTS; i++)
        //    totalPlaytime += PlaytimeStore[i];

        WriteFileLine(f, "MANHOURS %i", totalPlaytime);

        if (!CUR_CLIENTS)
            WriteFileLine(f, "ACTIVETIME %i", ACTIVE_TIME);
        else
            WriteFileLine(f, "ACTIVETIME %i", ACTIVE_TIME + (GetTime() - FIRST_PLAYER));

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

    if (CUR_CLIENTS)
        FIRST_PLAYER = GetTime();

    StringMapSnapshot snapshot = UniquePlayers.Snapshot();
    StringMap tempStrMap = UniquePlayers.Clone();
    
    UniquePlayers.Clear();

    char steamid[64]; 
    int playtime;

    for (int i = 0; i < snapshot.Length; i++)
    {
        snapshot.GetKey(i, steamid, sizeof(steamid));
        tempStrMap.GetValue(steamid, playtime);

        if (playtime > DUMP_CYCLE * 60 * 60) // player is currently connected
            UniquePlayers.SetValue(steamid, GetTime(), true);
    }

    delete tempStrMap;
    delete snapshot;
}

Action Timer_PostConnect(Handle timer, any data)
{
    int client = view_as<int>(data);

    if (IsClientAuthorized(client))
    {
        char steamid[64];
        GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));

        // Insert a unique player or update their entry
        if (!UniquePlayers.SetValue(steamid, GetTime(), false))
        {
            UniquePlayers.GetValue(steamid, PlaytimeStore[client]);
            UniquePlayers.SetValue(steamid, GetTime(), true);
        }

        CUR_CLIENTS++;

        if (CUR_CLIENTS > MAX_CLIENTS)
            MAX_CLIENTS = CUR_CLIENTS;

        if (CUR_CLIENTS == 1)
            FIRST_PLAYER = GetTime();

        ++CONNECTIONS;
    }

    return Plugin_Stop;
}
