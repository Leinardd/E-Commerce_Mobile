-- ============================================================
-- Varón Chat System — Supabase Migration
-- Run this in the Supabase SQL Editor
-- ============================================================

-- ── Tables ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS chat_rooms (
  id                   UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  buyer_email          TEXT        NOT NULL,
  seller_email         TEXT        NOT NULL,
  seller_id            TEXT        NOT NULL DEFAULT '',
  seller_name          TEXT        NOT NULL DEFAULT '',
  buyer_name           TEXT        NOT NULL DEFAULT '',
  last_message         TEXT        NOT NULL DEFAULT '',
  last_message_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_message_sender  TEXT        NOT NULL DEFAULT '',
  buyer_unread_count   INT         NOT NULL DEFAULT 0,
  seller_unread_count  INT         NOT NULL DEFAULT 0,
  is_resolved          BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(buyer_email, seller_email)
);

CREATE TABLE IF NOT EXISTS messages (
  id                UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  room_id           UUID        NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
  sender_email      TEXT        NOT NULL,
  sender_role       TEXT        NOT NULL CHECK (sender_role IN ('buyer', 'seller')),
  content           TEXT        NOT NULL DEFAULT '',
  image_url         TEXT,
  message_type      TEXT        NOT NULL DEFAULT 'text'
                    CHECK (message_type IN ('text', 'image', 'product')),
  product_id        TEXT,
  product_name      TEXT,
  product_image_url TEXT,
  product_price     NUMERIC,
  is_read           BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ──────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_messages_room_id
  ON messages(room_id);

CREATE INDEX IF NOT EXISTS idx_messages_created_at
  ON messages(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_buyer_email
  ON chat_rooms(buyer_email);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_seller_email
  ON chat_rooms(seller_email);

CREATE INDEX IF NOT EXISTS idx_chat_rooms_last_message_at
  ON chat_rooms(last_message_at DESC);

-- ── Enable RLS ───────────────────────────────────────────────

ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages   ENABLE ROW LEVEL SECURITY;

-- ── RLS Policies: chat_rooms ─────────────────────────────────

-- Allow participants to read their own rooms
CREATE POLICY "chat_rooms_select" ON chat_rooms
  FOR SELECT USING (
    auth.jwt() ->> 'email' = buyer_email
    OR auth.jwt() ->> 'email' = seller_email
  );

-- Allow any authenticated user to insert (creating a new room)
CREATE POLICY "chat_rooms_insert" ON chat_rooms
  FOR INSERT WITH CHECK (
    auth.jwt() ->> 'email' = buyer_email
  );

-- Allow participants to update room metadata (unread counts, last message)
CREATE POLICY "chat_rooms_update" ON chat_rooms
  FOR UPDATE USING (
    auth.jwt() ->> 'email' = buyer_email
    OR auth.jwt() ->> 'email' = seller_email
  );

-- ── RLS Policies: messages ───────────────────────────────────

-- Allow participants to read messages in their rooms
CREATE POLICY "messages_select" ON messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM chat_rooms r
      WHERE r.id = room_id
        AND (
          auth.jwt() ->> 'email' = r.buyer_email
          OR auth.jwt() ->> 'email' = r.seller_email
        )
    )
  );

-- Allow participants to insert messages in their rooms
CREATE POLICY "messages_insert" ON messages
  FOR INSERT WITH CHECK (
    auth.jwt() ->> 'email' = sender_email
    AND EXISTS (
      SELECT 1 FROM chat_rooms r
      WHERE r.id = room_id
        AND (
          auth.jwt() ->> 'email' = r.buyer_email
          OR auth.jwt() ->> 'email' = r.seller_email
        )
    )
  );

-- Allow participants to update is_read
CREATE POLICY "messages_update" ON messages
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM chat_rooms r
      WHERE r.id = room_id
        AND (
          auth.jwt() ->> 'email' = r.buyer_email
          OR auth.jwt() ->> 'email' = r.seller_email
        )
    )
  );

-- ── RPC: send_message ────────────────────────────────────────
-- Atomically inserts message and updates room last_message + unread counter.
-- Returns the inserted message row.

CREATE OR REPLACE FUNCTION send_message(
  p_room_id           UUID,
  p_sender_email      TEXT,
  p_sender_role       TEXT,
  p_content           TEXT,
  p_message_type      TEXT    DEFAULT 'text',
  p_image_url         TEXT    DEFAULT NULL,
  p_product_id        TEXT    DEFAULT NULL,
  p_product_name      TEXT    DEFAULT NULL,
  p_product_image_url TEXT    DEFAULT NULL,
  p_product_price     NUMERIC DEFAULT NULL
)
RETURNS messages
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_message messages;
  v_display_content TEXT;
