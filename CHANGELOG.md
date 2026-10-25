# Changelog

## 0.2.0

- Set collection progress ("Set pieces collected: X / Y") in the completion icon tooltip, via LibSets; cached
  and refreshed when the game reports collection changes. New setting, on by default.
- "Pledge done today": turned-in Undaunted pledges are remembered per character and shown on the dungeon's
  quest marker until the next daily reset (19:00 JST / 10:00 UTC, one constant in Core.lua). Entries older than
  8 days are dropped. New setting, on by default. Today's pledges themselves are still not visible to addons.
- Tests for both features.

## 0.1.0

First release (successor of the unreleased DungeonCompletion addon).

- Completion icon per dungeon, from the dungeon's achievement (exact mapping through LibSets).
- Completion dates in the tooltips of the completion icon and the tier markers, and sort by completion date.
- Extra veteran achievement markers: hard mode, speed run, no death, trifecta.
- Quest marker for dungeons you have an active quest for (Undaunted pledges and other dungeon quests),
  with the other characters that have one.
- Dungeon Finder list: group by completion or DLC / chapter, pin quest dungeons to the top, sort, search,
  hide completed; progress summary above the list.
- Buttons: Select quest dungeons, Select and queue (optionally veteran instead of normal).
- LibAddonMenu-2.0 settings panel (required dependency); English strings with a lang/ structure for translators.
- Settings and per-character quest records are imported once from DungeonCompletion.
