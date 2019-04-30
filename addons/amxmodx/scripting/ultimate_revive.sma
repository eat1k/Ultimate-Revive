/*
 * Author contact: http://t.me/twisternick or:
 *	- Official topic of the resource in Russian forum: https://dev-cs.ru/threads/2500/
 *	- Official topic of the resource in English forum: https://forums.alliedmods.net/showthread.php?p=2626306#post2626306
 *	- Official topic of the resource in Spanish forum: https://amxmodx-es.com/Thread-Ultimate-Revive-v0-5?pid=192169#pid192169
 *
 * Changelog:
 *	- 0.5.1: Fixed getting CVars' values. Now it's happening after execution of the config (thanks to zhorzh78).
 *	- 0.5:
 *		- Removed AMX Mod X 1.8.2/1.8.3 support.
 *		- Defines are replaced by CVars.
 *		- Added automatic creation and execution of a configuration file with CVars: "amxmodx/configs/plugins/ultimate_revive.cfg".
 *		- Added a menu to revive players so added new CVars, too: ur_menu_cmd to enable the menu and ur_menu_cmd_name (command to open the menu).
 *	- 0.3: Added define BOT_SUPPORT (by enabling, you'll be able to revive bots).
 *	- 0.2:
 *		- Fixed some things.
 *		- Added define UR_ACCESS_DENY_MODE (when a player has no access and tries to use the console command to revive a player/team/everyone).
 *	- 0.1: Release.
 */

#include <amxmodx>
#include <amxmisc>
#include <reapi>

#pragma semicolon 1

#define PLUGIN_VERSION "0.5.1"

/****************************************************************************************
****************************************************************************************/

enum _:CVARS
{
	CVAR_CONSOLE_CMD_NAME[32],
	CVAR_CONSOLE_CMD_ACCESS_DENY_MODE,
	CVAR_ARMOR_TYPE,
	CVAR_BOT_SUPPORT,
	CVAR_MESSAGES,
	CVAR_LOG
};

new g_vCvar[CVARS];

new g_szLogFile[PLATFORM_MAX_PATH];

// Menu
new g_iMenuPlayers[MAX_PLAYERS+1][MAX_PLAYERS], g_iMenuPosition[MAX_PLAYERS+1];

new Float:g_flHealth[MAX_PLAYERS+1] = { 100.0, ... };
new g_iArmor[MAX_PLAYERS+1] = { 100, ... };

