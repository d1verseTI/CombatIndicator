# CombatIndicator

A World of Warcraft addon for the **Forever** client (Interface 16001). It tells you the moment you drop out of combat. Rogues (and druids in cat form) also see whether Stealth / Prowl is ready to use again.

## What it shows

One movable icon with a number and a short label:

| State | Display |
|---|---|
| In combat | Swords icon, red "Combat" (optional, `/ci combat`) |
| In PvP combat | Swords icon with an orange countdown to the expected combat drop. It glows in the last 2 seconds and restarts on every hostile player action to or from you. |
| Left combat | Sound, plus the Stealth icon glowing green "Stealth!" (or grey with a cooldown swipe if Stealth is still on cooldown) |
| Stealthed / timed out | Hidden |

The PvP drop timer learns itself after each PvP fight.

## Commands

| Command | Does |
|---|---|
| `/ci lock` / `/ci unlock` | Lock the icon, or unlock it so you can drag it |
| `/ci scale <0.5-3>` | Resize the icon |
| `/ci sound` | Toggle the alert sound |
| `/ci combat` | Toggle the "In combat" display |
| `/ci timer [sec]` | Show or set the PvP combat-drop timer (3-10 s) |
| `/ci showat [sec]` | Only show the PvP countdown when this many seconds are left |
| `/ci test` / `/ci testpvp` | Preview the out-of-combat alert / PvP countdown |
| `/ci debug [clear]` | Toggle debug logging, or clear the log |
| `/ci reset` | Restore defaults |

## Install

Copy the `CombatIndicator` folder into `World of Warcraft\_forever_\Interface\AddOns\` and restart the game or `/reload`.

## Libraries

Bundled under `Libs/`:

- [LibStub](https://www.wowace.com/projects/libstub): public domain
- [LibCustomGlow-1.0](https://github.com/Stanzilla/LibCustomGlow): MIT

## License

MIT. See [LICENSE](LICENSE).

## Contact

- Bugs and feature requests: open an issue on this repository.
- Anything else, including work enquiries: [d1verseti.gg@gmail.com](mailto:d1verseti.gg@gmail.com)
