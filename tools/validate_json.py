#!/usr/bin/env python3
"""
Simple JSON validation script for level files.
Validates JSON syntax and basic level structure.
"""

import json
import os
from pathlib import Path

def validate_level(file_path):
    """Validate a single level file"""
    errors = []
    warnings = []

    # Try to load JSON
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        return False, [f"JSON parse error: {e}"], []
    except Exception as e:
        return False, [f"Error reading file: {e}"], []

    # Check required fields
    required_fields = ['level_id', 'level_name', 'grid_size', 'player_start_position', 'cell_data']
    for field in required_fields:
        if field not in data:
            errors.append(f"Missing required field: {field}")

    # Validate grid_size
    if 'grid_size' in data:
        gs = data['grid_size']
        if 'x' not in gs or 'y' not in gs:
            errors.append("grid_size must have 'x' and 'y' fields")
        elif gs['x'] <= 0 or gs['y'] <= 0:
            errors.append(f"grid_size must be positive (got {gs['x']}x{gs['y']})")

    # Validate player_start_position
    if 'player_start_position' in data:
        psp = data['player_start_position']
        if 'x' not in psp or 'y' not in psp:
            errors.append("player_start_position must have 'x' and 'y' fields")
        elif 'grid_size' in data:
            gs = data['grid_size']
            if psp['x'] < 0 or psp['x'] >= gs['x'] or psp['y'] < 0 or psp['y'] >= gs['y']:
                errors.append(f"player_start_position ({psp['x']}, {psp['y']}) is outside grid bounds")

    # Check for at least one goal
    if 'cell_data' in data:
        has_goal = False
        for pos, cell_type in data['cell_data'].items():
            if cell_type == 3:  # GOAL
                has_goal = True
                break
        if not has_goal:
            errors.append("No goal cell defined (cell_type = 3)")

    # Check for level ID
    if 'level_id' in data and not data['level_id']:
        warnings.append("Level has empty ID")

    # Check difficulty
    if 'difficulty' in data:
        if data['difficulty'] < 1 or data['difficulty'] > 5:
            warnings.append(f"Difficulty {data['difficulty']} is outside typical range (1-5)")

    return len(errors) == 0, errors, warnings


def main():
    print("=== Level JSON Validation Script ===\n")

    levels_dir = Path("levels/campaign")
    if not levels_dir.exists():
        print(f"ERROR: Directory {levels_dir} not found")
        return 1

    level_files = sorted(levels_dir.glob("*.json"))

    if not level_files:
        print(f"ERROR: No JSON files found in {levels_dir}")
        return 1

    print(f"Found {len(level_files)} level files\n")

    total_levels = 0
    valid_levels = 0
    invalid_levels = 0
    total_warnings = 0

    for level_file in level_files:
        total_levels += 1
        print(f"Validating: {level_file.name}")
        print("-" * 60)

        valid, errors, warnings = validate_level(level_file)

        # Try to print level info
        try:
            with open(level_file, 'r') as f:
                data = json.load(f)
                print(f"  ID: {data.get('level_id', 'N/A')}")
                print(f"  Name: {data.get('level_name', 'N/A')}")
                if 'grid_size' in data:
                    gs = data['grid_size']
                    print(f"  Grid: {gs.get('x', '?')}x{gs.get('y', '?')}")
                print(f"  Difficulty: {data.get('difficulty', 'N/A')}")
        except:
            pass

        if valid:
            print("  Status: [VALID]")
            valid_levels += 1
        else:
            print("  Status: [INVALID]")
            invalid_levels += 1

        if errors:
            print("  Errors:")
            for error in errors:
                print(f"    - {error}")

        if warnings:
            print("  Warnings:")
            for warning in warnings:
                print(f"    - {warning}")
            total_warnings += len(warnings)

        print()

    # Summary
    print("=" * 60)
    print("VALIDATION SUMMARY")
    print("=" * 60)
    print(f"Total levels: {total_levels}")
    print(f"Valid levels: {valid_levels}")
    print(f"Invalid levels: {invalid_levels}")
    print(f"Total warnings: {total_warnings}")
    print()

    if invalid_levels == 0:
        print("✓ All levels are valid!")
        return 0
    else:
        print("✗ Some levels have errors")
        return 1


if __name__ == "__main__":
    exit(main())
