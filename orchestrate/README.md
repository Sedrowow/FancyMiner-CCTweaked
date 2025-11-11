# Orchestrate Server Modules

This directory contains modular components for the orchestration server that coordinates multi-turtle mining operations.

## Module Overview

### `display.lua`
Handles all screen output (monitor or terminal):
- Main overview display showing all workers
- Worker detail view with individual statistics
- Touch event handling for interactive display
- Color-coded status indicators

### `state.lua`
Manages server state persistence:
- State structure definition
- Save/load operations to disk
- State recovery after restart

### `firmware.lua`
Handles firmware distribution to workers:
- Disk validation and checking
- File reading from floppy disk
- Chunked file transfer over modem
- Firmware deployment to individual workers

### `resource_manager.lua`
Manages shared resource access (fuel/output chests):
- Queue management for resource requests
- Lock/unlock mechanism with timeouts
- Automatic timeout detection and recovery
- Resource grant coordination

### `zone_manager.lua`
Calculates and assigns mining zones:
- Zone calculation based on quarry dimensions
- GPS zone boundary creation
- Worker-to-zone matching by position
- Initial direction calculation based on chest positions

### `message_handler.lua`
Central message routing and handling:
- Dispatcher for all message types
- Worker lifecycle management (online, ready, complete)
- Deployment coordination
- Status updates and synchronization

## Usage

The main `orchestrate_server.lua` file loads all modules and coordinates their interaction. Each module is designed to be independent and testable.

## Design Principles

1. **Separation of Concerns**: Each module has a single, well-defined responsibility
2. **Loose Coupling**: Modules communicate through defined interfaces
3. **State Management**: Centralized state with clear ownership
4. **Error Handling**: Graceful degradation and recovery
5. **Readability**: Clear function names and comprehensive comments
