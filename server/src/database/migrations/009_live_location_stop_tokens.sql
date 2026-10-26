ALTER TABLE live_locations
    ADD COLUMN IF NOT EXISTS stop_token_hash TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_live_locations_stop_token_hash
    ON live_locations(stop_token_hash)
    WHERE stop_token_hash IS NOT NULL;

DELETE FROM live_locations
WHERE stop_token_hash IS NULL;
