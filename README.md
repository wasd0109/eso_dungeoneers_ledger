# Dungeoneer's Ledger

> **Disclaimer:** this addon was written with the help of AI (Claude by Anthropic) and reviewed by its author. It was tested in the game by its author as far as possible, but bugs are possible - please report them, and back up your SavedVariables if you rely on it.

## Overview

Dungeoneer's Ledger adds a progress ledger to the keyboard Dungeon Finder (Group > Dungeon Finder > Specific Dungeons). See at a glance which dungeons you have completed, which extra veteran achievements you have earned and which dungeons you have a quest for, then group, sort, search and select them in one click.

## Features

- Completion icon next to every dungeon, taken from the dungeon's own achievement (exact mapping through LibSets).
- Extra veteran achievement markers: hard mode, speed run, no death and trifecta, lit once earned.
- Quest marker for dungeons you have an active quest for: Undaunted pledges and other dungeon quests.
- Tooltip lists your other characters that have a quest for the same dungeon.
- Group the list by completion or DLC / chapter, and pin quest dungeons to the top.
- Sort by name, DLC or completion, search by name, hide completed dungeons.
- Progress line above the list, e.g. "Completed: Normal 27/41 - Veteran 18/41".
- One-click "Select quest dungeons" and "Select and queue" buttons.

## Settings

Open them from Settings > Add-Ons > Dungeoneer's Ledger or with `/dledger settings`.

- **Show completion icon** (on): the check box next to each dungeon name; its tooltip names the achievement.
- **Show completion dates in tooltips** (on): adds the date an achievement was earned to the tooltips of the completion icon and the extra achievement markers, formatted by the game for your language.
- **Show set collection progress in tooltips** (on): adds "Set pieces collected: X / Y" for the dungeon to the completion icon tooltip, from the game's item set collections (through LibSets).
- **Show extra achievement markers** (on): small markers for a veteran dungeon's extra achievements, using the achievement's own icon. Grey until earned. The tooltip lists each tier.
  - **Hard mode marker**, **Speed run marker**, **No death marker**, **Trifecta marker** (all on): show or hide each tier separately. Only available while the main markers toggle is on. A dungeon without a tier shows no marker for it.
- **Show dungeons I have a quest for** (on): marks dungeons that match an active quest of the current character (the tooltip names the quest, or "Current Undaunted pledge").
- **Show which characters have quests for a dungeon** (on): adds "Also active on: ..." to that tooltip for your other characters.
- **Remember completed pledges (done today)** (on): records the Undaunted pledges your characters turn in and shows "Pledge completed today (character)" on the dungeon's quest marker until the next daily reset (19:00 JST / 10:00 UTC). Records older than 8 days are dropped.
- **Pin dungeons with a quest to the top** (off): puts those dungeons in their own group, "Dungeons with a quest", at the top of the NORMAL and VETERAN lists. Works together with grouping.
- **Select and queue veteran dungeons instead of normal** (off): the two buttons pick the veteran version of each dungeon whichever difficulty the finder shows. Off: they follow your current dungeon difficulty.
- **Skip completed when selecting quest dungeons** (off): the buttons leave out dungeons whose achievement is already completed.
- **Icon size** (18, range 12-32): size of all icons.
- **Hide completed dungeons** (off): removes completed dungeons from the list.
- **Group dungeons by** (None): None keeps the game's order; Completion makes "Not completed" and "Completed" groups; DLC / chapter groups by the DLC or chapter a dungeon belongs to. Group headers show counts.
- **Sort dungeons by** (Game order): Game order, Name (A-Z), DLC, Completion, Completion date (newest first) or Completion date (oldest first), inside each list or group. Dungeons without a completion date sort last.

## Slash commands

- `/dledger` (or `/dungeoneersledger`): show usage.
- `/dledger settings`: open the settings panel.
- `/dledger debug`: print how each dungeon row was matched (LibSets, name or override) and which quests were found.
- `/dledger debug on` / `off`: print the first error of each kind once.

## Buttons

Two buttons sit beside the game's Join Queue button in the Specific Dungeons view.

- **Select quest dungeons** ticks the dungeons you have a quest for, for one difficulty (your current dungeon difficulty, or veteran if that setting is on). Existing ticks are replaced; nothing changes if there is nothing to tick.
- **Select and queue** does the same and then presses the game's own Join Queue.

Safeguards: one click is one action; nothing is ever selected or queued automatically; the game's own checks apply (locked dungeons are not ticked and are listed in chat); nothing happens while you are queued, when the Group Finder is in use, or when you are in a group but not its leader; normal and veteran are never mixed in one selection. Dungeons hidden by the search or hide-completed filter are never queued.

## Notes and limitations

- Achievements are account-wide, so completion is the same on every character.
- "Also active on" only knows characters you have logged into with this addon installed.
- Today's Undaunted pledges cannot be seen by any addon before you accept them from Maj, Glirion or Urgarlag; the game does not expose them. The addon can only remember pledges your characters completed (daily reset at 19:00 JST / 10:00 UTC).
- Extra achievement markers and the exact dungeon mapping depend on LibSets data; dungeons newer than your LibSets version fall back to name matching or show no icon.
- Keyboard and mouse UI only.

## Install

1. Install LibSets and LibAddonMenu-2.0 (both required).
2. Remove or disable the old DungeonCompletion addon if you had it. Settings and character records are imported once.
3. Copy the `DungeoneersLedger` folder to `Documents\Elder Scrolls Online\live\AddOns\`.

## Dependencies

- LibSets (required)
- LibAddonMenu-2.0 (required, for the settings panel)

## Credits

- LibSets by @Baertram (CC BY-NC-ND). This addon only depends on it; it is never bundled or copied.
- LibAddonMenu-2.0 by Seerah, sirinsidiator and contributors.
- This Add-On is not created by, affiliated with or sponsored by ZeniMax Media Inc. or its affiliates. The Elder Scrolls and related logos are registered trademarks or trademarks of ZeniMax Media Inc. in the United States and/or other countries. All rights reserved.

## Source

`git clone <repository url>` (suggested repository name: `eso_dungeoneers_ledger`)

Licensed under the MIT License, see `LICENSE`.
