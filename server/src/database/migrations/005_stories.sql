-- ============================================================================
-- Migration: 005_stories.sql
-- Description: 24-hour photo stories (like Telegram) and who has seen them
-- ============================================================================

CREATE TABLE IF NOT EXISTS stories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- The photo is stored encrypted like chat attachments; its key is kept here so the
    -- poster's friends can open it (stories are shared, not end-to-end encrypted)
    attachment_id UUID NOT NULL REFERENCES attachments(id) ON DELETE CASCADE,
    media_key TEXT NOT NULL,
    media_iv TEXT NOT NULL,
    media_sha256 VARCHAR(64) NOT NULL,
    mime_type VARCHAR(64) NOT NULL,
    caption TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '24 hours'
);

CREATE INDEX IF NOT EXISTS idx_stories_user_expires ON stories(user_id, expires_at);

CREATE TABLE IF NOT EXISTS story_views (
    story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
    viewer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (story_id, viewer_id)
);
