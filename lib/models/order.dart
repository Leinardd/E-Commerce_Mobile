import 'dart:developer' as developer;

class Order {
  final String id;
  final String sellerEmail;
  final String buyerEmail;
  final String productId;
  final String productName;
  final String productImageUrl;
  final double unitPrice;
  final int quantity;
  final String deliveryAddress;
  final DateTime createdAt;
  String status;
  String? riderEmail;

  // ── Status constants ──────────────────────────────────────────────────────
  static const String pending        = 'pending';
  static const String confirmed      = 'confirmed';
  static const String preparing      = 'preparing';
  static const String readyForPickup = 'ready_for_pickup';
  static const String shipped        = 'shipped';
  static const String outForDelivery = 'out_for_delivery';
  static const String delivered      = 'delivered';
  static const String completed      = 'completed';
  static const String cancelled      = 'cancelled';

  // Legacy — kept so old SharedPreferences data can still be parsed
  static const String toPay        = 'toPay';
  static const String toShip       = 'toShip';
  static const String toReceive    = 'toReceive';
  static const String riderAccepted = 'riderAccepted';
  static const String pickedUp     = 'pickedUp';
  static const String inTransit    = 'inTransit';
  static const String nearLocation = 'nearLocation';

  static const double commissionRate = 0.15;

  double get total      => unitPrice * quantity;
  double get commission => total * commissionRate;

  static const List<String> riderStatuses = [shipped, outForDelivery, delivered];

  Order({
    this.id = '',
    required this.sellerEmail,
    required this.buyerEmail,
    required this.productId,
    required this.productName,
    required this.productImageUrl,
    required this.unitPrice,
    required this.quantity,
    required this.deliveryAddress,
    required this.createdAt,
    required this.status,
    this.riderEmail,
  });

  // Parses both snake_case (Supabase) and camelCase (legacy SharedPreferences).
  factory Order.fromJson(Map<String, dynamic> json) {
    try {
      final unitPrice = json['unit_price'] ?? json['unitPrice'];
      final createdAtStr =
          json['created_at'] as String? ?? json['createdAt'] as String?;
      return Order(
        id:              json['id'] as String? ?? '',
        sellerEmail:     json['seller_email'] as String? ?? json['sellerEmail'] as String? ?? '',
        buyerEmail:      json['buyer_email'] as String? ?? json['buyerEmail'] as String? ?? '',
        productId:       json['product_id'] as String? ?? json['productId'] as String? ?? '',
        productName:     json['product_name'] as String? ?? json['productName'] as String? ?? 'Unknown Product',
        productImageUrl: json['product_image_url'] as String? ?? json['productImageUrl'] as String? ?? '',
        unitPrice:       unitPrice is num ? unitPrice.toDouble() : 0.0,
        quantity:        json['quantity'] as int? ?? 1,
        deliveryAddress: json['delivery_address'] as String? ?? json['deliveryAddress'] as String? ?? '',
        createdAt:       createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now(),
        status:          json['status'] as String? ?? pending,
        riderEmail:      json['rider_email'] as String? ?? json['riderEmail'] as String?,
      );
    } catch (e) {
      developer.log('[Order.fromJson] Parsing error: $e\nJSON: $json');
      rethrow;
    }
  }

  // Used for Supabase inserts — id is omitted so Supabase generates a UUID.
  Map<String, dynamic> toSupabaseJson() {
    final m = <String, dynamic>{
      'buyer_email':       buyerEmail,
      'seller_email':      sellerEmail,
      'product_id':        productId,
      'product_name':      productName,
      'product_image_url': productImageUrl,
      'unit_price':        unitPrice,
      'quantity':          quantity,
      'delivery_address':  deliveryAddress,
      'status':            status,
    };
    if (riderEmail != null) m['rider_email'] = riderEmail;
    return m;
  }

  static String statusLabel(String status) {
    switch (status) {
      case pending:        return 'Pending';
      case confirmed:      return 'Confirmed';
      case preparing:      return 'Preparing';
      case readyForPickup: return 'Ready for Pickup';
      case shipped:        return 'Shipped';
      case outForDelivery: return 'Out for Delivery';
      case delivered:      return 'Delivered';
      case completed:      return 'Completed';
      case cancelled:      return 'Cancelled';
      // Legacy
      case toPay:          return 'To Pay';
      case toShip:         return 'To Ship';
      case toReceive:      return 'To Receive';
      case riderAccepted:  return 'Rider Accepted';
      case pickedUp:       return 'Picked Up';
      case inTransit:      return 'In Transit';
      case nearLocation:   return 'Near Location';
      default:             return status;
    }
  }
}