public plugin_init()
{
	register_plugin("Ultimate Revive", PLUGIN_VERSION, "w0w");
	register_dictionary("ultimate_revive.txt");

	new pCvar;

	new pCvarAdminAccess = create_cvar("ur_admin_access", "m", FCVAR_NONE, "Admin access to console command to revive players");
	new pCvarConsoleCmd = create_cvar("ur_console_cmd", "1", FCVAR_NONE, "1 - it's enabled the console command to revive a player/team/everyone; 0 - disabled");
	new pCvarConsoleCmdName = create_cvar("ur_console_cmd_name", "amx_revive", FCVAR_NONE, "Console command to revive players");

	pCvar = create_cvar("ur_console_cmd_access_deny_mode", "0", FCVAR_NONE, "If a player has no access and entered the command. 0 - he'll see ^"Unknown command: ...^" (depending on ur_console_cmd_name); 1 - he'll see only the command he entered; 2 - he'll see ^"You have no access to that command^" (NO_ACC_COM in common.txt)", true, 0.0, true, 2.0);
	bind_pcvar_num(pCvar, g_vCvar[CVAR_CONSOLE_CMD_ACCESS_DENY_MODE]);

	new pCvarMenuCmd = create_cvar("ur_menu_cmd", "1", FCVAR_NONE, "1 - it's enabled the menu command to revive a player; 0 - disabled");
	new pCvarMenuCmdName = create_cvar("ur_menu_cmd_name", "amx_revivemenu", FCVAR_NONE, "Command to open a menu to revive players");

	pCvar = create_cvar("ur_bot_support", "0", FCVAR_NONE, "Bot support. 0 - disabled support; 1 - enabled", true, 0.0, true, 1.0);
	bind_pcvar_num(pCvar, g_vCvar[CVAR_BOT_SUPPORT]);

	pCvar = create_cvar("ur_messages", "1", FCVAR_NONE, "0 - disabled; 1 - show only to who used the command and who was revived; 2 - show to everyone", true, 0.0, true, 2.0);
	bind_pcvar_num(pCvar, g_vCvar[CVAR_MESSAGES]);

	new pCvarLog = create_cvar("ur_log", "0", FCVAR_NONE, "Logging when admins revive a player/team/everyone. 0 - disabled; 1 - enabled", true, 0.0, true, 1.0);

	AutoExecConfig(true, "ultimate_revive");

	// After execution of the config, not before.
	new szAdminAccess[32], iConsoleCmd, iMenuCmd, szMenuCmdName[32];

	get_pcvar_string(pCvarAdminAccess, szAdminAccess, charsmax(szAdminAccess));

	iConsoleCmd = get_pcvar_num(pCvarConsoleCmd);
	get_pcvar_string(pCvarConsoleCmdName, g_vCvar[CVAR_CONSOLE_CMD_NAME], charsmax(g_vCvar[CVAR_CONSOLE_CMD_NAME]));

	iMenuCmd = get_pcvar_num(pCvarMenuCmd);
	get_pcvar_string(pCvarMenuCmdName, szMenuCmdName, charsmax(szMenuCmdName));

	g_vCvar[CVAR_LOG] = get_pcvar_num(pCvarLog);

	if(!iConsoleCmd && !iMenuCmd)
	{
		set_fail_state("Menu and console commands are disabled");
		return;
	}

	if(iConsoleCmd)
		register_clcmd(g_vCvar[CVAR_CONSOLE_CMD_NAME], "func_ConsoleCmdRevive", read_flags(szAdminAccess));

	if(iMenuCmd)
	{
		register_clcmd(szMenuCmdName, "func_ClCmdReviveMenu", read_flags(szAdminAccess));
		register_menucmd(register_menuid("func_ReviveMenu"), (1<<0|1<<1|1<<2|1<<3|1<<4|1<<5|1<<6|1<<7|1<<8|1<<9), "func_ReviveMenu_Handler");

		register_clcmd("ur_set_health", "func_MessageModeSetHealth");
		register_clcmd("ur_set_armor", "func_MessageModeSetArmor");
	}

	if(g_vCvar[CVAR_LOG])
	{
		new szLogsDir[PLATFORM_MAX_PATH]; get_localinfo("amxx_logs", szLogsDir, charsmax(szLogsDir));
		formatex(g_szLogFile, charsmax(g_szLogFile), "%s/ultimate_revive.log", szLogsDir);
	}
}

public client_putinserver(id)
{
	g_flHealth[id] = 100.0;
	g_iArmor[id] = 100;
}

