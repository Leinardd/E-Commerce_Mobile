import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_room.dart';
import '../models/chat_message.dart';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  ChatService._internal();
  factory ChatService() => _instance;

  static SupabaseClient get _db => Supabase.instance.client;

  // ── Room management ──────────────────────────────────────────────────────────

  /// Returns or creates the room for this buyer-seller pair.
  Future<ChatRoom?> getOrCreateRoom({
    required String buyerEmail,
    required String sellerEmail,
    required String sellerId,
    required String sellerName,
    String buyerName = '',
  }) async {
    try {
      final data = await _db.rpc('get_or_create_room', params: {
        'p_buyer_email': buyerEmail,
        'p_seller_email': sellerEmail,
        'p_seller_id': sellerId,
        'p_seller_name': sellerName,
        'p_buyer_name': buyerName,
      });
      return ChatRoom.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      developer.log('[ChatService] getOrCreateRoom error: $e');
      return null;
    }
  }

  /// Live stream of all rooms for a buyer, ordered by most recent.
  Stream<List<ChatRoom>> watchBuyerRooms(String buyerEmail) {
    return _db
        .from('chat_rooms')
        .stream(primaryKey: ['id'])
        .eq('buyer_email', buyerEmail)
        .order('last_message_at', ascending: false)
        .map((rows) => rows.map(ChatRoom.fromJson).toList());
  }

  /// Live stream of all rooms for a seller, ordered by most recent.
  Stream<List<ChatRoom>> watchSellerRooms(String sellerEmail) {
    return _db
        .from('chat_rooms')
        .stream(primaryKey: ['id'])
        .eq('seller_email', sellerEmail)
        .order('last_message_at', ascending: false)
        .map((rows) => rows.map(ChatRoom.fromJson).toList());
  }

  // ── Messages ─────────────────────────────────────────────────────────────────

  /// Paginated fetch of past messages in a room (most recent first).
  Future<List<ChatMessage>> fetchMessages(
    String roomId, {
    int limit = 40,
    String? beforeId,
  }) async {
    try {
      var query = _db
          .from('messages')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: false)
          .limit(limit);

      if (beforeId != null) {
        // Fetch the timestamp for the cursor message then use it for pagination
        final cursor = await _db
            .from('messages')
            .select('created_at')
            .eq('id', beforeId)
            .single();
        query = _db
            .from('messages')
            .select()
            .eq('room_id', roomId)
            .lt('created_at', cursor['created_at'] as String)
            .order('created_at', ascending: false)
            .limit(limit);
      }

      final rows = await query;
      return rows.map((r) => ChatMessage.fromJson(r)).toList();
    } catch (e) {
      developer.log('[ChatService] fetchMessages error: $e');
      return [];
    }
  }

  /// Real-time stream of new messages in a room.
  /// Only delivers messages created AFTER subscription — use fetchMessages
  /// for history, then attach this for live updates.
  Stream<ChatMessage> watchNewMessages(String roomId) {
    final controller = StreamController<ChatMessage>.broadcast();

    final channel = _db
        .channel('messages:$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final msg = ChatMessage.fromJson(
                  payload.newRecord as Map<String, dynamic>);
              controller.add(msg);
            } catch (e) {
              developer.log('[ChatService] watchNewMessages parse error: $e');
            }
          },
        )
        .subscribe();

    controller.onCancel = () {
      _db.removeChannel(channel);
    };

    return controller.stream;
  }

  /// Send a text message via RPC (atomic insert + room update).
  Future<ChatMessage?> sendTextMessage({
    required String roomId,
    required String senderEmail,
    required String senderRole,
    required String content,
  }) async {
    try {
      final data = await _db.rpc('send_message', params: {
        'p_room_id': roomId,
        'p_sender_email': senderEmail,
        'p_sender_role': senderRole,
        'p_content': content,
        'p_message_type': 'text',
      });
      return ChatMessage.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      developer.log('[ChatService] sendTextMessage error: $e');
      return null;
    }
  }

  /// Upload an image to Supabase Storage and send an image message.
  Future<ChatMessage?> sendImageMessage({
    required String roomId,
    required String senderEmail,
    required String senderRole,
    required File imageFile,
  }) async {
    try {
      final fileName =
          '${roomId}_${senderEmail}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _db.storage
          .from('chat-images')
          .upload(fileName, imageFile);
      final url = _db.storage.from('chat-images').getPublicUrl(fileName);

      final data = await _db.rpc('send_message', params: {
        'p_room_id': roomId,
        'p_sender_email': senderEmail,
        'p_sender_role': senderRole,
        'p_content': '',
        'p_message_type': 'image',
        'p_image_url': url,
      });
      return ChatMessage.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      developer.log('[ChatService] sendImageMessage error: $e');
      return null;
    }
  }

  /// Send a product reference message.
  Future<ChatMessage?> sendProductMessage({
    required String roomId,
    required String senderEmail,
    required String senderRole,
    required String productId,
    required String productName,
    required String productImageUrl,
    required double productPrice,
  }) async {
    try {
      final data = await _db.rpc('send_message', params: {
        'p_room_id': roomId,
        'p_sender_email': senderEmail,
        'p_sender_role': senderRole,
        'p_content': '',
        'p_message_type': 'product',
        'p_product_id': productId,
        'p_product_name': productName,
        'p_product_image_url': productImageUrl,
        'p_product_price': productPrice,
      });
      return ChatMessage.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      developer.log('[ChatService] sendProductMessage error: $e');
      return null;
    }
  }

  /// Send an automated system message (bot reply).
  /// Does not increment unread counts — purely informational.
  Future<ChatMessage?> sendSystemMessage({
    required String roomId,
    required String content,
  }) async {
    try {
      final data = await _db.rpc('send_system_message', params: {
        'p_room_id': roomId,
        'p_content': content,
      });
      return ChatMessage.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      developer.log('[ChatService] sendSystemMessage error: $e');
      return null;
    }
  }

  /// Mark all messages in a room as read and reset unread counter.
  Future<void> markMessagesRead(String roomId, String readerRole) async {
    try {
      await _db.rpc('mark_messages_read', params: {
        'p_room_id': roomId,
        'p_reader_role': readerRole,
      });
    } catch (e) {
      developer.log('[ChatService] markMessagesRead error: $e');
    }
  }

  // ── Typing indicators (Broadcast — ephemeral, no DB storage) ──────────────

  RealtimeChannel? _typingChannel;

  void subscribeTyping({
    required String roomId,
    required void Function(String senderEmail, bool isTyping) onTyping,
  }) {
    _typingChannel?.unsubscribe();
    _typingChannel = _db
        .channel('typing:$roomId')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final email = payload['email'] as String? ?? '';
            final typing = payload['typing'] as bool? ?? false;
            onTyping(email, typing);
          },
        )
        .subscribe();
  }

  void sendTyping({
    required String roomId,
    required String senderEmail,
    required bool isTyping,
  }) {
    _typingChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'email': senderEmail, 'typing': isTyping},
    );
  }

  void unsubscribeTyping() {
    _typingChannel?.unsubscribe();
    _typingChannel = null;
  }

  // ── Total unread count ───────────────────────────────────────────────────────

  /// Returns total unread count for buyer (for badge on Messages tab).
  Future<int> getBuyerTotalUnread(String buyerEmail) async {
    try {
      final rows = await _db
          .from('chat_rooms')
          .select('buyer_unread_count')
          .eq('buyer_email', buyerEmail);
      return (rows as List).fold<int>(
          0, (sum, r) => sum + ((r['buyer_unread_count'] as int?) ?? 0));
    } catch (e) {
      developer.log('[ChatService] getBuyerTotalUnread error: $e');
      return 0;
    }
  }

  /// Returns total unread count for seller (for badge on inbox card).
  Future<int> getSellerTotalUnread(String sellerEmail) async {
    try {
      final rows = await _db
          .from('chat_rooms')
          .select('seller_unread_count')
          .eq('seller_email', sellerEmail);
      return (rows as List).fold<int>(
          0, (sum, r) => sum + ((r['seller_unread_count'] as int?) ?? 0));
    } catch (e) {
      developer.log('[ChatService] getSellerTotalUnread error: $e');
      return 0;
    }
  }
}
