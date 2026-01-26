# Darkest Days Bots

An addon for Garry's Mod that aims to provide challenging and life-like AI opponents for the Darkest Days game mode. Originally a LeadBot fork, after heavy refactoring and customization, it has become a standalone project.

## Installation

Navigate to your Garry's Mod addons folder, and then clone the repository:
```bash
git clone https://github.com/tbv001/ddbot.git
```

## Commands

- dd_bot_add [name]: Adds a bot to the game, with a custom name if specified.
- dd_bot_kick [name]: Kicks all bots from the game, or a specific bot if a name is specified.
- dd_bot_generatenavmesh: Generates a quick, cheap navmesh for the current map, requires sv_cheats 1.
- dd_bot_aim_speed_mult [number]: Multiplies the bot's aim speed by the given value.
- dd_bot_aim_spread_mult [number]: Multiplies the bot's aim spread by the given value.
- dd_bot_slide [0/1]: Enables or disables sliding for bots.
- dd_bot_dive [0/1]: Enables or disables diving for bots.
- dd_bot_combat_movement [0/1]: Enables or disables combat movement for bots.
- dd_bot_use_grenades [0/1]: Enables or disables grenade usage for bots.
- dd_bot_use_spells [0/1]: Enables or disables spell usage for bots.
- dd_bot_aim_prediction [0/1]: Enables or disables aim prediction for bots.
- dd_bot_quota [0-128]: Sets the bot quota.

## Credits

- [LeadKiller](https://github.com/LeadKiller): Original LeadBot author.
- [And other LeadBot contributors.](https://github.com/LeadKiller/leadbot/graphs/contributors)

## License

This project is licensed under the **MIT License** - see the [LICENSE](https://github.com/tbv001/ddbot/blob/master/LICENSE) file for details.
