# Development Guide

## Hot Reload

During development, ESW supports automatic recompilation of `.esw` files when they change.

### Using the Watch Script

The easiest way to enable hot reload is to use the provided watch script:

```bash
./scripts/dev_watch.sh
```

This script:
- Watches all `.esw` files in your project (excluding `.build` and `.git` directories)
- Automatically runs `swift build` when changes are detected
- Shows build status (success/failure)

### Requirements

The watch script requires `fswatch`:

```bash
brew install fswatch
```

### Manual Approach

If you prefer not to use `fswatch`, you can manually rebuild:

```bash
# After editing .esw files
swift build
```

### Integration with SwiftPM

ESW's build plugin automatically discovers and compiles `.esw` files during the build process, so hot reload works out of the box with the watch script.

### Tip: Combine with Server Restart

For full-stack hot reload, combine the watch script with your server's restart mechanism:

```bash
# Terminal 1: Watch ESW files
./scripts/dev_watch.sh

# Terminal 2: Run your app with auto-restart
swift run App --watch
```
