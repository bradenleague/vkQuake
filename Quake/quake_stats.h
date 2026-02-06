/*
 * Quake stat and item definitions
 *
 * Shared between the engine (quakedef.h) and the UI layer (game_data_model.cpp).
 * Extracted to avoid duplicating these constants across the codebase.
 */

#ifndef QUAKE_STATS_H
#define QUAKE_STATS_H

//
// stats are integers communicated to the client by the server
//
// clang-format off
typedef enum
{
	MAX_CL_BASE_STATS	= 32,
	MAX_CL_STATS		= 256,

	STAT_HEALTH			= 0,
	STAT_FRAGS			= 1,
	STAT_WEAPON			= 2,
	STAT_AMMO			= 3,
	STAT_ARMOR			= 4,
	STAT_WEAPONFRAME	= 5,
	STAT_SHELLS			= 6,
	STAT_NAILS			= 7,
	STAT_ROCKETS		= 8,
	STAT_CELLS			= 9,
	STAT_ACTIVEWEAPON	= 10,
	STAT_NONCLIENT		= 11,	// first stat not included in svc_clientdata
	STAT_TOTALSECRETS	= 11,
	STAT_TOTALMONSTERS	= 12,
	STAT_SECRETS		= 13,	// bumped on client side by svc_foundsecret
	STAT_MONSTERS		= 14,	// bumped by svc_killedmonster
	STAT_ITEMS			= 15,	//replaces clc_clientdata info
	STAT_VIEWHEIGHT		= 16, // replaces clc_clientdata info
	STAT_VIEWZOOM		= 21, // DP
	STAT_IDEALPITCH		= 25, // nq-emu
	STAT_PUNCHANGLE_X	= 26, // nq-emu
	STAT_PUNCHANGLE_Y	= 27, // nq-emu
	STAT_PUNCHANGLE_Z	= 28, // nq-emu
} stat_t;

// stock defines
//
typedef enum
{
	IT_SHOTGUN			= 1,
	IT_SUPER_SHOTGUN	= 2,
	IT_NAILGUN			= 4,
	IT_SUPER_NAILGUN	= 8,
	IT_GRENADE_LAUNCHER	= 16,
	IT_ROCKET_LAUNCHER	= 32,
	IT_LIGHTNING		= 64,
	IT_SUPER_LIGHTNING	= 128,
	IT_SHELLS			= 256,
	IT_NAILS			= 512,
	IT_ROCKETS			= 1024,
	IT_CELLS			= 2048,
	IT_AXE				= 4096,
	IT_ARMOR1			= 8192,
	IT_ARMOR2			= 16384,
	IT_ARMOR3			= 32768,
	IT_SUPERHEALTH		= 65536,
	IT_KEY1				= 131072,
	IT_KEY2				= 262144,
	IT_INVISIBILITY		= 524288,
	IT_INVULNERABILITY	= 1048576,
	IT_SUIT				= 2097152,
	IT_QUAD				= 4194304,
	IT_SIGIL1			= (1<<28),
	IT_SIGIL2			= (1<<29),
	IT_SIGIL3			= (1<<30),
	IT_SIGIL4			= (1<<31),
} items_t;
// clang-format on

#endif /* QUAKE_STATS_H */
