/**
 * =============================================================================
 * Custom Weapon Models
 *
 * Copyright (C) 2014 Andersso
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * =============================================================================
 * How to create a custom view model
 * =============================================================================
 *
 * In order to create a functional custom model, a few changes need to be made
 * to your view model. Here is the list of things of what you will have to do.
 * 
 * 1. Decompile your desired view model with a MDL decompiler.
 *    Note: If you have issues decompiling the model, use google.
 * 
 * 2. Open the QC file generated by the decompiler, and select all $sequence
 *    keys, copy and paste them directly after.
 *
 * 3. To prevent name conflicts, add an underscore in front of all the copied
 *    sequence names, from example idle to _idle. However, do not change name of
 *    the quoted string that is directly after.
 * 
 * 4. Remove the activity associated with all the copied sequences. The activity
 *    name always starts with ACT_VM_ and is then followed by a number, remove
 *    both of those.
 *
 *   *If you followed the last steps correctly, a copied sequence should look
 *    something like this:
 *
 *    Before:
 *    $sequence shoot1 "shoot1" ACT_VM_PRIMARYATTACK 1 fps 60.00 {
 *        { event 5001 0 "31" }
 *        { event 6002 2 "0" }
 *    }
 *
 *    After:
 *    $sequence _shoot1 "shoot1" fps 60.00 {
 *        { event 5001 0 "31" }
 *        { event 6002 2 "0" }
 *    }
 *
 * 5. This step is ONLY required for games that use external arm models.
 *    (CS:GO/L4D(2)) Unfortunately, the arm models does not attach properly to
 *    the custom view model. And therefore it needs to get included to view
 *    model manually. To do this, you will have to decompile your desired arms
 *    model, and then include it by adding an additional $model key for it
 *    inside the QC.
 *
 * 6. This step is ONLY required for games that has client-predicted weapon
 *    switching. (CS:GO/L4D(2)/Portal 2(???)) Since weapon switching is client-
 *    predicted, it's not possible to stop the the drawing animation of the
 *    original view model. This means that you can't stop the drawing sound
 *    effect either. To prevent multiple drawing sounds from playing
 *    simultaneously, you will have to remove the draw sound effect in your
 *    custom view model. Find the draw sequence either by its commonly referred
 *    name or by its activity name (ACT_VM_DRAW) and remove all events
 *    that are followed by number 5004. Do the same for the copied sequence.
 *
 *   *If you followed the last step correctly, the result should look
 *    something like this:
 *
 *    Before:
 *    $sequence draw "draw" ACT_VM_DRAW 1 snap rotate -90 fps 32.00 {
 *        { event 5004 0 "Weapon_Colt.Draw" }
 *        { event 5001 0 "1" }
 *    }
 *
 *    (Copied sequence):
 *    $sequence _draw "draw" snap rotate -90 fps 32.00 {
 *        { event 5004 0 "Weapon_Colt.Draw" }
 *        { event 5001 0 "1" }
 *    }
 *
 *    After:
 *    $sequence draw "draw" ACT_VM_DRAW 1 snap rotate -90 fps 32.00 {
 *        { event 5001 0 "1" }
 *    }
 *
 *    (Copied sequence):
 *    $sequence _draw "draw" snap rotate -90 fps 32.00 {
 *        { event 5001 0 "1" }
 *    }
 *
 * 7. Set a new name to your model, and compile it.
 *    Note: If you have issues compiling the model, check if you made any
 *    mistakes and use google.
 *
 * 8. Edit weaponmodels_config.cfg and add your new model, and you are done.
 *
 *   *For world models, I suggest doing a hex edit if you need to the change
 *    model name. Since they don't require any special edits, it saves you from
 *    the hassle of decompiling and compiling.
 */

// TODO:
// Test L4D1/L4D2
// Toggle animation seems to bug on some rare occasions
// Proxy over m_nSkin to view model 2? (sleeve skin)
// Add support for non-custom weapon models

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

// Change this if you need more custom weapon models
#define MAX_CUSTOM_WEAPONS 50

#define CLASS_NAME_MAX_LENGTH 48

#define EF_NODRAW 0x20

#define PARTICLE_DISPATCH_FROM_ENTITY (1 << 0)

#define PATTACH_WORLDORIGIN 5

#define PLUGIN_NAME "Custom Weapon Models"
#define PLUGIN_VERSION "1.0"

public Plugin:myinfo =
{
	name        = PLUGIN_NAME,
	author      = "Andersso",
	description = "Change any weapon model",
	version     = PLUGIN_VERSION,
	url         = "http://www.sourcemod.net/"
};

// This value should be true on the later versions of Source which uses client-predicted weapon switching
new bool:g_bPredictedWeaponSwitch;

new EngineVersion:g_iEngineVersion;

new String:g_szViewModelClassName[CLASS_NAME_MAX_LENGTH] = "predicted_viewmodel";

new Handle:g_hSDKCall_UpdateTransmitState; // UpdateTransmitState will stop the view model from transmitting if EF_NODRAW flag is present

new g_iOffset_StudioHdr;
new g_iOffset_SequenceCount;

