CREATE TABLE IF NOT EXISTS fms_graph_versions (
    version_id        BIGSERIAL PRIMARY KEY,
    site_name         VARCHAR(64) NOT NULL,
    map_name          VARCHAR(128) NOT NULL DEFAULT 'default',
    content_hash      VARCHAR(64) NOT NULL,
    node_count        INTEGER NOT NULL,
    link_count        INTEGER NOT NULL,
    snapshot_payload  JSONB NOT NULL,
    is_active         BOOLEAN NOT NULL DEFAULT FALSE,
    created_by        VARCHAR(64) NOT NULL DEFAULT 'gui_fms',
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_graph_versions_site_active
    ON fms_graph_versions (site_name, is_active, version_id DESC);
