#!/bin/bash

# Get commit message from argument, or use default
COMMIT_MESSAGE=${1:-"Update app files"}

# Add Swift source files
git add ContentView.swift
git add HeartbeatApp.swift

# Add Xcode project files
git add HeartbeatApp.xcodeproj/project.pbxproj

# Add asset catalog configuration
git add Assets.xcassets/Contents.json
git add Assets.xcassets/AppIcon.appiconset/Contents.json
git add Assets.xcassets/AccentColor.colorset/Contents.json

# Add Python scripts
git add process_icon.py

# Add documentation and config files
git add README.md
git add .gitignore

# Add this script
git add git.sh

# Commit the changes
git commit -m "$COMMIT_MESSAGE"