new g_iOffset_Effects;
new g_iOffset_ModelIndex;

new g_iOffset_WorldModelIndex;

new g_iOffset_ViewModel;
new g_iOffset_ActiveWeapon;

new g_iOffset_Owner;
new g_iOffset_Weapon;
new g_iOffset_Sequence;
new g_iOffset_PlaybackRate;
new g_iOffset_ViewModelIndex;

new g_iOffset_ItemDefinitionIndex;

enum ClientInfo
{
	ClientInfo_ViewModels[2],
	ClientInfo_LastSequence,
	ClientInfo_CustomWeapon,
	ClientInfo_DrawSequence,
	ClientInfo_weaponIndex,
	bool:ClientInfo_ToggleSequence,
	ClientInfo_LastSequenceParity,
	Float:ClientInfo_UpdateTransmitStateTime
};

new g_ClientInfo[MAXPLAYERS + 1][ClientInfo];

enum WeaponModelInfoStatus
{
	WeaponModelInfoStatus_Free,
	WeaponModelInfoStatus_Config,
	WeaponModelInfoStatus_API
};

enum WeaponModelInfo
{
	WeaponModelInfo_DefIndex,
	Handle:WeaponModelInfo_Forward,
	String:WeaponModelInfo_ClassName[CLASS_NAME_MAX_LENGTH],
	String:WeaponModelInfo_ViewModel[PLATFORM_MAX_PATH + 1],
	String:WeaponModelInfo_WorldModel[PLATFORM_MAX_PATH + 1],
	WeaponModelInfo_ViewModelIndex,
	WeaponModelInfo_WorldModelIndex,
	WeaponModelInfo_NumAnims,
	WeaponModelInfo_TeamNum,
	bool:WeaponModelInfo_BlockLAW,
	WeaponModelInfoStatus:WeaponModelInfo_Status
};

new g_WeaponModelInfo[MAX_CUSTOM_WEAPONS][WeaponModelInfo];

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("weaponmodels");

	CreateNative("WeaponModels_AddWeaponByClassName", Native_AddWeaponByClassName);
	CreateNative("WeaponModels_AddWeaponByItemDefIndex", Native_AddWeaponByItemDefIndex);
	CreateNative("WeaponModels_RemoveWeaponModel", Native_RemoveWeaponModel);
}

public Native_AddWeaponByClassName(Handle:plugin, numParams)
{
	decl String:className[CLASS_NAME_MAX_LENGTH];
	GetNativeString(1, className, sizeof(className));

	new weaponIndex = -1;

	for (new i; i < MAX_CUSTOM_WEAPONS; i++)
	{
		// Check if class-name is already used
		if (g_WeaponModelInfo[i][WeaponModelInfo_Status] != WeaponModelInfoStatus_Free && StrEqual(g_WeaponModelInfo[i][WeaponModelInfo_ClassName], className, false))
		{
			if (CheckForwardCleanup(i))
			{
				// If the forward handle is cleaned up, it also means that the index is no longer used
				weaponIndex = i;

				break;
			}

			return -1;
		}
	}

	if (weaponIndex == -1 && (weaponIndex = GetFreeWeaponInfoIndex()) == -1)
	{
		return -1;
	}

	decl String:viewModel[PLATFORM_MAX_PATH + 1], String:worldModel[PLATFORM_MAX_PATH + 1];
	GetNativeString(2, viewModel, sizeof(viewModel));
	GetNativeString(3, worldModel, sizeof(worldModel));

	g_WeaponModelInfo[weaponIndex][WeaponModelInfo_DefIndex] = -1;

	strcopy(g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ClassName], CLASS_NAME_MAX_LENGTH, className);

	AddWeapon(weaponIndex, viewModel, worldModel, plugin, Function:GetNativeCell(4));

	return weaponIndex;
}

public Native_AddWeaponByItemDefIndex(Handle:plugin, numParams)
{
	new itemDefIndex = GetNativeCell(1);

	if (itemDefIndex < 0)
	{
		ThrowNativeError(SP_ERROR_INDEX, "Item definition index was invalid");
	}

	new weaponIndex = -1;

	for (new i; i < MAX_CUSTOM_WEAPONS; i++)
	{
		// Check if definition index is already used
		if (g_WeaponModelInfo[i][WeaponModelInfo_Status] != WeaponModelInfoStatus_Free && g_WeaponModelInfo[i][WeaponModelInfo_DefIndex] == itemDefIndex)
		{
			if (CheckForwardCleanup(i))
			{
				// If the forward handle is cleaned up, it also means that the index is no longer used
				weaponIndex = i;

				break;
			}

			return -1;
		}
	}

	if (weaponIndex == -1 && (weaponIndex = GetFreeWeaponInfoIndex()) == -1)
	{
		return -1;
	}

	g_WeaponModelInfo[weaponIndex][WeaponModelInfo_DefIndex] = itemDefIndex;

	decl String:viewModel[PLATFORM_MAX_PATH + 1], String:worldModel[PLATFORM_MAX_PATH + 1];

	GetNativeString(2, viewModel, sizeof(viewModel));
	GetNativeString(3, worldModel, sizeof(worldModel));

	AddWeapon(weaponIndex, viewModel, worldModel, plugin, Function:GetNativeCell(4));

	return weaponIndex;
}

