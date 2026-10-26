-- ============================================================================
-- Migration: 013_app_owner_and_admin_controls.sql
-- Description: App owner role, cover_url, border_template, story reactions, and admin controls
-- ============================================================================

-- 1. Extend user roles to include 'owner'
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (role IN ('owner', 'superadmin', 'member'));

-- 2. Extend invitation roles to include 'owner'
ALTER TABLE invitations DROP CONSTRAINT IF EXISTS invitations_role_check;
ALTER TABLE invitations ADD CONSTRAINT invitations_role_check CHECK (role IN ('owner', 'superadmin', 'member'));

-- 3. Add cover_url and border_template to users
ALTER TABLE users ADD COLUMN IF NOT EXISTS cover_url TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS border_template VARCHAR(64) DEFAULT 'platinumExecutive';

-- 4. Create story_reactions table
CREATE TABLE IF NOT EXISTS story_reactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(story_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_story_reactions_story ON story_reactions(story_id);

-- 5. Seed / Ensure jame.kh account as the Owner of the app
DO $$
DECLARE
    owner_user_id UUID;
    pw_hash VARCHAR(255) := '$2b$10$EpRnTzVlqHNP0.fUbXUwSOyuiXe/QLSUG6x8ek5qWmMmveTeQ7i9e'; -- password: password123
BEGIN
    SELECT id INTO owner_user_id FROM users WHERE LOWER(username) = 'jame.kh';
    
    IF owner_user_id IS NOT NULL THEN
        UPDATE users 
        SET role = 'owner',
            display_name = CASE WHEN display_name = 'User' OR display_name IS NULL THEN 'Jame (Owner & Dev)' ELSE display_name END,
            border_template = COALESCE(border_template, 'goldLeaf'),
            cover_url = COALESCE(cover_url, 'cover:obsidian'),
            developer_profile = jsonb_set(
                COALESCE(developer_profile, '{}'::jsonb),
                '{headline}',
                '"Chief Architect & Owner"'
            )
        WHERE id = owner_user_id;
    ELSE
        INSERT INTO users (
            username,
            display_name,
            password_hash,
            role,
            status,
            border_template,
            cover_url,
            bio,
            developer_profile
        ) VALUES (
            'jame.kh',
            'Jame (Owner & Dev)',
            pw_hash,
            'owner',
            'active',
            'goldLeaf',
            'cover:obsidian',
            'System Owner & Lead Architect of Our Chat',
            json_build_object(
                'headline', 'Chief Architect & Owner',
                'skills', json_build_array('Swift 6', 'SwiftUI', 'NestJS', 'PostgreSQL', 'LiveKit WebRTC', 'Signal Protocol'),
                'work_availability', 'available_for_work',
                'projects', json_build_array(
                    json_build_object(
                        'id', gen_random_uuid()::text,
                        'title', 'Our Chat Core Protocol',
                        'summary', 'Zero-knowledge end-to-end encrypted real-time communications infrastructure',
                        'technologies', json_build_array('Swift 6', 'CryptoKit', 'Signal Ratchet'),
                        'is_pinned', true
                    )
                )
            )::jsonb
        );
    END IF;
END $$;
