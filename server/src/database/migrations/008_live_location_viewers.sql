CREATE TABLE IF NOT EXISTS live_location_viewers (
    owner_user_id UUID NOT NULL REFERENCES live_locations(user_id) ON DELETE CASCADE,
    viewer_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (owner_user_id, viewer_user_id),
    CHECK (owner_user_id <> viewer_user_id)
);

CREATE INDEX IF NOT EXISTS idx_live_location_viewers_viewer
    ON live_location_viewers(viewer_user_id);
