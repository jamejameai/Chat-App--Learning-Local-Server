-- ============================================================================
-- Migration: 014_name_color_and_public_reactions.sql
-- Description: Add name_color to users table and set owner default to red (#FF3B30)
-- ============================================================================

-- 1. Add name_color to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS name_color VARCHAR(32);

-- 2. Set default name_color for app owner (jame.kh) and any user with role 'owner' to luxury crimson/red
UPDATE users
SET name_color = '#FF3B30'
WHERE (role = 'owner' OR LOWER(username) = 'jame.kh') AND (name_color IS NULL OR name_color = '');

-- 3. Ensure index on story_reactions for quick aggregation
CREATE INDEX IF NOT EXISTS idx_story_reactions_aggregated ON story_reactions(story_id, reaction);