public func_ConsoleCmdRevive(id, lvl, cid)
{
	switch(g_vCvar[CVAR_CONSOLE_CMD_ACCESS_DENY_MODE])
	{
		case 0:
		{
			if(!cmd_access(id, lvl, cid, 0, true))
				return PLUGIN_CONTINUE;
		}
		case 1:
		{
			if(!cmd_access(id, lvl, cid, 0, true))
				return PLUGIN_HANDLED;
		}
		case 2:
		{
			if(!cmd_access(id, lvl, cid, 0))
				return PLUGIN_HANDLED;
		}
	}

	enum { name = 1, health = 2, armor };

	new szArgName[MAX_NAME_LENGTH]; read_argv(name, szArgName, charsmax(szArgName));
	if(!szArgName[0])
	{
		client_print(id, print_console, "%l", "UR_ERROR_USAGE", g_vCvar[CVAR_CONSOLE_CMD_NAME]);
		return PLUGIN_HANDLED;
	}

	new szArgHealth[10]; read_argv(health, szArgHealth, charsmax(szArgHealth));
	new szArgArmor[10]; read_argv(armor, szArgArmor, charsmax(szArgArmor));
	new Float:flHealth, iArmor;
	new bool:bNeedSetHealth, bool:bNeedSetArmor, ArmorType:iArmorType;

	if(szArgHealth[0])
	{
		if(!is_digit_arg(szArgHealth))
		{
			client_print(id, print_console, "%l", "UR_ERROR_USAGE", g_vCvar[CVAR_CONSOLE_CMD_NAME]);
			return PLUGIN_HANDLED;
		}

		bNeedSetHealth = true;
		flHealth = str_to_float(szArgHealth);

		if(flHealth == 0.0)
			flHealth = 1.0;
		else if(flHealth > 2147483520.0)
			flHealth = 2147483520.0;
	}

	if(szArgArmor[0] > 0)
	{
		if(!is_digit_arg(szArgArmor))
		{
			client_print(id, print_console, "%l", "UR_ERROR_USAGE", g_vCvar[CVAR_CONSOLE_CMD_NAME]);
			return PLUGIN_HANDLED;
		}

		bNeedSetArmor = true;
		iArmor = str_to_num(szArgArmor);
		if(iArmor > 999)
			iArmor = 999;

		// ARMOR_KEVLAR or ARMOR_VESTHELM
		iArmorType = ArmorType:(g_vCvar[CVAR_ARMOR_TYPE] + 1);
	}

	new iPlayers[MAX_PLAYERS], iPlayerCount, i, iPlayer;

	get_players_ex(iPlayers, iPlayerCount, !g_vCvar[CVAR_BOT_SUPPORT] ? (GetPlayers_ExcludeAlive|GetPlayers_ExcludeBots|GetPlayers_ExcludeHLTV) : (GetPlayers_ExcludeAlive|GetPlayers_ExcludeHLTV));

	new szTeam[64];

	if(equal(szArgName, "T"))
	{
		new iCount;
		for(i = 0; i < iPlayerCount; i++)
		{
			iPlayer = iPlayers[i];

			if(get_member(iPlayer, m_iTeam) != TEAM_TERRORIST)
				continue;

			iCount++;
			rg_round_respawn(iPlayer);

			if(bNeedSetHealth)
				set_entvar(iPlayer, var_health, flHealth);
			if(bNeedSetArmor)
				rg_set_user_armor(iPlayer, iArmor, iArmorType);

			if(g_vCvar[CVAR_MESSAGES] == 1)
				client_print_color(iPlayer, print_team_default, "%l", "UR_REVIVED_PLAYER_TARGET", id);
		}

		if(!iCount) return PLUGIN_HANDLED;

		formatex(szTeam, charsmax(szTeam), "%l", "UR_MSG_T");

		switch(g_vCvar[CVAR_MESSAGES])
		{
			case 1: client_print_color(id, print_team_red, "%l", "UR_REVIVED_MSG", szTeam);
			case 2: client_print_color(0, print_team_red, "%l", "UR_REVIVED_MSG_ALL", id, szTeam);
		}

		if(g_vCvar[CVAR_LOG])
		{
			new szAuthID[MAX_AUTHID_LENGTH]; get_user_authid(id, szAuthID, charsmax(szAuthID));
			new szIP[MAX_IP_LENGTH]; get_user_ip(id, szIP, charsmax(szIP), 1);
			log_to_file(g_szLogFile, "%l", "UR_REVIVED_TEAM_LOG", id, szAuthID, szIP, szTeam);
		}

		return PLUGIN_HANDLED;
	}
	else if(equal(szArgName, "CT"))
	{
		new iCount;
		for(i = 0; i < iPlayerCount; i++)
		{
			iPlayer = iPlayers[i];

			if(get_member(iPlayer, m_iTeam) != TEAM_CT)
				continue;

			iCount++;
			rg_round_respawn(iPlayer);

			if(bNeedSetHealth)
				set_entvar(iPlayer, var_health, flHealth);
			if(bNeedSetArmor)
				rg_set_user_armor(iPlayer, iArmor, iArmorType);

			if(g_vCvar[CVAR_MESSAGES] == 1)
				client_print_color(iPlayer, print_team_default, "%l", "UR_REVIVED_PLAYER_TARGET", id);
		}

		if(!iCount) return PLUGIN_HANDLED;

		formatex(szTeam, charsmax(szTeam), "%l", "UR_MSG_CT");

		switch(g_vCvar[CVAR_MESSAGES])
		{
			case 1: client_print_color(id, print_team_blue, "%l", "UR_REVIVED_MSG", szTeam);
			case 2: client_print_color(0, print_team_blue, "%l", "UR_REVIVED_MSG_ALL", id, szTeam);
		}

		if(g_vCvar[CVAR_LOG])
		{
			new szAuthID[MAX_AUTHID_LENGTH]; get_user_authid(id, szAuthID, charsmax(szAuthID));
			new szIP[MAX_IP_LENGTH]; get_user_ip(id, szIP, charsmax(szIP), 1);
			log_to_file(g_szLogFile, "%l", "UR_REVIVED_TEAM_LOG", id, szAuthID, szIP, szTeam);
		}

		return PLUGIN_HANDLED;
	}
	else if(equal(szArgName, "ALL"))
	{
		new iCount;
		for(i = 0; i < iPlayerCount; i++)
		{
			iPlayer = iPlayers[i];

			if(get_member(iPlayer, m_iTeam) == TEAM_SPECTATOR)
				continue;

			iCount++;
			rg_round_respawn(iPlayer);

			if(bNeedSetHealth)
				set_entvar(iPlayer, var_health, flHealth);
			if(bNeedSetArmor)
				rg_set_user_armor(iPlayer, iArmor, iArmorType);

			if(g_vCvar[CVAR_MESSAGES] == 1)
				client_print_color(iPlayer, print_team_default, "%l", "UR_REVIVED_PLAYER_TARGET", id);
		}

		if(!iCount) return PLUGIN_HANDLED;

		formatex(szTeam, charsmax(szTeam), "%l", "UR_MSG_ALL");

		switch(g_vCvar[CVAR_MESSAGES])
		{
			case 1: client_print_color(id, print_team_grey, "%l", "UR_REVIVED_MSG", szTeam);
			case 2: client_print_color(0, print_team_grey, "%l", "UR_REVIVED_MSG_ALL", id, szTeam);
		}

		if(g_vCvar[CVAR_LOG])
		{
			new szAuthID[MAX_AUTHID_LENGTH]; get_user_authid(id, szAuthID, charsmax(szAuthID));
			new szIP[MAX_IP_LENGTH]; get_user_ip(id, szIP, charsmax(szIP), 1);
			log_to_file(g_szLogFile, "%l", "UR_REVIVED_TEAM_LOG", id, szAuthID, szIP, szTeam);
		}

		return PLUGIN_HANDLED;
	}
	else
	{
		new iTarget = cmd_target(id, szArgName, CMDTARGET_ALLOW_SELF);
		if(!iTarget) return PLUGIN_HANDLED;

		if(is_user_alive(iTarget))
		{
			client_print(id, print_console, "%l", "UR_ERROR_ALIVE");
			return PLUGIN_HANDLED;
		}

		if(get_member(iTarget, m_iTeam) != TEAM_TERRORIST && get_member(iTarget, m_iTeam) != TEAM_CT)
		{
			client_print(id, print_console, "%l", "UR_ERROR_TEAM");
			return PLUGIN_HANDLED;
		}

		rg_round_respawn(iTarget);
		if(bNeedSetHealth)
			set_entvar(iTarget, var_health, flHealth);
		if(bNeedSetArmor)
			rg_set_user_armor(iTarget, iArmor, iArmorType);

		func_AfterReviveAction(id, iTarget);
	}

	return PLUGIN_HANDLED;
}

