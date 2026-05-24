class Product {
  final dynamic id;
  final String name;
  final double price;
  final String description;
  final String category;
  final String imageUrl;
  final dynamic sellerId;
  final String sellerName;
  final String sellerLogoUrl;
  final int stock;
  final int totalSold;

  Product({
    required this.id,
    required this.name,
    required this.price,
    required this.description,
    required this.category,
    required this.imageUrl,
    this.sellerId,
    this.sellerName = '',
    this.sellerLogoUrl = '',
    this.stock = 0,
    this.totalSold = 0,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final sellers = json['sellers'] as Map<String, dynamic>?;
    return Product(
      id: json['id'],
      name: json['name'] ?? '',
      price: (json['price'] is int)
          ? (json['price'] as int).toDouble()
          : (json['price'] as double?) ?? 0.0,
      description: json['description'] ?? '',
      category: json['category'] as String? ?? 'Uncategorized',
      imageUrl: _firstImageUrl(json),
      sellerId: json['seller_id'],
      sellerName: (sellers?['store_name'] as String?) ?? '',
      sellerLogoUrl: (sellers?['logo_url'] as String?) ??
                     (sellers?['avatar_url'] as String?) ?? '',
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      totalSold: (json['total_sold'] as num?)?.toInt() ?? 0,
    );
  }

  static String _firstImageUrl(Map<String, dynamic> json) {
    return json['image_url'] as String? ?? '';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'description': description,
        'category': category,
        'imageUrl': imageUrl,
        'sellerId': sellerId,
        'sellerName': sellerName,
        'sellerLogoUrl': sellerLogoUrl,
        'stock': stock,
      };

  factory Product.fromCartJson(Map<String, dynamic> json) => Product(
        id: json['id'],
        name: json['name'] as String? ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        description: json['description'] as String? ?? '',
        category: json['category'] as String? ?? '',
        imageUrl: json['imageUrl'] as String? ?? '',
        sellerId: json['sellerId'],
        sellerName: json['sellerName'] as String? ?? '',
        sellerLogoUrl: json['sellerLogoUrl'] as String? ?? '',
        stock: json['stock'] as int? ?? 0,
      );

  Product copyWith({
    dynamic id,
    String? name,
    double? price,
    String? description,
    String? category,
    String? imageUrl,
    dynamic sellerId,
    String? sellerName,
    String? sellerLogoUrl,
    int? stock,
    int? totalSold,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      description: description ?? this.description,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerLogoUrl: sellerLogoUrl ?? this.sellerLogoUrl,
      stock: stock ?? this.stock,
      totalSold: totalSold ?? this.totalSold,
    );
  }
}

class CartItem {
  final Product product;
  int quantity;
  final String? selectedSize;
  final String? selectedColor;

  CartItem({
    required this.product,
    this.quantity = 1,
    this.selectedSize,
    this.selectedColor,
  });

  // Unique key per product+variant combo — prevents merging size M with size L
  String get variantKey =>
      '${product.id}|${selectedSize ?? ''}|${selectedColor ?? ''}';

  double getTotal() => product.price * quantity;

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'quantity': quantity,
        'selectedSize': selectedSize,
        'selectedColor': selectedColor,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        product: Product.fromCartJson(
            json['product'] as Map<String, dynamic>),
        quantity: json['quantity'] as int? ?? 1,
        selectedSize: json['selectedSize'] as String?,
        selectedColor: json['selectedColor'] as String?,
      );
}
