#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>

ConVar g_cvExtendTime; // Extend time cvar
ConVar g_cvMaxExtends; // Maximum amount of extends
ConVar g_cvMinPercentage; // Minimum percentage for a vote extend to pass
ConVar g_cvIncreasePercentage; // Subsequent votes should have their requirements increase by how many percent
ConVar g_cvMaxPercentage; // Maximum percentage for vote extends

Handle mp_timelimit = INVALID_HANDLE;
int g_iTimeLimit;

int g_iExtends = 0; // How many extends have happened in current map

public Plugin myinfo = 
{
	name = "Vote Extend",
	author = "koen",
	description = "Vote extend plugin for tiered admin system",
	version = "1.2",
	url = "https://github.com/notkoen"
};

public void OnPluginStart()
{
	// Timelimit handle
	mp_timelimit = FindConVar("mp_timelimit");
	g_iTimeLimit = GetConVarInt(mp_timelimit);
	HookConVarChange(mp_timelimit, OnConvarChange);
	
	// Plugin cvars
	g_cvMaxExtends = CreateConVar("sm_max_vote_extends", "2", "Maximum amount of vote extends available on each map", _, true, 0.0);
	g_cvExtendTime = CreateConVar("sm_vote_extend_time", "10.0", "Time in minutes that is added to the remaining map time if a vote extend is successful", _, true, 0.0);
	g_cvMinPercentage = CreateConVar("sm_vote_extend_min_percentage", "0.65", "In float value, base percentage value needed for first vote extend to be considered a pass", _, true, 0.5, true, 1.0);
	g_cvIncreasePercentage = CreateConVar("sm_vote_extend_increase", "0.10", "In float value, subsequent vote extends should have their minimum percentage increased by this value", _, true, 0.0, true, 1.00);
	g_cvMaxPercentage = CreateConVar("sm_vote_extend_max_percentage", "0.95", "In float value, specify maximum percentage for subsequent votes", _, true, 0.0, true, 1.0);
	
	// Plugin commands
	RegAdminCmd("sm_extend", Command_Extend, ADMFLAG_UNBAN, "sm_extend <minutes> - Increase or shorten map timelimit");
	RegAdminCmd("sm_ve", Command_VoteExtend, ADMFLAG_KICK, "Start a extend map vote");
	RegAdminCmd("sm_voteextend", Command_VoteExtend, ADMFLAG_KICK, "Start a extend map vote");
	
	AutoExecConfig(true);
}

public void OnConvarChange(Handle cvar, const char[] oldValue, const char[] newValue)
{
	g_iTimeLimit = GetConVarInt(mp_timelimit);
}

public void OnMapStart()
{
	g_iExtends = 0;
}

public Action Command_Extend(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;
	
	if (args < 1)
	{
		CReplyToCommand(client, " \x04[Extend] \x01Usage: sm_extend <minutes> - Extend/shorten map time");
		return Plugin_Handled;
	}
	
	char buffer[8];
	GetCmdArgString(buffer, sizeof(buffer));
	int time = StringToInt(buffer);
	
	if (time != 0)
	{
		SetConVarInt(mp_timelimit, g_iTimeLimit + time);
		
		if (time > 0)
		{
			CShowActivity2(client, "", " \x04[Extend] \x01Extended map time by \x04%d \x01minutes!", time);
			LogAction(client, -1, "\"%L\" Extended map time by %d minutes", client, time);
		}
		else
		{
			CShowActivity2(client, "", " \x04[Extend] \x01Shortened map time by \x04%d \x01minutes!", time);
			LogAction(client, -1, "\"%L\" Shortened map time by %d minutes", client, time);
		}
	}
	return Plugin_Handled;
}

public Action Command_VoteExtend(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;
	
	if (IsVoteInProgress())
	{
		CReplyToCommand(client, " \x04[Extend] \x01Please wait until the current vote has finished.");
		return Plugin_Handled;
	}

	if (g_iExtends >= g_cvMaxExtends.IntValue)
	{
		CReplyToCommand(client, " \x04[Extend] \x01Maximum number of extends reached for this map.");
		return Plugin_Handled;
	}

	// If 1 extend has already been called, assume it was called by a junior/senior admin so do a check
	if (g_iExtends == 1 && !CheckCommandAccess(client, "", ADMFLAG_UNBAN))
	{
		CReplyToCommand(client, " \x04[Extend] \x01You have already used up the admin extend for this map. Ask head admin or server manager for more");
		return Plugin_Handled;
	}
	
	// Run vote extend function if the prior checks passed
	StartVoteExtend(client);
	return Plugin_Handled;
}


public void StartVoteExtend(int client)
{
	float minPercentage;
	
	if (g_iExtends > 0)
		minPercentage = g_cvMinPercentage.FloatValue + (g_cvIncreasePercentage.FloatValue * g_iExtends);
	else
		minPercentage = g_cvMinPercentage.FloatValue;
	
	CPrintToChatAll(" \x04[Extend] \x01Vote to extend for \x04%d \x01minutes started by \x10%N", g_cvExtendTime.IntValue, client);
	g_iExtends++; // Increment the total number of vote extends so far

	Menu voteExtend = CreateMenu(H_VoteExtend);
	SetVoteResultCallback(voteExtend, H_VoteExtendCallback);
	SetMenuTitle(voteExtend, "Extend %d minutes? (%d%% required)", g_cvExtendTime.IntValue, RoundToNearest(minPercentage * 100));
	
	AddMenuItem(voteExtend, "", "Yes");
	AddMenuItem(voteExtend, "", "No");
	SetMenuExitButton(voteExtend, false);
	VoteMenuToAll(voteExtend, 20);
}

public void H_VoteExtendCallback(Menu menu, int num_votes, int num_clients, const int[][] client_info, int num_items, const int[][] item_info)
{
	int votesYes = 0;
	float minPercentage = 0.0, voteRatio = 0.0;

	if (item_info[0][VOTEINFO_ITEM_INDEX] == 0) // If the winner is Yes
		votesYes = item_info[0][VOTEINFO_ITEM_VOTES];
	else // If the winner is No
		if (num_items > 1)
			votesYes = item_info[1][VOTEINFO_ITEM_VOTES];

	if (g_iExtends > 0)
	{
		minPercentage = g_cvMinPercentage.FloatValue + (g_cvIncreasePercentage.FloatValue * g_iExtends);
		if (minPercentage > g_cvMaxPercentage.FloatValue)
			minPercentage = g_cvMaxPercentage.FloatValue;
	}
	else
		minPercentage = g_cvMinPercentage.FloatValue;

	voteRatio = float(votesYes) / float(num_votes);

	if (voteRatio > minPercentage)
	{
		CPrintToChatAll(" \x04[Extend] \x01Vote to extend succeeded, map extended for \x04%d\x01 minutes. (Received \x04%d \x01of \x04%d \x01votes)", g_cvExtendTime.IntValue, votesYes, num_votes);
		ExtendMapTimeLimit(RoundToFloor(GetConVarFloat(g_cvExtendTime) * 60));
	}
	else
		CPrintToChatAll(" \x04[Extend] \x01Vote to extend failed. (Receieved \x04%d \x01of \x04%d \x01votes)", votesYes, num_votes);
}

public int H_VoteExtend(Menu tMenu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		CloseHandle(tMenu);
	return 0;
}

stock bool IsValidClient(int client)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client))
		return false;
	return true;
}
