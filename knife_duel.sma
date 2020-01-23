/*
    Credits:
        - mogel: drawing the mins and maxs taken from his walkguardmenu.
        - sTyLa: took the duel model from her server.        
        - me: took part of the challenge code from my rush duel plugin.
*/
#include < amxmodx >
#include < amxmisc >
#include < fakemeta >
#include < hamsandwich >
#include < regex >
#include < xs >

#define set_bit(%1,%2)      (%1 |= (1<<(%2&31)))
#define clear_bit(%1,%2)    (%1 &= ~(1<<(%2&31)))
#define check_bit(%1,%2)    (%1 & (1<<(%2&31)))

#if AMXX_VERSION_NUM < 183
    set_fail_state( "Plugin requires 1.8.3 or higher." );
#endif

// --------- Editable Stuff ---------

#define ADMIN_FLAG          ADMIN_LEVEL_A
#define MAX_ARENA           4
#define PREFIX              "^4[KNIFE]^1"

new const szModel[] = "models/knife_duel/duel_platform.mdl";

new const szCmds[][] =
{
    "say /kd",
    "say kd",
    "say /duel",
    "say duel",
    "say /knifeduel",
    "say knifeduel",
    "kd_menu"
};

new const szStopCmds[][] = 
{
    "say /stop",
    "say /stopduel",
    "say /stopkd",
    "stop_duel"
};
// ----------------------------------

#define pev_rplayer1        pev_iuser1
#define pev_rplayer2        pev_iuser2
#define pev_rtotal          pev_iuser3
#define pev_rfake           pev_iuser4

new const Float:MAX_DISTANCE  =   550.0;
new const Float:MIN_DISTANCE  =   250.0;

new const Float:MAX_LONGTIME  =   200.0;
new const Float:MIN_LONGTIME  =   30.0;

new const Float:MAX_SMALLTIME =   60.0;
new const Float:MIN_SMALLTIME =   3.0;

new const VERSION[] = "1.1.0";

new const DisableAccess = ( 1 << 26 );
const iWalls = 5;

new activeArenas, busyArenas;
new bIsArenaBusy
new iArenaEnt[ MAX_ARENA ];
new iArenaWall[ MAX_ARENA ][ iWalls ];
new Float:iOrigin[ MAX_ARENA ][ 3 ];

new const Float:fUnit[] =
{
    1.0,
    5.0,
    10.0,
    25.0,
    50.0,
    100.0
};

new currUnit = 3;

enum _:eWalls
{
    SIDE_BACK = 0,
    SIDE_FORWARD,
    SIDE_LEFT,
    SIDE_RIGHT,
    SIDE_UP
};
enum _:attType
{
    BOTH = 0,
    SLASH,
    STAB
}
enum _:duelData
{
    PLAYER1 = 0,
    PLAYER2,
    DUELTYPE
}
enum _:eLastData
{
    IPLAYER1 = 0,
    IPLAYER2,
    IROUND1,
    IROUND2,
    IWINNER,
    IREASON,
    IPOS,
    IARENA
}
enum _:eEndDuelReason
{
    NONE = 0,
    FAKE_ROUNDS,
    TIME_END,
    PLAYER_STOP,
    PLAYER_DISCONNECTED
}
enum _:eTaskIds ( += 1000 )
{
    TASK_DRAW = 322,
    TASK_HP,
    TASK_DUELROUND,
    TASK_AUTOKILLEND,
    TASK_REVIVE,
    TASK_RESTART
}
enum _:eAliveData
{
    REVIVE_WINNER1 = 0,
    REVIVE_WINNER2,
    REVIVE_LAST,
    REVIVE_BOTH
}

new const Float:fMaxs[ 3 ] = { 337.0, 237.0, 4.0 };
new const Float:fMins[ 3 ] = { -337.0, -237.0, -4.0 };
new const Float:fSafeDistance = 25.0;
new const Float:fVerticalDistance = 300.0;
new const Float:fSafeSpawn = 50.0;

new knfDir[ 128 ];

new g_DuelInfo[ MAX_ARENA ][ duelData ];
new hasDisabledDuel;
new hasBlocked[ 33 ];
new bIsInDuel;
new Float:fLastDuel[ 33 ];
new bool:bCanDuel;

new Float:g_HealthCache[ MAX_ARENA ][ 2 ];
new Float:g_PosCache[ MAX_ARENA ][ 2 ][ 3 ];
new Float:fMapHp;

// -- draw -- 
new const szBeam[]  = "sprites/lgtning.spr";
new beam;
new editor, edit_zone;
new direction;
// ----------

new HamHook:PlayerSpawnPost, HamHook:PlayerKilledPre, HamHook:PlayerKilledPost;
new PlayerThink;

new pSaveHealth, pSavePos, pAttackType, pPunish;
new pFakeRounds, pRounds;
new pAlive;
new Float:pHealth[ attType ];
new Float:pDistance;
new Float:pSmallTime, Float:pLongTime;
new Float:pNextDuel;

public plugin_init()
{
    register_plugin( "Knife Duel", VERSION, "DusT" );
    create_cvar( "Knife_Duel_Dust", VERSION, FCVAR_SPONLY | FCVAR_SERVER );

    register_clcmd( "kd_arena_menu", "CmdArenaMenu", ADMIN_FLAG );

    for( new i; i < sizeof szCmds; i++ )
        register_clcmd( szCmds[ i ], "CmdMainMenu" );

    for( new i; i < sizeof szStopCmds; i++ )
        register_clcmd( szStopCmds[ i ], "CmdStopDuel" );

    bind_pcvar_float( create_cvar( "kd_health_slash", "1" , _, _, true, 0.0, true, 100.0 ), Float:pHealth[ SLASH ] );
    bind_pcvar_float( create_cvar( "kd_health_stab",  "35", _, _, true, 0.0, true, 100.0 ), Float:pHealth[ STAB ]  );
    bind_pcvar_float( create_cvar( "kd_health_both",  "0" , _, _, true, 0.0, true, 100.0 ), Float:pHealth[ BOTH ]  );
    bind_pcvar_float( create_cvar( "kd_players_distance", "500", _, _, true, MIN_DISTANCE, true, MAX_DISTANCE ), pDistance );
    bind_pcvar_float( create_cvar( "kd_max_round_time", "10", _, "0 to disable. After this time passed on one round, round will restart.",  true, 0.0, true, MAX_SMALLTIME ), pSmallTime );
    bind_pcvar_float( create_cvar( "kd_max_duel_time", "100", _, "0 to disable. After this time passed on the duel, duel will be stopped.", true, 0.0, true, MAX_LONGTIME  ), pLongTime  );
    bind_pcvar_float( create_cvar( "kd_cooldown", "10", _, _, true, 0.0 ), pNextDuel );

    bind_pcvar_num( create_cvar( "kd_stop_punish", "0", _, "0:Nothing, 1:slay, 2+:increase cooldown by the number", true, 0.0), pPunish );    
    bind_pcvar_num( create_cvar( "kd_save_health", "1", _, _, true, 0.0, true, 1.0 ), pSaveHealth );
    bind_pcvar_num( create_cvar( "kd_save_pos", "1", _, _, true, 0.0, true, 1.0 ), pSavePos );
    bind_pcvar_num( create_cvar( "kd_rounds", "10", _, _, true, 1.0 ), pRounds );
    /*
        description:
            - 0: both
            - 1: slash / m1 
            - 2: stab / m2
            - 3: allow player to choose
    */
    bind_pcvar_num( create_cvar( "kd_attack_type", "0", _, "more info at github.com/amxDusT/KnifeDuel-amxx", true, 0.0, true, 3.0 ), pAttackType );
    /*
        if kd_max_round_time expires or duel player gets killed not by enemy the round is not counted, but it gets added to the
        not counted round ("fake rounds").
        Once fake rounds reaches kd_fake_rounds cvar, the duel is interrupted. 
    */
    bind_pcvar_num( create_cvar( "kd_fake_rounds", "5", _, "more info at github.com/amxDusT/KnifeDuel-amxx", true, 0.0 ), pFakeRounds );
    /*
        description:
            - 0: revives who won the round. In case of draw, both revive.
            - 1: revives who won the round. In case of draw, both dead.
            - 2: revives who killed the player on last round. 
            - 3: both revive.
    */
    bind_pcvar_num( create_cvar( "rush_alive", "3", _, "Info on github.com/amxDust/KnifeDuel-amxx", true, 0.0, true, 3.0 ), pAlive );

    DisableHamForward( PlayerKilledPost = RegisterHamPlayer( Ham_Killed, "fw_PlayerKilled_Post", 1 ) ); 
    DisableHamForward( PlayerKilledPre  = RegisterHamPlayer( Ham_Killed, "fw_PlayerKilled_Pre",  0 ) ); 
    DisableHamForward( PlayerSpawnPost  = RegisterHamPlayer( Ham_Spawn,  "fw_PlayerSpawn_Post",  1 ) );

    register_logevent( "RoundStart", 2, "1=Round_Start" );
    register_logevent( "RoundEnd"  , 2, "1=Round_End"   );

    activeArenas = GetArenas();
}

