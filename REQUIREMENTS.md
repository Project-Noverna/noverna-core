# Noverna Core - Requirements

This document outlines all prerequisites and dependencies required to run Noverna Core on your FiveM server.

## Server Requirements

### FiveM Server

- **Minimum Artifact**: 23368 or higher
- **Recommended**: Latest stable artifact
- **Platform**: Windows or Linux
- **Lua Version**: 5.4 (lua54 manifest required)

### Hardware Recommendations

- **CPU**: 2+ cores
- **RAM**: 4GB minimum, 8GB+ recommended
- **Storage**: SSD recommended for database operations
- **Network**: Stable connection with low latency

## Required Dependencies

### 1. noverna-database

PostgreSQL database wrapper for Noverna Framework.

- **Purpose**: Handles all database operations with connection pooling
- **GitHub**: [Repository](https://github.com/Project-Noverna/noverna-database)
- **Installation**: Must be started before noverna-core

```cfg
ensure noverna-database
```

### 2. noverna-cache

Redis caching layer for high-performance data access.

- **Purpose**: Caching frequently accessed data, session management
- **GitHub**: [Repository](https://github.com/Project-Noverna/noverna-cache)
- **Installation**: Must be started before noverna-core

```cfg
ensure noverna-cache
```

### 3. ox_lib

Utility library providing common functions and UI components.

- **Purpose**: Core utilities, callbacks, and locale system
- **GitHub**: [https://github.com/overextended/ox_lib](https://github.com/overextended/ox_lib)
- **Version**: 3.32.2 or higher
- **Installation**: Download from GitHub releases

```cfg
ensure ox_lib
```

## External Services

### PostgreSQL Database

- **Version**: 12.x or higher recommended
- **Configuration**:
  - Database name: Configure in noverna-database
  - User with full permissions
  - Network access from FiveM server

### Redis Server

- **Version**: 6.x or higher recommended
- **Configuration**:
  - Default port (6379) or custom
  - Password protection recommended
  - Persistence enabled (optional but recommended)

## Development Tools

### Lua Language Server (LuaLS)

For optimal development experience with type checking and autocomplete:

- **VS Code Extension**: [LuaLS](https://marketplace.visualstudio.com/items?itemName=sumneko.lua)
- **Configuration**: Required for global type definitions

#### LuaLS Workspace Setup

To use Noverna Core's type definitions across all your resources, configure the Lua Language Server:

**Method 1: Workspace Configuration (.luarc.json)**

Create a `.luarc.json` file in your workspace root:

```json
{
  "workspace.library": ["server/data/resources/noverna-core"],
  "runtime.version": "Lua 5.4",
  "runtime.path": ["?.lua", "?/init.lua"],
  "diagnostics.globals": [
    "exports",
    "CreateThread",
    "Wait",
    "TriggerEvent",
    "RegisterNetEvent",
    "AddEventHandler"
  ]
}
```

**Method 2: VS Code Settings**

Add to your workspace `.vscode/settings.json`:

```json
{
  "Lua.workspace.library": ["server/data/resources/noverna-core"],
  "Lua.runtime.version": "Lua 5.4",
  "Lua.runtime.path": ["?.lua", "?/init.lua"],
  "Lua.diagnostics.globals": [
    "exports",
    "CreateThread",
    "Wait",
    "TriggerEvent",
    "RegisterNetEvent",
    "AddEventHandler"
  ]
}
```

This configuration allows you to:

- Access all type definitions from noverna-core in any resource
- Get autocomplete for NvCore classes and functions
- Avoid duplicate type annotations across resources
- Maintain consistency in type definitions

## Installation Order

The correct order for starting resources in `server.cfg`:

```cfg
# 1. External utilities
ensure ox_lib

# 2. Infrastructure layer
ensure noverna-database
ensure noverna-cache

# 3. Core framework
ensure noverna-core

# 4. Your application resources
ensure your-custom-resource
```

**Critical**: The order matters. Starting resources out of order may cause initialization failures.

## Verification

After starting your server, verify the installation:

### Console Output

You should see the following initialization sequence:

```
[NvCore] Stage 1: Early Initialization
[NvCore] Stage 1 Complete
[NvCore] Stage 2: Loading Dependencies
[NvCore] Cache loaded successfully
[NvCore] Database loaded successfully
[NvCore] Stage 2 Complete
[NvCore] Stage 3: Loading Core Modules
[NvCore] Stage 3 Complete
[NvCore] Stage 4: Finalization
[NvCore] Framework Ready!
[NvCore] Version: 1.0.0
```

### Troubleshooting

**Cache not ready error:**

- Verify noverna-cache is started before noverna-core
- Check Redis server is running and accessible
- Review noverna-cache configuration

**Database not ready error:**

- Verify noverna-database is started before noverna-core
- Check PostgreSQL server is running
- Verify database credentials in noverna-database config
- Ensure database user has proper permissions

**Stage 2 timeout:**

- Check network connectivity to Redis/PostgreSQL
- Increase retry delay in init.lua if needed
- Review logs in noverna-database and noverna-cache

## Optional Dependencies

### Future Compatibility

The following will be required for upcoming features:

- **noverna-inventory**: Inventory system (planned)
- **noverna-banking**: Economy system (planned)
- **noverna-vehicles**: Vehicle management (planned)

## Support

For issues with dependencies:

- **noverna-database**: Check repository issues (link pending)
- **noverna-cache**: Check repository issues (link pending)
- **ox_lib**: [GitHub Issues](https://github.com/overextended/ox_lib/issues)
- **FiveM**: [FiveM Forums](https://forum.cfx.re/)

## Version Compatibility

| Noverna Core | noverna-database | noverna-cache | ox_lib  |
| ------------ | ---------------- | ------------- | ------- |
| 1.0.0        | 1.0.0+           | 1.0.0+        | 3.32.2+ |

Always use compatible versions to avoid runtime errors.