bool:CheckForwardCleanup(weaponIndex)
{
	new Handle:forwardHandle = g_WeaponModelInfo[weaponIndex][WeaponModelInfo_Forward];

	if (forwardHandle)
	{
		CloseHandle(forwardHandle);

		return true;
	}

	return false;
}

GetFreeWeaponInfoIndex()
{
	for (new i; i < MAX_CUSTOM_WEAPONS; i++)
	{
		if (g_WeaponModelInfo[i][WeaponModelInfo_Status] == WeaponModelInfoStatus_Free)
		{
			return i;
		}
	}

	return -1;
}

AddWeapon(weaponIndex, const String:viewModel[], const String:worldModel[], Handle:plugin, Function:function)
{
	new Handle:forwardHandle = CreateForward(ET_Single, Param_Cell, Param_Cell, Param_Cell, Param_String, Param_Cell);

	AddToForward(forwardHandle, plugin, function);

	g_WeaponModelInfo[weaponIndex][WeaponModelInfo_Forward] = forwardHandle;

	strcopy(g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ViewModel], PLATFORM_MAX_PATH + 1, viewModel);
	strcopy(g_WeaponModelInfo[weaponIndex][WeaponModelInfo_WorldModel], PLATFORM_MAX_PATH + 1, worldModel);

	PrecacheWeaponInfo(weaponIndex);

	g_WeaponModelInfo[weaponIndex][WeaponModelInfo_NumAnims] = -1;
	g_WeaponModelInfo[weaponIndex][WeaponModelInfo_Status] = WeaponModelInfoStatus_API;
}

PrecacheWeaponInfo(weaponIndex)
{
	g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ViewModelIndex] = PrecacheWeaponInfo_PrecahceModel(g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ViewModel]);
	g_WeaponModelInfo[weaponIndex][WeaponModelInfo_WorldModelIndex] = PrecacheWeaponInfo_PrecahceModel(g_WeaponModelInfo[weaponIndex][WeaponModelInfo_WorldModel]);
}

PrecacheWeaponInfo_PrecahceModel(const String:model[])
{
	return model[0] != '\0' ? PrecacheModel(model, true) : 0;
}

public Native_RemoveWeaponModel(Handle:plugin, numParams)
{
	new weaponIndex = GetNativeCell(1);

	if (weaponIndex < 0 || weaponIndex >= MAX_CUSTOM_WEAPONS)
	{
		ThrowNativeError(SP_ERROR_INDEX, "Weapon index was invalid");
	}

	CloseHandle(g_WeaponModelInfo[weaponIndex][WeaponModelInfo_Forward]);

	g_WeaponModelInfo[weaponIndex][WeaponModelInfo_Status] = WeaponModelInfoStatus_Free;
}

