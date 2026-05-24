import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

/// products.seller_id  →  sellers.id  (int, auto-increment PK of sellers table)
/// sellers.user_id     →  users.id    (int)
/// sellers.auth_user_id→  auth.users.id (UUID string)
class ProductService {
  static final _client = Supabase.instance.client;

  // ── Category cache ──────────────────────────────────────────────────────────

  static Map<int, String>? _categoryCache;

  static Future<Map<int, String>> _categoryMap() async {
    if (_categoryCache != null && _categoryCache!.isNotEmpty) return _categoryCache!;
    try {
      final rows = await _client
          .from('categories')
          .select('id, name')
          .order('name');
      final list = rows as List;
      if (list.isNotEmpty) {
        _categoryCache = {
          for (final r in list)
            (r['id'] as num).toInt(): (r['name'] as String),
        };
        debugPrint('✅ ProductService categories: ${_categoryCache!.length} loaded');
      } else {
        debugPrint('⚠️ ProductService: categories table returned empty');
      }
    } catch (e) {
      debugPrint('❌ Error loading category map: $e');
    }
    return _categoryCache ?? {};
  }

  // ── Image helpers ───────────────────────────────────────────────────────────

  static const _imageBucket = 'products';

  static String _toPublicUrl(String raw) {
    if (raw.startsWith('http')) return raw;
    final filename = raw.contains('/') ? raw.split('/').last : raw;
    return _client.storage.from(_imageBucket).getPublicUrl(filename);
  }

  static Future<Map<dynamic, String>> _imageMap(List<dynamic> ids) async {
    if (ids.isEmpty) return {};
    try {
      final rows = await _client
          .from('product_images')
          .select('product_id, image_url')
          .inFilter('product_id', ids);
      final map = <dynamic, String>{};
      for (final r in (rows as List)) {
        final pid = r['product_id'];
        if (!map.containsKey(pid)) {
          final raw = r['image_url'] as String? ?? '';
          map[pid] = raw.isEmpty ? '' : _toPublicUrl(raw);
        }
      }
      return map;
    } catch (e) {
      debugPrint('❌ Error loading image map: $e');
      return {};
    }
  }

  // ── Seller lookup ───────────────────────────────────────────────────────────
  //
  // products.seller_id == sellers.id (int)
  // Query sellers directly by their PK — no FK constraint needed.

  static Future<Map<int, Map<String, dynamic>>> _sellerMap(
      List<dynamic> rawIds) async {
    final ids = rawIds
        .where((id) => id != null)
        .map<int?>((id) {
          if (id is num) return id.toInt();
          return int.tryParse(id.toString());
        })
        .whereType<int>()
        .toSet()
        .toList();

    if (ids.isEmpty) return {};

    try {
      // Query by sellers.id first
      var rows = await _client
          .from('sellers')
          .select()
          .inFilter('id', ids);

      // If none found, products may store sellers.user_id instead of sellers.id
      if ((rows as List).isEmpty) {
        rows = await _client
            .from('sellers')
            .select()
            .inFilter('user_id', ids);
      }

      final map = <int, Map<String, dynamic>>{};
      for (final r in (rows as List)) {
        final data = r as Map<String, dynamic>;
        // Index by sellers.id
        final sid = (data['id'] as num).toInt();
        map[sid] = data;
        // Also index by sellers.user_id so either FK value resolves
        final uid = data['user_id'];
        if (uid != null) {
          map.putIfAbsent((uid as num).toInt(), () => data);
        }
      }
      debugPrint('🏪 Seller map: ${map.length} entries loaded for ids=$ids');
      return map;
    } catch (e) {
      debugPrint('❌ Error loading seller map: $e');
      return {};
    }
  }

  // ── Sold counts ─────────────────────────────────────────────────────────────

  static Future<Map<dynamic, int>> _soldMap(List<dynamic> productIds) async {
    if (productIds.isEmpty) return {};
    try {
      final rows = await _client
          .from('orders')
          .select('product_id, quantity')
          .neq('status', 'cancelled')
          .inFilter('product_id', productIds.map((id) => id.toString()).toList());
      final map = <dynamic, int>{};
      for (final r in (rows as List)) {
        final pid = r['product_id'];
        final qty = (r['quantity'] as num?)?.toInt() ?? 0;
        map[pid] = (map[pid] ?? 0) + qty;
      }
      return map;
    } catch (e) {
      debugPrint('❌ Error loading sold map: $e');
      return {};
    }
  }

  // ── Enrich ──────────────────────────────────────────────────────────────────

