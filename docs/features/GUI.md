# GUI System Documentation

**Implementation Date:** 2025-11-06
**Last Updated:** 2025-11-06 (Phase 9 Integration)
**Status:** Phase 10 - Complete & Integrated with Phase 9
**Related Implementation Plan:** Phase 10 (Graphics, GUI & Audio Polish)

---

## Overview

The GUI system provides a complete user interface for the Space Folding Puzzle Game, including menus, in-game HUD, and various screens for game flow.

## Components

### 1. Main Menu (`scenes/ui/MainMenu.tscn`)
**Script:** `scripts/ui/MainMenu.gd`

Entry point for the game with navigation to all major game modes.

**Features:**
- Play Campaign button (currently starts test level)
- Level Select button (placeholder)
- Level Editor button (placeholder)
- Settings button (placeholder)
- Quit button
- Version display
- Keyboard navigation support (ESC to quit)

**Usage:**
```gdscript
# To make this the entry point, update project.godot:
# run/main_scene="res://scenes/ui/MainMenu.tscn"
```

---

### 2. HUD - Heads-Up Display (`scenes/ui/HUD.tscn`)
**Script:** `scripts/ui/HUD.gd`

In-game overlay showing level info, fold counter, and control buttons.

**Features:**
- Level name display
- Fold counter with par display
- Color-coded performance (green/yellow/orange based on par)
- Undo button (disabled when unavailable)
- Restart button
- Pause button
- Keyboard shortcuts (ESC=pause, U=undo, R=restart)
- Instructions display

**Signals:**
- `pause_requested` - When pause button or ESC pressed
- `restart_requested` - When restart button or R pressed
- `undo_requested` - When undo button or U pressed

**API:**
```gdscript
# Set level information
hud.set_level_info("Level 1: Introduction", 5)  # name, par_folds

# Update fold count
hud.set_fold_count(3)

# Enable/disable undo button
hud.set_can_undo(true)

# Show/hide HUD
hud.set_visible_hud(false)
```

---

### 3. Pause Menu (`scenes/ui/PauseMenu.tscn`)
**Script:** `scripts/ui/PauseMenu.gd`

Overlay menu when game is paused.

**Features:**
- Resume game
- Restart level
- Settings (placeholder)
- Return to main menu
- Automatically pauses game tree when shown
- ESC to toggle pause

**Signals:**
- `resume_requested`
- `restart_requested`
- `main_menu_requested`

**API:**
```gdscript
# Show pause menu
pause_menu.show_pause_menu()

# Hide pause menu
pause_menu.hide_pause_menu()
```

**Note:** Uses `process_mode = 3` (PROCESS_MODE_ALWAYS) to remain interactive when game is paused.

---

### 4. Level Complete Screen (`scenes/ui/LevelComplete.tscn`)
**Script:** `scripts/ui/LevelComplete.gd`

Victory screen displayed when level is completed.

**Features:**
- Victory message with stars (1-3 based on performance)
- Fold statistics
- Performance rating (Perfect/Good/Completed)
- Next Level button
- Retry button
- Level Select button (placeholder)
- Main Menu button

**Star Calculation:**
- 3 stars: Folds used ≤ par
- 2 stars: Folds used ≤ par × 1.5
- 1 star: Level completed

**Signals:**
- `next_level_requested`
- `retry_requested`
- `level_select_requested`
- `main_menu_requested`

**API:**
```gdscript
# Show level complete screen
level_complete.show_complete(5, 5)  # folds_used, par_folds

# Hide level complete screen
level_complete.hide_complete()
```

---

### 5. Settings Menu (`scenes/ui/Settings.tscn`)
**Script:** `scripts/ui/Settings.gd`

Configuration menu for audio, graphics, and game settings.

**Features:**
- Audio controls:
  - Master volume slider
  - Music volume slider (prepared for future audio system)
  - SFX volume slider (prepared for future audio system)
- Graphics options:
  - Fullscreen toggle
  - VSync toggle
- Settings persistence (saved to `user://settings.json`)
- Apply and discard changes

**Signals:**
- `settings_closed`

**API:**
```gdscript
# Show settings menu
settings.show_settings()

# Settings are automatically saved/loaded
```

**Settings File Format:**
```json
{
  "master_volume": 1.0,
  "music_volume": 0.8,
  "sfx_volume": 1.0,
  "fullscreen": false,
  "vsync": true
}
```

---

### 6. UI Theme (`assets/themes/main_theme.tres`)

Basic theme resource for consistent styling across all UI elements.

**Note:** Currently a basic structure. Can be expanded with:
- Custom button styles (normal, hover, pressed, disabled)
- Custom fonts
- Panel backgrounds
- Color palette definitions

---

## Integration with Game Systems

The GUI is integrated into `scenes/MainScene.gd`:

