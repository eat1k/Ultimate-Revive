/*
 * Official resource topic: https://dev-cs.ru/resources/447/
 */

#include <amxmodx>
#include <amxmisc>
#include <reapi>

#pragma semicolon 1

public stock const PluginName[] = "Ultimate Revive";
public stock const PluginVersion[] = "1.0.0";
public stock const PluginAuthor[] = "twisterniq";
public stock const PluginURL[] = "https://github.com/twisterniq/Ultimate-Revive";
public stock const PluginDescription[] = "Adds the ability to respawn a player/team/everyone through console command or menu with the option to set HP and armor";

new const CONFIG_NAME[] = "ultimate_revive";

// Console command to revive players
new const CONSOLE_COMMAND[] = "amx_revive";

// Console command to open the menu to revive players
new const CONSOLE_MENU_COMMAND[] = "amx_revivemenu";

// Players per page in menu. No more than six.
const PLAYERS_PER_PAGE = 6;

enum _:CVARS
{
	CVAR_ACCESS[32],
	CVAR_ARMOR_TYPE,
	CVAR_BOT_SUPPORT,
	CVAR_MESSAGES,
	CVAR_LOG
};

new g_eCvar[CVARS];

enum _:CVAR_MESSAGE_TYPES
{
	MESSAGE_SHOW_USER_TARGET = 1,
	MESSAGE_SHOW_ALL
};

new g_szLogFile[PLATFORM_MAX_PATH];

// Menu
new g_iMenuPlayers[MAX_PLAYERS+1][MAX_PLAYERS], g_iMenuPosition[MAX_PLAYERS+1];

new Float:g_flHealth[MAX_PLAYERS+1] = { 100.0, ... };
new g_iArmor[MAX_PLAYERS+1] = { 100, ... };

public plugin_init()
{
#if AMXX_VERSION_NUM == 190
	register_plugin(
		.plugin_name = PluginName,
		.version = PluginVersion,
		.author = PluginAuthor);
#endif

	register_dictionary("ultimate_revive.txt");

	register_clcmd(CONSOLE_COMMAND, "@func_ConsoleCmdRevive");

	// Menu cmd
	register_clcmd(CONSOLE_MENU_COMMAND, "@func_ClCmdReviveMenu");
	register_menucmd(register_menuid("func_ReviveMenu"), 1023, "@func_ReviveMenu_Handler");

	register_clcmd("ur_set_health", "@func_MessageModeSetHealth");
	register_clcmd("ur_set_armor", "@func_MessageModeSetArmor");

	bind_pcvar_string(create_cvar(
		.name = "ur_access",
		.string = "m",
		.flags = FCVAR_NONE,
		.description = fmt("%L", LANG_SERVER, "UR_CVAR_ACCESS")),
		g_eCvar[CVAR_ACCESS], charsmax(g_eCvar[CVAR_ACCESS]));

	bind_pcvar_num(create_cvar(
		.name = "ur_bot_support",
		.string = "0",
		.flags = FCVAR_NONE,
		.description = fmt("%L", LANG_SERVER, "UR_CVAR_BOT_SUPPORT"),
		.has_min = true,
		.min_val = 0.0,
		.has_max = true,
		.max_val = 1.0), g_eCvar[CVAR_BOT_SUPPORT]);

	bind_pcvar_num(create_cvar(
		.name = "ur_messages",
		.string = "1",
		.flags = FCVAR_NONE,
		.description = fmt("%L", LANG_SERVER, "UR_CVAR_MESSAGES"),
		.has_min = true,
		.min_val = 0.0,
		.has_max = true,
		.max_val = 2.0), g_eCvar[CVAR_MESSAGES]);

	bind_pcvar_num(create_cvar(
		.name = "ur_log",
		.string = "0",
		.flags = FCVAR_NONE,
		.description = fmt("%L", LANG_SERVER, "UR_CVAR_LOG"),
		.has_min = true,
		.min_val = 0.0,
		.has_max = true,
		.max_val = 1.0), g_eCvar[CVAR_LOG]);

	AutoExecConfig(true, CONFIG_NAME);

	new szPath[PLATFORM_MAX_PATH];

	get_localinfo("amxx_configsdir", szPath, charsmax(szPath));
	server_cmd("exec %s/plugins/%s.cfg", szPath, CONFIG_NAME);
	server_exec();

	get_localinfo("amxx_logs", szPath, charsmax(szPath));
	formatex(g_szLogFile, charsmax(g_szLogFile), "%s/%s.log", szPath, CONFIG_NAME);
}

public client_putinserver(id)
{
	g_flHealth[id] = 100.0;
	g_iArmor[id] = 100;
}