  static Map<String, dynamic> _enrich(
    Map<String, dynamic> json,
    Map<int, String> categories,
    Map<dynamic, String> images, {
    Map<int, Map<String, dynamic>> sellers = const {},
    Map<dynamic, int> sold = const {},
  }) {
    final catId = json['category_id'];
    final catName =
        catId != null ? categories[(catId as num).toInt()] : null;

    final rawSellerId = json['seller_id'];
    final sellerId = rawSellerId != null
        ? (rawSellerId is num
            ? rawSellerId.toInt()
            : int.tryParse(rawSellerId.toString()))
        : null;
    final sellerData = sellerId != null ? sellers[sellerId] : null;

    final pid = json['id'];
    final totalSold = sold[pid] ?? sold[pid?.toString()] ?? 0;

    return {
      ...json,
      'category': catName ?? 'Uncategorized',
      'image_url': images[pid] ?? '',
      'total_sold': totalSold,
      if (sellerData != null) 'sellers': sellerData,
    };
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Fetch all approved products with seller info.
  static Future<List<Product>> getAllProducts() async {
    final catMap = await _categoryMap();
    // Let the products query throw — callers can catch and show retry UI.
    final rows = await _client
        .from('products')
        .select()
        .or('approval_status.eq.approved,approval_status.is.null')
        .or('archive_status.eq.active,archive_status.is.null')
        .order('created_at', ascending: false);

    final list = rows as List;
    if (list.isEmpty) return [];

    final ids = list.map((r) => r['id']).toList();
    final results = await Future.wait([
      _imageMap(ids),
      _sellerMap(list.map((r) => r['seller_id']).toList()),
      _soldMap(ids),
    ]);
    final imgMap  = results[0] as Map<dynamic, String>;
    final selMap  = results[1] as Map<int, Map<String, dynamic>>;
    final soldMap = results[2] as Map<dynamic, int>;

    return list
        .map((r) => Product.fromJson(
            _enrich(r as Map<String, dynamic>, catMap, imgMap,
                sellers: selMap, sold: soldMap)))
        .toList();
  }

  /// Fetch the 4 most recently added approved products for the featured section.
  static Future<List<Product>> getFeatured() async {
    try {
      final catMap = await _categoryMap();
      final rows = await _client
          .from('products')
          .select()
          .or('approval_status.eq.approved,approval_status.is.null')
          .or('archive_status.eq.active,archive_status.is.null')
          .order('created_at', ascending: false)
          .limit(4);

      final list = rows as List;
      if (list.isEmpty) return [];

      final imgMap = await _imageMap(list.map((r) => r['id']).toList());
      final selMap = await _sellerMap(list.map((r) => r['seller_id']).toList());

      return list
          .map((r) => Product.fromJson(
              _enrich(r as Map<String, dynamic>, catMap, imgMap,
                  sellers: selMap)))
          .toList();
    } catch (e) {
      debugPrint('❌ Error fetching featured products: $e');
      return [];
    }
  }

  /// Fetch approved products for a given category name.
  static Future<List<Product>> getProductsByCategory(String category) async {
    try {
      final catMap = await _categoryMap();
      final entry =
          catMap.entries.where((e) => e.value == category).firstOrNull;
      if (entry == null) return [];

      final rows = await _client
          .from('products')
          .select()
          .eq('category_id', entry.key)
          .or('approval_status.eq.approved,approval_status.is.null')
          .or('archive_status.eq.active,archive_status.is.null')
          .order('created_at', ascending: false);

      final list = rows as List;
      final imgMap = await _imageMap(list.map((r) => r['id']).toList());
      final selMap = await _sellerMap(
          list.map((r) => r['seller_id']).toList());

      return list
          .map((r) => Product.fromJson(
              _enrich(r as Map<String, dynamic>, catMap, imgMap,
                  sellers: selMap)))
          .toList();
    } catch (e) {
      debugPrint('❌ Error fetching products by category: $e');
      return [];
    }
  }

  /// Fetch all approved products by a specific seller (sellers.id).
  static Future<List<Product>> getProductsBySellerId(dynamic sellerId) async {
    if (sellerId == null) return [];
    try {
      final id = sellerId is num
          ? sellerId.toInt()
          : int.tryParse(sellerId.toString());
      if (id == null) {
        debugPrint('⚠️ getProductsBySellerId: invalid sellerId=$sellerId');
        return [];
      }

      final catMap = await _categoryMap();
      final rows = await _client
          .from('products')
          .select()
          .eq('seller_id', id)
          .or('approval_status.eq.approved,approval_status.is.null')
          .or('archive_status.eq.active,archive_status.is.null')
          .order('created_at', ascending: false);

      final list = rows as List;
      debugPrint('🏪 getProductsBySellerId($id): ${list.length} products');
      final imgMap = await _imageMap(list.map((r) => r['id']).toList());
      final selMap = await _sellerMap([id]);

      return list
          .map((r) => Product.fromJson(
              _enrich(r as Map<String, dynamic>, catMap, imgMap,
                  sellers: selMap)))
          .toList();
    } catch (e) {
      debugPrint('❌ Error fetching seller products: $e');
      return [];
    }
  }

  /// Fetch the sellers row — tries sellers.id first, then sellers.user_id.
  static Future<Map<String, dynamic>?> getSellerProfile(
      dynamic sellerId) async {
    if (sellerId == null) return null;
    final id = sellerId is num
        ? sellerId.toInt()
        : int.tryParse(sellerId.toString());
    if (id == null) {
      debugPrint('⚠️ getSellerProfile: invalid sellerId=$sellerId');
      return null;
    }
    try {
      // Try by sellers.id (PK)
      var row = await _client
          .from('sellers')
          .select()
          .eq('id', id)
          .maybeSingle();

      // Fallback: products might store sellers.user_id as the seller_id
      row ??= await _client
          .from('sellers')
          .select()
          .eq('user_id', id)
          .maybeSingle();

      debugPrint('🏪 getSellerProfile($id): ${row != null ? 'found → ${row['store_name']}' : 'not found'}');
      return row;
    } catch (e) {
      debugPrint('❌ Error fetching seller profile: $e');
      return null;
    }
  }

  /// Look up the contact_email for a seller by their integer seller ID.
  /// Falls back to a direct sellers table query (allowed by anon RLS policy).
  static Future<String?> getSellerEmailById(dynamic sellerId) async {
    if (sellerId == null) return null;
    final id = sellerId is num
        ? sellerId.toInt()
        : int.tryParse(sellerId.toString());
    if (id == null) return null;

    // Try the SECURITY DEFINER RPC first (exists if chat migration was run).
    try {
      final result = await _client.rpc(
        'get_seller_email',
        params: {'p_seller_id': id},
      );
      if (result != null) return result as String?;
    } catch (_) {}

    // Fallback: direct sellers table query (anon SELECT allowed for active sellers).
    try {
      final row = await _client
          .from('sellers')
          .select('contact_email')
          .eq('id', id)
          .maybeSingle();
      return row?['contact_email'] as String?;
    } catch (e) {
      debugPrint('❌ getSellerEmailById error: $e');
      return null;
    }
  }

  /// Returns sorted list of active category names.
  static Future<List<String>> getCategories() async {
    final map = await _categoryMap();
    final names = map.values.toList()..sort();
    return names;
  }

  /// Returns category name → product image URL.
  /// Every category gets an image: its own product image if available,
  /// otherwise a rotating fallback from other categories in the DB.
  static Future<Map<String, String>> getCategoryImages() async {
    try {
      final catMap = await _categoryMap();
      final rows = await _client
          .from('products')
          .select('id, category_id')
          .order('created_at', ascending: false);

      final list = rows as List;
      if (list.isEmpty) return {};

      final imgMap = await _imageMap(list.map((r) => r['id']).toList());

      // Build a pool of all available images (in DB order)
      final imagePool = <String>[];
      final result = <String, String>{};

      for (final r in list) {
        final imgUrl = imgMap[r['id']];
        if (imgUrl != null && imgUrl.isNotEmpty) imagePool.add(imgUrl);

        final catId = r['category_id'];
        if (catId == null) continue;
        final catName = catMap[(catId as num).toInt()];
        if (catName == null || result.containsKey(catName)) continue;
        if (imgUrl != null && imgUrl.isNotEmpty) {
          result[catName] = imgUrl;
        }
      }

      // Assign a rotating fallback image to categories that have no products
      if (imagePool.isNotEmpty) {
        int poolIdx = 0;
        for (final catName in catMap.values) {
          if (!result.containsKey(catName)) {
            result[catName] = imagePool[poolIdx % imagePool.length];
            poolIdx++;
          }
        }
      }

      return result;
    } catch (e) {
      debugPrint('❌ getCategoryImages error: $e');
      return {};
    }
  }

  /// Fetch a single product by ID with seller info.
  static Future<Product?> getProductById(dynamic productId) async {
    try {
      final catMap = await _categoryMap();
      final row = await _client
          .from('products')
          .select()
          .eq('id', productId)
          .maybeSingle();

      if (row == null) return null;
      final imgMap = await _imageMap([productId]);
      final selMap = await _sellerMap([row['seller_id']]);
      return Product.fromJson(_enrich(row, catMap, imgMap, sellers: selMap));
    } catch (e) {
      debugPrint('❌ Error fetching product: $e');
      return null;
    }
  }

  /// Decrements a product's stock by [quantity]. Clamps at 0 — never goes negative.
  static Future<void> decrementStock(dynamic productId, int quantity) async {
    try {
      final id = productId is int ? productId : int.tryParse(productId.toString());
      if (id == null) return;
      await _client.rpc('decrement_product_stock', params: {
        'p_product_id': id,
        'p_quantity': quantity,
      });
    } catch (e) {
      debugPrint('❌ decrementStock error: $e');
    }
  }

  static Future<void> incrementStock(dynamic productId, int quantity) async {
    try {
      final id = productId is int ? productId : int.tryParse(productId.toString());
      if (id == null) return;
      await _client.rpc('increment_product_stock', params: {
        'p_product_id': id,
        'p_quantity': quantity,
      });
    } catch (e) {
      debugPrint('❌ incrementStock error: $e');
    }
  }

  /// Clears the category cache (call after admin changes categories).
  static void clearCategoryCache() => _categoryCache = null;
}
