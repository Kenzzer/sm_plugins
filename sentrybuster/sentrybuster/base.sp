static CEntityFactory EntityFactory;
static ConVar tf_bot_suicide_bomb_range;
static int g_particleExplosion[2];
static int g_particleImpact;

methodmap SentryBuster < CBaseCombatCharacter
{
	property int hTarget
	{
		public get()
		{
			return GetEntPropEnt(this.index, Prop_Data, "m_hTarget");
		}
		public set(int entity)
		{
			SetEntPropEnt(this.index, Prop_Data, "m_hTarget", entity);
		}
	}

	public static void Precache()
	{
		// If/When PrecacheScriptSound is fixed, these should no longer
		// be necessary
		PrecacheSound(")mvm/sentrybuster/mvm_sentrybuster_explode.wav");
		PrecacheSound(")mvm/sentrybuster/mvm_sentrybuster_spin.wav");
		PrecacheSound("mvm/sentrybuster/mvm_sentrybuster_loop.wav");
		PrecacheSound(")mvm/sentrybuster/mvm_sentrybuster_intro.wav");
	
		PrecacheSound("^mvm/sentrybuster/mvm_sentrybuster_step_01.wav");
		PrecacheSound("^mvm/sentrybuster/mvm_sentrybuster_step_02.wav");
		PrecacheSound("^mvm/sentrybuster/mvm_sentrybuster_step_03.wav");
		PrecacheSound("^mvm/sentrybuster/mvm_sentrybuster_step_04.wav");

		// Actual precache part
		PrecacheScriptSound("MVM.SentryBusterExplode");
		PrecacheScriptSound("MVM.SentryBusterSpin");
		PrecacheScriptSound("MVM.SentryBusterLoop");
		PrecacheScriptSound("MVM.SentryBusterIntro");
		PrecacheScriptSound("MVM.SentryBusterStep");

		PrecacheModel("models/bots/demo/bot_sentry_buster.mdl", true);

		g_particleExplosion[0] = PrecacheParticleSystem("explosionTrail_seeds_mvm");
		g_particleExplosion[1] = PrecacheParticleSystem("fluidSmokeExpl_ring_mvm");
		g_particleImpact = PrecacheParticleSystem("bot_impact_heavy");
	}

	public void Detonate()
	{
		int myTeam = this.GetProp(Prop_Data, "m_iTeamNum");

		float pos[3], ang[3];
		this.GetAbsOrigin(pos);
		this.GetAbsAngles(ang);

		TE_Particle(g_particleExplosion[0], pos, _, ang);
		TE_SendToAll();
		TE_Particle(g_particleExplosion[1], pos, _, ang);
		TE_SendToAll();
		
		EmitGameSoundToAll("MVM.SentryBusterExplode", .origin = pos);

		UTIL_ScreenShake(pos, 25.0, 5.0, 5.0, 1000.0, SHAKE_START, false);

		ArrayList victims = new ArrayList();
		int entity = -1;
		while ((entity = FindEntityByClassname(entity, "*")) != -1)
		{
			if (IsValidEntity(entity))
			{
				CBaseEntity victim = CBaseEntity(entity);
				if (victim.IsCombatCharacter() && victim.GetProp(Prop_Data, "m_iTeamNum") != myTeam)
				{
					victims.Push(victim);
				}
			}
		}

		float center[3], victimCenter[3], delta[3];
		this.WorldSpaceCenter(center);

		IVision vision = this.MyNextBotPointer().GetVisionInterface();

		for(int i = 0, max = victims.Length; i < max; ++i)
		{
			CBaseCombatCharacter victim = victims.Get(i);
			victim.WorldSpaceCenter(victimCenter);

			SubtractVectors(victimCenter, center, delta);

			if (GetVectorLength(delta) > tf_bot_suicide_bomb_range.FloatValue)
			{
				continue;
			}

			if (0 < victim.index && victim.index <= MaxClients)
			{
				int white[4] = { 255, 255, 255, 255 };
				UTIL_ScreenFade(victim.index, white, 1.0, 0.1, FFADE_IN);
			}

			if (vision.IsLineOfSightClearToEntity(victim.index))
			{
				float damage = float(victim.GetProp(Prop_Send, "m_iHealth"));
				SDKHooks_TakeDamage(victim.index, this.index, this.index, damage * 4, DMG_BLAST, _, CalculateMeleeDamageForce(damage, delta, 1.0), center);
			}
		}

		delete victims;
		RequestFrame(Frame_DeleteBuster, EntIndexToEntRef(this.index));
	}

	public void OnCreate()
	{
		this.SetProp(Prop_Data, "m_iHealth", 4500);
		this.SetPropFloat(Prop_Data, "m_flModelScale", 1.75);
		// We robots, don't bleed
		this.SetProp(Prop_Data, "m_bloodColor", -1);
		// For triggers
		this.AddFlag(FL_CLIENT);

		this.SetModel("models/bots/demo/bot_sentry_buster.mdl");
		this.SetProp(Prop_Data, "m_moveXPoseParameter", this.LookupPoseParameter("move_x"));
		this.SetProp(Prop_Data, "m_moveYPoseParameter", this.LookupPoseParameter("move_y"));
		this.SetProp(Prop_Data, "m_idleSequence", this.LookupSequence("Stand_MELEE"));
		this.SetProp(Prop_Data, "m_runSequence", this.LookupSequence("Run_MELEE"));
		this.SetProp(Prop_Data, "m_airSequence", this.LookupSequence("a_jumpfloat_ITEM1"));
		this.hTarget = INVALID_ENT_REFERENCE;

		SDKHook(this.index, SDKHook_SpawnPost, SentryBuster_SpawnPost);
		SDKHook(this.index, SDKHook_OnTakeDamageAlivePost, SentryBuster_OnTakeDamageAlivePost);
		this.Hook_HandleAnimEvent(SentryBuster_HandleAnimEvent);

		CBaseNPC npc = TheNPCs.FindNPCByEntIndex(this.index);

		npc.flStepSize = 18.0;
		npc.flGravity = 800.0;
		npc.flAcceleration = 2000.0;
		npc.flJumpHeight = 85.0;
		npc.flWalkSpeed = 440.0;
		npc.flRunSpeed = 440.0;
		npc.flDeathDropHeight = 2000.0;
	}

	public void OnSpawnPost()
	{
		EmitGameSoundToAll("MVM.SentryBusterLoop",  this.index);
	}
}