public func_ClCmdReviveMenu(id, lvl, cid)
{
	switch(g_vCvar[CVAR_CONSOLE_CMD_ACCESS_DENY_MODE])
	{
		case 0:
		{
			if(!cmd_access(id, lvl, cid, 0, true))
				return PLUGIN_CONTINUE;
		}
		case 1:
		{
			if(!cmd_access(id, lvl, cid, 0, true))
				return PLUGIN_HANDLED;
		}
		case 2:
		{
			if(!cmd_access(id, lvl, cid, 0))
				return PLUGIN_HANDLED;
		}
	}

	func_ReviveMenu(id, 0, .bChat = true);
	return PLUGIN_HANDLED;
}

func_ReviveMenu(id, iPage, bool:bChat = false)
{
	if(iPage < 0) return PLUGIN_HANDLED;

	new iPlayerCount;
	for(new i = 1; i <= MaxClients; i++)
	{
		if(!is_user_connected(i) || is_user_alive(i) || get_member(i, m_iTeam) != TEAM_TERRORIST && get_member(i, m_iTeam) != TEAM_CT || !g_vCvar[CVAR_BOT_SUPPORT] && is_user_bot(i))
			continue;

		g_iMenuPlayers[id][iPlayerCount++] = i;
	}

	new i = min(iPage * 6, iPlayerCount);
	new iStart = i - (i % 6);
	new iEnd = min(iStart + 6, iPlayerCount);
	g_iMenuPosition[id] = iPage = iStart / 6;

	new szMenu[MAX_MENU_LENGTH], iMenuItem, iKeys = (1<<9), iPagesNum = (iPlayerCount / 6 + ((iPlayerCount % 6) ? 1 : 0));

	new iLen = formatex(szMenu, charsmax(szMenu), "\y%l \d\R%d/%d^n^n", "UR_MENU_TITLE", iPage + 1, iPagesNum);

	for(new a = iStart, iPlayer; a < iEnd; ++a)
	{
		iPlayer = g_iMenuPlayers[id][a];

		iKeys |= (1<<iMenuItem);
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y%d. \w%n^n", ++iMenuItem, iPlayer);
	}

	if(!iMenuItem)
	{
		if(bChat)
			client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_PLAYERS");
		return PLUGIN_HANDLED;
	}

	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\y7. \w%l^n", "UR_MENU_HEALTH", g_flHealth[id]);
	iKeys |= (1<<6);

	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y8. \w%l^n", "UR_MENU_ARMOR", g_iArmor[id]);
	iKeys |= (1<<7);

	if(iEnd != iPlayerCount)
	{
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\y9. \w%l^n\y0. \w%l", "UR_NEXT", iPage ? "UR_BACK" : "UR_EXIT");
		iKeys |= (1<<8);
	}
	else formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\y0. \w%l", iPage ? "UR_BACK" : "UR_EXIT");

	show_menu(id, iKeys, szMenu, -1, "func_ReviveMenu");
	return PLUGIN_HANDLED;
}

