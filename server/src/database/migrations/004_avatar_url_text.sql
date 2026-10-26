-- Migration 004: Expand avatar_url to TEXT for base64 photo avatars
ALTER TABLE users ALTER COLUMN avatar_url TYPE TEXT;
ALTER TABLE conversations ALTER COLUMN avatar_url TYPE TEXT;