public plugin_natives()
{
    register_native( "is_user_in_duel", "_is_user_in_duel" );
}

public plugin_precache()
{
    precache_model( szModel );
    beam = precache_model( szBeam );
}

public client_disconnected( id )
{
    if( check_bit( bIsInDuel, id ) )
    {
        StopDuelPre( GetArena( id ), PLAYER_DISCONNECTED, id );
    }

    fLastDuel[ id ] = 0.0;
    hasBlocked[ id ] = 0;
    if( check_bit( hasDisabledDuel, id ) )
        clear_bit( hasDisabledDuel, id );
}

// mostly to avoid maps where you spawn with 100hp and then it gets removed by falling or an entity under the spawn
// so hp doesn't save to 100 when duel is over. 
public RoundStart()
{
    set_task( 2.0, "AllowDuel" );
}

public RoundEnd()
{
    bCanDuel = false;
}

public AllowDuel()
{
    bCanDuel = true;
}

public fw_PlayerThink_Pre( id )
{
    if( check_bit( bIsInDuel, id ) )
    {
        switch( g_DuelInfo[ GetArena( id ) ][ DUELTYPE ] )
        {
            case STAB:
            {
                new btn = pev( id, pev_button );
                if( btn & IN_ATTACK )
                {
                    set_pev( id, pev_button, ( btn & ~IN_ATTACK ) | IN_ATTACK2 );
                } 
            }
            case SLASH:
            {
                new btn = pev( id, pev_button );
                if( btn & IN_ATTACK2 )
                {
                    set_pev( id, pev_button, ( btn & ~IN_ATTACK2 ) | IN_ATTACK );
                }
            }
        }
    }
    return FMRES_IGNORED;
}

public fw_PlayerKilled_Post( victim, killer )
{
    if( check_bit( bIsInDuel, victim ) )
    {
        new arena = GetArena( victim );
        new pos = GetPos( victim, arena );

        if( task_exists( arena + TASK_DUELROUND ) )
            remove_task( arena + TASK_DUELROUND );
        
        if( killer != g_DuelInfo[ arena ][ 1 - pos ] )
        {
            new fakeRounds = pev( iArenaEnt[ arena ], pev_rfake ) + 1;
            if( fakeRounds >= pFakeRounds )
                StopDuelPre( arena, FAKE_ROUNDS )
            else
                set_pev( iArenaEnt[ arena ], pev_rfake, fakeRounds );
        }
        else
        {
            set_pev( iArenaEnt[ arena ], pev_rplayer1 + ( 1 - pos ), pev( iArenaEnt[ arena ], pev_rplayer1 + ( 1 - pos ) ) + 1 );
            
            new rTotal = pev( iArenaEnt[ arena ], pev_rtotal ) + 1;
            if( rTotal >= pRounds )
                StopDuelPre( arena );
            else
                set_pev( iArenaEnt[ arena ], pev_rtotal, rTotal );
        }

        if( check_bit( bIsInDuel, victim ) )
        {
            set_task( 0.1, "ReviveDead", victim + TASK_REVIVE );
            if( !task_exists( arena + TASK_RESTART ) )
                set_task( 0.5, "CallBackTeleportPlayer", arena + TASK_RESTART );
        }
    }
    return HAM_IGNORED;
}

public ReviveDead( id )
{
    id -= TASK_REVIVE;

    ExecuteHamB( Ham_CS_RoundRespawn, id );
}

public CallBackTeleportPlayer( arena )
{
    arena -= TASK_RESTART;

    TeleportPlayer( g_DuelInfo[ arena ][ PLAYER1 ], g_DuelInfo[ arena ][ PLAYER2 ], arena );
}

public fw_PlayerKilled_Pre( victim, killer )
{
    static msgCorpse;
    if( check_bit( bIsInDuel, victim ) )
    {
        if( msgCorpse || ( msgCorpse = get_user_msgid( "ClCorpse" ) ) )
            set_msg_block( msgCorpse, BLOCK_ONCE );
        return HAM_HANDLED;
    }
    return HAM_IGNORED;
}

public fw_PlayerSpawn_Post( id )
{
    if( check_bit( bIsInDuel, id ) )
    {
        new arena = GetArena( id );
        if( !task_exists( arena + TASK_RESTART ) )
        {
            if( task_exists( arena + TASK_DUELROUND ) )
                remove_task( arena + TASK_DUELROUND );
            set_task( 0.5, "CallBackTeleportPlayer", arena + TASK_RESTART );
        }
    }
    return HAM_IGNORED;
}

