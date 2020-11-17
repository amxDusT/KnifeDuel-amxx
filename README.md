# KnifeDuel-amxx
Knife Duel plugin for Knife servers.

Cvars ( if USE_INI is defined, they'll be in knife_duel.ini ):
  - kd_alive: when duel ends, who to revive/slay?
      - 0: revives who won the round. In case of draw, both revive.
      - 1: revives who won the round. In case of draw, both dead.
      - 2: revives who killed the player on last round. 
      - 3: both revive.
  - kd_attack_type: which attack type can players play during duel.
      - 0: both
      - 1: slash / m1 
      - 2: stab / m2
      - 3: allow player to choose
  - kd_health_slash: health on duel when duel type is only slash. 0 = use map defalt hp.
  - kd_health_stab : health on duel when duel type is only stab.  0 = use map defalt hp.
  - kd_health_both : health on duel when duel type is normal.  0 = use map defalt hp.
  - kd_players_distance: distance between players when spawning in the duel. ( max = 550, min = 250 )
  - kd_rounds: how many rounds the players in the duel will do.
  - kd_max_round_time: how long can each round last at max. 0 = disabled.
  - kd_max_duel_time: how long can a duel last at max. 0 = disabled.
  - kd_cooldown: how long before a player can play another duel after he ends one.
  - kd_save_health: save player's health before he starts the duel and restore that health once duel ended.
  - kd_save_pos: save player's position before he starts the duel and restore that position once duel ended.
  - kd_fake_rounds: how many fake rounds can the duel accept before it stops the duel.
      - a fake round can be caused by the ROUND time ending or because one of the players died but it wasn't the duel enemy to kill him.
        In case a "fake round" happens, the round is not counted as an effective one and the same round is restarted.
 
 (FROM VERSION 1.1.X)
  - kd_stop_punish:  a sort of penalty for players that use the StopDuel command. 
      - 0: disabled.
      - 1: slays if alive.
      - 2+: adds this number to the seconds of the cooldown. 
  - kd_public_result: show who won a duel to everyone.
      
      
Admin Commands: 
  - kd_arena_menu: create new arena or edit existing ones. Editing consists of changing arena's position, saving it so it lasts even
    map change or delete it.

Commands: 
  - say /kd, kd, /duel, duel, /knifeduel, knifeduel : opens knife duel menu
  - kd_menu : opens knife duel menu
  - say /stop, /stopduel, /stopkd : ends a duel.
  - stop_duel : ends a duel.

Various Stuff:
  - you can block player from sending you invites.
  - you can block everyone from sending you invites.
  - each arena has 5 walls to block players from joining.
  - when duel starts, if there are players near the arena, they get respawned to get removed from the arena.
  - if players disconnects, the duel is stopped.
  - if server's round ends, the duel will continue on next round.
  - corspes on the arena should get removed within ~2 seconds ( just the time of the animation ).
  - plugin has "is_user_in_duel" native that returns 1 if player is in duel, 0 otherwise. 
  - either use knife_duels.ini or cvars to set up the plugin.
  - you can choose whether kills/deaths in the duel should affect client's score.
  
## Screens
  [1](https://steamuserimages-a.akamaihd.net/ugc/770613696247526342/B8B3792EEDCBC2990AD2B449035FA13F85157734/)<br>
  [2](https://steamuserimages-a.akamaihd.net/ugc/770613696247526834/D6E7D2C9789F842EA44047F6067DE41F352ACD9B/)<br>
  [3](https://steamuserimages-a.akamaihd.net/ugc/770613696247527892/D21F94226FF42FBD6788A5FDBED72475C117DB9F/)<br>
