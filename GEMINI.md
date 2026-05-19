# Engineering Standards & Testing Workflow

## 🛡️ Testing Mandate
To ensure stability as the project grows, all functional changes must be accompanied by automated verification.

### 1. Unit Testing (`tests/test_campaign_state.gd`)
Focuses on core logic (state transitions, progression, arithmetic).
*   **Run command**: `godot --headless -s tests/test_campaign_state.gd`
*   **When to run**: After any change to `campaign_state.gd` or core math logic in `main.gd`.

### 2. UI Initialization Testing (`tests/test_ui_initialization.gd`)
Verifies that scenes load without crashes and dynamic UI nodes are correctly instantiated.
*   **Note**: Requires manual singleton setup in the script if run via `--headless -s`.
*   **When to run**: After adding new dynamic UI elements or refactoring scene structures.

## 🎨 UI & Asset Conventions
*   **Thematic Assets**: Always prefer pixel-art textures (Parchment, Stone, Wood) generated via Pixellab over solid `ColorRect` components.
*   **Dynamic Styling**: When possible, apply styles in `_ready()` via `add_theme_stylebox_override` to maintain script-based control over the UI overhaul.
*   **Centering**: Always use `Control.PRESET_CENTER` and `BoxContainer.ALIGNMENT_CENTER` for major alerts to ensure widescreen compatibility.

## 🚀 Future Sessions
1.  **Always** run `tests/test_campaign_state.gd` before finishing a task.
2.  If adding a new gameplay feature, add a corresponding test case to `tests/`.
3.  If adding a new UI screen, ensure it is added to the `test_ui_initialization.gd` suite.

## 🔄 Workflow & Session Management
*   **Frequent Commits:** Commit work-in-progress every 5-10 turns or after completing each logical sub-task. This prevents large batches of unstaged files and makes restoration easier.
*   **Plan Persistence:** Always keep the current tactical plan updated in `development_plan.md`. Every session should begin by reviewing and, if necessary, updating this file to reflect the current objective.
