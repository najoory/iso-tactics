# Development Plan: Tactical Hex Game

## Tech Stack
*   **Engine:** Godot Engine 4.6 (Forward Plus)
*   **Language:** GDScript

---

## Iteration 1-7: Foundations to Siege Tactics
*   [DONE] Hexagonal Grid, Basic AI, Unit Archetypes.
*   [DONE] Campaign Persistence, Strategic Orders, Hold Position.
*   [DONE] Destructible Terrain, Siege Damage, Architectural Generation.

---

## Iteration 8: Professional Art Upgrade & Reward System
*   [DONE] **8-Directional Units:** Integrated PixelLab sprites for all units.
*   [DONE] **Reward Overhaul:** Implemented `RewardCard` for recruitment and training post-victory.
*   [DONE] **Debug Victory:** Added fast-cheat button to main menu for testing.

---

## Iteration 9: Victory Screen Statistics
*   [DONE] **Casualty Tracking:** Track killed player and enemy units during the battle.
*   [DONE] **Visual Layout:** Created a "Graveyard" view in the Victory screen with hexagonal positioning and corpse sprites.

---

## Iteration 10: Battlefield UI & Performance
*   **Goal:** Enhance in-game HUD and optimize launch performance.
*   [DONE] **Performance Optimization:** Implemented SpriteFrames caching in `Unit.gd`, resolving launch-time freezes.
*   [DONE] **Stage Counter:** Added top-right "Stage X" indicator.
*   [DONE] **Turn Animation:** Implemented animated centered "PLAYER TURN" banner.
*   [DONE] **Victory Chance:** Added top-left dynamic victory chance indicator.

---

## Iteration 11: Immersive Feedback & Tactical Scenarios (Current)
*   **Goal:** Make the battlefield feel alive with personality-driven chatter and procedural diversity.
*   **Tasks:**
	*   **Battle Chatter:** Thematic dialogue for units (Frontline, Attack, Idle, Hard Hit) driven by `config/units.json`.
	*   **Flavor Text:** Map Victory Chance to 10 tiers of randomized phrases (e.g., "Dark Red: Start praying").
	*   **Dynamic Scenarios:** 11 distinct level types (Ambush, Horde, Cave Outbreak, Orc Maze).
	*   **Orc Maze:** Procedural labyrinth generation with a "big and tough" Overlord boss.
	*   **Level Intro UI:** Set the stage with fullscreen scenario intros.

---

## Iteration 12: Fog of War, Stealth & Polish
*   **Tasks:**
	*   Implement Fog of War (Hexes hidden until within unit vision range).
	*   Add "Scout" class or ability to Archers (increased vision).
	*   Add "Hidden" state for enemies in Forests.
	*   Final UI Skinning (Parchment/Stone/Wood themes applied repo-wide).
	*   Walk/Attack animations integration.

---

## Iteration 13: Sound Design
*   **Goal:** Epic orchestral music and punchy SFX via AI MCP tools.
*   **Tasks:**
	*   **Music (Suno AI MCP):** Orchestral tactical themes and menu music.
	*   **SFX (ElevenLabs/AudioGen):** Unit-specific impact and death sounds.
	*   **AudioManager:** Centralized Godot singleton for mixing and BGM cross-fading.