public func_ReviveMenu_Handler(id, iKey)
{
	switch(iKey)
	{
		case 6:
		{
			client_cmd(id, "messagemode ur_set_health");
			func_ReviveMenu(id, g_iMenuPosition[id]);
		}
		case 7:
		{
			client_cmd(id, "messagemode ur_set_armor");
			func_ReviveMenu(id, g_iMenuPosition[id]);
		}
		case 8: func_ReviveMenu(id, ++g_iMenuPosition[id]);
		case 9: func_ReviveMenu(id, --g_iMenuPosition[id]);
		default:
		{
			new iTarget = g_iMenuPlayers[id][(g_iMenuPosition[id] * 6) + iKey];
			if(is_user_alive(iTarget) || get_member(iTarget, m_iTeam) != TEAM_TERRORIST && get_member(iTarget, m_iTeam) != TEAM_CT)
				return func_ReviveMenu(id, g_iMenuPosition[id]);

			// ARMOR_KEVLAR or ARMOR_VESTHELM
			new ArmorType:iArmorType = ArmorType:(g_vCvar[CVAR_ARMOR_TYPE] + 1);

			rg_round_respawn(iTarget);
			set_entvar(iTarget, var_health, g_flHealth[id]);
			rg_set_user_armor(iTarget, g_iArmor[id], iArmorType);

			func_AfterReviveAction(id, iTarget);
			func_ReviveMenu(id, g_iMenuPosition[id]);
		}
	}
	return PLUGIN_HANDLED;
}

