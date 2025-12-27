-- Noverna - Logging System (PostgreSQL)
-- V1.5_Logs.sql
-- Diese Logs werden später in ein externes System (Grafana/Loki) exportiert
-- Aktuell für Entwicklung und Debugging

CREATE SCHEMA IF NOT EXISTS logs;

-- ============================================================================
-- LOG ENUMS
-- ============================================================================

CREATE TYPE log_level AS ENUM ('debug', 'info', 'warn', 'error', 'critical');
CREATE TYPE action_category AS ENUM ('auth', 'character', 'gameplay', 'economy', 'social', 'admin', 'other');
CREATE TYPE action_severity AS ENUM ('low', 'medium', 'high', 'critical');
CREATE TYPE log_account_type AS ENUM ('cash', 'bank', 'crypto', 'company', 'other');
CREATE TYPE connection_type AS ENUM ('connect', 'disconnect', 'timeout', 'kicked', 'banned');
CREATE TYPE respawn_type AS ENUM ('hospital', 'ems', 'admin', 'bleedout');

-- ============================================================================
-- Allgemeine System-Logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.system (
    id BIGSERIAL PRIMARY KEY,

    -- Log Metadata
    level log_level NOT NULL DEFAULT 'info',
    category VARCHAR(50) NOT NULL, -- 'database', 'network', 'resource', 'performance', etc.

    -- Message
    message TEXT NOT NULL,
    stack_trace TEXT, -- Für Errors

    -- Context
    resource_name VARCHAR(100), -- Welche Resource hat geloggt
    source_file VARCHAR(255), -- Datei aus der geloggt wurde
    line_number INTEGER,

    -- Metadata
    metadata JSONB DEFAULT NULL, -- Zusätzliche Daten

    -- Server Info
    server_id VARCHAR(50), -- Für Multi-Server Setups
    server_uptime BIGINT, -- Sekunden seit Server-Start

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Player Action Logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.player_actions (
    id BIGSERIAL PRIMARY KEY,

    -- Player Info
    source INTEGER NOT NULL, -- Server ID des Spielers
    license VARCHAR(255) NOT NULL,
    character_id INTEGER,
    player_name VARCHAR(100),

    -- Action Details
    action_type VARCHAR(50) NOT NULL, -- 'login', 'logout', 'character_select', 'character_create', 'death', 'revive', etc.
    action_category action_category NOT NULL DEFAULT 'other',

    description TEXT,

    -- Location
    position JSONB DEFAULT NULL, -- { x, y, z }
    zone VARCHAR(100), -- 'Legion Square', 'Sandy Shores', etc.

    -- Additional Context
    target_player INTEGER, -- Falls Aktion einen anderen Spieler betrifft
    target_entity INTEGER, -- Entity ID falls relevant

    metadata JSONB DEFAULT NULL,

    -- IP & Session (optional, für Security)
    ip_address VARCHAR(45), -- IPv6 support
    session_id VARCHAR(100),

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Chat Logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.chat (
    id BIGSERIAL PRIMARY KEY,

    -- Sender
    source INTEGER NOT NULL,
    license VARCHAR(255) NOT NULL,
    character_id INTEGER,
    sender_name VARCHAR(100),

    -- Message
    channel VARCHAR(50) NOT NULL, -- 'global', 'local', 'whisper', 'company', 'admin', 'ooc', etc.
    message TEXT NOT NULL,

    -- Recipients (für private messages)
    recipient_character_id INTEGER,
    recipient_name VARCHAR(100),

    -- Location
    position JSONB DEFAULT NULL,
    zone VARCHAR(100),

    -- Flags
    is_command BOOLEAN DEFAULT FALSE,
    is_blocked BOOLEAN DEFAULT FALSE, -- Blocked by filter
    block_reason VARCHAR(255),

    metadata JSONB DEFAULT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Admin Actions
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.admin_actions (
    id BIGSERIAL PRIMARY KEY,

    -- Admin
    admin_license VARCHAR(255) NOT NULL,
    admin_character_id INTEGER,
    admin_name VARCHAR(100),

    -- Action
    action_type VARCHAR(50) NOT NULL, -- 'ban', 'kick', 'warn', 'teleport', 'give_item', 'revive', 'noclip', etc.
    action_severity action_severity DEFAULT 'medium',

    command_used VARCHAR(255), -- Original command
    description TEXT,

    -- Target
    target_license VARCHAR(255),
    target_character_id INTEGER,
    target_name VARCHAR(100),

    -- Details
    reason TEXT,
    duration INTEGER, -- In Sekunden (für Bans/Mutes)

    metadata JSONB DEFAULT NULL, -- z.B. Items given, Money amount, etc.

    -- Result
    success BOOLEAN DEFAULT TRUE,
    error_message TEXT,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Economy/Transaction Logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.economy (
    id BIGSERIAL PRIMARY KEY,

    -- Player
    license VARCHAR(255) NOT NULL,
    character_id INTEGER,
    player_name VARCHAR(100),

    -- Transaction
    transaction_type VARCHAR(50) NOT NULL, -- 'cash_add', 'cash_remove', 'bank_add', 'bank_remove', 'purchase', 'salary', etc.
    amount DECIMAL(15, 2) NOT NULL,

    account_type log_account_type DEFAULT 'cash',

    balance_before DECIMAL(15, 2),
    balance_after DECIMAL(15, 2),

    -- Reason/Source
    reason VARCHAR(255),
    source VARCHAR(100), -- 'job', 'admin', 'shop', 'player', 'company', etc.

    -- Related Entities
    target_player INTEGER, -- Falls Geld transferiert wurde
    company_id INTEGER, -- Falls Company-bezogen

    metadata JSONB DEFAULT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Vehicle Logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.vehicles (
    id BIGSERIAL PRIMARY KEY,

    -- Vehicle
    vehicle_id INTEGER,
    plate VARCHAR(10) NOT NULL,
    model VARCHAR(100),

    -- Player
    license VARCHAR(255) NOT NULL,
    character_id INTEGER,
    player_name VARCHAR(100),

    -- Action
    action_type VARCHAR(50) NOT NULL, -- 'spawn', 'despawn', 'purchase', 'sell', 'impound', 'lock', 'unlock', 'mod', etc.

    -- Location
    position JSONB DEFAULT NULL,
    zone VARCHAR(100),

    -- Details
    details TEXT,
    metadata JSONB DEFAULT NULL, -- z.B. Mods applied, Purchase price, etc.

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Inventory/Item Logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.inventory (
    id BIGSERIAL PRIMARY KEY,

    -- Player
    license VARCHAR(255) NOT NULL,
    character_id INTEGER,
    player_name VARCHAR(100),

    -- Action
    action_type VARCHAR(50) NOT NULL, -- 'add', 'remove', 'use', 'give', 'drop', 'craft', 'trade', etc.

    -- Item
    item_name VARCHAR(100) NOT NULL,
    item_label VARCHAR(255),
    amount INTEGER DEFAULT 1,

    -- Source/Target
    source VARCHAR(100), -- 'shop', 'craft', 'admin', 'player', 'loot', etc.
    target_player INTEGER, -- Falls Item an anderen Spieler

    -- Inventory Details
    inventory_type VARCHAR(50), -- 'player', 'vehicle', 'stash', 'drop', etc.
    inventory_id VARCHAR(100), -- ID des Inventars

    metadata JSONB DEFAULT NULL, -- Item metadata, durability, etc.

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Death/Respawn Logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.deaths (
    id BIGSERIAL PRIMARY KEY,

    -- Victim
    victim_license VARCHAR(255) NOT NULL,
    victim_character_id INTEGER,
    victim_name VARCHAR(100),

    -- Killer (falls PvP)
    killer_license VARCHAR(255),
    killer_character_id INTEGER,
    killer_name VARCHAR(100),

    -- Death Details
    death_cause VARCHAR(100), -- Weapon name, 'fall', 'vehicle', 'drowning', etc.
    damage_type VARCHAR(50), -- 'melee', 'bullet', 'explosion', 'environment', etc.

    -- Location
    position JSONB DEFAULT NULL,
    zone VARCHAR(100),

    -- Respawn Info
    respawn_type respawn_type DEFAULT 'hospital',
    respawn_time INTEGER, -- Sekunden bis Respawn

    metadata JSONB DEFAULT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Command Logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.commands (
    id BIGSERIAL PRIMARY KEY,

    -- Player
    source INTEGER NOT NULL,
    license VARCHAR(255) NOT NULL,
    character_id INTEGER,
    player_name VARCHAR(100),

    -- Command
    command VARCHAR(255) NOT NULL,
    args TEXT, -- Command arguments

    -- Context
    is_admin_command BOOLEAN DEFAULT FALSE,
    required_permission VARCHAR(100),

    -- Result
    success BOOLEAN DEFAULT TRUE,
    error_message TEXT,
    execution_time_ms INTEGER, -- Ausführungszeit in Millisekunden

    -- Location
    position JSONB DEFAULT NULL,

    metadata JSONB DEFAULT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Connection Logs
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.connections (
    id BIGSERIAL PRIMARY KEY,

    -- Player
    license VARCHAR(255) NOT NULL,
    player_name VARCHAR(100),

    -- Connection Type
    connection_type connection_type NOT NULL,

    -- Connection Info
    ip_address VARCHAR(45),
    identifiers JSONB DEFAULT NULL, -- All identifiers (steam, discord, etc.)

    -- Session
    session_id VARCHAR(100),
    session_duration INTEGER, -- Sekunden (nur bei disconnect)

    -- Reason (bei disconnect/kick)
    reason TEXT,
    kicked_by VARCHAR(100), -- Admin name

    -- Hardware Info (optional, für Ban-Umgehungs-Erkennung)
    hardware_id VARCHAR(255),

    metadata JSONB DEFAULT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Performance Logs (Optional - für Monitoring)
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.performance (
    id BIGSERIAL PRIMARY KEY,

    -- Metrics
    metric_type VARCHAR(50) NOT NULL, -- 'server_tick', 'resource_usage', 'database_query', 'event_handler', etc.
    metric_name VARCHAR(100),

    -- Values
    value DECIMAL(10, 2), -- Hauptwert (z.B. ms, %, count)
    unit VARCHAR(20), -- 'ms', 'percent', 'count', 'mb', etc.

    -- Context
    resource_name VARCHAR(100),
    event_name VARCHAR(100),

    -- Thresholds
    threshold_warning DECIMAL(10, 2),
    threshold_critical DECIMAL(10, 2),
    is_over_threshold BOOLEAN DEFAULT FALSE,

    metadata JSONB DEFAULT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- Security Events (Exploits, Cheats, etc.)
-- ============================================================================
CREATE TABLE IF NOT EXISTS logs.security (
    id BIGSERIAL PRIMARY KEY,

    -- Player
    source INTEGER NOT NULL,
    license VARCHAR(255) NOT NULL,
    character_id INTEGER,
    player_name VARCHAR(100),

    -- Event
    event_type VARCHAR(50) NOT NULL, -- 'exploit_attempt', 'invalid_data', 'suspicious_behavior', 'cheat_detected', etc.
    severity action_severity DEFAULT 'medium',

    description TEXT NOT NULL,

    -- Detection
    detection_method VARCHAR(100), -- 'anticheat', 'validation', 'manual', etc.
    triggered_rule VARCHAR(255),

    -- Evidence
    evidence JSONB DEFAULT NULL, -- Screenshots, logs, etc.

    -- Action Taken
    action_taken VARCHAR(100), -- 'warned', 'kicked', 'banned', 'logged_only', etc.
    auto_action BOOLEAN DEFAULT FALSE,

    -- IP & Session
    ip_address VARCHAR(45),
    session_id VARCHAR(100),

    metadata JSONB DEFAULT NULL,

    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================================
-- INDEXES
-- ============================================================================

-- System Logs
CREATE INDEX idx_logs_system_level ON logs.system(level);
CREATE INDEX idx_logs_system_category ON logs.system(category);
CREATE INDEX idx_logs_system_created_at ON logs.system(created_at);
CREATE INDEX idx_logs_system_resource ON logs.system(resource_name);

-- Player Actions
CREATE INDEX idx_logs_player_actions_license ON logs.player_actions(license);
CREATE INDEX idx_logs_player_actions_character_id ON logs.player_actions(character_id);
CREATE INDEX idx_logs_player_actions_action_type ON logs.player_actions(action_type);
CREATE INDEX idx_logs_player_actions_action_category ON logs.player_actions(action_category);
CREATE INDEX idx_logs_player_actions_created_at ON logs.player_actions(created_at);
CREATE INDEX idx_logs_player_actions_session ON logs.player_actions(session_id);

-- Chat Logs
CREATE INDEX idx_logs_chat_license ON logs.chat(license);
CREATE INDEX idx_logs_chat_character_id ON logs.chat(character_id);
CREATE INDEX idx_logs_chat_channel ON logs.chat(channel);
CREATE INDEX idx_logs_chat_recipient ON logs.chat(recipient_character_id);
CREATE INDEX idx_logs_chat_created_at ON logs.chat(created_at);
-- Full-text search index für messages (PostgreSQL GIN)
CREATE INDEX idx_logs_chat_message_search ON logs.chat USING gin(to_tsvector('english', message));

-- Admin Actions
CREATE INDEX idx_logs_admin_actions_admin_license ON logs.admin_actions(admin_license);
CREATE INDEX idx_logs_admin_actions_action_type ON logs.admin_actions(action_type);
CREATE INDEX idx_logs_admin_actions_target_license ON logs.admin_actions(target_license);
CREATE INDEX idx_logs_admin_actions_severity ON logs.admin_actions(action_severity);
CREATE INDEX idx_logs_admin_actions_created_at ON logs.admin_actions(created_at);
-- Economy
CREATE INDEX idx_logs_economy_license ON logs.economy(license);
CREATE INDEX idx_logs_economy_character_id ON logs.economy(character_id);
CREATE INDEX idx_logs_economy_transaction_type ON logs.economy(transaction_type);
CREATE INDEX idx_logs_economy_created_at ON logs.economy(created_at);
CREATE INDEX idx_logs_economy_amount ON logs.economy(amount);

-- Vehicles
CREATE INDEX idx_logs_vehicles_vehicle_id ON logs.vehicles(vehicle_id);
CREATE INDEX idx_logs_vehicles_plate ON logs.vehicles(plate);
CREATE INDEX idx_logs_vehicles_license ON logs.vehicles(license);
CREATE INDEX idx_logs_vehicles_action_type ON logs.vehicles(action_type);
CREATE INDEX idx_logs_vehicles_created_at ON logs.vehicles(created_at);

-- Inventory
CREATE INDEX idx_logs_inventory_license ON logs.inventory(license);
CREATE INDEX idx_logs_inventory_character_id ON logs.inventory(character_id);
CREATE INDEX idx_logs_inventory_action_type ON logs.inventory(action_type);
CREATE INDEX idx_logs_inventory_item_name ON logs.inventory(item_name);
CREATE INDEX idx_logs_inventory_created_at ON logs.inventory(created_at);

-- Deaths
CREATE INDEX idx_logs_deaths_victim_license ON logs.deaths(victim_license);
CREATE INDEX idx_logs_deaths_killer_license ON logs.deaths(killer_license);
CREATE INDEX idx_logs_deaths_death_cause ON logs.deaths(death_cause);
CREATE INDEX idx_logs_deaths_created_at ON logs.deaths(created_at);

-- Commands
CREATE INDEX idx_logs_commands_license ON logs.commands(license);
CREATE INDEX idx_logs_commands_command ON logs.commands(command);
CREATE INDEX idx_logs_commands_success ON logs.commands(success);
CREATE INDEX idx_logs_commands_created_at ON logs.commands(created_at);

-- Connections
CREATE INDEX idx_logs_connections_license ON logs.connections(license);
CREATE INDEX idx_logs_connections_connection_type ON logs.connections(connection_type);
CREATE INDEX idx_logs_connections_ip_address ON logs.connections(ip_address);
CREATE INDEX idx_logs_connections_session_id ON logs.connections(session_id);
CREATE INDEX idx_logs_connections_created_at ON logs.connections(created_at);

-- Performance
CREATE INDEX idx_logs_performance_metric_type ON logs.performance(metric_type);
CREATE INDEX idx_logs_performance_resource_name ON logs.performance(resource_name);
CREATE INDEX idx_logs_performance_created_at ON logs.performance(created_at);
CREATE INDEX idx_logs_performance_over_threshold ON logs.performance(is_over_threshold);

-- Security
CREATE INDEX idx_logs_security_license ON logs.security(license);
CREATE INDEX idx_logs_security_event_type ON logs.security(event_type);
CREATE INDEX idx_logs_security_severity ON logs.security(severity);
CREATE INDEX idx_logs_security_created_at ON logs.security(created_at);
CREATE INDEX idx_logs_security_ip_address ON logs.security(ip_address);

-- ============================================================================
-- Log Retention & Cleanup
-- ============================================================================
-- Diese View gibt eine Übersicht über Log-Größen und Alter
CREATE OR REPLACE VIEW vw_log_statistics AS
SELECT
    'system' AS log_table,
    COUNT(*) AS total_entries,
    MIN(created_at) AS oldest_entry,
    MAX(created_at) AS newest_entry,
    ROUND((pg_total_relation_size('logs.system')::numeric / 1024 / 1024), 2) AS size_mb
FROM logs.system
UNION ALL
SELECT
    'player_actions',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.player_actions')::numeric / 1024 / 1024), 2)
FROM logs.player_actions
UNION ALL
SELECT
    'chat',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.chat')::numeric / 1024 / 1024), 2)
FROM logs.chat
UNION ALL
SELECT
    'admin_actions',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.admin_actions')::numeric / 1024 / 1024), 2)
FROM logs.admin_actions
UNION ALL
SELECT
    'economy',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.economy')::numeric / 1024 / 1024), 2)
FROM logs.economy
UNION ALL
SELECT
    'vehicles',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.vehicles')::numeric / 1024 / 1024), 2)
FROM logs.vehicles
UNION ALL
SELECT
    'inventory',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.inventory')::numeric / 1024 / 1024), 2)
FROM logs.inventory
UNION ALL
SELECT
    'deaths',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.deaths')::numeric / 1024 / 1024), 2)
FROM logs.deaths
UNION ALL
SELECT
    'commands',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.commands')::numeric / 1024 / 1024), 2)
FROM logs.commands
UNION ALL
SELECT
    'connections',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.connections')::numeric / 1024 / 1024), 2)
FROM logs.connections
UNION ALL
SELECT
    'performance',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.performance')::numeric / 1024 / 1024), 2)
FROM logs.performance
UNION ALL
SELECT
    'security',
    COUNT(*),
    MIN(created_at),
    MAX(created_at),
    ROUND((pg_total_relation_size('logs.security')::numeric / 1024 / 1024), 2)
FROM logs.security;

-- ============================================================================
-- Stored Procedure für Log Cleanup (PostgreSQL)
-- ============================================================================

-- Funktion zum Löschen alter Logs
CREATE OR REPLACE FUNCTION cleanup_old_logs(days_to_keep INTEGER DEFAULT 30)
RETURNS TABLE(
    table_name TEXT,
    rows_deleted BIGINT
) AS $$
DECLARE
    cutoff_date TIMESTAMP;
    deleted_rows BIGINT;
BEGIN
    cutoff_date := CURRENT_TIMESTAMP - (days_to_keep || ' days')::INTERVAL;

    -- System Logs
    DELETE FROM logs.system WHERE created_at < cutoff_date;
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.system';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Player Actions (keep longer)
    DELETE FROM logs.player_actions WHERE created_at < cutoff_date - INTERVAL '60 days';
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.player_actions';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Chat Logs
    DELETE FROM logs.chat WHERE created_at < cutoff_date;
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.chat';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Admin Actions (keep much longer)
    DELETE FROM logs.admin_actions WHERE created_at < cutoff_date - INTERVAL '180 days';
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.admin_actions';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Economy (keep longer)
    DELETE FROM logs.economy WHERE created_at < cutoff_date - INTERVAL '90 days';
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.economy';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Vehicle Logs
    DELETE FROM logs.vehicles WHERE created_at < cutoff_date;
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.vehicles';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Inventory Logs
    DELETE FROM logs.inventory WHERE created_at < cutoff_date;
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.inventory';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Deaths
    DELETE FROM logs.deaths WHERE created_at < cutoff_date - INTERVAL '60 days';
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.deaths';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Commands
    DELETE FROM logs.commands WHERE created_at < cutoff_date;
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.commands';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Connections
    DELETE FROM logs.connections WHERE created_at < cutoff_date - INTERVAL '90 days';
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.connections';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Performance Logs (keep short)
    DELETE FROM logs.performance WHERE created_at < cutoff_date - INTERVAL '7 days';
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.performance';
    rows_deleted := deleted_rows;
    RETURN NEXT;

    -- Security Events (keep very long)
    DELETE FROM logs.security WHERE created_at < cutoff_date - INTERVAL '365 days';
    GET DIAGNOSTICS deleted_rows = ROW_COUNT;
    table_name := 'logs.security';
    rows_deleted := deleted_rows;
    RETURN NEXT;

END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- HINWEISE FÜR PRODUCTION
-- ============================================================================
-- 1. Diese Tabellen sollten regelmäßig archiviert werden (z.B. monatlich)
-- 2. Für Production: Event-basiertes Logging an externes System (Loki, Elasticsearch)
-- 3. Partitionierung nach Datum für bessere Performance (siehe unten)
-- 4. Retention Policy: Logs älter als X Tage automatisch löschen/archivieren
--
-- Cleanup ausführen:
-- SELECT * FROM cleanup_old_logs(30); -- Löscht Logs älter als 30 Tage
--
-- Für Archivierung:
-- CREATE TABLE archive.logs_chat AS SELECT * FROM logs_chat WHERE created_at < NOW() - INTERVAL '30 days';
-- DELETE FROM logs_chat WHERE created_at < NOW() - INTERVAL '30 days';
--
-- Partitionierung Beispiel (für logs_chat):
-- CREATE TABLE logs_chat_partitioned (LIKE logs_chat INCLUDING ALL) PARTITION BY RANGE (created_at);
-- CREATE TABLE logs_chat_2025_01 PARTITION OF logs_chat_partitioned
--     FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
-- CREATE TABLE logs_chat_2025_02 PARTITION OF logs_chat_partitioned
--     FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