public OnPluginStart()
{
	CreateConVar("sm_weaponmodels_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);

	RegAdminCmd("sm_weaponmodels_reloadconfig", Command_ReloadConfig, ADMFLAG_CONFIG);

	switch (g_iEngineVersion = GetEngineVersion())
	{
		case Engine_DODS:
		{
			g_szViewModelClassName = "dod_viewmodel";
		}
		case Engine_TF2:
		{
			g_szViewModelClassName = "tf_viewmodel";
		}
		case Engine_Left4Dead, Engine_Left4Dead2, Engine_Portal2:
		{
			g_bPredictedWeaponSwitch = true;
		}
		case Engine_CSGO:
		{
			g_bPredictedWeaponSwitch = true;

			AddCommandListener(Command_LookAtWeapon, "+lookatweapon");

			HookEvent("hostage_follows", Event_HostageFollows);
			HookEvent("weapon_fire", Event_WeaponFire);
		}
	}

	HookEvent("player_death", Event_PlayerDeath);

	new Handle:gameConf = LoadGameConfigFile("plugin.weaponmodels");

	if (gameConf)
	{
		StartPrepSDKCall(SDKCall_Entity);
		PrepSDKCall_SetFromConf(gameConf, SDKConf_Virtual, "UpdateTransmitState");

		if (!(g_hSDKCall_UpdateTransmitState = EndPrepSDKCall()))
		{
			SetFailState("Failed to load SDK call \"UpdateTransmitState\"!");
		}

		InitGameConfOffset(gameConf, g_iOffset_StudioHdr, "StudioHdr");
		InitGameConfOffset(gameConf, g_iOffset_SequenceCount, "SequenceCount");

		CloseHandle(gameConf);
	}
	else
	{
		SetFailState("Failed to load game conf");
	}

	InitSendPropOffset(g_iOffset_Effects, "CBaseEntity", "m_fEffects");
	InitSendPropOffset(g_iOffset_ModelIndex, "CBaseEntity", "m_nModelIndex");

	InitSendPropOffset(g_iOffset_WorldModelIndex, "CBaseCombatWeapon", "m_iWorldModelIndex");

	InitSendPropOffset(g_iOffset_ViewModel, "CBasePlayer", "m_hViewModel");
	InitSendPropOffset(g_iOffset_ActiveWeapon, "CBasePlayer", "m_hActiveWeapon");

	InitSendPropOffset(g_iOffset_Owner, "CBaseViewModel", "m_hOwner");
	InitSendPropOffset(g_iOffset_Weapon, "CBaseViewModel", "m_hWeapon");
	InitSendPropOffset(g_iOffset_Sequence, "CBaseViewModel", "m_nSequence");
	InitSendPropOffset(g_iOffset_PlaybackRate, "CBaseViewModel", "m_flPlaybackRate");
	InitSendPropOffset(g_iOffset_ViewModelIndex, "CBaseViewModel", "m_nViewModelIndex");

	InitSendPropOffset(g_iOffset_ItemDefinitionIndex, "CEconEntity", "m_iItemDefinitionIndex", false);

	new lightingOriginOffset;
	InitSendPropOffset(lightingOriginOffset, "CBaseAnimating", "m_hLightingOrigin");

	// StudioHdr offset in gameconf is only relative to the offset of m_hLightingOrigin, in order to make the offset more resilient to game updates
	g_iOffset_StudioHdr += lightingOriginOffset;
}

InitGameConfOffset(Handle:gameConf, &offsetDest, const String:keyName[])
{
	if ((offsetDest = GameConfGetOffset(gameConf, keyName)) == -1)
	{
		SetFailState("Failed to get offset: \"%s\"!", keyName);
	}
}

InitSendPropOffset(&offsetDest, const String:serverClass[], const String:propName[], bool:failOnError = true)
{
	if ((offsetDest = FindSendPropInfo(serverClass, propName)) < 1 && failOnError)
	{
		SetFailState("Failed to find offset: \"%s\"!", propName);
	}
}

public Action:Command_ReloadConfig(client, numArgs)
{
	LoadConfig();
}

public Action:Command_LookAtWeapon(client, const String:command[], numArgs)
{
	if (g_ClientInfo[client][ClientInfo_CustomWeapon])
	{
		new weaponIndex = g_ClientInfo[client][ClientInfo_weaponIndex];

		if (g_WeaponModelInfo[weaponIndex][WeaponModelInfo_BlockLAW])
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Event_HostageFollows(Handle:event, const String:eventName[], bool:dontBrodcast)
{
	CreateTimer(0.01, Timer_RefreshVM, GetEventInt(event, "userid"), TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_RefreshVM(Handle:event, any:client)
{
	if ((client = GetClientOfUserId(client)) == 0)
	{
		return;
	}

	// When a hostage is picked up, the view model gets removed and replaced by another one
	if (g_ClientInfo[client][ClientInfo_CustomWeapon])
	{
		OnWeaponSwitchPost(client, g_ClientInfo[client][ClientInfo_CustomWeapon]);
	}
}

public Event_WeaponFire(Handle:event, const String:name[], bool:dontBrodcast)
{
	static Float:heatValue[MAXPLAYERS + 1], Float:lastSmoke[MAXPLAYERS + 1];

	new client = GetClientOfUserId(GetEventInt(event, "userid")), Float:gameTime = GetGameTime();

	if (g_ClientInfo[client][ClientInfo_CustomWeapon])
	{
		static primaryAmmoTypeOffset, lastShotTimeOffset;

		if (!primaryAmmoTypeOffset)
		{
			InitSendPropOffset(primaryAmmoTypeOffset, "CBaseCombatWeapon", "m_iPrimaryAmmoType");
		}

		new activeWeapon = GetEntDataEnt2(client, g_iOffset_ActiveWeapon);

		// Weapons without any type of ammo will not use smoke effects
		if (GetEntData(activeWeapon, primaryAmmoTypeOffset) == -1)
		{
			return;
		}

		if (!lastShotTimeOffset)
		{
			InitSendPropOffset(lastShotTimeOffset, "CWeaponCSBase", "m_fLastShotTime");
		}

		new Float:newHeat = ((gameTime - GetEntDataFloat(activeWeapon, lastShotTimeOffset)) * -0.5) + heatValue[client];

		if (newHeat <= 0.0)
		{
			newHeat = 0.0;
		}

		// This value would normally be set specifically for each weapon, but who really cares?
		newHeat += 0.3;

		if (newHeat > 1.0)
		{
			if (gameTime - lastSmoke[client] > 4.0)
			{
				new viewModel2 = EntRefToEntIndex(g_ClientInfo[client][ClientInfo_ViewModels][1]);

				if (viewModel2 != -1)
				{
					ShowMuzzleSmoke(client, viewModel2);
				}

				lastSmoke[client] = gameTime;
			}

			newHeat = 0.0;
		}

		heatValue[client] = newHeat;
	}
}

ShowMuzzleSmoke(client, entity)
{
	static muzzleSmokeIndex = INVALID_STRING_INDEX, effectIndex = INVALID_STRING_INDEX;

	if (muzzleSmokeIndex == INVALID_STRING_INDEX && (muzzleSmokeIndex = GetStringTableItemIndex("ParticleEffectNames", "weapon_muzzle_smoke")) == INVALID_STRING_INDEX)
	{
		return;
	}

	if (effectIndex == INVALID_STRING_INDEX && (effectIndex = GetStringTableItemIndex("EffectDispatch", "ParticleEffect")) == INVALID_STRING_INDEX)
	{
		return;
	}

	TE_Start("EffectDispatch");

	TE_WriteNum("entindex", entity);
	TE_WriteNum("m_fFlags", PARTICLE_DISPATCH_FROM_ENTITY);
	TE_WriteNum("m_nHitBox", muzzleSmokeIndex);
	TE_WriteNum("m_iEffectName", effectIndex);
	TE_WriteNum("m_nAttachmentIndex", 1);
	TE_WriteNum("m_nDamageType", PATTACH_WORLDORIGIN);

	TE_SendToClient(client);
}

StopParticleEffects(client, entity)
{
	static effectIndex = INVALID_STRING_INDEX;

	if (effectIndex == INVALID_STRING_INDEX && (effectIndex = GetStringTableItemIndex("EffectDispatch", "ParticleEffectStop")) == INVALID_STRING_INDEX)
	{
		return;
	}

	TE_Start("EffectDispatch");

	TE_WriteNum("entindex", entity);
	TE_WriteNum("m_iEffectName", effectIndex);

	TE_SendToClient(client);
}

GetStringTableItemIndex(const String:stringTable[], const String:string[])
{
	new tableIndex = FindStringTable(stringTable);

	if (tableIndex == INVALID_STRING_TABLE)
	{
		LogError("Failed to receive string table \"%s\"!", stringTable);

		return INVALID_STRING_INDEX;
	}

	new index = FindStringIndex(tableIndex, string);

	if (index == INVALID_STRING_TABLE)
	{
		LogError("Failed to receive item \"%s\" in string table \"%s\"!", string, stringTable);
	}

	return index;
}

public Event_PlayerDeath(Handle:event, const String:eventName[], bool:dontBrodcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	// Event is sometimes called with client index 0 in Left 4 Dead
	if (!client)
	{
		return;
	}

	// Add compatibility with Zombie:Reloaded
	if (IsPlayerAlive(client))
	{
		return;
	}

	new viewModel2 = EntRefToEntIndex(g_ClientInfo[client][ClientInfo_ViewModels][1]);

	if (viewModel2 != -1)
	{
		// Hide the custom view model if the player dies
		ShowViewModel(viewModel2, false);
	}

	g_ClientInfo[client][ClientInfo_ViewModels] = { -1, -1 };
	g_ClientInfo[client][ClientInfo_CustomWeapon] = 0;
	g_ClientInfo[client][ClientInfo_LastSequence] = -1;
	g_ClientInfo[client][ClientInfo_ToggleSequence] = false;
	g_ClientInfo[client][ClientInfo_LastSequenceParity] = -1;
}

public OnPluginEnd()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && g_ClientInfo[i][ClientInfo_CustomWeapon])
		{
			new viewModel1 = EntRefToEntIndex(g_ClientInfo[i][ClientInfo_ViewModels][0]);
			new viewModel2 = EntRefToEntIndex(g_ClientInfo[i][ClientInfo_ViewModels][1]);

			if (viewModel1 != -1)
			{
				ShowViewModel(viewModel1, true);
			}

			if (viewModel2 != -1)
			{
				ShowViewModel(viewModel2, false);
			}
		}
	}
}

public OnConfigsExecuted()
{
	// In case of map-change
	for (new i; i < MAX_CUSTOM_WEAPONS; i++)
	{
		if (g_WeaponModelInfo[i][WeaponModelInfo_Status] == WeaponModelInfoStatus_API)
		{
			PrecacheWeaponInfo(i);
		}
	}

	LoadConfig();
}

LoadConfig()
{
	decl String:path[PLATFORM_MAX_PATH + 1], String:buffer[PLATFORM_MAX_PATH + 1];

	BuildPath(Path_SM, path, sizeof(path), "configs/weaponmodels_config.cfg");

	if (FileExists(path))
	{
		new Handle:kv = CreateKeyValues("ViewModelConfig");

		FileToKeyValues(kv, path);

		if (KvGotoFirstSubKey(kv))
		{
			new nextIndex = 0;

			do
			{
				new weaponIndex = -1;

				for (new i = nextIndex; i < MAX_CUSTOM_WEAPONS; i++)
				{
					// Select indexes of status free or config
					if (g_WeaponModelInfo[i][WeaponModelInfo_Status] < WeaponModelInfoStatus_API)
					{
						weaponIndex = i;

						break;
					}
				}

				if (weaponIndex == -1)
				{
					LogError("Out of weapon indexes! Change MAX_CUSTOM_WEAPONS in source code to increase limit");

					break;
				}

				KvGetSectionName(kv, buffer, sizeof(buffer));

				new defIndex;

				// Check if string is numeral
				if (StringToIntEx(buffer, defIndex) != strlen(buffer))
				{
					defIndex = -1;

					strcopy(g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ClassName], CLASS_NAME_MAX_LENGTH, buffer);
				}
				else if (defIndex < 0)
				{
					LogError("Item definition index %i is invalid (Weapon index %i)", defIndex, weaponIndex + 1);

					continue;
				}

				g_WeaponModelInfo[weaponIndex][WeaponModelInfo_DefIndex] = defIndex;

				KvGetString(kv, "ViewModel", g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ViewModel], PLATFORM_MAX_PATH + 1);
				KvGetString(kv, "WorldModel", g_WeaponModelInfo[weaponIndex][WeaponModelInfo_WorldModel], PLATFORM_MAX_PATH + 1);

				PrecacheWeaponInfo(weaponIndex);

				g_WeaponModelInfo[weaponIndex][WeaponModelInfo_TeamNum] = KvGetNum(kv, "TeamNum");
				g_WeaponModelInfo[weaponIndex][WeaponModelInfo_BlockLAW] = KvGetNum(kv, "BlockLAW") > 0;

				g_WeaponModelInfo[weaponIndex][WeaponModelInfo_NumAnims] = -1;
				g_WeaponModelInfo[weaponIndex][WeaponModelInfo_Status] = WeaponModelInfoStatus_Config;

				nextIndex = weaponIndex + 1;
			}
			while (KvGotoNextKey(kv));
		}

		CloseHandle(kv);
	}
	else
	{
		SetFailState("Failed to open config file: \"%s\"!", path);
	}

	BuildPath(Path_SM, path, sizeof(path), "configs/weaponmodels_downloadlist.cfg");

	new Handle:file = OpenFile(path, "r");

	if (file)
	{
		while (!IsEndOfFile(file) && ReadFileLine(file, buffer, sizeof(buffer)))
		{
			if (SplitString(buffer, "//", buffer, sizeof(buffer)) == 0)
			{
				continue;
			}

			if (TrimString(buffer))
			{
				if (FileExists(buffer))
				{
					AddFileToDownloadsTable(buffer);
				}
				else
				{
					LogError("File \"%s\" was not found!", buffer);
				}
			}
		}

		CloseHandle(file);
	}
	else
	{
		LogError("Failed to open config file: \"%s\" !", path);
	}
}

