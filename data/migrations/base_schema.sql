--- Base PostgreSQL schema for Noverna Core
-- This script sets up the foundational tables and relationships

-- ============================================
-- ENUMS
-- ============================================

CREATE TYPE whitelist_status AS ENUM ('none', 'pending', 'approved', 'denied');
CREATE TYPE account_type AS ENUM ('bank', 'cash', 'black_money', 'crypto');
CREATE TYPE item_type AS ENUM ('item', 'weapon', 'key', 'license');
CREATE TYPE vehicle_type AS ENUM ('car', 'boat', 'air', 'bike');
CREATE TYPE vehicle_state AS ENUM ('out', 'garaged', 'impounded', 'seized');

-- ============================================
-- CORE TABLES
-- ============================================

-- Users (Account Level)
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  username VARCHAR(50) UNIQUE NOT NULL,
  license VARCHAR(100) UNIQUE NOT NULL,
  identifier VARCHAR(100) UNIQUE NOT NULL,
  last_connection TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Whitelist
CREATE TABLE whitelist (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  full_name VARCHAR(100) NOT NULL,
  date_of_birth DATE NOT NULL,
  reason TEXT,
  submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  status whitelist_status NOT NULL DEFAULT 'pending',
  reviewed_at TIMESTAMP,
  reviewed_by VARCHAR(50),
  review_notes TEXT,
  CONSTRAINT unique_whitelist_user UNIQUE (user_id) WHERE status = 'approved'
);

-- Bans
CREATE TABLE bans (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  reason TEXT NOT NULL,
  banned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  banned_by VARCHAR(50),
  pardoned BOOLEAN DEFAULT FALSE,
  pardon_reason TEXT,
  pardoned_by VARCHAR(50),
  pardoned_at TIMESTAMP,
  expires_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_active_ban UNIQUE (user_id) WHERE pardoned = FALSE
);

-- Characters (Multiple characters per user)
CREATE TABLE characters (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  first_name VARCHAR(50) NOT NULL,
  last_name VARCHAR(50) NOT NULL,
  date_of_birth DATE NOT NULL,
  sex VARCHAR(1) CHECK (sex IN ('m', 'f', 'd')) NOT NULL,
  height INTEGER DEFAULT 180,
  job VARCHAR(50) DEFAULT 'unemployed',
  job_grade INTEGER DEFAULT 0,
  job_label VARCHAR(100),
  gang VARCHAR(50) DEFAULT 'none',
  gang_grade INTEGER DEFAULT 0,
  gang_label VARCHAR(100),
  is_dead BOOLEAN DEFAULT FALSE,
  last_played TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_character_name UNIQUE (first_name, last_name)
);

-- Character Accounts (Bank, Cash, etc.)
CREATE TABLE character_accounts (
  id SERIAL PRIMARY KEY,
  character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  account_type account_type NOT NULL,
  balance DECIMAL(15, 2) DEFAULT 0.00,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_character_account UNIQUE (character_id, account_type)
);


-- Character Positions
CREATE TABLE character_positions (
  id SERIAL PRIMARY KEY,
  character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  position JSONB DEFAULT '{"x": 0.0, "y": 0.0, "z": 72.0, "heading": 0.0}'::jsonb,
  dimension INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_character_position UNIQUE (character_id)
);

-- Character Metadata
CREATE TABLE character_metadata (
  id SERIAL PRIMARY KEY,
  character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_character_metadata UNIQUE (character_id)
);

CREATE TABLE character_appearances (
  id SERIAL PRIMARY KEY,
  character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  appearance JSONB DEFAULT '{}'::jsonb,
  tattoos JSONB DEFAULT '[]'::jsonb,
  clothing JSONB DEFAULT '{}'::jsonb,
  extras JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_character_appearance UNIQUE (character_id)
);

-- ============================================
-- ITEMS & INVENTORY
-- ============================================