StopDuelPre( arena, reason = NONE, player = 0 )
{
    new param[ eLastData ];

    param[ PLAYER1 ] = g_DuelInfo[ arena ][ PLAYER1 ];
    param[ PLAYER2 ] = g_DuelInfo[ arena ][ PLAYER2 ];
    param[ IROUND1 ] = pev( iArenaEnt[ arena ], pev_rplayer1 );
    param[ IROUND2 ] = pev( iArenaEnt[ arena ], pev_rplayer2 );
    param[ IREASON ] = reason;
    param[ IARENA ]  = arena;

    if( player )
        param[ IPOS ] = GetPos( player, arena );

    clear_bit( bIsInDuel, param[ PLAYER1 ] );
    clear_bit( bIsInDuel, param[ PLAYER2 ] );

    fLastDuel[ param[ PLAYER1 ] ] = get_gametime();
    fLastDuel[ param[ PLAYER2 ] ] = get_gametime();

    if( task_exists( arena + TASK_RESTART ) )
        remove_task( arena + TASK_RESTART );
    
    if( task_exists( arena + TASK_AUTOKILLEND ) )
        remove_task( arena + TASK_AUTOKILLEND );
    
    if( task_exists( arena + TASK_DUELROUND ) )
        remove_task( arena + TASK_DUELROUND );

    switch( reason )
    {
        case NONE:
        {
            if( param[ IROUND1 ] > param[ IROUND2 ] )
            {
                param[ IWINNER ] = param[ PLAYER1 ]; 
            }  
            else if( param[ IROUND2 ] > param[ IROUND1 ] )
            {
                param[ IWINNER ] = param[ PLAYER2 ];
                param[ IPOS ]    = PLAYER2;
            }
            else
                param[ IWINNER ] = 0;
            
            switch( pAlive )
            {
                case REVIVE_WINNER1, REVIVE_WINNER2:
                {
                    if( param[ IWINNER ] )
                    {
                        set_task( 0.1, "ReviveDead", param[ IWINNER ] + TASK_REVIVE );
                        if( is_user_alive( param[ 1 - param[ IPOS ] ] ) )
                            user_silentkill( param[ 1 - param[ IPOS ] ] );
                    }
                    else
                    {
                        if( pAlive == REVIVE_WINNER1 )
                        {
                            set_task( 0.1, "ReviveDead", param[ PLAYER1 ] + TASK_REVIVE );
                            set_task( 0.1, "ReviveDead", param[ PLAYER2 ] + TASK_REVIVE );
                        }
                        else 
                        {
                            if( is_user_alive( param[ PLAYER1 ] ) )
                                user_silentkill( param[ PLAYER1 ] );

                            if( is_user_alive( param[ PLAYER2 ] ) )
                                user_silentkill( param[ PLAYER2 ] );
                        }
                    }   
                }
                case REVIVE_LAST:
                {
                    if( is_user_alive( param[ PLAYER1 ] ) )
                        set_task( 0.1, "ReviveDead", param[ PLAYER1 ] + TASK_REVIVE );

                    if( is_user_alive( param[ PLAYER2 ] ) )
                        set_task( 0.1, "ReviveDead", param[ PLAYER2 ] + TASK_REVIVE );
                }
                case REVIVE_BOTH:
                {
                    set_task( 0.1, "ReviveDead", param[ PLAYER1 ] + TASK_REVIVE );
                    set_task( 0.1, "ReviveDead", param[ PLAYER2 ] + TASK_REVIVE );
                }
            }
        }
        case PLAYER_STOP:
        {
            param[ IWINNER ] = player;
            
            set_task( 0.1, "ReviveDead", param[ 1 - param[ IPOS ] ] + TASK_REVIVE );
            if( pPunish == 1 )
            {
                if( is_user_alive( player ) )
                    user_silentkill( player );
            }
            else if( pPunish > 1 )
            {
                fLastDuel[ player ] += float( pPunish );
            }
        }
        case PLAYER_DISCONNECTED:
        {
            param[ IWINNER ] = player;

            set_task( 0.1, "ReviveDead", param[ 1 - param[ IPOS ] ] + TASK_REVIVE );
        }
        case FAKE_ROUNDS: 
        {
            set_task( 0.1, "ReviveDead", param[ param[ IPOS ] ] + TASK_REVIVE );
            set_task( 0.1, "ReviveDead", param[ 1 - param[ IPOS ] ] + TASK_REVIVE );
        }
    }
    set_task( 0.5, "StopDuelPost", _, param, sizeof param );
}

