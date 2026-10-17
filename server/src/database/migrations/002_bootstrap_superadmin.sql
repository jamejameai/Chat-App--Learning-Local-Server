-- ============================================================================
-- Migration: 002_bootstrap_superadmin.sql
-- Description: Seed initial bootstrap invitation for first Super-Admin
-- ============================================================================

INSERT INTO invitations (code, role, expires_at)
SELECT 'invite_master_init_00000000', 'superadmin', NOW() + INTERVAL '365 days'
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE role = 'superadmin'
)
ON CONFLICT (code) DO NOTHING;