@func_ConsoleCmdRevive(const id)
{
	if (!has_flag(id, g_eCvar[CVAR_ACCESS]))
	{
		console_print(id, "%l", "UR_ERROR_HAVE_NO_ACCESS");
		return PLUGIN_HANDLED;
	}

	enum { arg_name = 1, arg_health = 2, arg_armor };

	new szArgName[MAX_NAME_LENGTH];
	read_argv(arg_name, szArgName, charsmax(szArgName));

	if (!szArgName[0])
	{
		console_print(id, "%l", "UR_ERROR_USAGE", CONSOLE_MENU_COMMAND);
		return PLUGIN_HANDLED;
	}

	new szArgHealth[10], szArgArmor[10];
	read_argv(arg_health, szArgHealth, charsmax(szArgHealth));
	read_argv(arg_armor, szArgArmor, charsmax(szArgArmor));

	new Float:flHealth, iArmor;
	new bool:bNeedSetHealth, bool:bNeedSetArmor, ArmorType:iArmorType;

	if (szArgHealth[0])
	{
		if (!is_digit_arg(szArgHealth))
		{
			console_print(id, "%l", "UR_ERROR_USAGE", CONSOLE_MENU_COMMAND);
			return PLUGIN_HANDLED;
		}

		bNeedSetHealth = true;
		flHealth = floatclamp(str_to_float(szArgHealth), 1.0, 2147483520.0);
	}

	if (szArgArmor[0] > 0)
	{
		if (!is_digit_arg(szArgArmor))
		{
			console_print(id, "%l", "UR_ERROR_USAGE", CONSOLE_MENU_COMMAND);
			return PLUGIN_HANDLED;
		}

		bNeedSetArmor = true;
		iArmor = clamp(str_to_num(szArgArmor), 0, 999);
		// ARMOR_KEVLAR or ARMOR_VESTHELM
		iArmorType = ArmorType:(g_eCvar[CVAR_ARMOR_TYPE] + 1);
	}

	new iSelected;

	enum { SELECTED_T, SELECTED_CT, SELECTED_ALL, SELECTED_TARGET };

	if (!strcmp(szArgName, "T"))
	{
		iSelected = SELECTED_T;
	}
	else if (!strcmp(szArgName, "CT"))
	{
		iSelected = SELECTED_CT;
	}
	else if (!strcmp(szArgName, "ALL"))
	{
		iSelected = SELECTED_ALL;
	}
	else
	{
		iSelected = SELECTED_TARGET;
	}

	if (SELECTED_T <= iSelected <= SELECTED_ALL)
	{
		new iPlayers[MAX_PLAYERS], iPlayerCount, i, iPlayer;
		get_players_ex(iPlayers, iPlayerCount, !g_eCvar[CVAR_BOT_SUPPORT] ? (GetPlayers_ExcludeAlive|GetPlayers_ExcludeBots|GetPlayers_ExcludeHLTV) : (GetPlayers_ExcludeAlive|GetPlayers_ExcludeHLTV));

		new iCount;

		for (i = 0; i < iPlayerCount; i++)
		{
			iPlayer = iPlayers[i];

			switch(iSelected)
			{
				case SELECTED_T:
				{
					if (get_member(iPlayer, m_iTeam) != TEAM_TERRORIST)
					{
						continue;
					}
				}
				case SELECTED_CT:
				{
					if (get_member(iPlayer, m_iTeam) != TEAM_CT)
					{
						continue;
					}
				}
				case SELECTED_ALL:
				{
					if (!(TEAM_TERRORIST <= get_member(iPlayer, m_iTeam) <= TEAM_CT))
					{
						continue;
					}
				}
			}

			iCount++;
			rg_round_respawn(iPlayer);

			if (bNeedSetHealth)
			{
				set_entvar(iPlayer, var_health, flHealth);
			}

			if (bNeedSetArmor)
			{
				rg_set_user_armor(iPlayer, iArmor, iArmorType);
			}

			if (g_eCvar[CVAR_MESSAGES] == MESSAGE_SHOW_USER_TARGET)
			{
				client_print_color(iPlayer, print_team_default, "%l", "UR_REVIVED_PLAYER_TARGET", id);
			}
		}

		if (!iCount)
		{
			return PLUGIN_HANDLED;
		}

		if (!g_eCvar[CVAR_MESSAGES] && !g_eCvar[CVAR_LOG])
		{
			return PLUGIN_HANDLED;
		}

		new szTeam[64];

		switch(iSelected)
		{
			case SELECTED_T:
			{
				formatex(szTeam, charsmax(szTeam), "%L", id, "UR_MSG_T");
			}
			case SELECTED_CT:
			{
				formatex(szTeam, charsmax(szTeam), "%L", id, "UR_MSG_CT");
			}
			case SELECTED_ALL:
			{
				formatex(szTeam, charsmax(szTeam), "%L", id, "UR_MSG_ALL");
			}
		}

		switch(g_eCvar[CVAR_MESSAGES])
		{
			case MESSAGE_SHOW_USER_TARGET:
			{
				client_print_color(id, print_team_red, "%l", "UR_REVIVED_MSG", szTeam);
			}
			case MESSAGE_SHOW_ALL:
			{
				client_print_color(0, print_team_red, "%l", "UR_REVIVED_MSG_ALL", id, szTeam);
			}
		}

		if (g_eCvar[CVAR_LOG])
		{
			new szAuthID[MAX_AUTHID_LENGTH], szIP[MAX_IP_LENGTH];
			get_user_authid(id, szAuthID, charsmax(szAuthID));
			get_user_ip(id, szIP, charsmax(szIP), 1);

			log_to_file(g_szLogFile, "%l", "UR_REVIVED_TEAM_LOG", id, szAuthID, szIP, szTeam);
		}

		return PLUGIN_HANDLED;
	}
	else
	{
		new iTarget = cmd_target(id, szArgName, CMDTARGET_ALLOW_SELF);

		if (!iTarget)
		{
			return PLUGIN_HANDLED;
		}

		if (is_user_alive(iTarget))
		{
			console_print(id, "%l", "UR_ERROR_ALIVE");
			return PLUGIN_HANDLED;
		}

		if (get_member(iTarget, m_iTeam) != TEAM_TERRORIST && get_member(iTarget, m_iTeam) != TEAM_CT)
		{
			console_print(id, "%l", "UR_ERROR_TEAM");
			return PLUGIN_HANDLED;
		}

		rg_round_respawn(iTarget);

		if (bNeedSetHealth)
		{
			set_entvar(iTarget, var_health, flHealth);
		}

		if (bNeedSetArmor)
		{
			rg_set_user_armor(iTarget, iArmor, iArmorType);
		}

		func_AfterReviveAction(id, iTarget);
	}

	return PLUGIN_HANDLED;
}

