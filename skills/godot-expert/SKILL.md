---
name: godot-expert
description: Expert GDScript development and Godot Editor automation. Use when modifying game logic, refactoring scenes, or using Godot AI MCP tools for editor-side operations.
---

# Godot Expert

## Overview
This skill optimizes the development of Godot 4.x projects by providing specialized workflows for GDScript authoring, scene manipulation, and editor automation via the Godot AI MCP server.

## Specialized Workflows

### 1. Editor Session Management
Always verify the active editor session before performing write operations.
- Use `session_manage(op="list")` to find available editors.
- Use `session_activate(session_id=...)` to pin commands to a specific project.
- Check `editor_state()` to ensure the editor is in the "ready" or "playing" state.

### 2. Atomic Scene Edits
For complex scene mutations (e.g., creating a node, setting its properties, and attaching a script), prefer `batch_execute`.
- **Benefits**: Atomic-on-failure semantics, single undo step, and reduced tool-call overhead.
- **Example**: Creating a styled enemy.
  ```json
  {
    "command": "batch_execute",
    "params": {
      "commands": [
        {"command": "create_node", "params": {"type": "Sprite2D", "name": "Enemy"}},
        {"command": "set_property", "params": {"path": "/Main/Enemy", "property": "texture", "value": "res://assets/enemy.png"}},
        {"command": "attach_script", "params": {"path": "/Main/Enemy", "script_path": "res://scripts/enemy.gd"}}
      ]
    }
  }
  ```

### 3. GDScript Authoring Standards
- **Strong Typing**: Always use explicit types for variables and function returns (e.g., `var health: int = 10`).
- **Signal Safety**: Use `is_node_ready()` checks in setters that modify UI.
- **Node Access**: Prefer `@onready` vars with unique names or absolute scene paths for stability.

## Performance & Context Efficiency
To minimize token usage and latency:
- **Cache Symbols**: Use `script_manage(op="find_symbols")` to understand a script's interface without reading the full source.
- **Surgical Reads**: Use `start_line` and `end_line` in `read_file` to fetch only relevant functions.
- **Ignore Internal Folders**: Ensure `.godot/` and `.git/` are in `.geminiignore`.

## Testing Workflow
Follow the project's testing mandate defined in `GEMINI.md`:
1. Run unit tests: `godot --headless -s tests/test_campaign_state.gd`.
2. Run UI tests: `godot --headless -s tests/test_ui_initialization.gd`.
3. Add new test cases for every functional change.
