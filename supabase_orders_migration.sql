-- ============================================================
-- Varón Orders — Supabase migration
-- Run this in the Supabase SQL Editor
-- ============================================================

-- Drop existing table (old camelCase schema) and recreate cleanly.
DROP TABLE IF EXISTS orders CASCADE;

CREATE TABLE orders (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_email       TEXT NOT NULL,
  seller_email      TEXT NOT NULL,
  product_id        TEXT NOT NULL,
  product_name      TEXT NOT NULL DEFAULT '',
  product_image_url TEXT NOT NULL DEFAULT '',
  unit_price        NUMERIC(12, 2) NOT NULL,
  quantity          INTEGER NOT NULL DEFAULT 1,
  delivery_address  TEXT NOT NULL DEFAULT '',
  status            TEXT NOT NULL DEFAULT 'pending',
  payment_method    TEXT NOT NULL DEFAULT 'cod',
  rider_email       TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT orders_status_check CHECK (status IN (
    'pending', 'confirmed', 'preparing', 'ready_for_pickup',
    'shipped', 'out_for_delivery', 'delivered', 'completed', 'cancelled'
  ))
);

CREATE INDEX orders_buyer_email_idx  ON orders (buyer_email);
CREATE INDEX orders_seller_email_idx ON orders (seller_email);
CREATE INDEX orders_rider_email_idx  ON orders (rider_email);
CREATE INDEX orders_status_idx       ON orders (status);
CREATE INDEX orders_created_at_idx   ON orders (created_at DESC);

-- Open access for this app (all roles use server-side validation via RPCs)
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "orders_open_access" ON orders FOR ALL USING (true) WITH CHECK (true);

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE orders;

-- ── updated_at trigger ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_updated_at ON orders;
CREATE TRIGGER orders_updated_at
  BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- ── Add payment_method to existing tables (safe to re-run) ───────────────────
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'cod';
