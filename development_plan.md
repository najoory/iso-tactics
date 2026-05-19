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

## Iteration 9: Victory Screen Statistics (Current)
*   **Goal:** Provide a thematic visual summary of battle casualties.
*   [DONE] **Casualty Tracking:** Track killed player and enemy units during the battle in `main.gd`.
*   [DONE] **Visual Layout:** Create a "Graveyard" view in the Victory screen.
	*   Player losses on the left, Enemy losses on the right.
	*   Use the "south-west" sprite for deceased units.
	*   Arrange units in a mini-hex grid pattern at the center of their respective sides.
*   [DONE] **Refactor Game Over UI:** Integrate the casualty statistics into the existing Victory popup.

---

## Iteration 10: Fog of War, Stealth & Polish (Upcoming)

*   **Tasks:**
	*   Implement Fog of War (Hexes hidden until within unit vision range).
	*   Add "Scout" class or ability to Archers (increased vision).
	*   Add "Hidden" state for enemies in Forests.
	*   Final UI Skinning (Parchment/Stone/Wood themes applied repo-wide).
	*   Walk/Attack animations integration.
