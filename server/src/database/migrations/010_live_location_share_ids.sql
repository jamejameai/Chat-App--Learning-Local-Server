ALTER TABLE live_locations
    ADD COLUMN IF NOT EXISTS share_id UUID NOT NULL DEFAULT gen_random_uuid();
