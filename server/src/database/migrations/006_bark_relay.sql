-- ============================================================================
-- Migration: 006_bark_relay.sql
-- Description: Notifications while Our Chat is closed, relayed through the free
--              Bark app (https://bark.day.app). Apple only delivers pushes to a
--              closed app that is signed by a paid developer account; Bark is, so
--              the server sends "new message" alerts to the user's Bark key instead.
-- ============================================================================

CREATE TABLE IF NOT EXISTS bark_relays (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    -- The key from the Bark app ("https://api.day.app/<key>/"); only ever sent to the Bark server
    device_key VARCHAR(64) NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    -- Bark sound names (built in, or a .caf the user imported into Bark, e.g. "ping")
    message_sound VARCHAR(64) NOT NULL DEFAULT 'glass',
    call_sound VARCHAR(64) NOT NULL DEFAULT 'multiwayinvitation',
    -- Language of the alert text ('en' or 'km'), taken from the app when it is set up
    language VARCHAR(8) NOT NULL DEFAULT 'en',
    -- Why the last push failed (e.g. the key was reset in Bark); NULL when it works
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