public OnClientPostAdminCheck(client)
{
	g_ClientInfo[client][ClientInfo_ViewModels] = { -1, -1 };
	g_ClientInfo[client][ClientInfo_CustomWeapon] = 0;

	SDKHook(client, SDKHook_SpawnPost, OnClientSpawnPost);
	SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitchPost);
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

public OnClientSpawnPost(client)
{
	// No spectators
	if (GetClientTeam(client) < 2)
	{
		return;
	}

	g_ClientInfo[client][ClientInfo_CustomWeapon] = 0;

	new viewModel1 = GetViewModel(client, 0);
	new viewModel2 = GetViewModel(client, 1);

	// If a secondary view model doesn't exist, create one
	if (viewModel2 == -1)
	{
		if ((viewModel2 = CreateEntityByName(g_szViewModelClassName)) == -1)
		{
			LogError("Failed to create secondary view model!");

			return;
		}

		SetEntDataEnt2(viewModel2, g_iOffset_Owner, client, true);
		SetEntData(viewModel2, g_iOffset_ViewModelIndex, 1, _, true);

		DispatchSpawn(viewModel2);

		SetViewModel(client, 1, viewModel2);
	}

	g_ClientInfo[client][ClientInfo_ViewModels][0] = EntIndexToEntRef(viewModel1);
	g_ClientInfo[client][ClientInfo_ViewModels][1] = EntIndexToEntRef(viewModel2);

	// Hide the secondary view model, in case the player has respawned
	ShowViewModel(viewModel2, false);

	new activeWeapon = GetEntDataEnt2(client, g_iOffset_ActiveWeapon);

	OnWeaponSwitch(client, activeWeapon);
	OnWeaponSwitchPost(client, activeWeapon);
}