@func_ClCmdReviveMenu(const id)
{
	if (!has_flag(id, g_eCvar[CVAR_ACCESS]))
	{
		console_print(id, "%l", "UR_ERROR_HAVE_NO_ACCESS");
		return PLUGIN_HANDLED;
	}

	func_ReviveMenu(id, 0, true);
	return PLUGIN_HANDLED;
}

func_ReviveMenu(const id, iPage, bool:bChat = false)
{
	if (iPage < 0)
	{
		return PLUGIN_HANDLED;
	}

	new iPlayerCount;

	for (new i = 1; i <= MaxClients; i++)
	{
		if (!is_user_connected(i) || is_user_alive(i) || get_member(i, m_iTeam) != TEAM_TERRORIST && get_member(i, m_iTeam) != TEAM_CT || !g_eCvar[CVAR_BOT_SUPPORT] && is_user_bot(i))
		{
			continue;
		}

		g_iMenuPlayers[id][iPlayerCount++] = i;
	}

	SetGlobalTransTarget(id);

	new i = min(iPage * PLAYERS_PER_PAGE, iPlayerCount);
	new iStart = i - (i % PLAYERS_PER_PAGE);
	new iEnd = min(iStart + PLAYERS_PER_PAGE, iPlayerCount);
	g_iMenuPosition[id] = iPage = iStart / PLAYERS_PER_PAGE;

	new szMenu[MAX_MENU_LENGTH], iMenuItem, iKeys = (MENU_KEY_0);
	new iPagesNum = (iPlayerCount / PLAYERS_PER_PAGE + ((iPlayerCount % PLAYERS_PER_PAGE) ? 1 : 0));
	new iLen = formatex(szMenu, charsmax(szMenu), "\y%l \d\R%d/%d^n^n", "UR_MENU_TITLE", iPage + 1, iPagesNum);

	for (new a = iStart, iPlayer; a < iEnd; ++a)
	{
		iPlayer = g_iMenuPlayers[id][a];

		iKeys |= (1<<iMenuItem);
		iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y%d. \w%n^n", ++iMenuItem, iPlayer);
	}

	if (!iMenuItem)
	{
		if (bChat)
		{
			client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_PLAYERS");
		}

		return PLUGIN_HANDLED;
	}

	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\y7. \w%l^n", "UR_MENU_HEALTH", g_flHealth[id]);
	iKeys |= (MENU_KEY_7);

	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y8. \w%l^n", "UR_MENU_ARMOR", g_iArmor[id]);
	iKeys |= (MENU_KEY_8);

	if (iEnd != iPlayerCount)
	{
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\y9. \w%l^n\y0. \w%l", "UR_NEXT", iPage ? "UR_BACK" : "UR_EXIT");
		iKeys |= (MENU_KEY_9);
	}
	else
	{
		formatex(szMenu[iLen], charsmax(szMenu) - iLen, "^n\y0. \w%l", iPage ? "UR_BACK" : "UR_EXIT");
	}

	show_menu(id, iKeys, szMenu, -1, "func_ReviveMenu");
	return PLUGIN_HANDLED;
}