BEGIN
  -- Choose display content for last_message preview
  v_display_content := CASE p_message_type
    WHEN 'image'   THEN '📷 Image'
    WHEN 'product' THEN '🛍 ' || COALESCE(p_product_name, 'Product')
    ELSE p_content
  END;

  -- Insert the message
  INSERT INTO messages (
    room_id, sender_email, sender_role, content, image_url,
    message_type, product_id, product_name, product_image_url, product_price
  ) VALUES (
    p_room_id, p_sender_email, p_sender_role, p_content, p_image_url,
    p_message_type, p_product_id, p_product_name, p_product_image_url, p_product_price
  )
  RETURNING * INTO v_message;

  -- Update room: last_message, last_message_at, last_message_sender,
  -- and increment the OTHER participant's unread counter
  UPDATE chat_rooms SET
    last_message        = v_display_content,
    last_message_at     = v_message.created_at,
    last_message_sender = p_sender_email,
    buyer_unread_count  = CASE WHEN p_sender_role = 'seller'
                               THEN buyer_unread_count + 1
                               ELSE buyer_unread_count END,
    seller_unread_count = CASE WHEN p_sender_role = 'buyer'
                               THEN seller_unread_count + 1
                               ELSE seller_unread_count END
  WHERE id = p_room_id;

  RETURN v_message;
END;
$$;

-- ── RPC: mark_messages_read ──────────────────────────────────
-- Marks all messages in a room as read and resets the caller's unread counter.

CREATE OR REPLACE FUNCTION mark_messages_read(
  p_room_id     UUID,
  p_reader_role TEXT   -- 'buyer' or 'seller'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Mark unread messages from the OTHER party as read
  UPDATE messages
  SET is_read = TRUE
  WHERE room_id = p_room_id
    AND is_read = FALSE
    AND sender_role <> p_reader_role;

  -- Reset the reader's unread counter on the room
  IF p_reader_role = 'buyer' THEN
    UPDATE chat_rooms SET buyer_unread_count = 0 WHERE id = p_room_id;
  ELSE
    UPDATE chat_rooms SET seller_unread_count = 0 WHERE id = p_room_id;
  END IF;
END;
$$;

-- ── RPC: get_or_create_room ──────────────────────────────────
-- Returns existing room or inserts a new one (upsert).

CREATE OR REPLACE FUNCTION get_or_create_room(
  p_buyer_email  TEXT,
  p_seller_email TEXT,
  p_seller_id    TEXT,
  p_seller_name  TEXT,
  p_buyer_name   TEXT DEFAULT ''
)
RETURNS chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room chat_rooms;
BEGIN
  INSERT INTO chat_rooms (buyer_email, seller_email, seller_id, seller_name, buyer_name)
  VALUES (p_buyer_email, p_seller_email, p_seller_id, p_seller_name, p_buyer_name)
  ON CONFLICT (buyer_email, seller_email) DO UPDATE
    SET seller_name = EXCLUDED.seller_name,
        seller_id   = EXCLUDED.seller_id
  RETURNING * INTO v_room;

  RETURN v_room;
END;
$$;

-- ── Storage bucket for chat images ───────────────────────────
-- Run this section separately if using Supabase dashboard Storage tab.
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('chat-images', 'chat-images', true)
-- ON CONFLICT DO NOTHING;

-- Storage policy: authenticated users can upload to chat-images
-- CREATE POLICY "chat_images_upload" ON storage.objects
--   FOR INSERT WITH CHECK (bucket_id = 'chat-images' AND auth.role() = 'authenticated');

-- Storage policy: public read
-- CREATE POLICY "chat_images_read" ON storage.objects
--   FOR SELECT USING (bucket_id = 'chat-images');

-- ── Enable Realtime for both tables ─────────────────────────
-- Run these in Supabase SQL Editor:
-- ALTER PUBLICATION supabase_realtime ADD TABLE chat_rooms;
-- ALTER PUBLICATION supabase_realtime ADD TABLE messages;

-- ── System message support ────────────────────────────────────
-- Run this block to add 'system' as a valid message/sender type.

ALTER TABLE messages
  DROP CONSTRAINT IF EXISTS messages_message_type_check;
ALTER TABLE messages
  ADD CONSTRAINT messages_message_type_check
  CHECK (message_type IN ('text', 'image', 'product', 'system'));

ALTER TABLE messages
  DROP CONSTRAINT IF EXISTS messages_sender_role_check;
ALTER TABLE messages
  ADD CONSTRAINT messages_sender_role_check
  CHECK (sender_role IN ('buyer', 'seller', 'system'));

-- RPC: send_system_message
-- Inserts a system message without touching unread counts.
-- SECURITY DEFINER so it bypasses the sender_email RLS check.
CREATE OR REPLACE FUNCTION send_system_message(
  p_room_id UUID,
  p_content  TEXT
)
RETURNS messages
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_message messages;
BEGIN
  INSERT INTO messages (
    room_id, sender_email, sender_role, content, message_type, is_read
  ) VALUES (
    p_room_id, 'system', 'system', p_content, 'system', TRUE
  )
  RETURNING * INTO v_message;

  RETURN v_message;
END;
$$;