GetViewModel(client, index)
{
	return GetEntDataEnt2(client, g_iOffset_ViewModel + index * 4);
}

SetViewModel(client, index, viewModel)
{
	SetEntDataEnt2(client, g_iOffset_ViewModel + index * 4, viewModel);
}

ShowViewModel(viewModel, bool:show)
{
	new flags = GetEntData(viewModel, g_iOffset_Effects);

	SetEntData(viewModel, g_iOffset_Effects, show ? flags & ~EF_NODRAW : flags | EF_NODRAW, _, true);
}

public Action:OnWeaponSwitch(client, weapon)
{
	new viewModel1 = EntRefToEntIndex(g_ClientInfo[client][ClientInfo_ViewModels][0]);
	new viewModel2 = EntRefToEntIndex(g_ClientInfo[client][ClientInfo_ViewModels][1]);

	if (viewModel1 == -1 || viewModel2 == -1)
	{
		return Plugin_Continue;
	}

	decl String:className[CLASS_NAME_MAX_LENGTH];
	if (!GetEdictClassname(weapon, className, sizeof(className)))
	{
		return Plugin_Continue;
	}

	for (new i; i < MAX_CUSTOM_WEAPONS; i++)
	{
		// Skip unused indexes
		if (g_WeaponModelInfo[i][WeaponModelInfo_Status] == WeaponModelInfoStatus_Free)
		{
			continue;
		}

		if (g_WeaponModelInfo[i][WeaponModelInfo_DefIndex] != -1)
		{
			if (g_iOffset_ItemDefinitionIndex == -1)
			{
				LogError("Game does not support item definition index! (Weapon index %i)", i + 1);

				continue;
			}

			new itemDefIndex = GetEntData(weapon, g_iOffset_ItemDefinitionIndex);

			if (g_WeaponModelInfo[i][WeaponModelInfo_DefIndex] != itemDefIndex)
			{
				continue;
			}

			if (g_WeaponModelInfo[i][WeaponModelInfo_Forward] && !ExecuteForward(i, client, weapon, className, itemDefIndex))
			{
				continue;
			}
		}
		else if (!StrEqual(className, g_WeaponModelInfo[i][WeaponModelInfo_ClassName], false))
		{
			continue;
		}
		else if (g_WeaponModelInfo[i][WeaponModelInfo_Forward])
		{
			if (!ExecuteForward(i, client, weapon, className))
			{
				continue;
			}
		}
		else if (g_WeaponModelInfo[i][WeaponModelInfo_TeamNum] && g_WeaponModelInfo[i][WeaponModelInfo_TeamNum] != GetClientTeam(client))
		{
			continue;
		}

		g_ClientInfo[client][ClientInfo_CustomWeapon] = weapon;
		g_ClientInfo[client][ClientInfo_weaponIndex] = i;

		return Plugin_Continue;
	}

	// Hide secondary view model if player has switched from a custom to a regular weapon
	if (g_ClientInfo[client][ClientInfo_CustomWeapon])
	{
		g_ClientInfo[client][ClientInfo_CustomWeapon] = 0;
		g_ClientInfo[client][ClientInfo_weaponIndex] = -1;
		g_ClientInfo[client][ClientInfo_ToggleSequence] = !g_ClientInfo[client][ClientInfo_ToggleSequence];
	}

	return Plugin_Continue;
}

