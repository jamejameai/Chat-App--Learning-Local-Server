CREATE TABLE IF NOT EXISTS live_locations (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
    heading DOUBLE PRECISION CHECK (heading IS NULL OR heading >= 0 AND heading < 360),
    accuracy DOUBLE PRECISION CHECK (accuracy IS NULL OR accuracy BETWEEN 0 AND 10000),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_live_locations_updated_at
    ON live_locations(updated_at DESC);