static Frame_DeleteBuster(int ref)
{
	int actor = EntRefToEntIndex(ref);
	if (actor != -1)
	{
		RemoveEntity(actor);
	}
}

static void SentryBuster_OnCreate(int entity)
{
	SentryBuster buster = view_as<SentryBuster>(entity);
	buster.OnCreate();
}

static void SentryBuster_SpawnPost(int entity)
{
	SentryBuster buster = view_as<SentryBuster>(entity);
	buster.OnSpawnPost();
}

public void SentryBuster_OnTakeDamageAlivePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3]) 
{
	int health = GetEntProp(victim, Prop_Data, "m_iHealth");
	if (health < 1)
	{
		health = 1;
		// We cannot die, no matter how. We go kaboom first
		SetEntProp(victim, Prop_Data, "m_iHealth", health);
	}

	TE_Particle(g_particleImpact, damagePosition);
	TE_SendToAll();

	Event event = CreateEvent("npc_hurt");
	if (event) 
	{
		event.SetInt("entindex", victim);
		event.SetInt("health", health > 0 ? health : 0);
		event.SetInt("damageamount", RoundToFloor(damage));
		event.SetBool("crit", (damagetype & DMG_ACID) == DMG_ACID);

		if (attacker > 0 && attacker <= MaxClients)
		{
			event.SetInt("attacker_player", GetClientUserId(attacker));
			event.SetInt("weaponid", 0);
		}
		else 
		{
			event.SetInt("attacker_player", 0);
			event.SetInt("weaponid", 0);
		}

		event.Fire();
	}
}

static void SentryBuster_OnRemove(int entity)
{
	StopSound(entity, SNDCHAN_STATIC, "mvm/sentrybuster/mvm_sentrybuster_loop.wav");
}

static MRESReturn SentryBuster_HandleAnimEvent(int actor, Handle hParams)
{
	int event = DHookGetParamObjectPtrVar(hParams, 1, 0, ObjectValueType_Int);
	if (event == 7001)
	{
		EmitGameSoundToAll("MVM.SentryBusterStep", actor);
	}
	return MRES_Ignored;
}

void SentryBuster_Init()
{
	SentryBusterExplode_Init();
	SentryBusterMain_InitBehavior();

	tf_bot_suicide_bomb_range = FindConVar("tf_bot_suicide_bomb_range");

	EntityFactory = new CEntityFactory("cbasenpc_sentry_buster", SentryBuster_OnCreate, SentryBuster_OnRemove);
	EntityFactory.DeriveFromNPC();
	EntityFactory.SetInitialActionFactory(SentryBusterMain_GetFactory());
	EntityFactory.BeginDataMapDesc()
		.DefineIntField("m_moveXPoseParameter")
		.DefineIntField("m_moveYPoseParameter")
		.DefineIntField("m_idleSequence")
		.DefineIntField("m_runSequence")
		.DefineIntField("m_airSequence")
		.DefineEntityField("m_hTarget")
	.EndDataMapDesc();

	EntityFactory.Install();
}

#include "behavior/explode.sp"
#include "behavior/main.sp"