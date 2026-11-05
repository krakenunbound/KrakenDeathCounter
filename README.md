# Kraken Death Counter

An on-screen death counter for World of Warcraft: Forever, made for streaming.
It shows your character's **Total deaths** statistic in a movable box so viewers
can see how many times you've died.

Current version: **1.0.0**, for the official Forever client (build 1.60.1.70790,
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

Settings (position, size, label, toggles) are account-wide in
`KrakenDeathCounter_DB`; the fallback counter is per character in
`KrakenDeathCounter_Char`.

## Testing

`tests/kdc_harness.py` runs the addon against a mock client with
[lupa](https://pypi.org/project/lupa/):

```
python -I tests/kdc_harness.py .
```

It covers a fresh character (`--` reads as 0), a death updating the count, an
existing total, the red flash, the slash commands, and the fallback counter.
It is a mock; in-game verification on the live client is still needed.

## License

The [LICENSE](LICENSE) applies: copyright 2026 tf4482, all rights reserved unless
otherwise explicitly stated.