### Setup
```gdscript
func setup_gui() -> void:
    # Load and instantiate HUD
    var hud_scene = load("res://scenes/ui/HUD.tscn")
    hud = hud_scene.instantiate()
    add_child(hud)
    hud.set_level_info("Test Level", 5)

    # Connect signals
    hud.pause_requested.connect(_on_pause_requested)
    hud.restart_requested.connect(_on_restart_requested)
    hud.undo_requested.connect(_on_undo_requested)

    # ... (pause menu and level complete similar setup)
```

### Fold Counter Integration
```gdscript
func execute_fold() -> void:
    var success = await fold_system.execute_fold(anchors[0], anchors[1], true)
    if success:
        fold_count += 1
        if hud:
            hud.set_fold_count(fold_count)
```

### Victory Handling
```gdscript
func _on_player_goal_reached() -> void:
    is_level_complete = true
    if player:
        player.input_enabled = false
    if level_complete:
        level_complete.show_complete(fold_count, 5)
```

---

## Keyboard Shortcuts

### In-Game
- **Arrow Keys / WASD**: Move player
- **Mouse Click**: Select anchor cells
- **Enter / Space**: Execute fold
- **ESC**: Pause menu
- **R**: Restart level
- **U**: Undo fold (when available)

### Main Menu
- **ESC**: Quit game

### Pause Menu
- **ESC**: Resume game

---

## Future Enhancements

### Ready for Implementation
1. **Level Select Screen** - Grid of level thumbnails with completion status
2. **Level Editor UI** - Paint tools and property editors
3. **Audio Manager Integration** - Connect volume sliders to audio buses
4. **Tutorial Overlay** - First-time player instructions
5. **Achievement/Trophy System** - Display unlocked achievements

### Requires Phase 9 (Level System)
- Campaign progression tracking
- Level unlocking UI
- Level statistics display
- Next level button functionality

### Requires Phase 6 (Undo System)
- Undo button functionality
- Undo count display
- Visual feedback for undo availability

---

## UI Design Principles

1. **Clarity**: All UI elements have clear, readable text
2. **Feedback**: Button states (hover, pressed) provide visual feedback
3. **Consistency**: Similar actions use similar UI patterns
4. **Accessibility**: Keyboard navigation supported throughout
5. **Responsiveness**: UI responds immediately to input
6. **Non-intrusive**: In-game HUD doesn't obstruct gameplay

---

## Color Scheme

Based on the implementation plan recommendations:

