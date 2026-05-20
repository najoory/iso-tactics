# Development Plan: Tactical Hex Game

## Tech Stack
*   **Engine:** Godot Engine 4.6 (Forward Plus)
*   **Language:** GDScript

---

## Iteration 1-11: Core Foundations & Immersive Scenarios
*   [DONE] Hexagonal Grid, Basic AI, Persistent Campaign.
*   [DONE] Professional Art Upgrade (8-Directional Units).
*   [DONE] Victory Statistics & Visual Graveyard.
*   [DONE] Battlefield HUD (Stage, Turn Banners, Dynamic Victory Chance).
*   [DONE] Battle Chatter (Personality-driven unit dialogue).
*   [DONE] Dynamic Level Scenarios & Orc Maze (11 level types).

---

## Iteration 12: Fog of War, Stealth & Tactical Polish
*   **Goal:** Deepen tactical complexity with environment bonuses, stealth mechanics, and improved UI feedback.
*   [DONE] **Balance Fixes:** Archer Forest/AP bonuses implemented.
*   [DONE] **UI Pathing:** Hexagon-based path highlighting with range feedback.
*   [DONE] **Stealth & Fog:** Dynamic vision system and enemy hiding in forests.
*   [DONE] **Difficulty Balancing:** Smoothed enemy count and level scaling for early stages.
*   [DONE] **UI Skinning:** Thematic intro and game over screens finalized.

---

## Iteration 13: Sound Design
*   **Goal:** Epic orchestral music and punchy SFX via AI MCP tools.
*   **Tasks:**
	*   **Music (Suno AI MCP):** Orchestral tactical themes and menu music.
	*   **SFX (ElevenLabs/AudioGen):** Unit-specific impact and death sounds.
	*   **AudioManager:** Centralized Godot singleton for mixing and BGM cross-fading.

---

## Iteration 14: Cavalry & Coin Economy
*   **Goal:** Add a new unit type and a persistent economic layer.
*   **Cavalry Unit:**
	*   **Bonus:** High AP (8-10) and "Charge" damage (bonus dmg based on distance moved).
	*   **Vulnerability:** Cannot enter Forest/Mountain. Low defense when standing still.
*   **Economic System:**
	*   **Coins:** Earned by killing enemies (10g) and winning stages (50g).
	*   **The Shop:** Between-battle menu to spend coins on extra recruits or specific training.
	*   **Mercenaries:** Hire Assassins regardless of your primary faction.

---

## Iteration 15: Faction Wars
*   **Goal:** Choose your side and fight against shifting alliances.
*   **Faction Selection:** Select Knights, Orcs, or Assassins at the start of a new game.
*   **Mixing Logic:**
	*   Orcs and Knights are arch-enemies (never on the same side).
	*   Assassins can ally with either (mercenary logic).
	*   Enemies can be mixed: e.g., an Orc Horde supported by Shadow Assassins.

---

## Iteration 16: Narrative Campaigns
*   **Goal:** Move beyond endless mode with character-driven stories.
*   **Campaign Structure:** Start, Middle, and End-game objectives for each faction.
*   **Lore Integration:** Unique intro/outro dialogues for key stages to tell the story of the chosen faction's struggle for dominance.

---

## Iteration 17: Quality Assurance & Shipment
*   **Tasks:**
	*   **Refactoring:** Decouple `main.gd` into modular managers.
	*   **Test Coverage:** Increase unit test coverage to 85%+.
	*   **Multi-Platform Export:** Presets for Linux, Windows, and Android.
	*   **CI/CD:** Automated builds via GitHub Actions.
