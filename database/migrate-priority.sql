-- Migration: Add priority column to stores table
-- This script adds support for store priority (1-5) to display featured stores first

ALTER TABLE stores
ADD COLUMN priority INT DEFAULT NULL,
ADD UNIQUE KEY unique_priority (priority);

-- Optional: Verify the change
-- SELECT id, name, priority FROM stores;
