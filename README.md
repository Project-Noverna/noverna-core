# Noverna Core

A modular, performance-focused core framework for FiveM servers. Noverna Core provides the foundational infrastructure for building scalable game servers with modern architecture patterns.

## Overview

Noverna Core serves as the central component of the Noverna Framework ecosystem. It handles player management, resource coordination, and provides a unified API for other resources to interact with the server infrastructure.

## Features

### Current Implementation

- **Staged Initialization System**: Four-stage boot process ensuring dependencies load in correct order
- **Dependency Management**: Automatic retry logic for external dependencies (Cache, Database)
- **Export Management**: Controlled namespace system for exposing functionality to other resources
- **Type Safety**: Full LuaLS annotations for better IDE support and type checking
- **Logging System**: Comprehensive logging with different severity levels
- **Constants Management**: Centralized configuration and constant values
- **Validation Layer**: Input validation utilities for secure data handling

### Architecture

```
┌─────────────────────────────────────────────┐
│         Application Layer (Resources)       │
│  (noverna-inventory, noverna-jobs, etc.)   │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│         Core Layer (noverna-core)           │
│  - API Layer                                │
│  - Event System                             │
│  - Business Logic                           │
│  - Player Management                        │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│      Infrastructure Layer                   │
│  - noverna-database (PostgreSQL)            │
│  - noverna-cache (Redis)                    │
│  - ox_lib (Utilities)                       │
└─────────────────────────────────────────────┘
```

## Installation

### Prerequisites

Before installing Noverna Core, ensure you have the following dependencies:

- FiveM Server (artifact 5848 or higher)
- noverna-cache - Redis caching layer
- noverna-database - PostgreSQL database wrapper
- [ox_lib](https://github.com/overextended/ox_lib) - Utility library

See [REQUIREMENTS.md](REQUIREMENTS.md) for detailed prerequisite information.

### Setup

1. Clone or download the repository to your server's resources folder:

```
server/data/resources/noverna-core/
```

2. Configure your `server/data/server.cfg`:

```cfg
ensure noverna-database
ensure noverna-cache
ensure noverna-core
```

**Important**: The order matters. noverna-core must start after its dependencies.

3. Start your server. You should see initialization messages:

```
[NvCore] Stage 1: Early Initialization
[NvCore] Stage 1 Complete
[NvCore] Stage 2: Loading Dependencies
[NvCore] Cache loaded successfully
[NvCore] Database loaded successfully
[NvCore] Stage 2 Complete
```

## Usage

### Accessing the Core Object

```lua
-- Method 1: Direct export
local NvCore = exports["noverna-core"]:GetCoreObject()

-- Method 2: Wait for ready state (recommended)
local NvCore = exports["noverna-core"]:GetCoreObject()
NvCore.OnReady(function()
    print("Core is ready")
    -- Your initialization code here
end)
```

### Using Namespaces

Noverna Core exposes functionality through controlled namespaces:

```lua
-- Access constants
local Constants = exports["noverna-core"]:GetNamespace("Constants")
print(Constants.VERSION)

-- Access validation utilities
local Validation = exports["noverna-core"]:GetNamespace("Validation")
local isValid = Validation:ValidateString(input, 3, 50)
```

### Type Definitions Across Resources

Noverna Core provides global type definitions that can be used across all your resources. This eliminates the need to duplicate type annotations in every resource.

#### Setup for LuaLS

Create a `.luarc.json` file in your workspace root or configure your VS Code settings:

**Option 1: .luarc.json (Recommended)**

```json
{
  "workspace.library": ["server/data/resources/noverna-core"],
  "runtime.version": "Lua 5.4"
}
```

**Option 2: VS Code Settings**

Add to your `.vscode/settings.json`:

```json
{
  "Lua.workspace.library": ["server/data/resources/noverna-core"],
  "Lua.runtime.version": "Lua 5.4"
}
```

After configuration, all type definitions from noverna-core (like `---@class NvCore`) will be available in all your resources without needing to redefine them.

### Example Resource Integration

**fxmanifest.lua:**

```lua
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

dependencies {
    'noverna-core'
}

server_scripts {
    'server.lua'
}
```

**server.lua:**

```lua
local NvCore = exports["noverna-core"]:GetCoreObject()

NvCore.OnReady(function()
    -- Access database
    local users = NvCore.Database:query("SELECT * FROM users")

    -- Access cache
    NvCore.Cache:set("server:status", "online", { ex = 300 })

    -- Use constants
    local maxPlayers = NvCore.Constants.MAX_PLAYERS
end)
```

## Current Status

### Completed Components

- ✅ Core initialization system with staged loading
- ✅ Dependency management with retry logic
- ✅ Export manager with namespace system
- ✅ Logging infrastructure
- ✅ Constants management
- ✅ Basic validation utilities
- ✅ Database integration (via noverna-database)
- ✅ Cache integration (via noverna-cache)

### In Development

The following features are currently being implemented:

- 🚧 Player Management System
  - Player data loading/saving
  - Character selection
  - Multi-character support
- 🚧 Event System
  - Secure event handling
  - Rate limiting
  - Event validation
- 🚧 Callback System
  - Client-server communication
  - Timeout handling
- 🚧 Permissions System
  - Role-based access control
  - Group management

## Planned Features

### Short-term Roadmap

- **Inventory System Integration**: Hook points for inventory resources
- **Economy System**: Money management, transactions, banking
- **Vehicle Management**: Persistent vehicles, ownership, keys
- **Housing System**: Property ownership and management
- **Job Framework**: Extensible job system with duty mechanics

### Long-term Vision

- **Plugin System**: Hot-loadable modules without server restart
- **API Gateway**: REST API for external integrations
- **Admin Panel**: Web-based server administration
- **Analytics Dashboard**: Real-time server metrics and player statistics
- **Multi-server Support**: Cross-server player data synchronization

## Configuration

Configuration is handled through resource/server/constants.lua. Key settings include:

```lua
Constants = {
    VERSION = "1.0.0",
    MAX_PLAYERS = 128,
    SAVE_INTERVAL = 300000, -- 5 minutes
    -- More configuration options...
}
```

## Documentation

For detailed documentation, see:

- CORE_ARCHITECTURE_GUIDE.md - Architecture and design decisions
- EVENT_SYSTEM_DESIGN.md - Event system specification
- REQUIREMENTS.md - Prerequisites and dependencies

## Performance

Noverna Core is designed with performance in mind:

- Lazy loading of player data
- Redis caching layer for frequently accessed data
- Connection pooling for database queries
- Minimal network overhead through batching
- Optimized Lua code following FiveM best practices

## Support

- **Issues**: Report bugs or request features via GitHub Issues
- **Documentation**: Check the `docs` folder for comprehensive guides
- **Community**: Join our Discord server (link coming soon)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Follow the existing code style
4. Add appropriate documentation
5. Submit a pull request

## License

This project is licensed under the MIT License. See LICENSE for details.

## Credits

Developed by the Noverna Team.

Special thanks to:

- [ox_lib](https://github.com/overextended/ox_lib) for utility functions
- The FiveM community for continuous feedback and support

---

**Note**: This is an early release. The framework is functional but still under active development. APIs may change as we refine the architecture. Production use is at your own risk.
