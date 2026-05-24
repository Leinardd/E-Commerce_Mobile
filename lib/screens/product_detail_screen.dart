import 'dart:convert';
import 'package:flutter/material.dart';
// ignore: unnecessary_import
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/product_service.dart';
import '../services/seller_product_service.dart';
import '../widgets/variant_picker_sheet.dart';
import 'chat_conversation_screen.dart';
import 'checkout_screen.dart';
import 'seller_store_screen.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int quantity = 1;
  String? _selectedSize;
  String? _selectedColor;
  late CartService cartService;
  late final TextEditingController _quantityController;

  // Review state
  List<Map<String, dynamic>> _reviews = [];

  // Seller state — fetched lazily so the card always shows
  Map<String, dynamic>? _sellerProfile;

  // Variants loaded from DB
  List<ProductVariant> _variants = [];

  // Color name → ARGB hex for swatch rendering
  static const _colorHexMap = <String, int>{
    'black': 0xFF0A0A0A,   'white': 0xFFF5F5F5,   'red': 0xFFDC2626,
    'navy': 0xFF1E2D55,    'blue': 0xFF2563EB,     'light blue': 0xFF93C5FD,
    'sky blue': 0xFF87CEEB,'green': 0xFF16A34A,    'khaki': 0xFFB5A898,
    'olive': 0xFF6B6B47,   'gray': 0xFF888888,     'grey': 0xFF888888,
    'charcoal': 0xFF36454F,'brown': 0xFF92400E,    'beige': 0xFFF5F0E8,
    'cream': 0xFFFFFDD0,   'pink': 0xFFEC4899,     'hot pink': 0xFFFF69B4,
    'purple': 0xFF7C3AED,  'lavender': 0xFFE6E6FA, 'orange': 0xFFF97316,
    'yellow': 0xFFEAB308,  'maroon': 0xFF800000,   'burgundy': 0xFF800020,
    'teal': 0xFF0D9488,    'mint': 0xFF86EFAC,     'coral': 0xFFFF7F7F,
    'gold': 0xFFD97706,    'silver': 0xFFC0C0C0,   'tan': 0xFFD2B48C,
    'dark blue': 0xFF1E3A5F,'dark gray': 0xFF374151,'light gray': 0xFFD1D5DB,
    'dark green': 0xFF14532D,'rose': 0xFFFF007F,   'violet': 0xFF8B00FF,
  };

  static int _hexFor(String name) =>
      _colorHexMap[name.toLowerCase().trim()] ?? 0xFF888888;

  static const _sizeOrder = ['XS', 'S', 'M', 'L', 'XL', 'XXL', 'XXXL',
      '6', '7', '8', '9', '10', '11', '12', '13'];

  // Whether the whole product is out of stock
  bool get _productOos => widget.product.stock == 0;

  // Unique colors from DB variants
  List<({String label, bool outOfStock})> get _colorOptions {
    final dbColors = _variants
        .where((v) => v.color != null && v.color!.isNotEmpty)
        .map((v) => v.color!)
        .toSet()
        .toList();
    if (dbColors.isNotEmpty) {
      // Only mark a colour OOS when the whole product has no stock
      return dbColors.map((c) => (label: c, outOfStock: _productOos)).toList();
    }
    // Fallback: category-based static colours
    if (!VariantPickerSheet.needsColorForCategory(widget.product.category)) return [];
    return [
      (label: 'Black', outOfStock: _productOos),
      (label: 'White', outOfStock: _productOos),
      (label: 'Navy',  outOfStock: _productOos),
      (label: 'Khaki', outOfStock: _productOos),
      (label: 'Olive', outOfStock: _productOos),
    ];
  }

  // Unique sizes from DB variants, sorted by standard order
  List<({String label, bool outOfStock})> get _sizeOptions {
    final dbSizes = _variants
        .where((v) => v.size != null && v.size!.isNotEmpty)
        .map((v) => v.size!)
        .toSet()
        .toList();
    if (dbSizes.isNotEmpty) {
      dbSizes.sort((a, b) {
        final ai = _sizeOrder.indexOf(a.toUpperCase());
        final bi = _sizeOrder.indexOf(b.toUpperCase());
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
      // Only mark a size OOS when the whole product has no stock
      return dbSizes.map((s) => (label: s, outOfStock: _productOos)).toList();
    }
    // Fallback: category-based static sizes
    return VariantPickerSheet.sizesForCategory(widget.product.category)
        .map((o) => (label: o.label, outOfStock: o.outOfStock))
        .toList();
  }


  @override
  void initState() {
    super.initState();
    cartService = CartService();
    _quantityController = TextEditingController(text: '$quantity');
    _loadReviews();
    _loadSellerProfile();
    _loadVariants();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  static String _reviewKey(dynamic id) => 'reviews_$id';

  Future<void> _loadReviews() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reviewKey(widget.product.id));
    if (raw == null || !mounted) return;
    var list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();

    // Migrate stored email-prefix authors to full display names
    final email = await AuthService.getUserEmail();
    final displayName = await AuthService.getUserDisplayName();
    if (email != null && displayName != null && displayName.isNotEmpty) {
      final emailPrefix = email.split('@').first;
      bool changed = false;
      list = list.map((r) {
        if (r['author'] == emailPrefix) {
          changed = true;
          return {...r, 'author': displayName};
        }
        return r;
      }).toList();
      if (changed) {
        await prefs.setString(_reviewKey(widget.product.id), jsonEncode(list));
      }
    }

    if (!mounted) return;
    setState(() => _reviews = list);
  }

  Future<void> _messageSeller() async {
    final messenger = ScaffoldMessenger.of(context);
    final buyerEmail = await AuthService.getUserEmail();
    if (buyerEmail == null || !mounted) return;
    final sellerEmail =
        await ProductService.getSellerEmailById(widget.product.sellerId);
    if (sellerEmail == null) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Unable to reach seller at this time.'),
        backgroundColor: Color(0xFF0A0A0A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        margin: EdgeInsets.all(16),
      ));
      return;
    }
    if (!mounted) return;
    await openConversation(
      context,
      currentEmail: buyerEmail,
      currentRole: 'buyer',
      sellerEmail: sellerEmail,
      sellerId: widget.product.sellerId?.toString() ?? '',
      sellerName: widget.product.sellerName,
      productRef: widget.product,
    );
  }

  Future<void> _loadSellerProfile() async {
    if (widget.product.sellerId == null) return;
    final profile =
        await ProductService.getSellerProfile(widget.product.sellerId);
    if (profile != null) {
      debugPrint('🏪 seller profile keys: ${profile.keys.toList()}');
      debugPrint('🏪 seller profile: $profile');
    }
    if (mounted && profile != null) {
      setState(() => _sellerProfile = profile);
    }
  }

  Future<void> _loadVariants() async {
    final variants =
        await SellerProductService.getVariants(widget.product.id);
    if (mounted) setState(() => _variants = variants);
  }

  void _setDetailQty(int value) {
    final maxQty = widget.product.stock > 0 ? widget.product.stock : 1;
    final v = value.clamp(1, maxQty);
    setState(() => quantity = v);
    _quantityController
      ..text = '$v'
      ..selection = TextSelection.fromPosition(TextPosition(offset: '$v'.length));
  }

  void _promptLogin() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Sign in required',
            style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF0A0A0A))),
        content: Text(
            'You need to be logged in to add items to your cart.',
            style: GoogleFonts.inter(
                fontSize: 13, color: const Color(0xFF666666), height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFF888888))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushNamed('/login');
            },
            child: Text('Sign In',
                style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0A0A0A))),
          ),
        ],
      ),
    );
  }

  Future<void> _addToCart() async {
    final email = await AuthService.getUserEmail();
    if (!mounted) return;
    if (email == null) {
      _promptLogin();
      return;
    }
    VariantPickerSheet.show(
      context,
      product: widget.product,
      variants: _variants,
      initialSize: _selectedSize,
      initialColor: _selectedColor,
      initialQuantity: quantity,
      onAddToCart: (size, color, qty) {
        setState(() {
          _selectedSize = size;
          _selectedColor = color;
          quantity = qty;
        });
        for (int i = 0; i < qty; i++) {
          cartService.addToCart(widget.product,
              selectedSize: size, selectedColor: color);
        }
        final parts = [if (size != null) size, if (color != null) color];
        final suffix = parts.isNotEmpty ? ' (${parts.join(' · ')})' : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check, color: Colors.white, size: 14),
            const SizedBox(width: 10),
            Flexible(
              child: Text('${widget.product.name}$suffix added to cart',
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w400)),
            ),
          ]),
          backgroundColor: const Color(0xFF0A0A0A),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          margin: const EdgeInsets.all(16),
        ));
      },
    );
  }

  Future<void> _buyNow() async {
    final email = await AuthService.getUserEmail();
    if (!mounted) return;
    if (email == null) {
      _promptLogin();
      return;
    }
    VariantPickerSheet.show(
      context,
      product: widget.product,
      variants: _variants,
      initialSize: _selectedSize,
      initialColor: _selectedColor,
      initialQuantity: quantity,
      onAddToCart: (size, color, qty) {
        setState(() {
          _selectedSize = size;
          _selectedColor = color;
          quantity = qty;
        });
        for (int i = 0; i < qty; i++) {
          cartService.addToCart(widget.product,
              selectedSize: size, selectedColor: color);
        }
        final variantKey = CartItem(
                product: widget.product,
                selectedSize: size,
                selectedColor: color)
            .variantKey;
        final cartItem = cartService
            .getCartItems()
            .firstWhere((i) => i.variantKey == variantKey);
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CheckoutScreen(selectedItems: [cartItem])));
      },
      onBuyNow: (size, color, qty) {
        setState(() {
          _selectedSize = size;
          _selectedColor = color;
          quantity = qty;
        });
        for (int i = 0; i < qty; i++) {
          cartService.addToCart(widget.product,
              selectedSize: size, selectedColor: color);
        }
        final variantKey = CartItem(
                product: widget.product,
                selectedSize: size,
                selectedColor: color)
            .variantKey;
        final cartItem = cartService
            .getCartItems()
            .firstWhere((i) => i.variantKey == variantKey);
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => CheckoutScreen(selectedItems: [cartItem])));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Color(0xFF0A0A0A), size: 16),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'VARÓN',
          style: GoogleFonts.commissioner(
            color: const Color(0xFF0A0A0A),
            fontSize: 16,
            fontWeight: FontWeight.w300,
            letterSpacing: 6,
          ),
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFEEEEEE), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Product image ───────────────────────────────────────────────
            _ProductImageGallery(
              imageUrl: widget.product.imageUrl,
              isMobile: isMobile,
            ),

            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 20 : 48,
                vertical: isMobile ? 28 : 40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category label
                  Text(
                    widget.product.category.toUpperCase(),
                    style: GoogleFonts.commissioner(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF999999),
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Product name — Playfair Display
                  Text(
                    widget.product.name,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: isMobile ? 24 : 32,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF0A0A0A),
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Star rating placeholder
                  Row(
                    children: [
                      ...List.generate(5, (i) => Icon(
                        i < 4 ? Icons.star : Icons.star_half,
                        size: 14,
                        color: const Color(0xFF0A0A0A),
                      )),
                      const SizedBox(width: 8),
                      Text(
                        '4.5 (24 reviews)',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFF888888),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Price
                  Text(
                    '₱${widget.product.price.toStringAsFixed(0)}',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 22 : 26,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0A0A0A),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Stock indicator
                  _buildStockBadge(widget.product.stock),

                  const SizedBox(height: 24),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),
                  const SizedBox(height: 24),

                  // Description
                  Text(
                    widget.product.description,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF555555),
                      height: 1.75,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Color selection (from DB variants) ───────────────────
                  if (_colorOptions.isNotEmpty) ...[
                    _SectionLabel(label: 'COLOR', trailing: _selectedColor),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: _colorOptions.map((opt) {
                        final hex = _hexFor(opt.label);
                        final selected = _selectedColor == opt.label;
                        return GestureDetector(
                          onTap: opt.outOfStock
                              ? null
                              : () => setState(() => _selectedColor = opt.label),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(hex),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: opt.outOfStock
                                    ? const Color(0xFFEEEEEE)
                                    : selected
                                        ? const Color(0xFF0A0A0A)
                                        : const Color(0xFFDDDDDD),
                                width: selected ? 2.5 : 1,
                              ),
                              boxShadow: selected && !opt.outOfStock
                                  ? [BoxShadow(
                                      color: const Color(0xFF0A0A0A).withValues(alpha: 0.15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )]
                                  : null,
                            ),
                            child: opt.outOfStock
                                ? const Icon(Icons.close, size: 12, color: Color(0xFFCCCCCC))
                                : selected
                                    ? Icon(Icons.check, size: 14,
                                        color: hex == 0xFFF5F5F5 || hex == 0xFFFFFDD0 || hex == 0xFFF5F0E8
                                            ? const Color(0xFF0A0A0A)
                                            : Colors.white)
                                    : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),
                  ],

                  // ── Size selection (from DB variants) ────────────────────
                  if (_sizeOptions.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SectionLabel(label: 'SIZE', trailing: _selectedSize),
                        GestureDetector(
                          onTap: () => _showSizeGuide(context),
                          child: Text(
                            'SIZE GUIDE',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color: const Color(0xFF888888),
                              letterSpacing: 1.5,
                              decoration: TextDecoration.underline,
                              decorationColor: const Color(0xFF888888),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _sizeOptions.map((opt) {
                        final selected = _selectedSize == opt.label;
                        return GestureDetector(
                          onTap: opt.outOfStock
                              ? null
                              : () => setState(() => _selectedSize = opt.label),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: selected ? const Color(0xFF0A0A0A) : Colors.white,
                              border: Border.all(
                                color: opt.outOfStock
                                    ? const Color(0xFFEEEEEE)
                                    : selected
                                        ? const Color(0xFF0A0A0A)
                                        : const Color(0xFFDDDDDD),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                opt.label,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: opt.outOfStock
                                      ? const Color(0xFFCCCCCC)
                                      : selected
                                          ? Colors.white
                                          : const Color(0xFF0A0A0A),
                                  letterSpacing: 0.5,
                                  decoration: opt.outOfStock ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 28),
                  ],

                  // ── Quantity ──────────────────────────────────────────────
                  const _SectionLabel(label: 'QUANTITY'),
                  const SizedBox(height: 14),
                  Container(
                    width: 140,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: const Color(0xFFDDDDDD), width: 1),
                    ),
                    child: Row(
                      children: [
                        _qtyButton(
                          Icons.remove,
                          quantity > 1 ? () => _setDetailQty(quantity - 1) : null,
                        ),
                        Expanded(
                          child: Center(
                            child: TextField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF0A0A0A),
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onChanged: (v) {
                                final n = int.tryParse(v);
                                if (n != null) {
                                  final maxQty = widget.product.stock > 0 ? widget.product.stock : 1;
                                  setState(() => quantity = n.clamp(1, maxQty));
                                }
                              },
                              onSubmitted: (v) => _setDetailQty(int.tryParse(v) ?? quantity),
                              onTapOutside: (_) => _setDetailQty(int.tryParse(_quantityController.text) ?? quantity),
                            ),
                          ),
                        ),
                        _qtyButton(
                          Icons.add,
                          (widget.product.stock == 0 || quantity >= widget.product.stock)
                              ? null
                              : () => _setDetailQty(quantity + 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Action buttons ────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: widget.product.stock > 0 ? _addToCart : null,
                          style: OutlinedButton.styleFrom(
                            disabledForegroundColor: const Color(0xFFAAAAAA),
                            side: BorderSide(
                              color: widget.product.stock > 0
                                  ? const Color(0xFF0A0A0A)
                                  : const Color(0xFFDDDDDD),
                              width: 1,
                            ),
                            padding: EdgeInsets.symmetric(
                                vertical: isMobile ? 15 : 17),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          child: Text(
                            'ADD TO CART',
                            style: GoogleFonts.commissioner(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: widget.product.stock > 0
                                  ? const Color(0xFF0A0A0A)
                                  : const Color(0xFFAAAAAA),
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: widget.product.stock > 0 ? _buyNow : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A0A0A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            disabledBackgroundColor: const Color(0xFFCCCCCC),
                            padding: EdgeInsets.symmetric(
                                vertical: isMobile ? 15 : 17),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          child: Text(
                            'BUY NOW',
                            style: GoogleFonts.commissioner(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Seller card ────────────────────────────────────────────
                  const SizedBox(height: 28),
                  _SellerSection(
                    sellerId: widget.product.sellerId,
                    sellerName: (_sellerProfile?['store_name'] as String?)
                        ?? widget.product.sellerName,
                    sellerLogoUrl: (_sellerProfile?['logo_url'] as String?)
                        ?? (_sellerProfile?['avatar_url'] as String?)
                        ?? widget.product.sellerLogoUrl,
                    onMessage: _messageSeller,
                  ),
                  const SizedBox(height: 40),

                  // ── Product details accordion ──────────────────────────────
                  Container(height: 1, color: const Color(0xFFEEEEEE)),
                  const _DetailRow(label: 'MATERIAL', value: '100% Premium Cotton'),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),
                  const _DetailRow(label: 'CARE',     value: 'Machine wash cold, tumble dry low'),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),
                  const _DetailRow(label: 'FIT',      value: 'Regular fit — model wears size M'),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),
                  const SizedBox(height: 40),

                  // ── Reviews section ────────────────────────────────────────
                  Text(
                    'CUSTOMER REVIEWS',
                    style: GoogleFonts.commissioner(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF0A0A0A),
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(width: 28, height: 1, color: const Color(0xFF0A0A0A)),
                  const SizedBox(height: 24),

                  // Rating summary
                  if (_reviews.isNotEmpty) _RatingSummary(reviews: _reviews),

                  // User-submitted reviews (newest first)
                  ..._reviews.map(
                    (r) => _ReviewCard(
                      author: r['author'] as String? ?? 'Customer',
                      rating: r['rating'] as int? ?? 5,
                      text: r['text'] as String? ?? '',
                      verified: true,
                    ),
                  ),

                  if (_reviews.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 64,
                              color: Color(0xFFDDDDDD),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No reviews yet',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 18,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF0A0A0A),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Be the first to review this product!',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF999999),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSizeGuide(BuildContext context) {
    VariantPickerSheet.showSizeGuideModal(context, widget.product.category);
  }

  Widget _buildStockBadge(int stock) {
    if (stock == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        color: const Color(0xFFFFF0F0),
        child: Text(
          'OUT OF STOCK',
          style: GoogleFonts.commissioner(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFCC0000),
            letterSpacing: 2,
          ),
        ),
      );
    }
    if (stock <= 5) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFD97706)),
          const SizedBox(width: 5),
          Text(
            'Only $stock left in stock',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFD97706),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF22C55E),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$stock in stock',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: const Color(0xFF555555),
          ),
        ),
      ],
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(
          icon,
          size: 14,
          color: onTap != null
              ? const Color(0xFF0A0A0A)
              : const Color(0xFFCCCCCC),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final String? trailing;

  const _SectionLabel({required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.commissioner(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF888888),
            letterSpacing: 2,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(
            '— $trailing',
            style: GoogleFonts.inter(
              fontSize: 9,
              color: const Color(0xFF0A0A0A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatefulWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  State<_DetailRow> createState() => _DetailRowState();
}

class _DetailRowState extends State<_DetailRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.label,
                  style: GoogleFonts.commissioner(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: const Color(0xFF0A0A0A),
                  ),
                ),
                Icon(
                  _expanded ? Icons.remove : Icons.add,
                  size: 14,
                  color: const Color(0xFF0A0A0A),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              Text(
                widget.value,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF555555),
                  height: 1.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rating summary — average score + star breakdown
// ─────────────────────────────────────────────────────────────────────────────

class _RatingSummary extends StatelessWidget {
  final List<Map<String, dynamic>> reviews;
  const _RatingSummary({required this.reviews});

  @override
  Widget build(BuildContext context) {
    final count = reviews.length;
    final avg = reviews.fold<double>(
          0,
          (sum, r) => sum + ((r['rating'] as num?)?.toDouble() ?? 0),
        ) /
        count;

    // Count per star level (5 down to 1)
    final counts = List.generate(5, (i) {
      final star = 5 - i;
      return reviews.where((r) => (r['rating'] as int? ?? 0) == star).length;
    });

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(18),
      color: const Color(0xFFF7F6F4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: big number + stars + count
          Column(
            children: [
              Text(
                avg.toStringAsFixed(1),
                style: GoogleFonts.playfairDisplay(
                  fontSize: 44,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF0A0A0A),
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: List.generate(5, (i) {
                  if (avg >= i + 1) {
                    return const Icon(Icons.star, size: 13, color: Color(0xFF0A0A0A));
                  } else if (avg > i) {
                    return const Icon(Icons.star_half, size: 13, color: Color(0xFF0A0A0A));
                  }
                  return const Icon(Icons.star_border, size: 13, color: Color(0xFF0A0A0A));
                }),
              ),
              const SizedBox(height: 4),
              Text(
                '$count ${count == 1 ? 'review' : 'reviews'}',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: const Color(0xFF888888),
                ),
              ),
            ],
          ),
          const SizedBox(width: 20),
          // Right: bar breakdown
          Expanded(
            child: Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                final barFill = count > 0 ? counts[i] / count : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        '$star',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: const Color(0xFF555555),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.star, size: 9, color: Color(0xFF0A0A0A)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: barFill,
                            minHeight: 5,
                            backgroundColor: const Color(0xFFE0E0E0),
                            valueColor: const AlwaysStoppedAnimation(Color(0xFF0A0A0A)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 16,
                        child: Text(
                          '${counts[i]}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: const Color(0xFF888888),
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String author;
  final int rating;
  final String text;
  final bool verified;

  const _ReviewCard({
    required this.author,
    required this.rating,
    required this.text,
    this.verified = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ...List.generate(
                5,
                (i) => Icon(
                  i < rating ? Icons.star : Icons.star_border,
                  size: 13,
                  color: const Color(0xFF0A0A0A),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                author,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0A0A0A),
                ),
              ),
              if (verified) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: const Color(0xFFF0F0F0),
                  child: const Text(
                    'VERIFIED',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: Color(0xFF555555),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF555555),
              height: 1.65,
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFF0F0F0)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seller section — shown below reviews
// ─────────────────────────────────────────────────────────────────────────────

class _SellerSection extends StatelessWidget {
  final dynamic sellerId;
  final String sellerName;
  final String sellerLogoUrl;
  final VoidCallback? onMessage;

  const _SellerSection({
    required this.sellerId,
    required this.sellerName,
    required this.sellerLogoUrl,
    this.onMessage,
  });

  void _goToStore(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SellerStoreScreen(
        sellerId: sellerId,
        sellerName: sellerName,
        sellerLogoUrl: sellerLogoUrl,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (sellerId == null && sellerName.isEmpty) return const SizedBox.shrink();
    final initials = sellerName.trim().isNotEmpty
        ? sellerName.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : 'S';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ABOUT THE SELLER',
          style: GoogleFonts.commissioner(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0A0A0A),
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 14),
        Container(width: 28, height: 1, color: const Color(0xFF0A0A0A)),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => _goToStore(context),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F6F4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0A0A0A),
                    shape: BoxShape.circle,
                  ),
                  child: sellerLogoUrl.isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            sellerLogoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(initials,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(initials,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOLD BY',
                        style: GoogleFonts.commissioner(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: const Color(0xFF999999),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        sellerName,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0A0A0A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () => _goToStore(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              foregroundColor: const Color(0xFF0A0A0A),
                              side: const BorderSide(
                                  color: Color(0xFF0A0A0A), width: 1),
                              shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.zero),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'VISIT SHOP',
                              style: GoogleFonts.commissioner(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),
                          ),
                          if (onMessage != null)
                            OutlinedButton.icon(
                              onPressed: onMessage,
                              icon: const Icon(Icons.chat_bubble_outline,
                                  size: 11),
                              label: Text(
                                'MESSAGE',
                                style: GoogleFonts.commissioner(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                foregroundColor: const Color(0xFF0A0A0A),
                                side: const BorderSide(
                                    color: Color(0xFF0A0A0A), width: 1),
                                shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.zero),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 12, color: Color(0xFF0A0A0A)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image gallery with thumbnail strip
// ─────────────────────────────────────────────────────────────────────────────

class _ProductImageGallery extends StatefulWidget {
  final String imageUrl;
  final bool isMobile;

  const _ProductImageGallery({
    required this.imageUrl,
    required this.isMobile,
  });

  @override
  State<_ProductImageGallery> createState() => _ProductImageGalleryState();
}

class _ProductImageGalleryState extends State<_ProductImageGallery> {
  int _activeIndex = 0;

  void _openViewer(BuildContext context, List<String> images, int startIndex) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _FullScreenViewer(
        images: images,
        initialIndex: startIndex,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Simulate multiple angles from the same image
    final images = List.generate(4, (_) => widget.imageUrl);
    final mainH  = widget.isMobile ? 340.0 : 500.0;
    final thumbH = widget.isMobile ? 56.0  : 72.0;

    return Column(
      children: [
        // Main image — tap to open full-screen viewer
        Stack(
          children: [
            GestureDetector(
              onTap: () => _openViewer(context, images, _activeIndex),
              child: SizedBox(
                width: double.infinity,
                height: mainH,
                child: Hero(
                  tag: 'product_image_$_activeIndex',
                  child: _NetImage(url: images[_activeIndex], fit: BoxFit.cover),
                ),
              ),
            ),
            // Subtle gradient overlay at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 80,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0),
                      Colors.white.withValues(alpha: 0.4),
                    ],
                  ),
                ),
              ),
            ),
            // Image counter
            Positioned(
              right: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                color: Colors.white.withValues(alpha: 0.85),
                child: Text(
                  '${_activeIndex + 1} / ${images.length}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: const Color(0xFF0A0A0A),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),

        // Thumbnail strip
        Container(
          color: const Color(0xFFF6F6F6),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: List.generate(images.length, (i) {
              final active = _activeIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _activeIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: thumbH,
                  height: thumbH,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: active
                          ? const Color(0xFF0A0A0A)
                          : const Color(0xFFDDDDDD),
                      width: active ? 2 : 1,
                    ),
                  ),
                  child: _NetImage(url: images[i], fit: BoxFit.cover),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;

  const _NetImage({required this.url, required this.fit});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const Center(
        child: Icon(Icons.image_outlined, size: 40, color: Color(0xFFCCCCCC)),
      );
    }
    return Image.network(
      url,
      fit: fit,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: Color(0xFF0A0A0A),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.image_outlined, size: 40, color: Color(0xFFCCCCCC)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen image viewer with pinch-to-zoom and swipe between images
// ─────────────────────────────────────────────────────────────────────────────

class _FullScreenViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;

  const _FullScreenViewer({required this.images, required this.initialIndex});

  @override
  State<_FullScreenViewer> createState() => _FullScreenViewerState();
}

class _FullScreenViewerState extends State<_FullScreenViewer> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Swipeable pages with pinch-zoom
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              return InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(
                  child: Hero(
                    tag: 'product_image_$i',
                    child: Image.network(
                      widget.images[i],
                      fit: BoxFit.contain,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white54,
                            strokeWidth: 1.5,
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: Colors.white24,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // Top bar: counter + close
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_current + 1} / ${widget.images.length}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