-- Items Definition
CREATE TABLE items (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  label VARCHAR(100) NOT NULL,
  description TEXT,
  type item_type NOT NULL DEFAULT 'item',
  weight DECIMAL(10, 2) DEFAULT 0.0,
  stackable BOOLEAN DEFAULT TRUE,
  usable BOOLEAN DEFAULT FALSE,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Character Inventory
CREATE TABLE character_inventory (
  id SERIAL PRIMARY KEY,
  character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  item_name VARCHAR(100) NOT NULL REFERENCES items(name) ON DELETE CASCADE,
  slot INTEGER NOT NULL,
  count INTEGER DEFAULT 1,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_inventory_slot UNIQUE (character_id, slot)
);

-- ============================================
-- VEHICLES
-- ============================================

-- Owned Vehicles
CREATE TABLE owned_vehicles (
  id SERIAL PRIMARY KEY,
  character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
  vehicle_model VARCHAR(100) NOT NULL,
  plate VARCHAR(10) UNIQUE NOT NULL,
  type vehicle_type NOT NULL DEFAULT 'car',
  state vehicle_state NOT NULL DEFAULT 'garaged',
  garage_name VARCHAR(100),
  vehicle_data JSONB DEFAULT '{}'::jsonb,
  fuel_level DECIMAL(5, 2) DEFAULT 100.00,
  body_health DECIMAL(10, 2) DEFAULT 1000.00,
  engine_health DECIMAL(10, 2) DEFAULT 1000.00,
  mileage DECIMAL(15, 2) DEFAULT 0.00,
  impound_fee DECIMAL(10, 2) DEFAULT 0.00,
  stored_position JSONB,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- JOBS & ORGANIZATIONS
-- ============================================

-- Jobs Definition
CREATE TABLE jobs (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) UNIQUE NOT NULL,
  label VARCHAR(100) NOT NULL,
  description TEXT,
  whitelisted BOOLEAN DEFAULT FALSE,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Job Grades
CREATE TABLE job_grades (
  id SERIAL PRIMARY KEY,
  job_name VARCHAR(50) NOT NULL REFERENCES jobs(name) ON DELETE CASCADE,
  grade INTEGER NOT NULL,
  name VARCHAR(50) NOT NULL,
  label VARCHAR(100) NOT NULL,
  salary INTEGER DEFAULT 0,
  permissions JSONB DEFAULT '{}'::jsonb,
  CONSTRAINT unique_job_grade UNIQUE (job_name, grade)
);

-- Gangs Definition
CREATE TABLE gangs (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50) UNIQUE NOT NULL,
  label VARCHAR(100) NOT NULL,
  description TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Gang Grades
CREATE TABLE gang_grades (
  id SERIAL PRIMARY KEY,
  gang_name VARCHAR(50) NOT NULL REFERENCES gangs(name) ON DELETE CASCADE,
  grade INTEGER NOT NULL,
  name VARCHAR(50) NOT NULL,
  label VARCHAR(100) NOT NULL,
  permissions JSONB DEFAULT '{}'::jsonb,
  CONSTRAINT unique_gang_grade UNIQUE (gang_name, grade)
);

-- ============================================
-- LOGS & TRANSACTIONS
-- ============================================

-- Transaction Logs
CREATE TABLE transaction_logs (
  id SERIAL PRIMARY KEY,
  character_id INTEGER REFERENCES characters(id) ON DELETE SET NULL,
  transaction_type VARCHAR(50) NOT NULL,
  amount DECIMAL(15, 2) NOT NULL,
  account_type account_type,
  source VARCHAR(100),
  target VARCHAR(100),
  reason TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Admin Logs
CREATE TABLE admin_logs (
  id SERIAL PRIMARY KEY,
  admin_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  action VARCHAR(100) NOT NULL,
  target_id INTEGER,
  target_type VARCHAR(50),
  details TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- INDEXES
-- ============================================

-- Users indexes
CREATE INDEX idx_users_license ON users(license);
CREATE INDEX idx_users_identifier ON users(identifier);
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_whitelist ON whitelist(user_id, status);
CREATE INDEX idx_bans_user_id ON bans(user_id);

-- Characters indexes
CREATE INDEX idx_characters_user_id ON characters(user_id);
CREATE INDEX idx_characters_name ON characters(first_name, last_name);
CREATE INDEX idx_characters_job ON characters(job);
CREATE INDEX idx_characters_gang ON characters(gang);
CREATE INDEX idx_character_positions_character_id ON character_positions(character_id);
CREATE INDEX idx_character_metadata_character_id ON character_metadata(character_id);
CREATE INDEX idx_character_appearances_character_id ON character_appearances(character_id);

-- Inventory indexes
CREATE INDEX idx_character_inventory_character_id ON character_inventory(character_id);
CREATE INDEX idx_character_inventory_item_name ON character_inventory(item_name);

-- Vehicles indexes
CREATE INDEX idx_owned_vehicles_character_id ON owned_vehicles(character_id);
CREATE INDEX idx_owned_vehicles_plate ON owned_vehicles(plate);
CREATE INDEX idx_owned_vehicles_state ON owned_vehicles(state);

-- Logs indexes
CREATE INDEX idx_transaction_logs_character_id ON transaction_logs(character_id);
CREATE INDEX idx_transaction_logs_created_at ON transaction_logs(created_at);
CREATE INDEX idx_admin_logs_admin_id ON admin_logs(admin_id);
CREATE INDEX idx_admin_logs_created_at ON admin_logs(created_at);

-- ============================================
-- TRIGGERS
-- ============================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply triggers to relevant tables
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_characters_updated_at BEFORE UPDATE ON characters
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_character_accounts_updated_at BEFORE UPDATE ON character_accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_character_inventory_updated_at BEFORE UPDATE ON character_inventory
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_owned_vehicles_updated_at BEFORE UPDATE ON owned_vehicles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_character_positions_updated_at BEFORE UPDATE ON character_positions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_character_metadata_updated_at BEFORE UPDATE ON character_metadata
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_character_appearances_updated_at BEFORE UPDATE ON character_appearances
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_bans_updated_at BEFORE UPDATE ON bans
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();