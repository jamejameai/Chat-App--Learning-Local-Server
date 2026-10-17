-- ============================================================================
-- Migration: 001_initial_schema.sql
-- Description: Core schema for Mini Telegram
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Migration Tracking
CREATE TABLE IF NOT EXISTS schema_migrations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Users Table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(32) NOT NULL UNIQUE,
    display_name VARCHAR(64) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    avatar_url VARCHAR(512),
    role VARCHAR(16) NOT NULL DEFAULT 'member' CHECK (role IN ('superadmin', 'member')),
    status VARCHAR(16) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'deactivated')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- Invitations Table
CREATE TABLE IF NOT EXISTS invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(64) NOT NULL UNIQUE,
    created_by_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    used_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    role VARCHAR(16) NOT NULL DEFAULT 'member' CHECK (role IN ('superadmin', 'member')),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked BOOLEAN NOT NULL DEFAULT FALSE,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_invitations_code ON invitations(code);

-- Devices Table
CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_name VARCHAR(64) NOT NULL,
    platform VARCHAR(16) NOT NULL DEFAULT 'ios',
    identity_key_pub TEXT NOT NULL,       -- Base64 encoded Curve25519 identity key
    signed_prekey_pub TEXT NOT NULL,     -- Base64 encoded Curve25519 signed prekey
    signed_prekey_sig TEXT NOT NULL,     -- Base64 encoded Ed25519 signature
    signed_prekey_id INTEGER NOT NULL,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    revoked_at TIMESTAMPTZ,
    last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, identity_key_pub)
);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);

-- Device One-Time Prekeys
CREATE TABLE IF NOT EXISTS device_prekeys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    key_id INTEGER NOT NULL,
    public_key TEXT NOT NULL,            -- Base64 encoded Curve25519 one-time prekey
    is_consumed BOOLEAN NOT NULL DEFAULT FALSE,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(device_id, key_id)
);
CREATE INDEX IF NOT EXISTS idx_device_prekeys_available ON device_prekeys(device_id) WHERE is_consumed = FALSE;

-- User Sessions (Refresh Tokens)
CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    refresh_token_hash VARCHAR(128) NOT NULL,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_user_sessions_device ON user_sessions(device_id);

-- Conversations Table
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(16) NOT NULL CHECK (type IN ('direct', 'group', 'channel')),
    title VARCHAR(128),
    avatar_url VARCHAR(512),
    created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    last_sequence_id BIGINT NOT NULL DEFAULT 0,
    last_message_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Conversation Members
CREATE TABLE IF NOT EXISTS conversation_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(16) NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member', 'read_only')),
    last_read_sequence_id BIGINT NOT NULL DEFAULT 0,
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    is_muted BOOLEAN NOT NULL DEFAULT FALSE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(conversation_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user ON conversation_members(user_id);
CREATE INDEX IF NOT EXISTS idx_conversation_members_conv ON conversation_members(conversation_id);

-- Messages Table (Opaque E2EE Envelopes)
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY, -- Client-generated UUID for idempotency
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sender_device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    sequence_id BIGINT NOT NULL,
    envelope_type VARCHAR(24) NOT NULL DEFAULT 'e2ee_text' CHECK (envelope_type IN ('e2ee_text', 'e2ee_attachment', 'e2ee_voice', 'e2ee_call_signal', 'system')),
    encrypted_payload TEXT NOT NULL,     -- Base64 encoded ciphertext
    iv TEXT NOT NULL,                    -- Base64 encoded IV
    reply_to_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    is_edited BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(conversation_id, sequence_id)
);
CREATE INDEX IF NOT EXISTS idx_messages_conv_seq ON messages(conversation_id, sequence_id ASC);

-- Message Receipts Table
CREATE TABLE IF NOT EXISTS message_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    status VARCHAR(16) NOT NULL CHECK (status IN ('delivered', 'read')),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(message_id, device_id, status)
);
CREATE INDEX IF NOT EXISTS idx_message_receipts_msg ON message_receipts(message_id);

-- Attachments Table
CREATE TABLE IF NOT EXISTS attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID REFERENCES messages(id) ON DELETE CASCADE,
    uploaded_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    byte_size BIGINT NOT NULL,
    sha256_checksum VARCHAR(64) NOT NULL,
    storage_path VARCHAR(512) NOT NULL,
    mime_type VARCHAR(128) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_attachments_msg ON attachments(message_id);

-- Calls Table
CREATE TABLE IF NOT EXISTS calls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    initiated_by_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    call_type VARCHAR(16) NOT NULL CHECK (call_type IN ('audio', 'video')),
    status VARCHAR(16) NOT NULL DEFAULT 'dialing' CHECK (status IN ('dialing', 'active', 'ended', 'declined', 'missed')),
    livekit_room_name VARCHAR(128) NOT NULL UNIQUE,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_calls_conv ON calls(conversation_id);

-- Call Participants Table
CREATE TABLE IF NOT EXISTS call_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    call_id UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    status VARCHAR(16) NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'ringing', 'joined', 'left', 'declined')),
    joined_at TIMESTAMPTZ,
    left_at TIMESTAMPTZ,
    UNIQUE(call_id, device_id)
);

-- Notification Devices (APNs Tokens)
CREATE TABLE IF NOT EXISTS notification_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    apns_token VARCHAR(255) NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Audit Events Table
CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(64) NOT NULL,
    target_type VARCHAR(32) NOT NULL,
    target_id VARCHAR(64),
    metadata JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_events(created_at DESC);
