#!/usr/bin/env python3
"""
Generate games.json manifest from directory structure.

Scans all folders in the directory where this script is located,
creates a games.json file containing all discovered games/apps.

Usage:
    python3 generate_manifest.py [output-file]

If no output file is specified, defaults to 'games.json'
"""

import os
import json
import sys
from pathlib import Path


def folder_name_to_friendly_name(folder_name):
    """Convert folder name to friendly display name."""
    # Replace underscores and hyphens with spaces
    name = folder_name.replace('_', ' ').replace('-', ' ')
    # Title case each word
    name = ' '.join(word.capitalize() for word in name.split())
    return name


def scan_directories(root_dir):
    """Scan directories and find game/app folders."""
    games = []
    
    # Get all subdirectories
    try:
        entries = os.listdir(root_dir)
    except PermissionError:
        print(f"❌ Permission denied reading {root_dir}", file=sys.stderr)
        return games
    
    for entry in sorted(entries):
        full_path = os.path.join(root_dir, entry)
        
        # Skip if not a directory
        if not os.path.isdir(full_path):
            continue
        
        # Skip hidden directories and common system folders
        if entry.startswith('.') or entry in ['node_modules', '__pycache__', '.git']:
            continue
        
        # Check if directory has index.html (indicator of a game/app)
        index_path = os.path.join(full_path, 'index.html')
        if os.path.isfile(index_path):
            game_id = entry
            game_name = folder_name_to_friendly_name(entry)
            
            game_entry = {
                "id": game_id,
                "name": game_name,
                "folder": entry
            }
            
            games.append(game_entry)
            print(f"✓ Found: {game_name} (ID: {game_id})")
        else:
            print(f"  Skipped: {entry} (no index.html)")
    
    return games


def generate_manifest(output_file='games.json'):
    """Generate the games manifest file."""
    # Get the directory where this script is located
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    print(f"📁 Scanning directory: {script_dir}")
    print()
    
    # Scan for games
    games = scan_directories(script_dir)
    
    print()
    print(f"📊 Found {len(games)} game(s)/app(s)")
    
    # Write to file
    output_path = os.path.join(script_dir, output_file)
    
    try:
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(games, f, indent=2, ensure_ascii=False)
        
        print(f"✅ Manifest written to: {output_path}")
        print(f"   Total size: {len(json.dumps(games))} bytes")
        return True
    except IOError as e:
        print(f"❌ Error writing manifest: {e}", file=sys.stderr)
        return False


def main():
    """Main entry point."""
    output_file = 'games.json'
    
    # Parse command line arguments
    if len(sys.argv) > 1:
        if sys.argv[1] in ['--help', '-h']:
            print(__doc__)
            sys.exit(0)
        else:
            output_file = sys.argv[1]
    
    success = generate_manifest(output_file)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
