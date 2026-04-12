# About `the-midnight-munch` <img src="https://github.com/user-attachments/assets/d0932df4-01a6-46f0-938c-3a9c73f2d324" width="4%" align="top">

![Gif of title screen](https://github.com/user-attachments/assets/ab19ee40-1968-431f-89ce-2b896d7a014a)

# Creator
- Keith Ashly M. Domingo
- Adriel Neyro Caraig

**Date: April 7, 2026**

# Description

## Summary
**`the-midnight-munch`** is a LAN multiplayer ocean predator game where 2–4 players each control a deep-sea fish and compete to be the last one swimming. Eat your way from a tiny larval fish at Level 0 up through 10 levels and two dramatic tier shifts, all while harassing rivals and fending off a dynamic ecosystem of AI creatures.

## Rationale
**`the-midnight-munch`** is a *Feeding Frenzy clone* with a twist, created as the second machine problem for CMSC 197 - Game Design and Development. To challenge the student's creativity and ingenuity, they were given a task to take an already existing game, analyze its game design, and create a unique recreation of the game while being restricted to keep the major features of the original game.

## The Twist: XP Attrition & the Death Floor
Unlike the original Feeding Frenzy, progression in **`the-midnight-munch`** can go *backwards*. Every bite you take from another fish — player or NPC — drains your XP. Sustained harassment will de-level you until you fall far enough behind your attacker to become prey. A fish reduced to **Level 0 with 0 XP** is eliminated on the very next bite from any source. There is no recovery from that state — it is the **Death Floor**.

This creates a tug-of-war where eating builds you up, being eaten tears you down, and the **Boost** ability (which drains your Energy reserve) is your only tactical escape.

The game also takes place in the **midnight zone deep-sea environment**. A dark overlay covers the map, and each fish emits light that fades over time. Eating luminous **Sea Angels** restores your light, making resource management a matter of both XP and visibility.

# Features

**`the-midnight-munch`** offers both unique mechanics and some from the original *Feeding Frenzy*:

- **LAN Multiplayer (2–4 players)** with auto-discovery via a shared session key — no raw IP entry required
- **Offline Single Player** mode with full AI ecosystem
- **XP Attrition Combat** — bites drain XP and can cause de-leveling
- **Three-Tier Visual Progression** — Baby (Lv 0–4), Teen (Lv 5–7), Adult (Lv 8–10) with animated tier-shift transitions
- **Boost System** — hold boost to sprint at the cost of Energy; Energy regenerates passively
- **Bioluminescence** — dynamic lighting where your visibility drains over time
- **Spectator Mode** — eliminated players become invisible ghost cameras and can still watch the match
- **Smart AI** — NPCs wander, lunge, and flee using a state machine with self-preservation logic
- **Dynamic NPC Ecosystem** — spawn levels scale to the alive player population; a guaranteed fodder floor ensures de-leveled players always have a recovery path
- **Collectibles** — Special Fish and Floating Items grant stat boosts; managed in an independent pool separate from NPC spawns
- **First-Come-First-Served Character Select** — choosing a fish in the lobby locks it for all other peers
- **Escape Speed Burst** — a successful bite automatically grants the defender a brief speed burst to prevent infinite stunlocks
- **Rematch Loop** — return to lobby and play again without relaunching the game

# Game Mechanic

## Core Loop
Players start as small larval fish at Level 0 and eat smaller creatures to gain XP and level up, growing larger and stronger through three visual tiers. Combat resolves on a **Kill / Bite** hierarchy:

| Condition | Result |
|---|---|
| Attacker tier > defender tier | Kill (1-level demotion for players; instant death for NPCs) |
| Same tier, attacker level ≥ defender + 2 | Kill |
| Same tier, within 1 level | Bite (XP drain, scales with attacker level) |
| Attacker tier < defender tier | Bite (smaller fish can still bite larger fish) |
| Defender at Level 0, 0 XP (any attacker) | **Elimination** |

> **Note:** A "Kill" result against a player applies a 1-level demotion — not true elimination — unless the player is already at the Death Floor (Level 0, 0 XP).

## Tier Scaling

| Level | Tier | Visual State |
|---|---|---|
| 0 – 4 | Baby | Small / Larval |
| 5 – 7 | Teen | Adolescent Hunter |
| 8 – 10 | Adult | Apex Deep-Sea Entity |

## Boost System
Hold the boost input to temporarily increase movement speed at the cost of Energy. Boost is ignored when Energy reaches zero. Energy regenerates passively while you are not boosting.

## Bioluminescence
The local player spawns a global dark overlay at match start. Each fish emits a light radius that drains over time. Eating **Luminous Orbs** (a floating collectible) restores your light. Running out of light does not eliminate you, but navigating in the dark puts you at a severe disadvantage.

# Controls Documentation

## Desktop

| Input | Action |
|---|---|
| Arrow Keys | Move |
| Shift/Space (hold) | Boost |

## Mobile / Touch

| Input | Action |
|---|---|
| Virtual Joystick (left side) | Move |
| Boost Button (right side) | Boost |

# Limitations and Issues

## Known Issues

**1. Boost Stacking (Infinite Speed)**
Collecting multiple copies of the same timed collectible (e.g., Lanter Fish) currently stacks their speed multipliers. Eating three Lantern Fish in quick succession makes the player uncontrollably fast. Fix requires `StatManager.gd` to check whether a stat is already boosted; if so, refresh the timer rather than appending a new multiplier.


## Unimplemented Features

The following features are scheduled for post-submission phases and are not present in the current build:

- **NPC Level Restrictions** — min and max spawn-level limits so the ecosystem spawns different NPCs that vary in difficulty
- **Additional Collectible Variants** — expanded `EffectComponent` usage for max energy buffs, bite power multipliers, and turn rate enhancements
- **Final XP Tuning** — adjusting the `XP_THRESHOLDS` array to match the pacing of the fast-combat system
- **Gene Cards (Roguelike Mutations)** — a non-blocking level-up overlay offering 3 random stat or passive mutation cards; deferred to a post-launch / V2 update

# Graphics and Tools
- Game Engine: [Godot](https://godotengine.org/download/windows/)
- Pixel Art: [Pixilart Studio](https://www.pixilart.com/)
- Audio Editing: [Audacity](https://www.audacityteam.org)

# Credits

Credits to the artists who made sprites used in this project:
- Itch.io Game Assets: [Itch.io](https://itch.io/game-assets)
- Craftpix Game Assets: [Craftpix](https://craftpix.net/)

Credits to the creators of free sound effects used in this project:
- Pixabay Sound Effects: [Pixabay](https://pixabay.com/)

A direct link to each respective download is provided in [CREDITS.md](CREDITS.md). These artists indirectly supported this project's success!

Sprites not credited were custom-built by the creators and are free for personal, non-commercial use.

# Getting Started: Players
To properly try and experience **`the-midnight-munch`**, follow these steps:
1. Download the exe file in the [releases section]() of the repository.
2. Run the exe and enjoy the game!

# License

- This game was created passionately as a machine problem for CMSC 197 - Game Design and Development.
- **All credits for sprites and original inspiration go to their respective owners.**
- Sprites not credited were custom-built by the creators and are free for personal, non-commercial use.
