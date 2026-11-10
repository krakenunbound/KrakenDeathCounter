# Kraken Death Counter

An on-screen death counter for World of Warcraft: Forever, made for streaming.
It shows your character's **Total deaths** statistic in a movable box so viewers
can see how many times you've died, and keeps a log of what killed you.

Current version: **1.1.0**, for the official Forever client (build 1.60.1.70790,
interface 16001).

## Where the number comes from

The count is read from the server's own **Total deaths** statistic, the same value
shown in the in-game Statistics window. It finds that row the same way Forever's
Statistics window does (`GetStatistic(categoryID, index)` named via
`GetAchievementInfo`), so it starts at your real lifetime total and stays correct
across reloads, characters and computers.

If the statistic can't be read, the addon falls back to the last known server value
plus the deaths it has counted itself (`PLAYER_DEAD`), and hands back to the server
value as soon as it is readable again, without double counting.

## Installation

Download the repository ZIP, extract it, and rename the folder to
**KrakenDeathCounter**. Put it in `_forever_\Interface\AddOns` so the folder
directly contains `KrakenDeathCounter.toc`. Fully restart WoW (a new addon is not
picked up by `/reload`) and enable it at character select.

## Using it

The counter starts at the top center of the screen. While it's unlocked, drag it
where you want it, then lock it.

- `/kdc lock` / `/kdc unlock` — lock it in place, or unlock it to drag.
- `/kdc scale 2` — size, from 0.5 to 4.
- `/kdc label Times I died` — the text before the number (default `Deaths`).
- `/kdc session` — toggle a smaller "This session: N" line.
- `/kdc icon` — toggle the skull icon.
- `/kdc bg` — toggle the background box (off = just the text, for stream layouts).
- `/kdc show` / `/kdc hide` — show or hide the counter.
- `/kdc reset` — move it back to the top center.
- `/kdc status` — show the count and whether it comes from the server statistic.

`/deaths` works as an alias for `/kdc`. When the number goes up it flashes red for
two seconds.

## What killed me

Every death from now on is logged: when, where, your level, what killed you, the
killing blow and the last few hits. Earlier deaths can't be filled in.

- `/kdc log`, or **right-click the counter** while it's unlocked, opens the log.
  - Newest deaths are at the top.
  - The top line shows your most frequent killers.
  - Hover a death to see the last hits, newest first, with how long before death
    each one landed.
  - The button at the top right switches between this character and all your
    characters.
- After each death a line goes to your chat, for example
  `Killed by Hogger (11 elite) with Melee 45 (12 overkill) in Fargodeep Mine, Elwynn Forest.`
  - `/kdc announce` turns that line off or on.
  - Only you see it.
- `/kdc last` prints your last death.
- `/kdc import` adds earlier deaths from Kraken Log (see below).
- `/kdc clearlog` erases this character's deaths. Your other characters' deaths are
  kept.

### Where the killer comes from

Forever gives addons no combat log, so the addon uses two sources.

1. **The game's Death Recap.** This is the same list the "Death Recap" button
   shows, giving who hit you, with what and for how much.
   - It can be unreadable for a moment after you die, so the addon keeps trying for
     about a minute, and again when you leave combat, release or resurrect.
   - Falls, drowning, fatigue and lava are named as such.
   - Players who killed you are marked "player".
2. **Whatever was attacking you.** If the recap isn't available, the addon blames
   an enemy that had you targeted while you were taking damage in the last 10
   seconds, such as your target, focus, mouseover or a nameplate.
   - These deaths say **probably**, since several enemies may have been on you.
   - The tooltip lists the other attackers.
   - If the recap turns up later, the entry is corrected and you get a
     `Death recap:` chat line.

With neither source, the death is logged as "an unknown attacker".

### Deaths from before the log: Kraken Log

If [Kraken Log](../KrakenLog) is installed, its saved record of each character is
read at login (once per character), and deaths it recorded are added to the log.

- The killer is the last enemy you targeted or attacked in the 30 seconds before
  you died, leaving out any you'd already killed (shown as **probably**).
- The tooltip lists everything in that fight, marking the ones you killed, plus
  where it happened (zone and coordinates) and your level at the time.
- Deaths already in the log aren't added twice.
- `/kdc import` runs it again, for example after `/kdc clearlog`.
- Deaths from before Kraken Log was installed can't be recovered: the counter
  still includes them, but the log doesn't.

The log is account-wide in `KrakenDeathCounter_DB.log`, with each entry's
character name. It holds your last 1000 deaths.

Settings (position, size, label, toggles) are account-wide in
`KrakenDeathCounter_DB`; the fallback counter is per character in
`KrakenDeathCounter_Char`.

## Testing

`tests/kdc_harness.py` runs the addon against a mock client with
[lupa](https://pypi.org/project/lupa/):

```
python -I tests/kdc_harness.py .
```

It covers:

- the counter: a fresh character (`--` reads as 0), a death updating the count, an
  existing total, the red flash, the slash commands and the fallback counter
- the death log:
  - recap deaths, falls and PvP kills
  - a recap that's secret at first
  - a previous death's recap not being reused
  - the "probably" fallback and unknown killers
  - the chat line, `/kdc log`, `last`, `clearlog`, `import` and `announce`
  - importing deaths from Kraken Log: the killer, skipping mobs already killed
    and players, duplicates, and once per character
  - the all-characters view and the 1000-entry cap

It's a mock. Whether Forever's Death Recap is readable by addons hasn't been
checked in the live client yet. If it isn't, every death will say "probably".

## License

The [LICENSE](LICENSE) applies: copyright 2026 tf4482, all rights reserved unless
otherwise explicitly stated.
