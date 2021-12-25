#include <sourcemod>
#include <dhooks>
#include <cbasenpc>
#include <sdktools>
#include <sdkhooks>

#define FFADE_IN			0x0001		// Just here so we don't pass 0 into the function
#define FFADE_OUT			0x0002		// Fade out (not in)
#define FFADE_MODULATE		0x0004		// Modulate (don't blend)
#define FFADE_STAYOUT		0x0008		// ignores the duration, stays faded out until new ScreenFade message received
#define FFADE_PURGE			0x0010		// Purges all other fades, replacing them with this one
#define SCREENFADE_FRACBITS	9

enum ShakeCommand_t
{
	SHAKE_START = 0,
	SHAKE_STOP,
	SHAKE_AMPLITUDE,
	SHAKE_FREQUENCY,
	SHAKE_START_RUMBLEONLY,
	SHAKE_START_NORUMBLE,
};

ConVar phys_pushscale;

#include "sentrybuster/base.sp"

public void OnPluginStart()
{
	phys_pushscale = FindConVar("phys_pushscale");
	SentryBuster_Init();

	RegConsoleCmd("sm_bust", Command_Buster);
}

public void OnMapStart()
{
	SentryBuster.Precache();
}

public Action Command_Buster(int client, int args)
{
	if (client == 0)
	{
		return Plugin_Continue;
	}

	SentryBuster buster = view_as<SentryBuster>(CreateEntityByName("cbasenpc_sentry_buster"));
	if (buster.index != -1)
	{
		ArrayList spawns = new ArrayList();
		int spawn = -1;
		while ((spawn = FindEntityByClassname(spawn, "info_player_teamspawn")) != -1)
		{
			if (GetEntProp(spawn, Prop_Data, "m_iTeamNum") == 3)
			{
				spawns.Push(spawn);
			}
		}

		CBaseEntity teamSpawn = CBaseEntity(spawns.Get(GetRandomInt(0, spawns.Length - 1)));
		float pos[3];
		teamSpawn.GetAbsOrigin(pos);

		buster.Teleport(pos);
		buster.hTarget = client;
		buster.SetProp(Prop_Data, "m_iTeamNum", 3); 
		buster.Spawn();
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

stock int FindStringIndex2(int tableidx, const char[] str)
{
	char buf[1024];
	int numStrings = GetStringTableNumStrings(tableidx);
	for (int idx = 0; idx < numStrings; idx++)
	{
		ReadStringTable(tableidx, idx, buf, sizeof(buf));
		if (strcmp(buf, str) == 0) 
		{
			return idx;
		}
	}
	
	return INVALID_STRING_INDEX;
}

stock int PrecacheParticleSystem(const char[] particleSystem)
{
	static int particleEffectNames = INVALID_STRING_TABLE;
	if (particleEffectNames == INVALID_STRING_TABLE) 
	{
		if ((particleEffectNames = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE) 
		{
			return INVALID_STRING_INDEX;
		}
	}

	int index = FindStringIndex2(particleEffectNames, particleSystem);
	if (index == INVALID_STRING_INDEX) 
	{
		int numStrings = GetStringTableNumStrings(particleEffectNames);
		if (numStrings >= GetStringTableMaxStrings(particleEffectNames)) 
		{
			return INVALID_STRING_INDEX;
		}
		
		AddToStringTable(particleEffectNames, particleSystem);
		index = numStrings;
	}
	
	return index;
}

void TE_Particle(int iParticleIndex, const float origin[3] = NULL_VECTOR, const float start[3] = NULL_VECTOR,
const float angles[3] = NULL_VECTOR, int entindex = -1, int attachtype = -1, int attachpoint = -1, bool resetParticles = true)
{
    TE_Start("TFParticleEffect");
    TE_WriteFloat("m_vecOrigin[0]", origin[0]);
    TE_WriteFloat("m_vecOrigin[1]", origin[1]);
    TE_WriteFloat("m_vecOrigin[2]", origin[2]);
    TE_WriteFloat("m_vecStart[0]", start[0]);
    TE_WriteFloat("m_vecStart[1]", start[1]);
    TE_WriteFloat("m_vecStart[2]", start[2]);
    TE_WriteVector("m_vecAngles", angles);
    TE_WriteNum("m_iParticleSystemIndex", iParticleIndex);
    TE_WriteNum("entindex", entindex);

    if (attachtype != -1)
    {
        TE_WriteNum("m_iAttachType", attachtype);
    }

    if (attachpoint != -1)
    {
        TE_WriteNum("m_iAttachmentPointIndex", attachpoint);
    }
    TE_WriteNum("m_bResetParticles", resetParticles ? 1 : 0);
}

stock int FixedUnsigned16(float value, int scale)
{
	int output;

	output = RoundToFloor(value * float(scale));
	if (output < 0)
	{
		output = 0;
	}
	if (output > 0xFFFF)
	{
		output = 0xFFFF;
	}

	return output;
}

public void UTIL_ScreenFade(int player, int color[4], float fadeTime, float fadeHold, int flags)
{
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("Fade", player, USERMSG_RELIABLE));
	if (bf != null)
	{
		bf.WriteShort(FixedUnsigned16(fadeTime, 1 << SCREENFADE_FRACBITS));
		bf.WriteShort(FixedUnsigned16(fadeHold, 1 << SCREENFADE_FRACBITS));
		bf.WriteShort(flags);
		bf.WriteByte(color[0]);
		bf.WriteByte(color[1]);
		bf.WriteByte(color[2]);
		bf.WriteByte(color[3]);

		EndMessage();
	}
}

const float MAX_SHAKE_AMPLITUDE = 16.0;
void UTIL_ScreenShake(const float center[3], float amplitude, float frequency, float duration, float radius, ShakeCommand_t eCommand, bool bAirShake)
{
	float localAmplitude;

	if (amplitude > MAX_SHAKE_AMPLITUDE)
	{
		amplitude = MAX_SHAKE_AMPLITUDE;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || (!bAirShake && (eCommand == SHAKE_START) && !(GetEntityFlags(i) & FL_ONGROUND)))
		{
			continue;
		}

		CBaseCombatCharacter cb = CBaseCombatCharacter(i);
		float playerCenter[3];
		cb.WorldSpaceCenter(playerCenter);

		localAmplitude = ComputeShakeAmplitude(center, playerCenter, amplitude, radius);

		// This happens if the player is outside the radius, in which case we should ignore 
		// all commands
		if (localAmplitude < 0)
		{
			continue;
		}

		TransmitShakeEvent(i, localAmplitude, frequency, duration, eCommand);
	}
}

float ComputeShakeAmplitude(const float center[3], const float shake[3], float amplitude, float radius) 
{
	if (radius <= 0)
	{
		return amplitude;
	}

	float localAmplitude = -1.0;
	float delta[3];
	SubtractVectors(center, shake, delta);
	float distance = GetVectorLength(delta);

	if (distance <= radius)
	{
		// Make the amplitude fall off over distance
		float perc = 1.0 - (distance / radius);
		localAmplitude = amplitude * perc;
	}

	return localAmplitude;
}

void TransmitShakeEvent(int player, float localAmplitude, float frequency, float duration, ShakeCommand_t eCommand)
{
	if ((localAmplitude > 0.0 ) || (eCommand == SHAKE_STOP))
	{
		if (eCommand == SHAKE_STOP)
		{
			localAmplitude = 0.0;
		}

		BfWrite msg = UserMessageToBfWrite(StartMessageOne("Shake", player, USERMSG_RELIABLE));
		if (msg != null)
		{
			msg.WriteByte(view_as<int>(eCommand));
			msg.WriteFloat(localAmplitude);
			msg.WriteFloat(frequency);
			msg.WriteFloat(duration);

			EndMessage();
		}
	}
} 

float[3] CalculateMeleeDamageForce(float damage, const float vecMeleeDir[3], float scale)
{
	// Calculate an impulse large enough to push a 75kg man 4 in/sec per point of damage
	float forceScale = damage * 75 * 4;
	float vecForce[3];
	NormalizeVector(vecMeleeDir, vecForce);
	ScaleVector(vecForce, forceScale);
	ScaleVector(vecForce, phys_pushscale.FloatValue);
	ScaleVector(vecForce, scale);
	return vecForce;
}