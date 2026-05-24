import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';
import '../services/rider_application_service.dart';
import '../services/seller_application_service.dart';
import '../widgets/variant_picker_sheet.dart';
import 'buyer_orders_screen.dart';
import 'product_detail_screen.dart';
import 'rider_application_form_screen.dart';
import 'rider/rider_dashboard_screen.dart';
import 'seller_application_form_screen.dart';
import 'shop_screen.dart';
import 'cart_screen.dart';
import 'seller/seller_dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _heroFade;
  late final Animation<Offset> _heroSlide;
  late final Animation<double> _sectionFade;

  final CartService _cartService = CartService();

  List<String> _categories = [];
  List<Product> _featuredProducts = [];
  Map<String, String> _catProductImages = {};

  String _catImage(String name) {
    final img = _catProductImages[name] ?? '';
    if (img.isNotEmpty) return img;
    // Fallback: use any available product image so no category shows blank
    return _catProductImages.values.firstWhere((v) => v.isNotEmpty, orElse: () => '');
  }

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _heroFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _heroSlide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
    ));
    _sectionFade = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );
    _ctrl.forward();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      ProductService.getCategories(),
      ProductService.getFeatured(),
      ProductService.getCategoryImages(),
    ]);
    if (!mounted) return;
    setState(() {
      _categories = results[0] as List<String>;
      _featuredProducts = results[1] as List<Product>;
      _catProductImages = results[2] as Map<String, String>;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await AuthService.logout();
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  void _shopNow() => Navigator.of(context).pushNamed('/shop');

  Future<void> _handleAddToCart(Product p) async {
    final email = await AuthService.getUserEmail();
    if (!mounted) return;
    if (email == null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('Sign in required',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600)),
          content: Text('You need to be logged in to add items to your cart.',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF666666), height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: GoogleFonts.inter(color: const Color(0xFF888888))),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushNamed('/login');
              },
              child: Text('Sign In',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF0A0A0A))),
            ),
          ],
        ),
      );
      return;
    }
    _showVariantPicker(p);
  }

  void _showVariantPicker(Product p) {
    VariantPickerSheet.show(
      context,
      product: p,
      onAddToCart: (size, color, qty) {
        for (int i = 0; i < qty; i++) {
          _cartService.addToCart(p, selectedSize: size, selectedColor: color);
        }
        final parts = [if (size != null) size, if (color != null) color];
        final suffix = parts.isNotEmpty ? ' (${parts.join(' · ')})' : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check, color: Colors.white, size: 14),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '${p.name}$suffix  ×$qty added to cart',
                  style: GoogleFonts.inter(
                      fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0A0A0A),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          margin: const EdgeInsets.all(16),
        ));
      },
    );
  }

  void _navigateToScreen(String label, BuildContext context) {
    switch (label.toLowerCase()) {
      case 'home':
        Navigator.of(context).pushReplacementNamed('/home');
        break;
      case 'shop':
        Navigator.of(context).pushNamed('/shop');
        break;
      case 'cart':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const CartScreen(),
        ));
        break;
      case 'profile':
        _showProfileSheet(context);
        break;
      default:
        // Treat any other label as a category name
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ShopScreen(category: label),
        ));
    }
  }

  void _showProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => _ProfileSheet(onLogout: _logout),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(context, isMobile),
              _buildHeroSection(context, isMobile),
              FadeTransition(
                opacity: _sectionFade,
                child: Column(
                  children: [
                    _buildCategoriesSection(context, isMobile),
                    _buildFeaturedProducts(context, isMobile),
                    _buildFooter(context, isMobile),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, bool isMobile) {
    final cartCount = _cartService.getCartCount();
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: 22,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'VARÓN',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w300,
              color: Color(0xFF0A0A0A),
              letterSpacing: 7,
            ),
          ),
          if (isMobile)
            Row(
              children: [
                // Cart icon with badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.shopping_cart_outlined,
                          color: Color(0xFF0A0A0A), size: 22),
                      onPressed: () => _navigateToScreen('cart', context),
                    ),
                    if (cartCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          width: 15,
                          height: 15,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0A0A0A),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '$cartCount',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => _showProfileSheet(context),
                  child: const Icon(Icons.account_circle_outlined,
                      color: Color(0xFF0A0A0A), size: 22),
                ),
              ],
            )
          else
            Row(
              children: [
                _navLink('HOME'),
                _navLink('SHOP'),
                _navLink('SHIRTS'),
                _navLink('PANTS'),
                _navLink('CART'),
                PopupMenuButton<String>(
                  onSelected: (result) {
                    if (result == 'logout') _logout();
                    if (result == 'profile') _showProfileSheet(context);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'profile', child: Text('Profile')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'logout', child: Text('Logout')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(Icons.account_circle_outlined,
                          color: Color(0xFF0A0A0A), size: 20),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _navLink(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: _HoverLink(
        label: label,
        onTap: () => _navigateToScreen(label, context),
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────────────

  Widget _buildHeroSection(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF6F6F6),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 48,
        vertical: isMobile ? 80 : 128,
      ),
      child: FadeTransition(
        opacity: _heroFade,
        child: SlideTransition(
          position: _heroSlide,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Elevate Your Style\nwith Varón',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontSize: isMobile ? 36 : 64,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF0A0A0A),
                  height: 1.15,
                  letterSpacing: -0.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'PREMIUM MINIMALIST FASHION',
                textAlign: TextAlign.center,
                style: GoogleFonts.commissioner(
                  fontSize: 10,
                  color: const Color(0xFF888888),
                  letterSpacing: 5,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 48),
              _HoverButton(
                label: 'SHOP NOW',
                onTap: _shopNow,
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _shopNow,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search,
                        size: 14, color: Color(0xFF888888)),
                    const SizedBox(width: 6),
                    Text(
                      'Search products',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF888888),
                        decoration: TextDecoration.underline,
                        decorationColor: const Color(0xFFCCCCCC),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.commissioner(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0A0A0A),
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 14),
        Container(width: 28, height: 1, color: const Color(0xFF0A0A0A)),
      ],
    );
  }

  // ── Categories ────────────────────────────────────────────────────────────

  Widget _buildCategoriesSection(BuildContext context, bool isMobile) {
    // Fall back to 4 static categories if DB hasn't loaded yet
    final cats = _categories.isNotEmpty
        ? _categories
        : ['Tops', 'Bottoms', 'Footwear', 'Accessories'];

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: isMobile ? 48 : 80,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('SHOP BY CATEGORY'),
          SizedBox(height: isMobile ? 28 : 40),
          LayoutBuilder(builder: (context, constraints) {
            final cols    = isMobile ? 2 : 4;
            final spacing = isMobile ? 10.0 : 16.0;
            final w       = (constraints.maxWidth - spacing * (cols - 1)) / cols;
            final h       = isMobile ? w * 1.25 : w * 1.15;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: w / h,
              ),
              itemCount: cats.length,
              itemBuilder: (_, i) => _CategoryCard(
                category: cats[i],
                imageUrl: _catImage(cats[i]),
                isMobile: isMobile,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ShopScreen(category: cats[i]),
                )),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Featured products ─────────────────────────────────────────────────────

  Widget _buildFeaturedProducts(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF6F6F6),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: isMobile ? 48 : 80,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('FEATURED PRODUCTS'),
          SizedBox(height: isMobile ? 28 : 40),
          LayoutBuilder(builder: (context, constraints) {
            final cols    = isMobile ? 2 : 4;
            final spacing = isMobile ? 10.0 : 16.0;
            final w       = (constraints.maxWidth - spacing * (cols - 1)) / cols;
            final h       = isMobile ? w * 1.75 : w * 1.55;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: w / h,
              ),
              itemCount: _featuredProducts.length,
              itemBuilder: (_, i) {
                final p = _featuredProducts[i];
                return _ProductCard(
                  name: p.name,
                  price: '₱${p.price.toStringAsFixed(0)}',
                  imageUrl: p.imageUrl,
                  isMobile: isMobile,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProductDetailScreen(product: p),
                  )),
                  onAddToCart: () => _handleAddToCart(p),
                );
              },
            );
          }),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context, bool isMobile) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0A0A0A),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 48,
        vertical: isMobile ? 48 : 72,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VARÓN',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      letterSpacing: 7,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'PREMIUM MINIMALIST FASHION',
                    style: TextStyle(
                      fontSize: 8,
                      color: Color(0xFF666666),
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ),
              if (!isMobile) _socialIcons(),
            ],
          ),
          const SizedBox(height: 48),
          if (isMobile) ...[
            Center(child: _socialIcons()),
            const SizedBox(height: 40),
          ],
          Container(height: 1, color: const Color(0xFF1E1E1E)),
          const SizedBox(height: 28),
          const Text(
            '© 2025 VARÓN. ALL RIGHTS RESERVED.',
            style: TextStyle(
              fontSize: 8,
              color: Color(0xFF555555),
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialIcons() {
    return const Row(
      children: [
        _FooterIcon(icon: Icons.facebook),
        _FooterIcon(icon: Icons.photo_camera_outlined),
        _FooterIcon(icon: Icons.share_outlined),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _HoverLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _HoverLink({required this.label, required this.onTap});

  @override
  State<_HoverLink> createState() => _HoverLinkState();
}

class _HoverLinkState extends State<_HoverLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: _hovered ? const Color(0xFF555555) : const Color(0xFF0A0A0A),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            fontFamily: 'Poppins',
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

class _HoverButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _HoverButton({required this.label, required this.onTap});

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 18),
          color: _hovered ? const Color(0xFF333333) : const Color(0xFF0A0A0A),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}


class _FooterIcon extends StatefulWidget {
  final IconData icon;
  const _FooterIcon({required this.icon});

  @override
  State<_FooterIcon> createState() => _FooterIconState();
}

class _FooterIconState extends State<_FooterIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              widget.icon,
              size: 17,
              color: _hovered ? Colors.white : const Color(0xFF666666),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category card with hover overlay
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final String category;
  final String imageUrl;
  final bool isMobile;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.imageUrl,
    required this.isMobile,
    required this.onTap,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final imgH = widget.isMobile ? 110.0 : 150.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: imgH,
                    child: widget.imageUrl.isNotEmpty
                        ? Image.network(
                            widget.imageUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                height: imgH,
                                color: const Color(0xFFF0F0F0),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1,
                                    color: Color(0xFF0A0A0A),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => _noImagePlaceholder(imgH),
                          )
                        : _noImagePlaceholder(imgH),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: imgH,
                    width: double.infinity,
                    color: _hovered
                        ? const Color(0xFF0A0A0A).withValues(alpha: 0.18)
                        : Colors.transparent,
                  ),
                ],
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.isMobile ? 10 : 14,
                  widget.isMobile ? 10 : 12,
                  widget.isMobile ? 10 : 14,
                  widget.isMobile ? 10 : 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.category.toUpperCase(),
                      style: TextStyle(
                        fontSize: widget.isMobile ? 9 : 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0A0A0A),
                        letterSpacing: 2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: widget.isMobile ? 2 : 3),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 150),
                      style: TextStyle(
                        fontSize: widget.isMobile ? 9 : 10,
                        color: _hovered
                            ? const Color(0xFF0A0A0A)
                            : const Color(0xFF999999),
                        letterSpacing: 0.3,
                      ),
                      child: const Text('Explore collection'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noImagePlaceholder(double height) {
    return Container(
      height: height,
      width: double.infinity,
      color: const Color(0xFF1A1A1A),
      child: Center(
        child: Text(
          widget.category.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product card with hover elevation
// ─────────────────────────────────────────────────────────────────────────────

class _ProductCard extends StatefulWidget {
  final String name;
  final String price;
  final String imageUrl;
  final bool isMobile;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const _ProductCard({
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.isMobile,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final imgH = widget.isMobile ? 130.0 : 180.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: Colors.white,
          transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  Image.network(
                    widget.imageUrl,
                    fit: BoxFit.cover,
                    height: imgH,
                    width: double.infinity,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return SizedBox(
                        height: imgH,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 1,
                            color: Color(0xFF0A0A0A),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => SizedBox(
                      height: imgH,
                      child: const Center(
                        child: Icon(Icons.image_outlined,
                            size: 32, color: Color(0xFFCCCCCC)),
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: imgH,
                    width: double.infinity,
                    color: _hovered
                        ? const Color(0xFF0A0A0A).withValues(alpha:0.06)
                        : Colors.transparent,
                  ),
                ],
              ),
              SizedBox(height: widget.isMobile ? 8 : 12),
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: widget.isMobile ? 2 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: widget.isMobile ? 28 : 34,
                      child: Text(
                        widget.name,
                        style: TextStyle(
                          fontSize: widget.isMobile ? 11 : 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF0A0A0A),
                          letterSpacing: 0.2,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: widget.isMobile ? 2 : 4),
                    Text(
                      widget.price,
                      style: TextStyle(
                        fontSize: widget.isMobile ? 12 : 13,
                        color: const Color(0xFF0A0A0A),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: widget.isMobile ? 8 : 12),
                    SizedBox(
                      width: double.infinity,
                      child: _AddToCartButton(
                        isMobile: widget.isMobile,
                        onTap: widget.onAddToCart,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddToCartButton extends StatefulWidget {
  final bool isMobile;
  final VoidCallback onTap;
  const _AddToCartButton({required this.isMobile, required this.onTap});

  @override
  State<_AddToCartButton> createState() => _AddToCartButtonState();
}

class _AddToCartButtonState extends State<_AddToCartButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
              vertical: widget.isMobile ? 8 : 10),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF0A0A0A) : Colors.white,
            border: Border.all(color: const Color(0xFF0A0A0A), width: 1),
          ),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: widget.isMobile ? 8 : 9,
                fontWeight: FontWeight.w700,
                color: _hovered ? Colors.white : const Color(0xFF0A0A0A),
                letterSpacing: 1.5,
              ),
              child: const Text('ADD TO CART'),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile bottom sheet (unchanged logic, minor polish)
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileSheet extends StatefulWidget {
  final VoidCallback onLogout;
  const _ProfileSheet({required this.onLogout});

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  String? _email;
  Map<String, int> _counts = {};
  String _role      = SellerApplicationService.roleUser;
  String _riderRole = RiderApplicationService.roleUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final email = await AuthService.getUserEmail();
    if (email == null || !mounted) return;
    final results = await Future.wait([
      OrderService.getByBuyer(email),
      SellerApplicationService.getRole(email),
      RiderApplicationService.getRole(email),
    ]);
    if (!mounted) return;
    final orders = results[0] as List;
    setState(() {
      _email      = email;
      _role       = results[1] as String;
      _riderRole  = results[2] as String;
      const toShipStatuses   = {Order.pending, Order.confirmed, Order.preparing};
      const toReceiveStatuses = {Order.readyForPickup, Order.shipped, Order.outForDelivery};
      _counts = {
        'purchased':  orders.length,
        'to_ship':    orders.where((o) => toShipStatuses.contains(o.status)).length,
        'to_receive': orders.where((o) => toReceiveStatuses.contains(o.status)).length,
      };
    });
  }

  Future<void> _openApplicationForm() async {
    Navigator.of(context).pop();
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SellerApplicationFormScreen()),
    );
    if (submitted == true && mounted) {
      setState(() => _role = SellerApplicationService.roleSeller);
    }
  }

  Future<void> _openRiderApplicationForm() async {
    Navigator.of(context).pop();
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RiderApplicationFormScreen()),
    );
    if (submitted == true && mounted) {
      setState(() => _riderRole = RiderApplicationService.roleRider);
    }
  }

  Widget _buildSellerSection() {
    if (_role == SellerApplicationService.roleSeller) {
      return _SheetAction(
        icon: Icons.storefront_outlined,
        label: 'SELLER DASHBOARD',
        dark: true,
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const SellerDashboardScreen(),
          ));
        },
      );
    }
    if (_role == SellerApplicationService.rolePending) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: const Color(0xFFFFF8E1),
        child: const Row(
          children: [
            Icon(Icons.hourglass_top_outlined, size: 16, color: Color(0xFFB8860B)),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('APPLICATION PENDING',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        letterSpacing: 2, color: Color(0xFFB8860B),
                      )),
                  SizedBox(height: 3),
                  Text('Your seller application is under review.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return _SheetAction(
      icon: Icons.storefront_outlined,
      label: 'APPLY AS SELLER',
      onTap: _openApplicationForm,
    );
  }

  Widget _buildRiderSection() {
    if (_riderRole == RiderApplicationService.roleRider) {
      return _SheetAction(
        icon: Icons.delivery_dining,
        label: 'RIDER DASHBOARD',
        dark: true,
        onTap: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const RiderDashboardScreen(),
          ));
        },
      );
    }
    return _SheetAction(
      icon: Icons.delivery_dining,
      label: 'APPLY AS RIDER',
      onTap: _openRiderApplicationForm,
    );
  }

  @override
  Widget build(BuildContext context) {
    final initials = (_email?.isNotEmpty == true)
        ? _email!.substring(0, 1).toUpperCase()
        : '?';

    final orderItems = <Map<String, dynamic>>[
      {'icon': Icons.shopping_bag_outlined,   'label': 'PURCHASED', 'count': '${_counts['purchased'] ?? 0}'},
      {'icon': Icons.local_shipping_outlined, 'label': 'TO SHIP',    'count': '${_counts['to_ship'] ?? 0}'},
      {'icon': Icons.move_to_inbox_outlined,  'label': 'TO RECEIVE', 'count': '${_counts['to_receive'] ?? 0}'},
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 14, bottom: 4),
            width: 32, height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('MY ACCOUNT',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 3, color: Color(0xFF0A0A0A),
                    )),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18, color: Color(0xFF888888)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFEEEEEE)),

          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  color: const Color(0xFF0A0A0A),
                  child: Center(
                    child: Text(initials,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w600, letterSpacing: 1,
                        )),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ACCOUNT',
                        style: TextStyle(
                          fontSize: 8, fontWeight: FontWeight.w600,
                          color: Color(0xFF999999), letterSpacing: 2,
                        )),
                    const SizedBox(height: 4),
                    Text(_email ?? '—',
                        style: const TextStyle(
                          fontSize: 13, color: Color(0xFF0A0A0A),
                        )),
                  ],
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFEEEEEE)),

          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ORDER STATUS',
                    style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      color: Color(0xFF0A0A0A), letterSpacing: 3,
                    )),
                const SizedBox(height: 10),
                Container(width: 24, height: 1, color: const Color(0xFF0A0A0A)),
                const SizedBox(height: 24),
                Row(
                  children: orderItems.map((item) => Expanded(
                    child: Column(
                      children: [
                        Text(item['count'] as String,
                            style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w300,
                              color: Color(0xFF0A0A0A),
                            )),
                        const SizedBox(height: 8),
                        Icon(item['icon'] as IconData, size: 20, color: const Color(0xFF0A0A0A)),
                        const SizedBox(height: 8),
                        Text(item['label'] as String,
                            style: const TextStyle(
                              fontSize: 7, fontWeight: FontWeight.w600,
                              color: Color(0xFF888888), letterSpacing: 1,
                            ),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFEEEEEE)),

          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: _SheetAction(
              icon: Icons.receipt_long_outlined,
              label: 'VIEW ALL ORDERS',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const BuyerOrdersScreen(),
                ));
              },
            ),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFEEEEEE)),

          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: _buildSellerSection(),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFEEEEEE)),

          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            child: _buildRiderSection(),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFEEEEEE)),

          Padding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
            child: SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onLogout();
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0A0A0A), width: 1),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                child: const Text('SIGN OUT',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 2.5, color: Color(0xFF0A0A0A),
                    )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool dark;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.label,
    this.dark = false,
    required this.onTap,
  });

  @override
  State<_SheetAction> createState() => _SheetActionState();
}

class _SheetActionState extends State<_SheetAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.dark
        ? (_hovered ? const Color(0xFF222222) : const Color(0xFF0A0A0A))
        : (_hovered ? const Color(0xFFEEEEEE) : const Color(0xFFF6F6F6));
    final fg = widget.dark ? Colors.white : const Color(0xFF0A0A0A);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: bg,
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: fg),
              const SizedBox(width: 12),
              Text(widget.label,
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 2, color: fg,
                  )),
              const Spacer(),
              Icon(Icons.arrow_forward_ios, size: 11,
                  color: widget.dark ? const Color(0xFF888888) : const Color(0xFFAAAAAA)),
            ],
          ),
        ),
      ),
    );
  }
}
