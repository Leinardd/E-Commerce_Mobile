class ChatRoom {
  final String id;
  final String buyerEmail;
  final String sellerEmail;
  final String sellerId;
  final String sellerName;
  final String buyerName;
  final String lastMessage;
  final DateTime lastMessageAt;
  final String lastMessageSender;
  final int buyerUnreadCount;
  final int sellerUnreadCount;
  final bool isResolved;
  final DateTime createdAt;

  const ChatRoom({
    required this.id,
    required this.buyerEmail,
    required this.sellerEmail,
    required this.sellerId,
    required this.sellerName,
    required this.buyerName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSender,
    required this.buyerUnreadCount,
    required this.sellerUnreadCount,
    required this.isResolved,
    required this.createdAt,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'] as String,
      buyerEmail: json['buyer_email'] as String? ?? '',
      sellerEmail: json['seller_email'] as String? ?? '',
      sellerId: json['seller_id'] as String? ?? '',
      sellerName: json['seller_name'] as String? ?? '',
      buyerName: json['buyer_name'] as String? ?? '',
      lastMessage: json['last_message'] as String? ?? '',
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : DateTime.now(),
      lastMessageSender: json['last_message_sender'] as String? ?? '',
      buyerUnreadCount: json['buyer_unread_count'] as int? ?? 0,
      sellerUnreadCount: json['seller_unread_count'] as int? ?? 0,
      isResolved: json['is_resolved'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  ChatRoom copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastMessageSender,
    int? buyerUnreadCount,
    int? sellerUnreadCount,
    bool? isResolved,
  }) {
    return ChatRoom(
      id: id,
      buyerEmail: buyerEmail,
      sellerEmail: sellerEmail,
      sellerId: sellerId,
      sellerName: sellerName,
      buyerName: buyerName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessageSender: lastMessageSender ?? this.lastMessageSender,
      buyerUnreadCount: buyerUnreadCount ?? this.buyerUnreadCount,
      sellerUnreadCount: sellerUnreadCount ?? this.sellerUnreadCount,
      isResolved: isResolved ?? this.isResolved,
      createdAt: createdAt,
    );
  }

  int unreadCountFor(String role) =>
      role == 'buyer' ? buyerUnreadCount : sellerUnreadCount;
}