@func_ReviveMenu_Handler(const id, iKey)
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
		case 8:
		{
			func_ReviveMenu(id, ++g_iMenuPosition[id]);
		}
		case 9:
		{
			func_ReviveMenu(id, --g_iMenuPosition[id]);
		}
		default:
		{
			new iTarget = g_iMenuPlayers[id][(g_iMenuPosition[id] * PLAYERS_PER_PAGE) + iKey];
			new TeamName:iTargetTeam = get_member(iTarget, m_iTeam);

			if (is_user_alive(iTarget) || iTargetTeam != TEAM_TERRORIST && iTargetTeam != TEAM_CT)
			{
				func_ReviveMenu(id, g_iMenuPosition[id]);
				return PLUGIN_HANDLED;
			}

			// ARMOR_KEVLAR or ARMOR_VESTHELM
			new ArmorType:iArmorType = ArmorType:(g_eCvar[CVAR_ARMOR_TYPE] + 1);

			rg_round_respawn(iTarget);
			set_entvar(iTarget, var_health, g_flHealth[id]);
			rg_set_user_armor(iTarget, g_iArmor[id], iArmorType);

			func_AfterReviveAction(id, iTarget);
			func_ReviveMenu(id, g_iMenuPosition[id]);
		}
	}
	return PLUGIN_HANDLED;
}

func_AfterReviveAction(const id, const iTarget)
{
	switch(g_eCvar[CVAR_MESSAGES])
	{
		case MESSAGE_SHOW_USER_TARGET:
		{
			client_print_color(id, iTarget, "%l", "UR_REVIVED_MSG", iTarget);
			client_print_color(iTarget, print_team_default, "%l", "UR_REVIVED_PLAYER_TARGET", id);
		}
		case MESSAGE_SHOW_ALL:
		{
			client_print_color(0, iTarget, "%l", "UR_REVIVED_MSG_ALL", id, iTarget);
		}
	}

	if (g_eCvar[CVAR_LOG])
	{
		new szAuthID[MAX_AUTHID_LENGTH], szIP[MAX_IP_LENGTH];
		get_user_authid(id, szAuthID, charsmax(szAuthID));
		get_user_ip(id, szIP, charsmax(szIP), 1);

		new szTargetAuthID[MAX_AUTHID_LENGTH], szTargetIP[MAX_IP_LENGTH];
		get_user_authid(iTarget, szTargetAuthID, charsmax(szTargetAuthID));
		get_user_ip(iTarget, szTargetIP, charsmax(szTargetIP), 1);

		log_to_file(g_szLogFile, "%L", LANG_SERVER, "UR_REVIVED_ONE_LOG",
			id, szAuthID, szIP,
			iTarget, szTargetAuthID, szTargetIP);
	}
}

@func_MessageModeSetHealth(const id)
{
	enum { arg_health = 1 };

	new szArgHealth[10];
	read_argv(arg_health, szArgHealth, charsmax(szArgHealth));

	if (!szArgHealth[0])
	{
		client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_USAGE_ZERO");
		return PLUGIN_HANDLED;
	}

	if (szArgHealth[0])
	{
		if (!is_digit_arg(szArgHealth))
		{
			client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_USAGE_DIGIT");
			return PLUGIN_HANDLED;
		}

		g_flHealth[id] = floatclamp(str_to_float(szArgHealth), 1.0, 2147483520.0);

		func_ReviveMenu(id, g_iMenuPosition[id]);
	}

	return PLUGIN_HANDLED;
}

@func_MessageModeSetArmor(const id)
{
	enum { arg_armor = 1 };

	new szArgArmor[10];
	read_argv(arg_armor, szArgArmor, charsmax(szArgArmor));

	if (!szArgArmor[0])
	{
		client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_USAGE_ZERO");
		return PLUGIN_HANDLED;
	}

	if (szArgArmor[0])
	{
		if (!is_digit_arg(szArgArmor))
		{
			client_print_color(id, print_team_red, "%l", "UR_ERROR_MENU_USAGE_DIGIT");
			return PLUGIN_HANDLED;
		}

		g_iArmor[id] = clamp(str_to_num(szArgArmor), 0, 999);

		func_ReviveMenu(id, g_iMenuPosition[id]);
	}

	return PLUGIN_HANDLED;
}

stock is_digit_arg(szArg[])
{
	new bool:bIsDigit = true;

	for (new iCharacter, iLen = strlen(szArg); iCharacter < iLen; iCharacter++)
	{
		if (!isdigit(szArg[iCharacter]))
		{
			bIsDigit = false;
			break;
		}
	}

	return bIsDigit;
}