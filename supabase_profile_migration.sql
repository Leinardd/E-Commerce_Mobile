-- ============================================================
-- Varón Profile — Name change cooldown migration
-- Run this in the Supabase SQL Editor
-- ============================================================

-- Add the column that tracks when the user last changed their name
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS name_changed_at TIMESTAMPTZ;

-- ── RPC: update_display_name ─────────────────────────────────
-- Updates first_name / last_name with a 31-day cooldown.
-- Returns NULL on success, or an error string the app can display.
-- SECURITY DEFINER so it can write to `users` regardless of RLS.

CREATE OR REPLACE FUNCTION update_display_name(
  p_first_name TEXT,
  p_last_name  TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_email      TEXT;
  v_changed_at TIMESTAMPTZ;
  v_next       TIMESTAMPTZ;
BEGIN
  v_email := auth.jwt() ->> 'email';
  IF v_email IS NULL THEN
    RETURN 'not_authenticated';
  END IF;

  SELECT name_changed_at INTO v_changed_at
  FROM users
  WHERE email = v_email;

  IF v_changed_at IS NOT NULL THEN
    v_next := v_changed_at + INTERVAL '31 days';
    IF NOW() < v_next THEN
      -- Return "cooldown:<ISO date>" so the client can parse the unlock date
      RETURN 'cooldown:' || TO_CHAR(v_next AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
    END IF;
  END IF;

  UPDATE users
  SET
    first_name      = TRIM(p_first_name),
    last_name       = TRIM(p_last_name),
    name_changed_at = NOW()
  WHERE email = v_email;

  RETURN NULL; -- success
END;
$$;

-- ── RPC: get_name_cooldown ────────────────────────────────────
-- Returns the ISO timestamp when the user can next change their name,
-- or NULL if they can change it now.

CREATE OR REPLACE FUNCTION get_name_cooldown()
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_email      TEXT;
  v_changed_at TIMESTAMPTZ;
  v_next       TIMESTAMPTZ;
BEGIN
  v_email := auth.jwt() ->> 'email';
  IF v_email IS NULL THEN RETURN NULL; END IF;

  SELECT name_changed_at INTO v_changed_at
  FROM users WHERE email = v_email;

  IF v_changed_at IS NULL THEN RETURN NULL; END IF;

  v_next := v_changed_at + INTERVAL '31 days';
  IF NOW() >= v_next THEN RETURN NULL; END IF;

  RETURN v_next;
END;
$$;
