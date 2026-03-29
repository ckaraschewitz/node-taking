# Node Taking

Node Taking is a minimal macOS Markdown notes app built with SwiftUI.

It lets you choose a local workspace folder and manage notes as Markdown files with a desktop-first writing experience. The app includes folder-based navigation, timeline and canvas views, tag support, import/export actions, and lightweight Markdown formatting commands.

## Features

- Create, edit, duplicate, and delete Markdown notes
- Organize notes in folders inside a local workspace
- Browse notes in folder, timeline, and canvas lenses
- Add and filter by tags
- Import and export notes as JSON bundles
- Use built-in Markdown formatting actions for headings, lists, quotes, and code blocks
- Switch between system, English, and German language preferences

## Requirements

- macOS 14 or later
- Swift 6.2 toolchain

## Run From Terminal

From the project folder:

```bash
cd "/Users/D062085/Desktop/Code Projects/1 - Node taking"
CLANG_MODULE_CACHE_PATH=/tmp/swift-module-cache swift run NodeTaking
```

This builds and launches the app in debug mode.

## Build A macOS App Bundle

To package a runnable `.app` bundle:

```bash
cd "/Users/D062085/Desktop/Code Projects/1 - Node taking"
zsh scripts/package-app.sh
open "dist/Node Taking.app"
```

## Project Structure

- `Package.swift`: Swift Package Manager definition
- `Sources/MinimalMarkdownNotes`: SwiftUI source code
- `App/Info.plist`: app bundle metadata
- `scripts/package-app.sh`: release bundle packaging script
- `dist/`: packaged app output

## Notes

- This repository currently includes generated build output and packaged app artifacts.
- The app works with files in a user-selected local workspace folder rather than storing notes in a remote database.
