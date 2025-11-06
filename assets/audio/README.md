# Audio Assets Directory

This directory contains all audio resources for the Space Folding Puzzle Game.

## Directory Structure

```
audio/
├── music/          # Background music tracks
└── sfx/            # Sound effects
```

## Audio Format Requirements

- **Format**: .ogg (preferred), .wav, or .mp3
- **Sample Rate**: 44.1 kHz or 48 kHz
- **Bit Depth**: 16-bit minimum
- **Channels**: Stereo for music, mono or stereo for SFX

## Required Audio Assets

### Music Tracks (music/)

#### menu.ogg
- **Type**: Background music
- **Duration**: 2-3 minutes (loopable)
- **Style**: Calm, atmospheric, puzzle-themed
- **Mood**: Welcoming, contemplative
- **Usage**: Main menu screen

#### gameplay.ogg
- **Type**: Background music
- **Duration**: 3-5 minutes (loopable)
- **Style**: Ambient, minimal, puzzle-themed
- **Mood**: Focused, contemplative, slightly mysterious
- **Usage**: During puzzle gameplay
- **Notes**: Should not be distracting or too energetic

### Sound Effects (sfx/)

#### fold.ogg
- **Type**: Action SFX
- **Duration**: 0.5-1.0 seconds
- **Style**: Whoosh/swoosh with spatial warping quality
- **Usage**: When a fold operation is executed
- **Notes**: Should feel satisfying and "crunchy"

#### selection.ogg
- **Type**: UI/Feedback SFX
- **Duration**: 0.1-0.2 seconds
- **Style**: Soft click or beep
- **Usage**: When selecting anchor points on the grid
- **Notes**: Should be subtle and not annoying

#### error.ogg
- **Type**: Feedback SFX
- **Duration**: 0.2-0.3 seconds
- **Style**: Negative beep or buzz
- **Usage**: When an invalid action is attempted (blocked fold, invalid selection)
- **Notes**: Should communicate "no" without being harsh

#### victory.ogg
- **Type**: Celebration SFX
- **Duration**: 1-2 seconds
- **Style**: Uplifting chime or fanfare
- **Usage**: When player reaches the goal
- **Notes**: Should feel rewarding

#### footstep.ogg
- **Type**: Action SFX
- **Duration**: 0.1-0.2 seconds
- **Style**: Soft step sound
- **Usage**: When player moves to a new cell
- **Notes**: Will be played with pitch variation for variety

#### button_hover.ogg
- **Type**: UI SFX
- **Duration**: 0.05-0.1 seconds
- **Style**: Very subtle tick or whoosh
- **Usage**: When hovering over UI buttons
- **Notes**: Should be very quiet and subtle

#### button_click.ogg
- **Type**: UI SFX
- **Duration**: 0.1-0.2 seconds
- **Style**: Satisfying click
- **Usage**: When clicking UI buttons
- **Notes**: Should feel responsive

#### undo.ogg
- **Type**: Action SFX
- **Duration**: 0.3-0.5 seconds
- **Style**: Reverse whoosh (like fold.ogg but backwards)
- **Usage**: When undoing a fold operation
- **Notes**: Should mirror the fold sound

## Audio Sources

### Free Audio Resources

You can find royalty-free audio assets at:
- **Music**:
  - [Incompetech](https://incompetech.com/) - Royalty-free music
  - [OpenGameArt](https://opengameart.org/) - Community audio assets
  - [Freesound](https://freesound.org/) - Community sound effects

- **SFX**:
  - [Freesound](https://freesound.org/)
  - [Zapsplat](https://www.zapsplat.com/)
  - [SoundBible](http://soundbible.com/)

### Creating Custom Audio

If creating custom audio:
1. Use a DAW like Audacity (free) or Reaper
2. Export as .ogg for best Godot compatibility
3. Normalize audio levels
4. Remove silence at start/end of files
5. Test in-game for appropriate volume levels

## Integration

The AudioManager singleton automatically loads all audio files from these directories on startup. File names (without extension) are used as keys for playing audio.

Example:
```gdscript
# Play music
AudioManager.play_music("gameplay")

# Play sound effect
AudioManager.play_sfx("fold")

# Play with pitch variation
AudioManager.play_sfx("footstep", true)
```

## Volume Mixing Guidelines

Recommended relative volumes:
- **Master**: 100%
- **Music**: 70% (ambient, should not overpower SFX)
- **SFX**: 80% (clear and noticeable)

Individual audio files should be normalized to avoid clipping, then final mixing is done through the AudioManager.

## Testing Checklist

- [ ] All required audio files present
- [ ] No audio pops or clicks at start/end
- [ ] Music loops smoothly
- [ ] SFX trigger at appropriate times
- [ ] Volume levels are balanced
- [ ] No audio distortion at max volume
- [ ] Audio enhances gameplay (not distracting)

## License Information

When sourcing audio, ensure you have appropriate licenses:
- Check attribution requirements
- Verify commercial use is allowed
- Include credits in game documentation
- Save license information with audio files
