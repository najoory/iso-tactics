# Development Plan: Tactical Hex Game

## Tech Stack
*   **Engine:** Godot Engine 4.6 (Forward Plus)
*   **Language:** GDScript

---

## Iteration 1-13: Core, Immersive Feedback & Sound
*   [DONE] Hexagonal Grid, Basic AI, Persistent Campaign.
*   [DONE] Professional Art Upgrade & Battle Chatter.
*   [DONE] Dynamic Scenarios (Ambush, Horde, Maze, etc.).
*   [DONE] Fog of War & Stealth Mechanics.
*   [DONE] Sound Design Foundation (AudioManager singleton).

---

## Iteration 14: Cavalry, Economy & Massive Battles (Current)
*   **Goal:** Expand unit variety and scale the battlefield to epic proportions.
*   **Cavalry Unit:**
	*   **High Mobility:** 8-10 AP, ignore Z-sorting of friendly units.
	*   **Charge Mechanic:** Damage bonus scales with distance moved in a straight line.
	*   **Vulnerability:** Massive damage penalty in Forest/Mountains; weak to Ballistae.
*   **Massive Battle Scaling:**
	*   **Chess-like Starting Roster:** Standardize starting armies (e.g., 3 Knights, 2 Archers, 2 Cavalry, 1 Ballista).
	*   **Balanced Spawning:** Refine AI counts to match the player's scaled-up roster.
*   **Coin Economy:**
	*   **Earning:** 10g per kill, 50g per victory.
	*   **Shop Menu:** Spend coins between battles for extra reinforcements or permanent stat boosts.

---

## Iteration 15: Advanced UI & Settings
*   **Goal:** Provide user customization and better onboarding.
*   **Settings Menu:**
	*   **Logic:** Integrated with `config/game.json`.
	*   **Options:** Toggle Fog of War, Toggle UI Help/Tips, Audio Volume sliders.
	*   **Visuals:** Unique PixelLab-generated background (e.g., a technical blueprint or a military desk).
*   **Controls Screen:**
	*   Full-screen reference showing WASD, Mouse buttons, and hotkeys.
	*   Thematic background (e.g., an old training manual or wall scroll).

---

## Iteration 16: Strategic Objectives & Factions
*   **Goal:** Introduce mission variety beyond simple elimination.
*   **New Objectives:**
	*   **Regicide:** One unit is designated the "King" (High HP, low AP). Loss of King = Defeat.
	*   **Capture the Flag:** Move a unit to a specific "Goal" hex and hold it for 1 turn.
	*   **Rescue:** Reach a "Prisoner" unit in the enemy half and escort them back.
*   **Faction Wars:**
	*   Select Knights, Orcs, or Assassins at start.
	*   Orcs and Knights are enemies; Assassins are neutral/mercenaries available to both.

---

## Iteration 17: Narrative Campaigns
*   **Goal:** Contextualize the battles with story.
*   **Structure:** Each faction gets a 10-stage narrative arc with unique dialogue.
*   **Lore:** Integrated into the Level Intro UI.

---

## Iteration 18: Quality Assurance & Shipment
*   **Tasks:**
	*   Decouple `main.gd` into modular managers.
	*   Unit test coverage to 85%+.
	*   Export presets for Linux, Windows, and Android.
