ALTER TABLE users
    ADD COLUMN IF NOT EXISTS developer_profile JSONB NOT NULL DEFAULT '{}'::jsonb;