bool:ExecuteForward(weaponIndex, client, weapon, const String:className[], itemDefIndex=-1)
{
	new Handle:forwardHandle = g_WeaponModelInfo[weaponIndex][WeaponModelInfo_Forward];

	// Clean-up, if required
	if (!GetForwardFunctionCount(forwardHandle))
	{
		CloseHandle(forwardHandle);

		g_WeaponModelInfo[weaponIndex][WeaponModelInfo_Status] = WeaponModelInfoStatus_Free;

		return false;
	}

	Call_StartForward(g_WeaponModelInfo[weaponIndex][WeaponModelInfo_Forward]);

	Call_PushCell(weaponIndex);
	Call_PushCell(client);
	Call_PushCell(weapon);
	Call_PushString(className);
	Call_PushCell(itemDefIndex);

	new bool:result;
	Call_Finish(result);

	return result;
}

public OnWeaponSwitchPost(client, weapon)
{
	// Callback is sometimes called on disconnected clients
	if (!IsClientConnected(client))
	{
		return;
	}

	new viewModel1 = EntRefToEntIndex(g_ClientInfo[client][ClientInfo_ViewModels][0]);
	new viewModel2 = EntRefToEntIndex(g_ClientInfo[client][ClientInfo_ViewModels][1]);

	if (viewModel1 == -1 || viewModel2 == -1)
	{
		return;
	}

	new weaponIndex = g_ClientInfo[client][ClientInfo_weaponIndex];

	if (weapon != g_ClientInfo[client][ClientInfo_CustomWeapon])
	{
		// Hide the secondary view model. This needs to be done on post because the weapon needs to be switched first
		if (weaponIndex == -1)
		{
			ShowViewModel(viewModel1, true);
			SDKCall(g_hSDKCall_UpdateTransmitState, viewModel1);

			ShowViewModel(viewModel2, false);
			SDKCall(g_hSDKCall_UpdateTransmitState, viewModel2);

			g_ClientInfo[client][ClientInfo_weaponIndex] = 0;
		}

		return;
	}

	if (g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ViewModelIndex])
	{
		ShowViewModel(viewModel1, false);
		ShowViewModel(viewModel2, true);

		if (g_iEngineVersion == Engine_CSGO)
		{
			StopParticleEffects(client, viewModel2);
		}

		if (g_bPredictedWeaponSwitch)
		{
			new sequence = GetEntData(viewModel1, g_iOffset_Sequence);

			g_ClientInfo[client][ClientInfo_DrawSequence] = sequence;
			g_ClientInfo[client][ClientInfo_LastSequence] = sequence;
			// UpdateTransmitStateTime needs to be delayed a bit to prevent the drawing sequence from locking up and being repeatedly played client-side
			g_ClientInfo[client][ClientInfo_UpdateTransmitStateTime] = GetGameTime() + 0.5;

			// Switch to an invalid sequence to prevent it from playing sounds before UpdateTransmitStateTime() is called
			SetEntData(viewModel1, g_iOffset_Sequence, -2, _, true);
		}
		else
		{
			g_ClientInfo[client][ClientInfo_LastSequence] = -1;

			SDKCall(g_hSDKCall_UpdateTransmitState, viewModel1);
		}

		SetEntityModel(weapon, g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ViewModel]);

		if (g_WeaponModelInfo[weaponIndex][WeaponModelInfo_NumAnims] == -1)
		{
			new Address:pStudioHdr = Address:GetEntData(weapon, g_iOffset_StudioHdr), numAnims;

			// Check if StudioHdr is valid
			if (pStudioHdr >= Address_MinimumValid && (pStudioHdr = Address:LoadFromAddress(pStudioHdr, NumberType_Int32)) >= Address_MinimumValid)
			{
				numAnims = LoadFromAddress(pStudioHdr + Address:g_iOffset_SequenceCount, NumberType_Int32) / 2;
			}
			else
			{
				LogError("Failed to get StudioHdr for weapon using model \"%s\" - Animations may not work as expected", g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ViewModel]);
			}

			g_WeaponModelInfo[weaponIndex][WeaponModelInfo_NumAnims] = numAnims;
		}

		SetEntDataEnt2(viewModel2, g_iOffset_Weapon, weapon, true);
		SetEntData(viewModel2, g_iOffset_ModelIndex, g_WeaponModelInfo[weaponIndex][WeaponModelInfo_ViewModelIndex], _, true);
		SetEntDataFloat(viewModel2, g_iOffset_PlaybackRate, GetEntDataFloat(viewModel1, g_iOffset_PlaybackRate), true);
	}
	else
	{
		g_ClientInfo[client][ClientInfo_CustomWeapon] = 0;
	}

	if (g_WeaponModelInfo[weaponIndex][WeaponModelInfo_WorldModelIndex])
	{
		SetEntData(weapon, g_iOffset_WorldModelIndex, g_WeaponModelInfo[weaponIndex][WeaponModelInfo_WorldModelIndex], _, true);
	}
}

