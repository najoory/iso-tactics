# Development Plan: Tactical Hex Game

## Tech Stack
*   **Engine:** Godot Engine 4.6 (Forward Plus)
*   **Language:** GDScript

---

## Iteration 1-5: Foundations, AI, and persistence
*   [DONE] Hexagonal Grid & Isometric Rendering.
*   [DONE] Basic AI & Ranged Combat.
*   [DONE] Unit Archetypes (Knight, Archer, Ballista).
*   [DONE] Campaign Persistence & Scaling Difficulty.

---

## Iteration 6: Strategy, Permadeath, and Tactical Depth
*   [DONE] **Advanced Ranged Mechanics:** Obstacles reduce range (-1); Melee penalty for Archers (-50% DMG).
*   [DONE] **Permadeath:** Units that die in battle are permanently removed from the roster.
*   [DONE] **Strategic Orders:** Right-click to assign persistent targets/destinations (Red/Blue lines).
*   [DONE] **Hold Position:** Units act as defensive turrets, picking off closest enemies without moving.
*   [DONE] **Unified Execution:** "End Turn" triggers all strategic orders and defensive actions.

---

## Iteration 7: Siege Tactics & Destructible Environments
*   [DONE] **Veteran Progression:** All survivors automatically promote (+2 HP, +1 DMG) after a stage.
*   [DONE] **Destructible Terrain:** Forests (2 HP), Walls (8 HP), and Houses (10 HP) can be demolished.
*   [DONE] **Siege Damage:** Ballistas deal x2 damage to structures (Houses/Walls).
*   [DONE] **Architectural Generation:** Maps now feature "Wilderness", "Village", or "Boss Castle" biomes.
*   [DONE] **UI Polish:** Hovering shows Terrain HP; redundant "End Turn" button removed in favor of "Execute Orders".

---

## Iteration 8: Fog of War & Stealth (Upcoming)
*   **Tasks:**
	*   Implement Fog of War (Hexes hidden until within unit vision range).
	*   Add "Scout" class or ability to Archers (increased vision).
	*   Add "Hidden" state for enemies in Forests.