func_AfterReviveAction(id, iTarget)
{
	switch(g_vCvar[CVAR_MESSAGES])
	{
		case 1:
		{
			client_print_color(id, iTarget, "%l", "UR_REVIVED_MSG", iTarget);
			client_print_color(iTarget, print_team_default, "%l", "UR_REVIVED_PLAYER_TARGET", id);
		}
		case 2: client_print_color(0, iTarget, "%l", "UR_REVIVED_MSG_ALL", id, iTarget);
	}

	if(g_vCvar[CVAR_LOG])
	{
		new szAuthID[MAX_AUTHID_LENGTH]; get_user_authid(id, szAuthID, charsmax(szAuthID));
		new szIP[MAX_IP_LENGTH]; get_user_ip(id, szIP, charsmax(szIP), 1);
		new szTargetAuthID[MAX_AUTHID_LENGTH]; get_user_authid(iTarget, szTargetAuthID, charsmax(szTargetAuthID));
		new szTargetIP[MAX_IP_LENGTH]; get_user_ip(iTarget, szTargetIP, charsmax(szTargetIP), 1);

		log_to_file(g_szLogFile, "%l", "UR_REVIVED_ONE_LOG",
			id, szAuthID, szIP,
			iTarget, szTargetAuthID, szTargetIP);
	}
}

public func_MessageModeSetHealth(id)
{
	enum { health = 1 };

	new szArgHealth[10]; read_argv(health, szArgHealth, charsmax(szArgHealth));

	if(!szArgHealth[0])
	{
		client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_USAGE_ZERO");
		return PLUGIN_HANDLED;
	}

	if(szArgHealth[0])
	{
		if(!is_digit_arg(szArgHealth))
		{
			client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_USAGE_DIGIT");
			return PLUGIN_HANDLED;
		}

		g_flHealth[id] = str_to_float(szArgHealth);

		if(g_flHealth[id] == 0.0)
			g_flHealth[id] = 1.0;
		else if(g_flHealth[id] > 2147483520.0)
			g_flHealth[id] = 2147483520.0;

		func_ReviveMenu(id, g_iMenuPosition[id]);
	}

	return PLUGIN_HANDLED;
}

public func_MessageModeSetArmor(id)
{
	enum { armor = 1 };

	new szArgArmor[10]; read_argv(armor, szArgArmor, charsmax(szArgArmor));

	if(!szArgArmor[0])
	{
		client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_USAGE_ZERO");
		return PLUGIN_HANDLED;
	}

	if(szArgArmor[0])
	{
		if(!is_digit_arg(szArgArmor))
		{
			client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_USAGE_DIGIT");
			return PLUGIN_HANDLED;
		}

		g_iArmor[id] = str_to_num(szArgArmor);

		if(g_iArmor[id] > 999)
			g_iArmor[id] = 999;

		func_ReviveMenu(id, g_iMenuPosition[id]);
	}

	return PLUGIN_HANDLED;
}

/****************************************************************************************
****************************************************************************************/

stock is_digit_arg(szArg[])
{
	new bool:bIsDigit = true;
	for(new iCharacter, iLen = strlen(szArg); iCharacter < iLen; iCharacter++)
	{
		if(!isdigit(szArg[iCharacter]))
		{
			bIsDigit = false;
			break;
		}
	}

	return bIsDigit;
}