import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/product_service.dart';
import '../widgets/size_guide_widget.dart';
import '../widgets/variant_picker_sheet.dart';
import 'product_detail_screen.dart';
import 'seller_store_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _productsKey = GlobalKey();
  final GlobalKey _aboutKey = GlobalKey();

  late final CartService _cartService;
  StreamSubscription<AuthState>? _authSub;

  List<Product> _allProducts = [];
  List<String> _categories = ['All'];
  String _selectedCategory = 'All';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cartService = CartService();
    _loadProducts();

    // Reload products on initial session (covers guest + logged-in app start),
    // sign-in, and sign-out so the product list always reflects the current
    // auth state without waiting for products to be empty.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      if (state.event == AuthChangeEvent.initialSession ||
          state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.signedOut) {
        _loadProducts();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await ProductService.getAllProducts();
      if (!mounted) return;
      final catSet = <String>{};
      for (final p in products) {
        if (p.category.isNotEmpty && p.category != 'Uncategorized') {
          catSet.add(p.category);
        }
      }
      setState(() {
        _allProducts = products;
        _categories = ['All', ...catSet.toList()..sort()];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load products. Please try again.';
      });
    }
  }

  List<Product> get _filtered {
    if (_selectedCategory == 'All') return _allProducts;
    return _allProducts.where((p) => p.category == _selectedCategory).toList();
  }

  void _scrollTo(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final target = (_scrollController.offset + box.localToGlobal(Offset.zero).dy)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(target,
        duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
  }

  Future<void> _handleAddToCart(Product p) async {
    final email = await AuthService.getUserEmail();
    if (!mounted) return;
    if (email == null) {
      _promptLogin();
      return;
    }
    VariantPickerSheet.show(
      context,
      product: p,
      onAddToCart: (size, color, qty) {
        for (int i = 0; i < qty; i++) {
          _cartService.addToCart(p, selectedSize: size, selectedColor: color);
        }
        setState(() {});
        final parts = [if (size != null) size, if (color != null) color];
        final suffix = parts.isNotEmpty ? ' (${parts.join(' · ')})' : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check, color: Colors.white, size: 14),
            const SizedBox(width: 10),
            Flexible(
              child: Text('${p.name}$suffix added to cart',
                  style: GoogleFonts.inter(fontSize: 12)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        onRefresh: _loadProducts,
        color: const Color(0xFF0A0A0A),
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              _header(),
              _hero(),
              _productsSection(),
              _aboutSection(),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Varón',
              style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0A0A0A))),
          Row(
            children: [
              TextButton(
                onPressed: () => _scrollTo(_productsKey),
                child: Text('Browse',
                    style: GoogleFonts.inter(
                        fontSize: 14, color: const Color(0xFF0A0A0A))),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _scrollTo(_aboutKey),
                child: Text('About',
                    style: GoogleFonts.inter(
                        fontSize: 14, color: const Color(0xFF0A0A0A))),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/login'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF0A0A0A),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('Login',
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Hero ──────────────────────────────────────────────────────────────────

  Widget _hero() {
    return Container(
      color: const Color(0xFF1A1A1A),
      padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: MediaQuery.of(context).size.height * 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VARÓN / MANILA',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2,
                  color: const Color(0xFFAAAAAA))),
          const SizedBox(height: 24),
          Text('Menswear\nredefined for the\nmodern gentleman.',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2)),
          const SizedBox(height: 24),
          Text(
              'Discover contemporary silhouettes, elevated fabrics, and purposeful essentials designed for discerning Filipino men.',
              style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFFCCCCCC),
                  height: 1.6)),
          const SizedBox(height: 32),
          Row(
            children: [
              _heroBtn('Shop Now', filled: true,
                  onTap: () => _scrollTo(_productsKey)),
              const SizedBox(width: 16),
              _heroBtn('Our Story', filled: false,
                  onTap: () => _scrollTo(_aboutKey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroBtn(String label,
      {required bool filled, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.transparent,
          border: filled ? null : Border.all(color: Colors.white),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(label,
            style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: filled
                    ? const Color(0xFF0A0A0A)
                    : Colors.white)),
      ),
    );
  }

  // ── Products Section ──────────────────────────────────────────────────────

  Widget _productsSection() {
    return Container(
      key: _productsKey,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Shop by Category',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0A0A0A))),
          const SizedBox(height: 6),
          Text('Browse our curated collection of premium menswear.',
              style: GoogleFonts.inter(
                  fontSize: 13, color: const Color(0xFF666666))),
          const SizedBox(height: 20),

          // Category tabs (only when loaded)
          if (!_loading && _error == null && _categories.length > 1)
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final active = cat == _selectedCategory;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF0A0A0A)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(cat,
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: active
                                  ? Colors.white
                                  : const Color(0xFF444444))),
                    ),
                  );
                },
              ),
            ),

          const SizedBox(height: 20),

          // States
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: CircularProgressIndicator(
                    strokeWidth: 1.5, color: Color(0xFF0A0A0A)),
              ),
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Column(
                  children: [
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            color: const Color(0xFF888888))),
                    const SizedBox(height: 16),
                    OutlinedButton(
                      onPressed: _loadProducts,
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: Color(0xFF0A0A0A)),
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero)),
                      child: Text('Retry',
                          style: GoogleFonts.inter(
                              fontSize: 13,
                              color: const Color(0xFF0A0A0A))),
                    ),
                  ],
                ),
              ),
            )
          else if (_filtered.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Text(
                    _allProducts.isEmpty
                        ? 'No products available yet.'
                        : 'No products in this category.',
                    style: GoogleFonts.inter(
                        fontSize: 14,
                        color: const Color(0xFF888888))),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 12,
                childAspectRatio: 0.58,
              ),
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final p = _filtered[i];
                return _LandingProductCard(
                  product: p,
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ProductDetailScreen(product: p))),
                  onAddToCart: () => _handleAddToCart(p),
                  onSellerTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => SellerStoreScreen(
                                sellerId: p.sellerId,
                                sellerName: p.sellerName,
                                sellerLogoUrl: p.sellerLogoUrl,
                              ))),
                );
              },
            ),
        ],
      ),
    );
  }

  // ── About ─────────────────────────────────────────────────────────────────

  Widget _aboutSection() {
    return Container(
      key: _aboutKey,
      color: const Color(0xFFFAFAFA),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ABOUT VARÓN',
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 2,
                  color: const Color(0xFFAAAAAA))),
          const SizedBox(height: 16),
          Text('Crafted in Manila,\ninspired by the world.',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0A0A0A),
                  height: 1.2)),
          const SizedBox(height: 20),
          Text(
              'Varón began in 2025 with a simple idea: elevate everyday wardrobes without losing the warmth of Filipino craftsmanship. Today, we curate limited capsules with independent ateliers, regional sellers, and textile partners who share our obsession for detail.',
              style: GoogleFonts.inter(
                  fontSize: 14,
                  color: const Color(0xFF555555),
                  height: 1.8)),
          const SizedBox(height: 28),
          _aboutFeature('Responsible Materials',
              'Organic cotton, linen, and recycled blends sourced from certified mills across Luzon and Visayas.'),
          const SizedBox(height: 20),
          _aboutFeature('Community First',
              '48+ local partner ateliers and riders ensure every order fuels homegrown livelihoods.'),
          const SizedBox(height: 20),
          _aboutFeature('Seamless Experience',
              'Same-day Metro deliveries, curated styling notes, and transparent updates in every package.'),
        ],
      ),
    );
  }

  Widget _aboutFeature(String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
              color: Color(0xFF0A0A0A), shape: BoxShape.circle),
          child: Center(
              child: Text('✓',
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0A0A0A))),
              const SizedBox(height: 4),
              Text(body,
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF666666),
                      height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _footer() {
    return Container(
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Varón',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Text('Minimal, responsibly-made apparel.',
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFFAAAAAA),
                  height: 1.5)),
          const SizedBox(height: 32),
          const Divider(color: Color(0xFF333333)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Varón — Minimal Apparel',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: const Color(0xFF666666))),
              Text('© 2025',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: const Color(0xFF666666))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Product Card ──────────────────────────────────────────────────────────────

class _LandingProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final VoidCallback onSellerTap;

  const _LandingProductCard({
    required this.product,
    required this.onTap,
    required this.onAddToCart,
    required this.onSellerTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product image
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFFF5F5F5),
              child: product.imageUrl.isNotEmpty
                  ? Image.network(
                      product.imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFFCCCCCC)),
                        );
                      },
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(Icons.image_not_supported_outlined,
                            size: 32, color: Color(0xFFCCCCCC)),
                      ),
                    )
                  : const Center(
                      child: Icon(Icons.image_outlined,
                          size: 32, color: Color(0xFFCCCCCC)),
                    ),
            ),
          ),
          const SizedBox(height: 8),

          // Name
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF0A0A0A),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 3),

          // Seller name
          if (product.sellerName.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onSellerTap,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      size: 10,
                      color: Color(0xFF888888),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        product.sellerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: const Color(0xFF888888),
                          decoration: TextDecoration.underline,
                          decorationColor: const Color(0xFFCCCCCC),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Price
          Text(
            '₱${product.price.toStringAsFixed(0)}',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0A0A0A),
            ),
          ),

          // Size guide link — only shown for sized categories
          SizeGuideButton(category: product.category),

          // Add to cart
          SizedBox(
            width: double.infinity,
            height: 34,
            child: ElevatedButton(
              onPressed: product.stock > 0 ? onAddToCart : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A0A0A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE0E0E0),
                elevation: 0,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                product.stock > 0 ? 'Add to Cart' : 'Out of Stock',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: product.stock > 0
                      ? Colors.white
                      : const Color(0xFF999999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