public OnClientPostThinkPost(client)
{
	// Callback is sometimes called on disconnected clients
	if (!IsClientConnected(client))
	{
		return;
	}

	if (!g_ClientInfo[client][ClientInfo_CustomWeapon])
	{
		return;
	}

	new viewModel1 = EntRefToEntIndex(g_ClientInfo[client][ClientInfo_ViewModels][0]);
	new viewModel2 = EntRefToEntIndex(g_ClientInfo[client][ClientInfo_ViewModels][1]);

	if (viewModel1 == -1 || viewModel2 == -1)
	{
		return;
	}

	ShowViewModel(viewModel1, false);

	new sequence = GetEntData(viewModel1, g_iOffset_Sequence);

	if (g_bPredictedWeaponSwitch)
	{
		new Float:updateTransmitStateTime = g_ClientInfo[client][ClientInfo_UpdateTransmitStateTime];

		if (updateTransmitStateTime && GetGameTime() > updateTransmitStateTime)
		{
			SDKCall(g_hSDKCall_UpdateTransmitState, viewModel1);

			g_ClientInfo[client][ClientInfo_UpdateTransmitStateTime] = 0.0;
		}

		if (sequence == -2)
		{
			sequence = g_ClientInfo[client][ClientInfo_DrawSequence];
		}
	}

	static newSequenceParityOffset;

	if (!newSequenceParityOffset)
	{
		InitDataMapOffset(newSequenceParityOffset, viewModel1, "m_nNewSequenceParity");
	}

	new sequenceParity = GetEntData(viewModel1, newSequenceParityOffset);

	if (sequence == g_ClientInfo[client][ClientInfo_LastSequence])
	{
		// Return if sequence hasn't finished
		if (sequenceParity == g_ClientInfo[client][ClientInfo_LastSequenceParity])
		{
			return;
		}

		g_ClientInfo[client][ClientInfo_ToggleSequence] = !g_ClientInfo[client][ClientInfo_ToggleSequence];
	}
	else
	{
		g_ClientInfo[client][ClientInfo_LastSequence] = sequence;
	}

	if (g_ClientInfo[client][ClientInfo_ToggleSequence])
	{
		new weaponIndex = g_ClientInfo[client][ClientInfo_weaponIndex];

		new numAnims = g_WeaponModelInfo[weaponIndex][WeaponModelInfo_NumAnims];

		if (numAnims)
		{
			// By adding this value you select the cloned animation instead
			sequence += numAnims;
		}
		else
		{
			// Make sure its not selecting the same sequence that is currently playing
			sequence = sequence ? 0 : 1;

			// Swap back animation next think
			g_ClientInfo[client][ClientInfo_LastSequence] = sequence;
			g_ClientInfo[client][ClientInfo_ToggleSequence] = false;
		}
	}

	SetEntData(viewModel2, g_iOffset_Sequence, sequence, _, true);

	g_ClientInfo[client][ClientInfo_LastSequenceParity] = sequenceParity;
}

InitDataMapOffset(&offset, entity, const String:propName[])
{
	if ((offset = FindDataMapOffs(entity, propName)) == -1)
	{
		SetFailState("Fatal Error: Failed to find offset: \"%s\"!", propName);
	}
}