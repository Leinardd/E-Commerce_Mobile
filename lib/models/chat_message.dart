class ChatMessage {
  final String id;
  final String roomId;
  final String senderEmail;
  final String senderRole; // 'buyer' | 'seller'
  final String content;
  final String? imageUrl;
  final String messageType; // 'text' | 'image' | 'product'
  final String? productId;
  final String? productName;
  final String? productImageUrl;
  final double? productPrice;
  final bool isRead;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderEmail,
    required this.senderRole,
    required this.content,
    this.imageUrl,
    required this.messageType,
    this.productId,
    this.productName,
    this.productImageUrl,
    this.productPrice,
    required this.isRead,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      roomId: json['room_id'] as String? ?? '',
      senderEmail: json['sender_email'] as String? ?? '',
      senderRole: json['sender_role'] as String? ?? 'buyer',
      content: json['content'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      messageType: json['message_type'] as String? ?? 'text',
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String?,
      productImageUrl: json['product_image_url'] as String?,
      productPrice: json['product_price'] != null
          ? (json['product_price'] as num).toDouble()
          : null,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  bool get isImage => messageType == 'image';
  bool get isProduct => messageType == 'product';
  bool get isText => messageType == 'text';
  bool get isSystem => messageType == 'system';
}