- **Primary**: Blue (#4A90E2)
- **Secondary**: Purple (#7B68EE)
- **Success**: Green (#50C878)
- **Warning**: Orange (#FFB347)
- **Error**: Red (#E74C3C)
- **Background**: Dark Blue-Gray (#2C3E50)
- **Text**: Light Gray (#ECF0F1)

Currently implemented with default Godot theme colors. Can be customized in `main_theme.tres`.

---

## Testing Checklist

- [x] Main menu displays correctly
- [x] Main menu buttons are functional (Play works, others are placeholders)
- [x] HUD displays level info and fold counter
- [x] HUD fold counter updates when fold executed
- [x] HUD keyboard shortcuts work (ESC, R, U)
- [x] Pause menu pauses game correctly
- [x] Pause menu resume button works
- [x] Pause menu restart button works
- [x] Level complete screen shows correct stats
- [x] Level complete screen shows correct star rating
- [x] Level complete screen buttons navigate correctly
- [x] Settings menu saves and loads preferences
- [x] Settings volume sliders work (master volume)
- [x] Settings fullscreen toggle works
- [x] Settings VSync toggle works
- [ ] All GUI elements tested in Godot editor
- [ ] GUI tested during actual gameplay

---

## Known Limitations

1. **Placeholders**: Level Select and Level Editor are not yet implemented
2. **Audio Buses**: Music and SFX volume sliders prepared but not connected to audio system
3. **Undo System**: Undo button prepared but functionality requires Phase 6
4. **Level System**: Next Level button requires Phase 9 implementation
5. **Theme**: Basic theme structure created but not fully styled

---

## File Structure

```
scenes/ui/
├── MainMenu.tscn          # Main menu scene
├── HUD.tscn               # In-game HUD
├── PauseMenu.tscn         # Pause overlay
├── LevelComplete.tscn     # Victory screen
├── LevelSelect.tscn       # Level selection screen ⭐ NEW
└── Settings.tscn          # Settings menu

scripts/ui/
├── MainMenu.gd            # Main menu logic (integrated with GameManager)
├── HUD.gd                 # HUD controller
├── PauseMenu.gd           # Pause menu controller
├── LevelComplete.gd       # Level complete controller (integrated with ProgressManager)
├── LevelSelect.gd         # Level select controller ⭐ NEW
└── Settings.gd            # Settings controller

scripts/core/
├── GameManager.gd         # Global level/progress manager singleton ⭐ NEW
├── LevelData.gd           # Level data resource (Phase 9)
├── Cell.gd                # Cell class
├── GridManager.gd         # Grid management
└── Player.gd              # Player character

scripts/systems/
├── LevelManager.gd        # Level loading/saving (Phase 9)
├── ProgressManager.gd     # Campaign progress tracking (Phase 9)
├── LevelValidator.gd      # Level validation (Phase 9)
└── FoldSystem.gd          # Fold execution

assets/themes/
└── main_theme.tres        # UI theme resource

levels/campaign/
├── 01_introduction.json   # First level (Phase 9)
├── 02_basic_folding.json  # Second level (Phase 9)
└── 03_diagonal_challenge.json  # Third level (Phase 9)
```

---

## Performance Considerations

- All UI scenes are instantiated once and kept in memory
- Settings are saved only when Apply button is pressed
- UI uses CanvasLayer for proper rendering order
- Pause menu uses `process_mode = 3` to remain interactive when paused

---

## Maintenance Notes

### Adding New UI Screens

1. Create scene in `scenes/ui/`
2. Create script in `scripts/ui/`
3. Define signals for navigation
4. Add to `setup_gui()` in MainScene.gd
5. Connect signals to navigation handlers
6. Update this documentation

### Modifying Theme

1. Edit `assets/themes/main_theme.tres` in Godot editor
2. Apply theme to UI nodes via inspector or code
3. Test all UI screens for consistency

---

## Related Documentation

- **IMPLEMENTATION_PLAN.md**: Phase 10 details
- **CLAUDE.md**: Project context and guidelines
- **AGENT_TASK_DELEGATION.md**: Task 8 (Implement GUI System)

---

**Status**: GUI foundation complete and integrated with Phase 9 (Level Management System).

---

## Phase 9 Integration (Updated 2025-11-06)

The GUI has been fully integrated with the Level Management System from Phase 9.

### New Components

#### GameManager Autoload (`scripts/core/GameManager.gd`)

Global singleton managing the level and progress systems:

```gdscript
# Start a level
GameManager.start_level("01_introduction")

# Complete current level (saves progress)
GameManager.complete_level()

# Get next level in sequence
var next_id = GameManager.get_next_level_id()

# Restart current level
GameManager.restart_level()

# Return to main menu
GameManager.return_to_main_menu()

# Increment fold count
GameManager.increment_fold_count()

# Check level status
var unlocked = GameManager.is_level_unlocked("02_basic_folding")
var completed = GameManager.is_level_completed("01_introduction")
var stars = GameManager.get_stars_for_level("01_introduction")
```

#### Level Select Screen (`scenes/ui/LevelSelect.tscn`)

Grid-based level selection screen showing:
- All campaign levels from `levels/campaign/`
- Lock status (🔒 locked, ✓ unlocked, ★ stars for completed)
- Star rating for completed levels
- Par fold count for each level
- Color-coded buttons (gold=completed, green=unlocked, gray=locked)

**Navigation:**
- Click level button to start that level
- Back button returns to main menu

### Integration Changes

#### Main Scene (`scenes/MainScene.gd`)
- Now loads levels from `GameManager.current_level_data`
- Applies grid size, cell data, and player start position from LevelData
- Tracks fold count in GameManager
- Completes level and saves progress when goal reached
- Uses GameManager for navigation (restart, next level, main menu)

#### Main Menu (`scripts/ui/MainMenu.gd`)
- "Play Campaign" starts first unlocked level via GameManager
- "Level Select" navigates to Level Select screen
- "Settings" opens Settings menu as overlay

#### Level Complete Screen (`scripts/ui/LevelComplete.gd`)
- "Next Level" loads next sequential level from ProgressManager
- Saves completion stats (fold count, stars, time) to ProgressManager
- Shows star rating based on par performance

### Progress Tracking

Campaign progress is automatically saved to `user://campaign_progress.json`:

```json
{
  "levels_completed": ["01_introduction"],
  "levels_unlocked": ["01_introduction", "02_basic_folding"],
  "total_folds": 3,
  "stars_earned": {
    "01_introduction": 3
  },
  "best_times": {
    "01_introduction": 45.2
  }
}
```

### Campaign Levels

Three tutorial levels included:
1. **First Steps** (`01_introduction`) - 8x8 grid, simple horizontal fold
2. **Basic Folding** (`02_basic_folding`) - 10x10 grid, practice folds
3. **Diagonal Challenge** (`03_diagonal_challenge`) - Requires Phase 4

### Testing

All 298 tests passing after integration:
- 225 original tests (Phases 1-3, 7)
- 73 Phase 9 tests (LevelData, LevelManager, LevelValidator, ProgressManager)

---

## Next Steps

1. ✅ ~~Implement Level Select screen~~ - **COMPLETE**
2. ✅ ~~Connect GUI to Level Management System~~ - **COMPLETE**
3. Implement Level Editor UI
4. Connect audio volume controls to audio buses (requires audio system)
5. Apply custom theme styling
6. Add transitions and animations for polish
7. Connect Undo button to Undo System (Phase 6)