public StopDuelPost( param[] )
{
    if( is_user_alive( param[ PLAYER1 ] ) )
    {
        if( pSaveHealth )
            set_pev( param[ PLAYER1 ], pev_health, g_HealthCache[ param[ IARENA ] ][ PLAYER1 ] );
        
        if( pSavePos )
        {
            set_pev( param[ PLAYER1 ], pev_velocity, Float:{ 0.0, 0.0, 0.0 } );
            set_pev( param[ PLAYER1 ], pev_origin, g_PosCache[ param[ IARENA ] ][ PLAYER1 ] );
        }
    }
    if( is_user_alive( param[ PLAYER2 ] ) )
    {
        if( pSaveHealth )
            set_pev( param[ PLAYER2 ], pev_health, g_HealthCache[ param[ IARENA ] ][ PLAYER2 ] );
        
        if( pSavePos )
        {
            set_pev( param[ PLAYER2 ], pev_velocity, Float:{ 0.0, 0.0, 0.0 } );
            set_pev( param[ PLAYER2 ], pev_origin, g_PosCache[ param[ IARENA ] ][ PLAYER2 ] );
        }   
    }

    fm_set_entity_visibility( iArenaEnt[ param[ IARENA ] ], 0 );
    set_ent_solid( param[ IARENA ], false );
    
    clear_bit( bIsArenaBusy, param[ IARENA ] );
    busyArenas--;
    
    if( !busyArenas )
        ToggleFwds( false );

    switch( param[ IREASON ] )
    {
        case NONE:
        {
            if( param[ IWINNER ] )
            {
                client_print_color( param[ IWINNER ], print_team_red, "%s You won against ^3%n^1 [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, param[ 1 - param[ IPOS ] ],  param[ param[ IPOS ] + 2 ], param[ ( 1 - param[ IPOS ] ) + 2 ], pRounds );
                client_print_color( param[ 1 - param[ IPOS ] ], print_team_red, "%s You lost against ^4%n^1 [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, param[ IWINNER ], param[ ( 1 - param[ IPOS ] ) + 2 ], param[ param[ IPOS ] + 2 ], pRounds );
            }
            else
            {
                client_print_color( param[ PLAYER1 ], print_team_red, "%s You draw against ^3%n^1 [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, param[ PLAYER2 ], param[ IROUND1 ], param[ IROUND2 ], pRounds );
                client_print_color( param[ PLAYER2 ], print_team_red, "%s You draw against ^3%n^1 [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, param[ PLAYER1 ], param[ IROUND2 ], param[ IROUND1 ], pRounds );
            }
        }
        case FAKE_ROUNDS:
        {
            client_print_color( param[ PLAYER1 ], print_team_red, "%s ^3Duel interrupted^1: too many blocked rounds.", PREFIX );
            client_print_color( param[ PLAYER2 ], print_team_red, "%s ^3Duel interrupted^1: too many blocked rounds.", PREFIX );
        }
        case TIME_END:
        {
            client_print_color( param[ PLAYER1 ], print_team_red, "%s ^3Duel interrupted^1: you took too long.", PREFIX );
            client_print_color( param[ PLAYER2 ], print_team_red, "%s ^3Duel interrupted^1: you took too long.", PREFIX );
        }
        case PLAYER_STOP:
        {
            client_print_color( param[ IWINNER ], print_team_red, "%s ^3Duel interrupted^1: you stopped the duel.", PREFIX );
            client_print_color( param[ 1 - param[ IPOS ] ], print_team_red, "%s ^3Duel interrupted^1: %n stopped the duel.", PREFIX, param[ IWINNER ] );
        }
        case PLAYER_DISCONNECTED:
        {
            client_print_color( param[ 1 - param[ IPOS ] ], print_team_red, "%s ^3Duel interrupted^1: your enemy disconnected.", PREFIX );
        }
    }
}

public CmdStopDuel( id )
{
    if( check_bit( bIsInDuel, id ) )
    {
        if( task_exists( id + TASK_REVIVE ) )
            remove_task( id + TASK_REVIVE );

        StopDuelPre( GetArena( id ), PLAYER_STOP, id );
    }
        
    else
        client_print_color( id, print_team_red, "%s You are not in a duel.", PREFIX );
    
    return PLUGIN_HANDLED;
}

public CmdMainMenu( id )
{
    new menuid = menu_create( "Rush Menu", "MainHandler" );

    menu_additem( menuid, "Knife Duel" );
    menu_additem( menuid, "Block Player" );

    menu_additem( menuid, check_bit( hasDisabledDuel, id )? "ENABLE Requests":"DISABLE Requests" );

    menu_display( id, menuid );

    return PLUGIN_HANDLED;
}

public MainHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item != MENU_EXIT )
    {
        switch( item ) 
        {
            case 0: DuelMenu ( id );
            case 1: BlockMenu( id );
            case 2:
            {
                if( check_bit( hasDisabledDuel, id ) )
                    clear_bit( hasDisabledDuel, id );
                else
                    set_bit( hasDisabledDuel, id );
                
                CmdMainMenu( id );
            }
        }
    }

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

BlockMenu( id )
{
    new players[ 32 ], iNum;

    get_players( players, iNum );
    
    new menuid = menu_create( "Block Menu", "BlockMenuHandler" );
    new buff[ 2 ];
    // using "e" flag on get_players doesn't work always fine.
    for( new i; i < iNum; i++ )
    {                                                                                                          //spectator
        if( id == players[ i ] || get_user_team( id ) == get_user_team( players[ i ] ) || get_user_team( players[ i ] ) == 3 )
            continue;

        buff[ 0 ] = players[ i ];
        buff[ 1 ] = 0;
        menu_additem( menuid, fmt( "%n%s", buff[ 0 ], check_bit( hasBlocked[ id ], buff[ 0 ] )? " [UNBLOCK]":"" ), buff );
    } 

    menu_display( id, menuid );
}

public BlockMenuHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item != MENU_EXIT )
    {
        new buff[ 2 ]
        menu_item_getinfo( menuid, item, _, buff, charsmax( buff ) );
        
        if( is_user_connected( buff[ 0 ] ) )
        {
            if( check_bit( hasBlocked[ id ], buff[ 0 ] ) )
                clear_bit( hasBlocked[ id ], buff[ 0 ] );
            else
                set_bit( hasBlocked[ id ], buff[ 0 ] );
        }

        BlockMenu( id );
    }
    
    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

DuelMenu( id )
{
    if( !CanPlayerDuel( id ) )
        return PLUGIN_HANDLED;
    
    new players[ 32 ], num;

    get_players( players, num, "ach" );
    
    new menuid = menu_create( "\rDuel Menu^n\yChoose a Player", "DuelMenuHandler" );
    new bool:hasPlayers, buff[ 2 ];
    for( new i; i < num; i++ )
    {
        if( id == players[ i ] || get_user_team( id ) == get_user_team( players[ i ] ) || get_user_team( players[ i ] ) == 3 || check_bit( bIsInDuel, players[ i ] ) )
            continue;

        if( check_bit( hasBlocked[ players[ i ] ], id ) || check_bit( hasDisabledDuel, players[ i ] ) )
            continue;

        buff[ 0 ] = players[ i ];
        buff[ 1 ] = 0;

        if( !hasPlayers )
            hasPlayers = true;

        menu_additem( menuid, fmt( "%n", buff[ 0 ] ), buff );
    }
    if( !hasPlayers )
    {
        client_print_color( id, print_team_red, "%s There are no players to duel with!", PREFIX );
        return PLUGIN_HANDLED;
    }

    menu_display( id, menuid );
    return PLUGIN_HANDLED;
}

public DuelMenuHandler( id, menuid, item )
{
    if( CanPlayerDuel( id ) && item != MENU_EXIT )
    {
        new buff[ 2 ]
        menu_item_getinfo( menuid, item, _, buff, charsmax( buff ) );

        if( CanPlayerDuel( id, true, buff[ 0 ] ) )
        {
            // send request
            if( pAttackType == 3 )
            {
                new menuid2 = menu_create( "Choose Duel Type", "DuelTypeHandler" );
                menu_additem( menuid2, "Both ( M1 and M2 )", buff );
                menu_additem( menuid2, "Only Slash ( M1 )" );
                menu_additem( menuid2, "Only Stab  ( M2 )" );

                menu_display( id, menuid2 );
            }
            else
            {
                SendChallenge( id, buff[ 0 ], pAttackType )
            }
        }
    }

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

public DuelTypeHandler( id, menuid, item )
{
    if( CanPlayerDuel( id ) && item != MENU_EXIT )
    {
        new buff[ 2 ]
        menu_item_getinfo( menuid, 0, _, buff, charsmax( buff ) );

        if( CanPlayerDuel( id, true, buff[ 0 ] ) )
        {
            SendChallenge( id, buff[ 0 ], item );
        }
    }
    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

SendChallenge( id, pid, type )
{
    new menuid = menu_create( fmt( "\y'%n' wants to duel with you!^nAccept?", id ), "SendChallengeHandler" );
    new buffer[ 3 ];
    buffer[ 0 ] = id;
    buffer[ 1 ] = type;
    buffer[ 2 ] = 0;
    menu_additem( menuid, "Accept", buffer );
    menu_additem( menuid, "Refuse" );

    menu_display( pid, menuid, _, 10 );
}

public SendChallengeHandler( id, menuid, item )
{
    if( CanPlayerDuel( id , false ) && item == 0 )
    {
        new buff[ 3 ];
        menu_item_getinfo( menuid, 0, _, buff, charsmax( buff ) );
        if( CanPlayerDuel( id, true, buff[ 0 ] ) )
        {
            client_print_color( id, print_team_red, "%s You accepted %n's challenge.", PREFIX, buff[ 0 ] );
            client_print_color( id, print_team_red, "%s %n accepted your challenge.", PREFIX, id );
            GetReady( buff[ 0 ], id, buff[ 1 ] );
        }
    }
    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

GetReady( id, pid, type )
{
    new i;
    for( i = 0; i < activeArenas; i++ )
    {
        if( !check_bit( bIsArenaBusy, i ) && ( !editor || edit_zone != i ) )
            break;
        
        if( i == activeArenas - 1 )
        {
            client_print_color( id, print_team_red, "%s There are no free arenas to play. Retry later.", PREFIX );
            return;
        }
    }
    
    #if defined TEAM_PLUGIN
        kf_pause_teaming( id, pid );
    #endif

    set_bit( bIsInDuel, id );
    set_bit( bIsInDuel, pid );

    if( !busyArenas )
        ToggleFwds( true );

    set_bit( bIsArenaBusy, i );
    busyArenas++;

    RemovePlayersInArea( i, id, pid );
    fm_set_entity_visibility( iArenaEnt[ i ], true );
    set_ent_solid( i );

    // count rounds
    set_pev( iArenaEnt[ i ], pev_rplayer1, 0 );
    set_pev( iArenaEnt[ i ], pev_rplayer2, 0 );
    set_pev( iArenaEnt[ i ], pev_rtotal, 0 );
    set_pev( iArenaEnt[ i ], pev_rfake, 0 );

    g_DuelInfo[ i ][ PLAYER1  ] = id;
    g_DuelInfo[ i ][ PLAYER2  ] = pid;
    g_DuelInfo[ i ][ DUELTYPE ] = type;
    if( pSaveHealth )
    {
        pev( id,  pev_health, g_HealthCache[ i ][ PLAYER1 ] );
        pev( pid, pev_health, g_HealthCache[ i ][ PLAYER2 ] );
    }
    
    if( pSavePos )
    {
        pev( id,  pev_origin, g_PosCache[ i ][ PLAYER1 ] );
        pev( pid, pev_origin, g_PosCache[ i ][ PLAYER2 ] );
    }
    
    TeleportPlayer( id, pid, i );
    if( pLongTime && pLongTime < MIN_LONGTIME )
        pLongTime = MIN_LONGTIME;
    
    if( pLongTime )
        set_task( pLongTime, "AutoSlayDuelEnd", i + TASK_AUTOKILLEND );
}

RemovePlayersInArea( arena, id, pid )
{
    new Float:fP[ 3 ];
    new players[ 32 ], num;
    get_players( players, num );

    for( new i, cid; i < num; i++ )
    {
        if( players[ i ] == id || players[ i ] == pid )
            continue;

        cid = players[ i ];
        pev( cid, pev_origin, fP );

        if( fP[ 0 ] > iOrigin[ arena ][ 0 ] - fMaxs[ 0 ] - ( fSafeSpawn * 2 ) && 
            fP[ 0 ] < iOrigin[ arena ][ 0 ] + fMaxs[ 0 ] + ( fSafeSpawn * 2 ) && 
            fP[ 1 ] > iOrigin[ arena ][ 1 ] - fMaxs[ 1 ] - ( fSafeSpawn * 2 ) && 
            fP[ 1 ] < iOrigin[ arena ][ 1 ] + fMaxs[ 1 ] + ( fSafeSpawn * 2 ) && 
            fP[ 2 ] > iOrigin[ arena ][ 2 ] - fMaxs[ 1 ] - ( fSafeSpawn * 2 ) && 
            fP[ 2 ] < iOrigin[ arena ][ 2 ] + fMaxs[ 1 ] + fVerticalDistance + ( fSafeSpawn * 2 ) )
        {
            new param[ 1 ];
            get_user_health( cid );
            ExecuteHamB( Ham_CS_RoundRespawn, cid );
            client_print_color( cid, print_team_red, "%s You were respawned because arena near you is now being used.", PREFIX );
            set_task( 0.5, "ReturnHealth", cid + TASK_HP, param, sizeof param );
        }
    }
}

public ReturnHealth( param[], id )
{
    id -= TASK_HP;
    pev( id, pev_health, Float:param[ 0 ] );
}

public AutoSlayDuelEnd( arena )
{
    arena -= TASK_AUTOKILLEND;

    StopDuelPre( arena, TIME_END );
}

public EndDuelRound( arena )
{
    arena -= TASK_DUELROUND;

    client_print_color( g_DuelInfo[ arena ][ PLAYER1 ], print_team_red, "%s You took too long.", PREFIX );
    client_print_color( g_DuelInfo[ arena ][ PLAYER2 ], print_team_red, "%s You took too long.", PREFIX );

    new fakeRounds = pev( iArenaEnt[ arena ], pev_rfake ) + 1;

    if( fakeRounds >= pFakeRounds )
        StopDuelPre( arena, FAKE_ROUNDS );
    else
    {
        set_pev( iArenaEnt[ arena ], pev_rfake, fakeRounds );
        TeleportPlayer( g_DuelInfo[ arena ][ PLAYER1 ], g_DuelInfo[ arena ][ PLAYER2 ], arena );
    }
    
}

TeleportPlayer( id, pid, arena )
{
    new Float:fP1[ 3 ], Float:fP2[ 3 ];

    fP1[ 0 ] = iOrigin[ arena ][ 0 ] - ( pDistance / 2 );
    fP1[ 1 ] = iOrigin[ arena ][ 1 ];
    fP1[ 2 ] = iOrigin[ arena ][ 2 ] + fSafeSpawn;
    
    fP2[ 0 ] = iOrigin[ arena ][ 0 ] + ( pDistance / 2 );
    fP2[ 1 ] = iOrigin[ arena ][ 1 ];
    fP2[ 2 ] = iOrigin[ arena ][ 2 ] + fSafeSpawn;

    engfunc( EngFunc_SetOrigin, id, fP1 );
    engfunc( EngFunc_SetOrigin, pid, fP2 );
    
    set_pev( id, pev_velocity, Float:{ 0.0, 0.0, 0.0 } );
    set_pev( pid, pev_velocity, Float:{ 0.0, 0.0, 0.0 } );

    if( pHealth[ g_DuelInfo[ arena ][ DUELTYPE ] ] > 0.0 )
    {
        set_pev( id,  pev_health, pHealth[ g_DuelInfo[ arena ][ DUELTYPE ] ] );
        set_pev( pid, pev_health, pHealth[ g_DuelInfo[ arena ][ DUELTYPE ] ] );
    }
    else 
    {
        set_pev( id,  pev_health, fMapHp );
        set_pev( pid, pev_health, fMapHp );
    }

    LookAtOrigin( id, fP2 );
    LookAtOrigin( pid, fP1 );

    if( pSmallTime && pSmallTime < MIN_SMALLTIME )
        pSmallTime = MIN_SMALLTIME;

    if( pSmallTime )
        set_task( pSmallTime, "EndDuelRound", arena + TASK_DUELROUND );
    
    client_print_color( id,  print_team_red, "%s Round %d [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, pev( iArenaEnt[ arena ], pev_rtotal ) + 1, pev( iArenaEnt[ arena ], pev_rplayer1 ), pev( iArenaEnt[ arena ], pev_rplayer2 ), pev( iArenaEnt[ arena ], pev_rtotal ) );
    client_print_color( pid, print_team_red, "%s Round %d [ ^4%d^1 | ^3%d^1 | %d ]", PREFIX, pev( iArenaEnt[ arena ], pev_rtotal ) + 1, pev( iArenaEnt[ arena ], pev_rplayer2 ), pev( iArenaEnt[ arena ], pev_rplayer1 ), pev( iArenaEnt[ arena ], pev_rtotal ) );
}

ToggleFwds( bool:enable = true )
{
    if( enable )
    {
        EnableHamForward( PlayerSpawnPost  );
        EnableHamForward( PlayerKilledPost );
        EnableHamForward( PlayerKilledPre  );

        PlayerThink = register_forward( FM_PlayerPreThink, "fw_PlayerThink_Pre" );
    }
    else 
    {
        DisableHamForward( PlayerSpawnPost  );
        DisableHamForward( PlayerKilledPost );
        DisableHamForward( PlayerKilledPre  );

        unregister_forward( FM_PlayerPreThink, PlayerThink );
    }
}

GetArena( id )
{
    for( new fr; fr < activeArenas; fr++ )
    {
        if( g_DuelInfo[ fr ][ 0 ] == id || g_DuelInfo[ fr ][ 1 ] == id )
            return fr;
    }

    return -1;
}

GetPos( id, arena = -1 )
{
    if( arena == -1 )
        arena = GetArena( id );

    if( g_DuelInfo[ arena ][ 0 ] == id )  
        return 0;
    if( g_DuelInfo[ arena ][ 1 ] == id )
        return 1;
 
    return -1
}

bool:CanPlayerDuel( id, bool:message = true, player=0 )
{
    if( !is_user_connected( id ) )
        return false;

    if( !bCanDuel )
    {
        if( message )
            client_print_color( id, print_team_red, "%s You can't duel now. Retry in few seconds.", PREFIX );
        return false;
    }
    if( get_gametime() - fLastDuel[ id ] < pNextDuel )
    {
        if( message )
            client_print_color( id, print_team_red, "%s You can't duel now. Wait ^3%.2f^1 seconds.", PREFIX, pNextDuel - ( get_gametime() - fLastDuel[ id ] ) );
        return false;
    }
    else if( !activeArenas )
    {
        if( message )
            client_print_color( id, print_team_red, "%s This map has no arenas available", PREFIX );
        return false;
    }
    else if( busyArenas >= activeArenas )
    {
        if( message )
            client_print_color( id, print_team_red, "%s There are no free arenas to play. Retry later.", PREFIX );
        return false;
    }
    else if( player )
    {
        if( !is_user_connected( player ) )
        {
            if( message )
                client_print_color( id, print_team_red, "%s Player is not connected.", PREFIX );
            return false;
        }
        else if( get_gametime() - fLastDuel[ player ] < pNextDuel )
        {
            if( message )
                client_print_color( id, print_team_red, "%s Player can't duel now. Wait ^3%.2f^1 seconds.", PREFIX, pNextDuel - ( get_gametime() - fLastDuel[ player ] ) );
            return false;
        }
        else if( !is_user_alive( player ) )
        {
            if( message )
                client_print_color( id, print_team_red, "%s Player is not alive.", PREFIX );
            return false;
        }
        else if( check_bit( bIsInDuel, player ) )
        {
            if( message )
                client_print_color( id, print_team_red, "%s Player is already in a challenge.", PREFIX );
            return false;
        }
        else if( get_user_team( id ) == get_user_team( player ) )
        {
            if( message )
                client_print_color( id, print_team_red, "%s You can't challenge a teammate.", PREFIX );
            return false;
        }
    }
    else if( !is_user_alive( id ) )
    {
        if( message )
            client_print_color( id, print_team_red, "%s You must be alive in order to access ^4Duel Menu", PREFIX );
        return false;
    }
    else if( check_bit( bIsInDuel, id ) )
    {
        if( message )
            client_print_color( id, print_team_red, "%s You are already in a challenge", PREFIX );
        return false;
    }
    

    return true;
}

public CmdArenaMenu( id, level, cid )
{
    if( !cmd_access( id, level, cid, 0 ) )
        return PLUGIN_HANDLED;

    ArenaMenu( id );
    
    return PLUGIN_HANDLED;
}

ArenaMenu( id )
{
    if( editor ) 
        editor = 0;
    new menuid = menu_create( fmt( "\rArena Menu^n^nCurrent Active Arenas: %d", activeArenas ), "ArenaMenuHandler" );
    
    menu_additem( menuid, "Create New Arena", _, activeArenas >= MAX_ARENA? DisableAccess:0 );

    menu_additem( menuid, "Edit Existing Arena", _, activeArenas <= 0? DisableAccess:0 );

    menu_display( id, menuid );

    return PLUGIN_HANDLED;
}

public ArenaMenuHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item != MENU_EXIT )
    {
        switch( item )
        {
            case 0: EditArena( id, -1 );
            case 1: EditArenaMenu( id );
        }
    }

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

EditArena( id, arena )
{
    if( check_bit( bIsArenaBusy, arena ) )
    {
        client_print_color( id, print_team_red, "%s This arena is being used. Retry later.", PREFIX );
        ArenaMenu( id );
        return;
    }
    if( arena == -1 )
    {
        if( activeArenas >= MAX_ARENA )
            return;

        arena = activeArenas++;
        pev( id, pev_origin, iOrigin[ arena ] );

        iOrigin[ arena ][ 2 ] += 120.0;

        if( iOrigin[ arena ][ 2 ] < 0.0 )
        {
            iOrigin[ arena ][ 2 ] = float( floatround( iOrigin[ arena ][ 2 ] ) );
        }

        CreateArena( arena, false );
    }

    new menuid = menu_create( fmt( "Arena #%d", ( arena + 1 ) ), "EditArenaHandler" );
    new buff[ 2 ];
    buff[ 0 ] = arena; buff[ 1 ] = 0;

    menu_additem( menuid, "Move towards \rRED", buff );
    menu_additem( menuid, "Move towards \yYELLOW^n" );
    menu_additem( menuid, "Change Directions" );
    menu_additem( menuid, fmt( "Change Unit (%.f)^n^n", fUnit[ currUnit ] ) );
    menu_additem( menuid, "Save" );
    menu_additem( menuid, fmt( "\rDelete%s^n\yPosition:\w %.2f %.2f %.2f", busyArenas? " \w[Not Available when any arena is busy]":"", iOrigin[ arena ][ 0 ], iOrigin[ arena ][ 1 ], iOrigin[ arena ][ 2 ] ), _, busyArenas? DisableAccess:0 );
    

    editor = id;
    if( !task_exists( TASK_DRAW ) )
        set_task( 0.2, "DrawLaser", TASK_DRAW, _, _, "b" );
    edit_zone = arena; 
    menu_display( id, menuid );
}

public EditArenaHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item != MENU_EXIT )
    {
        new buff[ 2 ];
        menu_item_getinfo( menuid, 0, _, buff, charsmax( buff ) );
        new arena = buff[ 0 ];
        
        switch( item )
        {
            case 0, 1:
            {
                if( item == 0 )
                    iOrigin[ arena ][ direction ] += fUnit[ currUnit ];
                else
                    iOrigin[ arena ][ direction ] -= fUnit[ currUnit ];

                if( direction == 2 && iOrigin[ arena ][ 2 ] < 0.0 )
                {
                    iOrigin[ arena ][ 2 ] = float( floatround( iOrigin[ arena ][ 2 ] ) );
                }
                engfunc( EngFunc_SetOrigin, iArenaEnt[ arena ], iOrigin[ arena ] );
                
                for( new i = 0; i < iWalls; i++ )
                {
                    engfunc( EngFunc_SetOrigin, iArenaWall[ arena ][ i ], iOrigin[ arena ] );
                }
            }
            case 2: direction = ( direction + 1 ) % 3;
            case 3: currUnit = ( currUnit + 1 ) % sizeof fUnit;
            case 4: SaveArena( arena );
            case 5: DeleteArena( arena );
        }
        if( item < 4 )
            EditArena( id, arena );
        else
            ArenaMenu( id );
    }
    else 
        editor = 0;

    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}

EditArenaMenu( id )
{
    if( editor )
        editor = 0;
    new menuid = menu_create( "Choose Arena", "EditMenuHandler" );
    
    for( new i = 0; i < activeArenas; i++ )
    {
        menu_additem( menuid, fmt( "Arena #%d%s", i + 1, check_bit( bIsArenaBusy, i )? " \r[BUSY]":"" ) );
    }

    menu_display( id, menuid );
}

public EditMenuHandler( id, menuid, item )
{
    if( is_user_connected( id ) && item != MENU_EXIT )
    {
        EditArena( id, item );
    }
    menu_destroy( menuid );
    return PLUGIN_HANDLED;
}
// mostly taken from the walkguard plugin. Life's much easier with that plugin. thanks mogel!
public DrawLaser()
{
    if( !is_user_connected( editor ) || !editor )
        remove_task( TASK_DRAW );
    
    static color[ 3 ] = { 200, 200, 200 };
    new arena = edit_zone;
    new Float:maxs[ 3 ];
    new Float:mins[ 3 ];

    maxs[ 0 ] = fMaxs[ 0 ] + iOrigin[ arena ][ 0 ];
    maxs[ 1 ] = fMaxs[ 1 ] + iOrigin[ arena ][ 1 ];
    maxs[ 2 ] = fMaxs[ 2 ] + iOrigin[ arena ][ 2 ] + 10.0;

    mins[ 0 ] = fMins[ 0 ] + iOrigin[ arena ][ 0 ];
    mins[ 1 ] = fMins[ 1 ] + iOrigin[ arena ][ 1 ];
    mins[ 2 ] = fMins[ 2 ] + iOrigin[ arena ][ 2 ] - 10.0;

    new Float:origin[ 3 ];
    pev( editor, pev_origin, origin );

    DrawLine(origin[0], origin[1], origin[2], iOrigin[arena][0], iOrigin[arena][1], iOrigin[arena][2], color);

    switch( direction )
    {
        case 0:
        {
            DrawLine(maxs[0], maxs[1], maxs[2], maxs[0], mins[1], mins[2], {255,0,0})
            DrawLine(maxs[0], maxs[1], mins[2], maxs[0], mins[1], maxs[2], {255,0,0})
            
   
            DrawLine(mins[0], maxs[1], maxs[2], mins[0], mins[1], mins[2],  {255,255,0})
            DrawLine(mins[0], maxs[1], mins[2], mins[0], mins[1], maxs[2],  {255,255,0})
        }
	    case 1:
        {
            DrawLine(mins[0], mins[1], mins[2], maxs[0], mins[1], maxs[2],  {255,255,0})
            DrawLine(maxs[0], mins[1], mins[2], mins[0], mins[1], maxs[2],  {255,255,0})

            DrawLine(mins[0], maxs[1], mins[2], maxs[0], maxs[1], maxs[2], {255,0,0})
            DrawLine(maxs[0], maxs[1], mins[2], mins[0], maxs[1], maxs[2], {255,0,0})
        }	
	    case 2:
        {
            DrawLine(maxs[0], maxs[1], maxs[2], mins[0], mins[1], maxs[2], {255,0,0})
            DrawLine(maxs[0], mins[1], maxs[2], mins[0], maxs[1], maxs[2], {255,0,0})

            DrawLine(maxs[0], maxs[1], mins[2], mins[0], mins[1], mins[2], {255,255,0})
            DrawLine(maxs[0], mins[1], mins[2], mins[0], maxs[1], mins[2],  {255,255,0})
        }
    }    
    
    DrawLine(maxs[0], maxs[1], maxs[2], mins[0], maxs[1], maxs[2], color)
    DrawLine(maxs[0], maxs[1], maxs[2], maxs[0], mins[1], maxs[2], color)
    DrawLine(maxs[0], maxs[1], maxs[2], maxs[0], maxs[1], mins[2], color)
    
    DrawLine(mins[0], mins[1], mins[2], maxs[0], mins[1], mins[2], color)
    DrawLine(mins[0], mins[1], mins[2], mins[0], maxs[1], mins[2], color)
    DrawLine(mins[0], mins[1], mins[2], mins[0], mins[1], maxs[2], color)
    
    DrawLine(mins[0], maxs[1], maxs[2], mins[0], maxs[1], mins[2], color)
    DrawLine(mins[0], maxs[1], mins[2], maxs[0], maxs[1], mins[2], color)
    DrawLine(maxs[0], maxs[1], mins[2], maxs[0], mins[1], mins[2], color)
    DrawLine(maxs[0], mins[1], mins[2], maxs[0], mins[1], maxs[2], color)
    DrawLine(maxs[0], mins[1], maxs[2], mins[0], mins[1], maxs[2], color)
    DrawLine(mins[0], mins[1], maxs[2], mins[0], maxs[1], maxs[2], color)
}


DrawLine( Float:x1, Float:y1, Float:z1, Float:x2, Float:y2, Float:z2, color[ 3 ] )
{
    if( !editor || !is_user_connected( editor ) )
        return; 

    message_begin( MSG_ONE_UNRELIABLE, SVC_TEMPENTITY, _, editor );
    write_byte( TE_BEAMPOINTS );
    engfunc( EngFunc_WriteCoord, x1 );
    engfunc( EngFunc_WriteCoord, y1 );
    engfunc( EngFunc_WriteCoord, z1 );
    engfunc( EngFunc_WriteCoord, x2 );
    engfunc( EngFunc_WriteCoord, y2 );
    engfunc( EngFunc_WriteCoord, z2 );
    write_short( beam );
    write_byte( 1 );
    write_byte( 1 );
    write_byte( 4 );
    write_byte( 5 );
    write_byte( 0 );
    write_byte( color[ 0 ] );
    write_byte( color[ 1 ] );
    write_byte( color[ 2 ] );
    write_byte( 255 );
    write_byte( 0 );
    message_end();
}

CreateArena( arena, bool:use_pos = true, Float:position[ 3 ] = {0.0,0.0,0.0} )
{
    new ent = engfunc( EngFunc_CreateNamedEntity, engfunc( EngFunc_AllocString, "func_wall" ) );

    iArenaEnt[ arena ] = ent;
    if( !use_pos )
    {
        engfunc( EngFunc_SetOrigin, ent, iOrigin[ arena ] );
    }   
    else
    {
        if( position[ 2 ] < 0.0 )
        {
            position[ 2 ] = float( floatround( position[ 2 ] ) );
        }
        engfunc( EngFunc_SetOrigin, ent, position );
        iOrigin[ arena ][ 0 ] = position[ 0 ];
        iOrigin[ arena ][ 1 ] = position[ 1 ];
        iOrigin[ arena ][ 2 ] = position[ 2 ];
    }

    set_pev( ent, pev_classname, "knife_arena" );
    
    //set_pev( ent, pev_solid, SOLID_BBOX );
    set_pev( ent, pev_solid, SOLID_NOT );
    set_pev( ent, pev_movetype, MOVETYPE_FLY );
    engfunc( EngFunc_SetModel, ent, szModel );
    engfunc(EngFunc_SetSize, ent, fMins, fMaxs );

    fm_set_entity_visibility( ent, 0 );
    //set_pev( ent, pev_solid, SOLID_NOT );
    CreateWalls( arena );
}

CreateWalls( arena )
{
    new ent;
    new Float:mins[ 3 ], Float:maxs[ 3 ];
    for( new i = 0; i < iWalls; i++ )
    {
        ent = engfunc( EngFunc_CreateNamedEntity, engfunc( EngFunc_AllocString, "func_wall" ) );
        
        iArenaWall[ arena ][ i ] = ent;
        switch( i )
        {
            case SIDE_BACK: // done 
            {
                mins[ 0 ] = fMins[ 0 ] - fSafeDistance;
                mins[ 1 ] = fMins[ 1 ] - fSafeDistance;
                mins[ 2 ] = fMins[ 2 ] / 2;
                
                maxs[ 0 ] = fMaxs[ 0 ] + fSafeDistance;
                maxs[ 1 ] = fMins[ 1 ] + fSafeDistance;
                maxs[ 2 ] = fVerticalDistance;
            }
            case SIDE_FORWARD: // done 
            {
                mins[ 0 ] = fMins[ 0 ] - fSafeDistance;
                mins[ 1 ] = fMaxs[ 1 ] - fSafeDistance;
                mins[ 2 ] = fMins[ 2 ] / 2;
                
                maxs[ 0 ] = fMaxs[ 0 ] + fSafeDistance;
                maxs[ 1 ] = fMaxs[ 1 ] + fSafeDistance;
                maxs[ 2 ] = fVerticalDistance;
            }
            case SIDE_LEFT: // done 
            {
                mins[ 0 ] = fMins[ 0 ] - fSafeDistance;
                mins[ 1 ] = fMins[ 1 ] - fSafeDistance;
                mins[ 2 ] = fMins[ 2 ] / 2;
                
                maxs[ 0 ] = fMins[ 0 ] + fSafeDistance;
                maxs[ 1 ] = fMaxs[ 1 ] + fSafeDistance;
                maxs[ 2 ] = fVerticalDistance;
            }
            case SIDE_RIGHT: // done 
            {
                mins[ 0 ] = fMaxs[ 0 ] - fSafeDistance;
                mins[ 1 ] = fMins[ 1 ] - fSafeDistance;
                mins[ 2 ] = fMins[ 2 ] / 2;
                
                maxs[ 0 ] = fMaxs[ 0 ] + fSafeDistance;
                maxs[ 1 ] = fMaxs[ 1 ] + fSafeDistance;
                maxs[ 2 ] = fVerticalDistance;
            }
            case SIDE_UP: 
            {
                mins[ 0 ] = fMins[ 0 ] - fSafeDistance;
                mins[ 1 ] = fMins[ 1 ] - fSafeDistance;
                mins[ 2 ] = fMaxs[ 2 ] + ( fVerticalDistance - fSafeDistance );
                
                maxs[ 0 ] = fMaxs[ 0 ] + fSafeDistance;
                maxs[ 1 ] = fMaxs[ 1 ] + fSafeDistance;
                maxs[ 2 ] = fMaxs[ 2 ] + fVerticalDistance;
            }
        }

        engfunc( EngFunc_SetOrigin, ent, iOrigin[ arena ] );
        set_pev( ent, pev_classname, "knife_walls" );
        //set_pev( ent, pev_solid, SOLID_BBOX );
        set_pev( ent, pev_solid, SOLID_NOT );
        set_pev( ent, pev_movetype, MOVETYPE_FLY );
        engfunc( EngFunc_SetModel, ent, szModel );
        engfunc(EngFunc_SetSize, ent, mins, maxs );

        fm_set_entity_visibility( ent, 0 );
        //set_pev( ent, pev_solid, SOLID_NOT );
    }
}

GetArenas()
{
    new mapName[ 32 ];
    get_mapname( mapName, charsmax( mapName ) );
    strtolower( mapName );

    if( containi( mapName, "1hp" ) != -1 )
        fMapHp = 1.0;
    else if( containi( mapName, "15hp" ) != - 1 )
        fMapHp = 15.0;
    else if( containi( mapName, "35hp") != - 1 )
        fMapHp = 35.0;
    else if( containi( mapName, "ka" ) != - 1 )
        fMapHp = 100.0;
    else
        fMapHp = 35.0;

    new strDir[ 96 ];
    get_configsdir( strDir, charsmax( strDir ) );
    
    add( strDir, charsmax( strDir ), "/knife_duel" );
    
    if( !dir_exists( strDir ) )
    {
        mkdir( strDir );
        return 0;
    }

    formatex( knfDir, charsmax( knfDir ), "%s/%s.cfg", strDir, mapName );
    
    if( !file_exists( knfDir ) )
        return 0;
    
    new fp = fopen( knfDir, "rt" );

    new Regex:pPattern = regex_compile( "^^([-]?\d+\.\d+ ){2}[-]?\d+\.\d+$" );
    new arena;
    new szText[ 128 ], szX[ 10 ], szY[ 10 ], szZ[ 10 ];
    while( !feof( fp ) ){

        fgets( fp, szText, charsmax( szText ) );
        trim( szText );
        
        if( regex_match_c( szText, pPattern ) > 0 )
        {
            parse( szText, szX, charsmax( szX ), szY, charsmax( szY ), szZ, charsmax( szZ ) );

            iOrigin[ arena ][ 0 ] = str_to_float( szX );
            iOrigin[ arena ][ 1 ] = str_to_float( szY );
            iOrigin[ arena ][ 2 ] = str_to_float( szZ );
            CreateArena( arena, true, iOrigin[ arena ] );
            arena++;
        }
    }
    regex_free( pPattern );
    fclose( fp );

    return arena;
}

SaveArena( arena )
{
    if( !file_exists( knfDir ) ) 
	{
        new mapName[ 32 ];
        get_mapname( mapName, charsmax( mapName ) );
        write_file( knfDir, fmt( "; Knife Duel map: %s", mapName ), 0 );
	}

    write_file( knfDir, fmt( "%.2f %.2f %.2f", iOrigin[ arena ][ 0 ], iOrigin[ arena ][ 1 ], iOrigin[ arena ][ 2 ] ), arena * 2 + 1 );
    write_file( knfDir, "---------------------------", arena * 2 + 2 );
}

DeleteArena( arena )
{
    engfunc( EngFunc_RemoveEntity, iArenaEnt[ arena ] );

    for( new i = 0; i < iWalls; i++ )
        engfunc( EngFunc_RemoveEntity, iArenaWall[ arena ][ i ] );

    if( arena < activeArenas - 1 )
    {
        for( new i = arena; i < activeArenas - 1; i++ )
        {
            for( new j; j < 3; j++ )
            {
                iOrigin[ i ][ j ] = iOrigin[ i + 1 ][ j ];
                
            }
            iArenaEnt[ i ] = iArenaEnt[ i + 1 ];
            for( new j; j < iWalls; j++ )
            {
                iArenaWall[ i ][ j ] = iArenaWall[ i + 1 ][ j ];
            }
            write_file( knfDir, fmt( "%.3f %.3f %.3f", iOrigin[ arena ][ 0 ], iOrigin[ arena ][ 1 ], iOrigin[ arena ][ 2 ] ), i * 2 + 1 );
            write_file( knfDir, "---------------------------", i * 2 + 2 );
        }
    }
    activeArenas--;

    arrayset( iOrigin[ activeArenas ][ 0 ], 0.0, 3 );
    for( new i = 1; i < 3; i++ )
    {
        write_file( knfDir, "", activeArenas*2 + i );
    }
}

public _is_user_in_duel( plugin, argc )
{
    return check_bit( bIsInDuel, get_param( 1 ) );
}

set_ent_solid( arena, bool:solid = true )
{
    if( solid )
    {
        set_pev( iArenaEnt[ arena ], pev_solid, SOLID_BBOX );
        
        for( new i; i < iWalls; i++ )
            set_pev( iArenaWall[ arena ][ i ], pev_solid, SOLID_BBOX );
    }
    else
    {
        set_pev( iArenaEnt[ arena ], pev_solid, SOLID_NOT );
        
        for( new i; i < iWalls; i++ )
            set_pev( iArenaWall[ arena ][ i ], pev_solid, SOLID_NOT );
    }
}

stock fm_set_entity_visibility(index, visible = 1) {
	set_pev(index, pev_effects, visible == 1 ? pev(index, pev_effects) & ~EF_NODRAW : pev(index, pev_effects) | EF_NODRAW)

	return 1
}

stock LookAtOrigin(const id, const Float:fOrigin_dest[3])
{
    static Float:fOrigin[3];
    pev(id, pev_origin, fOrigin);
    
    if( 1 <= id && id <= 32 )
    {
        static Float:fVec[3];
        pev(id, pev_view_ofs, fVec);
        xs_vec_add(fOrigin, fVec, fOrigin);
    }
    
    static Float:fLook[3], Float:fLen;
    xs_vec_sub(fOrigin_dest, fOrigin, fOrigin);
    fLen = xs_vec_len(fOrigin);
    
    fOrigin[0] /= fLen;
    fOrigin[1] /= fLen;
    fOrigin[2] /= fLen;
    
    vector_to_angle(fOrigin, fLook);
    
    fLook[0] *= -1;
    
    set_pev(id, pev_angles, fLook);
    set_pev(id, pev_fixangle, 1);
}
