-- =============================================================
-- CallFlow Pro - Database Schema (MySQL 8 / MariaDB 10.6+)
-- =============================================================

CREATE DATABASE IF NOT EXISTS callflow_db
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE callflow_db;

-- -------------------------------------------------------------
-- Agents master table
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agents (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    extension       VARCHAR(10) NOT NULL UNIQUE,
    full_name       VARCHAR(100) NOT NULL,
    team            VARCHAR(50) NOT NULL,          -- sales/support/billing/floating
    email           VARCHAR(150),
    is_supervisor   BOOLEAN DEFAULT FALSE,
    active          BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_team (team)
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- Real-time agent status (updated via AGI / AMI events)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agent_status (
    extension       VARCHAR(10) PRIMARY KEY,
    status          ENUM('AVAILABLE','ON_CALL','WRAP_UP','BREAK','LOGGED_OUT') DEFAULT 'LOGGED_OUT',
    current_queue   VARCHAR(50) DEFAULT NULL,
    last_call_at    DATETIME DEFAULT NULL,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_agent_status_ext FOREIGN KEY (extension)
        REFERENCES agents(extension) ON DELETE CASCADE
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- Customers table (for VIP / returning-caller routing)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS customers (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    phone           VARCHAR(20) NOT NULL UNIQUE,
    name            VARCHAR(150),
    tier            ENUM('STANDARD','GOLD','VIP') DEFAULT 'STANDARD',
    preferred_lang  VARCHAR(10) DEFAULT 'en',
    notes           TEXT,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_phone (phone),
    INDEX idx_tier (tier)
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- CDR records (mirrors Asterisk CDR, extended with queue/agent)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cdr_records (
    id              BIGINT AUTO_INCREMENT PRIMARY KEY,
    calldate        DATETIME NOT NULL,
    src             VARCHAR(30),
    dst             VARCHAR(30),
    duration        INT DEFAULT 0,
    billsec         INT DEFAULT 0,
    disposition     VARCHAR(20),               -- ANSWERED / NO ANSWER / BUSY / FAILED
    queue_name      VARCHAR(50) DEFAULT NULL,
    agent_id        VARCHAR(10) DEFAULT NULL,
    recording_file  VARCHAR(255) DEFAULT NULL,
    uniqueid        VARCHAR(64),
    INDEX idx_calldate (calldate),
    INDEX idx_queue (queue_name),
    INDEX idx_agent (agent_id)
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- Queue SLA snapshots (for historical reporting / dashboards)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS queue_sla_snapshots (
    id                  BIGINT AUTO_INCREMENT PRIMARY KEY,
    queue_name          VARCHAR(50) NOT NULL,
    snapshot_time       DATETIME NOT NULL,
    calls_waiting       INT DEFAULT 0,
    longest_wait_secs   INT DEFAULT 0,
    agents_available    INT DEFAULT 0,
    agents_on_call      INT DEFAULT 0,
    INDEX idx_queue_time (queue_name, snapshot_time)
) ENGINE=InnoDB;

-- -------------------------------------------------------------
-- Seed sample data (safe to remove in production)
-- -------------------------------------------------------------
INSERT IGNORE INTO agents (extension, full_name, team, email) VALUES
    ('6001', 'John Doe', 'sales', 'agent6001@callflowpro.com'),
    ('6101', 'Sara Khan', 'support', 'agent6101@callflowpro.com'),
    ('6201', 'Ayesha Malik', 'billing', 'agent6201@callflowpro.com');

INSERT IGNORE INTO customers (phone, name, tier) VALUES
    ('+923001234567', 'Sample VIP Customer', 'VIP'),
    ('+923009876543', 'Sample Standard Customer', 'STANDARD');
