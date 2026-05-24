import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/product_service.dart';
import '../widgets/variant_picker_sheet.dart';
import 'product_detail_screen.dart';
import 'cart_screen.dart';
import 'seller_store_screen.dart';

class ShopScreen extends StatefulWidget {
  final String? category;
  const ShopScreen({super.key, this.category});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  late CartService cartService;
  String selectedCategory = 'All';
  String? _expandedCategory;
  String? _selectedSubcategory;

  List<Product> allProducts = [];
  List<String> availableCategories = [];
  bool isLoading = true;
  String? errorMessage;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _searchFocused = false;

  // ── Subcategory definitions (case-insensitive lookup via helpers below) ──────
  static const Map<String, List<String>> _subcategories = {
    'Tops': [
      'Barong',
      'Suits & Blazers',
      'Casual Shirts',
      'Polo Shirts',
      'Outerwear & Jackets',
      'Activewear & Fitness Tops',
    ],
    'Bottoms': [
      'Jeans & Denim',
      'Chinos & Trousers',
      'Shorts',
      'Joggers & Sweatpants',
      'Formal Pants',
    ],
    'Footwear': [
      'Sneakers',
      'Loafers & Dress Shoes',
      'Sandals & Slides',
      'Boots',
      'Athletic Shoes',
    ],
  };

  // Case-insensitive helpers so DB category names always match regardless of casing
  static List<String>? _getSubs(String category) {
    final key = _subcategories.keys.firstWhere(
      (k) => k.toLowerCase() == category.toLowerCase(),
      orElse: () => '',
    );
    return key.isEmpty ? null : _subcategories[key];
  }

  static bool _hasSubs(String category) => _getSubs(category) != null;

  // All subcategory names (flattened, lowercased) — used to strip them from the top-level chip row
  static final Set<String> _allSubNames = _subcategories.values
      .expand((list) => list)
      .map((s) => s.toLowerCase())
      .toSet();

  // Extra DB category names whose labels don't exactly match the dropdown entries
  // (singular/plural variants, abbreviated names, legacy names, etc.)
  static const Set<String> _hiddenDbCategories = {
    'pants',         // belongs under Bottoms
    'polo shirt',    // singular — matches "Polo Shirts" in Tops dropdown
    'shirt',
    'shirts',
    'shoes',
    'shoe',
    'jeans',
    'shorts',        // already in Bottoms but guard against direct DB match
    'sneaker',
    'sneakers',
    'boots',
    'sandals',
  };

  // Only parent-level categories — strips DB rows that are subcategories of Tops/Bottoms/Footwear
  // (by exact label match OR by the explicit hidden-names set above)
  List<String> get _topLevelCategories => availableCategories
      .where((c) =>
          !_allSubNames.contains(c.toLowerCase()) &&
          !_hiddenDbCategories.contains(c.toLowerCase()))
      .toList();


  // ── Init ────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    cartService = CartService();
    if (widget.category != null) selectedCategory = widget.category!;
    _loadProducts();
    _searchFocusNode.addListener(() {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final results = await Future.wait([
        ProductService.getAllProducts(),
        ProductService.getCategories(),
      ]);

      final products = results[0] as List<Product>;
      final categories = results[1] as List<String>;

      if (!mounted) return;
      setState(() {
        allProducts = products;
        errorMessage = null;
        availableCategories = categories;

        // Reset invalid initial category
        if (selectedCategory != 'All' &&
            !categories.any((c) => c.toLowerCase() == selectedCategory.toLowerCase())) {
          selectedCategory = 'All';
        }
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        allProducts = [];
        errorMessage = '❌ Failed to load products. Please check your connection.';
        isLoading = false;
      });
      debugPrint('❌ ShopScreen _loadProducts: $e');
    }
  }

  // ── Filtering ────────────────────────────────────────────────────────────────

  List<Product> get _filtered {
    List<Product> result;

    if (selectedCategory == 'All') {
      result = allProducts;
    } else if (_selectedSubcategory != null) {
      result = allProducts
          .where((p) => p.category.toLowerCase() == _selectedSubcategory!.toLowerCase())
          .toList();
    } else {
      final subs = _getSubs(selectedCategory);
      if (subs != null) {
        result = allProducts.where((p) {
          final cat = p.category.toLowerCase();
          return cat == selectedCategory.toLowerCase() ||
              subs.any((s) => s.toLowerCase() == cat);
        }).toList();
      } else {
        result = allProducts
            .where((p) => p.category.toLowerCase() == selectedCategory.toLowerCase())
            .toList();
      }
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.category.toLowerCase().contains(q))
          .toList();
    }

    return result;
  }

  String get _headerLabel {
    if (_selectedSubcategory != null) return _selectedSubcategory!;
    if (selectedCategory == 'All') return 'All Products';
    return selectedCategory;
  }

  // ── Category selection ───────────────────────────────────────────────────────

  void _selectCategory(String cat) {
    setState(() {
      if (_hasSubs(cat)) {
        _expandedCategory = _expandedCategory == cat ? null : cat;
        selectedCategory = cat;
        _selectedSubcategory = null;
      } else {
        selectedCategory = cat;
        _expandedCategory = null;
        _selectedSubcategory = null;
      }
    });
  }

  void _selectSubcategory(String sub) {
    setState(() {
      _selectedSubcategory = sub;
      _expandedCategory = null;
    });
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

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

  void _showVariantSheet(Product p) {
    VariantPickerSheet.show(
      context,
      product: p,
      onAddToCart: (size, color, qty) {
        for (int i = 0; i < qty; i++) {
          cartService.addToCart(p, selectedSize: size, selectedColor: color);
        }
        setState(() {});
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

  void _openDetail(Product p) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ProductDetailScreen(product: p)))
        .then((_) => setState(() {}));
  }

  void _openCart() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CartScreen()))
        .then((_) => setState(() {}));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final cartCount = cartService.getCartCount();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('VARÓN',
                style: GoogleFonts.commissioner(
                    color: const Color(0xFF0A0A0A),
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 6)),
            if (selectedCategory != 'All')
              Text(_headerLabel.toUpperCase(),
                  style: GoogleFonts.commissioner(
                      color: const Color(0xFF888888),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.5)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFEEEEEE), height: 1),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined,
                      color: Color(0xFF0A0A0A)),
                  onPressed: _openCart),
              if (cartCount > 0)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                        color: Color(0xFF0A0A0A), shape: BoxShape.circle),
                    child: Center(
                      child: Text('$cartCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (v) { if (v == 'logout') _logout(); },
            icon: const Icon(Icons.more_vert, color: Color(0xFF0A0A0A)),
            itemBuilder: (_) =>
                [const PopupMenuItem(value: 'logout', child: Text('Logout'))],
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                      color: Color(0xFF0A0A0A), strokeWidth: 1.5),
                  SizedBox(height: 16),
                  Text('Loading products…',
                      style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 40,
                    vertical: isMobile ? 16 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error / demo banner
                    if (errorMessage != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3CD),
                          border: Border.all(color: const Color(0xFFFFD580)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(errorMessage!,
                            style: const TextStyle(
                                color: Color(0xFF856404), fontSize: 12)),
                      ),

                    // ── Search bar + suggestions ──────────────────────────
                    _buildSearchBar(),
                    _buildSuggestions(),
                    SizedBox(height: isMobile ? 16 : 24),

                    // ── Category navigation ───────────────────────────────
                    _buildCategorySection(isMobile),

                    SizedBox(height: isMobile ? 20 : 32),

                    // Products header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_headerLabel.toUpperCase(),
                            style: GoogleFonts.commissioner(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF0A0A0A),
                                letterSpacing: 4)),
                        Text('${_filtered.length} items',
                            style: GoogleFonts.inter(
                                fontSize: 11, color: const Color(0xFF999999))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                        width: 28, height: 1, color: const Color(0xFF0A0A0A)),
                    SizedBox(height: isMobile ? 20 : 28),

                    _buildGrid(isMobile),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Search bar ───────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: _searchFocused ? Colors.white : const Color(0xFFF8F8F8),
        border: Border.all(
          color: _searchFocused ? const Color(0xFF0A0A0A) : const Color(0xFFE0E0E0),
          width: _searchFocused ? 1.5 : 1,
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF0A0A0A)),
        decoration: InputDecoration(
          hintText: 'Search products, categories…',
          hintStyle: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFAAAAAA)),
          prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF888888)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Color(0xFF888888)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
        ),
      ),
    );
  }

  // Flattened list of specific item types used as popular search hints
  static final List<String> _popularSearches = _subcategories.values
      .expand((list) => list)
      .toList();

  Widget _buildSuggestions() {
    if (!_searchFocused) return const SizedBox.shrink();

    // ── Empty query: show popular item-type searches ───────────────────────
    if (_searchQuery.isEmpty) {
      return _SuggestionPanel(children: [
        const _SuggestionHeader('POPULAR SEARCHES'),
        ..._popularSearches.take(8).map((term) => _SuggestionRow(
              icon: Icons.trending_up_rounded,
              text: term,
              onTap: () {
                _searchController.text = term;
                setState(() => _searchQuery = term);
                _searchFocusNode.unfocus();
              },
            )),
      ]);
    }

    // ── Has query: show matching product names from DB ─────────────────────
    final q = _searchQuery.toLowerCase();
    final matches = allProducts
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q))
        .take(7)
        .toList();

    if (matches.isEmpty) {
      return _SuggestionPanel(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            'No results for "$_searchQuery"',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF888888)),
          ),
        ),
      ]);
    }

    return _SuggestionPanel(children: [
      const _SuggestionHeader('SUGGESTIONS'),
      ...matches.map((p) => _SuggestionRow(
            icon: Icons.search,
            text: p.name,
            subtitle: p.category,
            onTap: () {
              _searchController.text = p.name;
              setState(() => _searchQuery = p.name);
              _searchFocusNode.unfocus();
            },
          )),
    ]);
  }

  // ── Category section ─────────────────────────────────────────────────────────

  Widget _buildCategorySection(bool isMobile) {
    final chips = ['All', ..._topLevelCategories];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SHOP BY CATEGORY',
            style: GoogleFonts.commissioner(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF888888),
                letterSpacing: 3)),
        const SizedBox(height: 12),
        if (isMobile)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: chips
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildChip(c),
                      ))
                  .toList(),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips.map(_buildChip).toList(),
          ),

        // Animated dropdown panel
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _expandedCategory != null
              ? _buildDropdown(_expandedCategory!, isMobile)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildChip(String cat) {
    final isSelected = selectedCategory == cat ||
        (_selectedSubcategory != null && _hasSubs(cat) && selectedCategory == cat);
    final isExpanded = _expandedCategory == cat;
    final hasSub = _hasSubs(cat);
    final subLabel = (isSelected && _selectedSubcategory != null) ? _selectedSubcategory : null;

    return _HoverChip(
      label: subLabel ?? cat,
      isSelected: isSelected,
      isExpanded: isExpanded,
      hasDropdown: hasSub,
      onTap: () => _selectCategory(cat),
    );
  }

  Widget _buildDropdown(String category, bool isMobile) {
    final subs = _getSubs(category) ?? [];

    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shop ${category.toUpperCase()}',
                    style: GoogleFonts.playfairDisplay(
                        fontSize: isMobile ? 16 : 19,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF0A0A0A))),
                const SizedBox(height: 4),
                Text('Choose a subcategory to refine your view',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: const Color(0xFF999999))),
                const SizedBox(height: 14),
                // View All button
                _HoverableViewAll(
                  label: 'VIEW ALL ${category.toUpperCase()}',
                  onTap: () => setState(() {
                    _selectedSubcategory = null;
                    _expandedCategory = null;
                  }),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
          // Subcategory rows
          ...subs.map((sub) => _SubRow(
                label: sub,
                isSelected: _selectedSubcategory == sub,
                onTap: () => _selectSubcategory(sub),
              )),
        ],
      ),
    );
  }

  // ── Product grid ─────────────────────────────────────────────────────────────

  Widget _buildGrid(bool isMobile) {
    final products = _filtered;
    if (products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: Column(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 36, color: Color(0xFFCCCCCC)),
              const SizedBox(height: 16),
              Text('No products in this category',
                  style: GoogleFonts.inter(
                      fontSize: 13, color: const Color(0xFF999999))),
              if (_selectedSubcategory != null) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedSubcategory = null;
                  }),
                  child: Text('View all ${selectedCategory}s',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF0A0A0A),
                          decoration: TextDecoration.underline)),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isMobile ? 2 : 4,
          crossAxisSpacing: isMobile ? 8 : 16,
          mainAxisSpacing: isMobile ? 12 : 24,
          mainAxisExtent: isMobile ? 295.0 : 358.0,
        ),
        itemCount: products.length,
        itemBuilder: (_, i) => _ProductCard(
          product: products[i],
          isMobile: isMobile,
          onTap: () => _openDetail(products[i]),
          onAddToCart: () => _showVariantSheet(products[i]),
          onSellerTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SellerStoreScreen(
              sellerId: products[i].sellerId,
              sellerName: products[i].sellerName,
              sellerLogoUrl: products[i].sellerLogoUrl,
            ),
          )),
        ),
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hoverable category chip
// ─────────────────────────────────────────────────────────────────────────────

class _HoverChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final bool hasDropdown;
  final VoidCallback onTap;

  const _HoverChip({
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.hasDropdown,
    required this.onTap,
  });

  @override
  State<_HoverChip> createState() => _HoverChipState();
}

class _HoverChipState extends State<_HoverChip> {
  bool _hovered = false;

  Color get _bg {
    if (widget.isSelected) return const Color(0xFF0A0A0A);
    if (_hovered) return const Color(0xFFF0EFED);
    return Colors.white;
  }

  Color get _fg {
    return widget.isSelected ? Colors.white : const Color(0xFF0A0A0A);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _bg,
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFF0A0A0A)
                  : _hovered
                      ? const Color(0xFF888888)
                      : const Color(0xFFCCCCCC),
              width: widget.isSelected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label.toUpperCase(),
                style: GoogleFonts.commissioner(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: _fg,
                ),
              ),
              if (widget.hasDropdown) ...[
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: widget.isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down, size: 14, color: _fg),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "View All" button inside dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _HoverableViewAll extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _HoverableViewAll({required this.label, required this.onTap});

  @override
  State<_HoverableViewAll> createState() => _HoverableViewAllState();
}

class _HoverableViewAllState extends State<_HoverableViewAll> {
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
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFF0EFED) : Colors.white,
            border: Border.all(color: const Color(0xFFCCCCCC), width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: GoogleFonts.commissioner(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: const Color(0xFF0A0A0A),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subcategory row inside dropdown
// ─────────────────────────────────────────────────────────────────────────────

class _SubRow extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _SubRow({required this.label, required this.isSelected, required this.onTap});

  @override
  State<_SubRow> createState() => _SubRowState();
}

class _SubRowState extends State<_SubRow> {
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
          duration: const Duration(milliseconds: 120),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? const Color(0xFFF4F3F0)
                : _hovered
                    ? const Color(0xFFF9F9F7)
                    : Colors.white,
            border: const Border(
                bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: const Color(0xFF0A0A0A),
                  ),
                ),
              ),
              if (widget.isSelected)
                const Icon(Icons.check, size: 14, color: Color(0xFF0A0A0A))
              else
                Icon(Icons.arrow_forward_ios,
                    size: 10,
                    color:
                        _hovered ? const Color(0xFF888888) : const Color(0xFFCCCCCC)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product card
// ─────────────────────────────────────────────────────────────────────────────

class _ProductCard extends StatefulWidget {
  final Product product;
  final bool isMobile;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final VoidCallback onSellerTap;

  const _ProductCard({
    required this.product,
    required this.isMobile,
    required this.onTap,
    required this.onAddToCart,
    required this.onSellerTap,
  });

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final imgH = widget.isMobile ? 130.0 : 190.0;
    final nameSize = widget.isMobile ? 11.0 : 13.0;
    final priceSize = widget.isMobile ? 12.0 : 14.0;
    final btnSize = widget.isMobile ? 9.0 : 10.0;
    final vPad = widget.isMobile ? 6.0 : 8.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  border: Border.all(
                    color: _hovered
                        ? const Color(0xFF888888)
                        : const Color(0xFFE8E8E8),
                    width: 1,
                  ),
                  boxShadow: _hovered
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          )
                        ]
                      : [],
                ),
                child: widget.product.imageUrl.isNotEmpty
                    ? Image.network(
                        widget.product.imageUrl,
                        height: imgH,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return SizedBox(
                            height: imgH,
                            child: Center(
                              child: CircularProgressIndicator(
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded /
                                        progress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 1.5,
                                color: const Color(0xFF0A0A0A),
                              ),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => SizedBox(
                          height: imgH,
                          child: Center(
                              child: Icon(Icons.image_outlined,
                                  size: widget.isMobile ? 28 : 36,
                                  color: const Color(0xFFCCCCCC))),
                        ),
                      )
                    : SizedBox(
                        height: imgH,
                        child: Center(
                            child: Icon(Icons.image_outlined,
                                size: widget.isMobile ? 28 : 36,
                                color: const Color(0xFFCCCCCC))),
                      ),
              ),

              SizedBox(height: widget.isMobile ? 8 : 10),

              // Content section - expands to fill available space
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category label
                    Text(
                      widget.product.category.toUpperCase(),
                      style: GoogleFonts.commissioner(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFAAAAAA),
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 3),

                    // Product name
                    SizedBox(
                      height: widget.isMobile ? 28 : 34,
                      child: Text(
                        widget.product.name,
                        style: GoogleFonts.inter(
                            fontSize: nameSize,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF0A0A0A),
                            height: 1.35),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Seller name
                    if (widget.product.sellerName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      GestureDetector(
                        onTap: widget.onSellerTap,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.storefront_outlined,
                                size: 10, color: Color(0xFF888888)),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                widget.product.sellerName,
                                style: GoogleFonts.inter(
                                    fontSize: widget.isMobile ? 9 : 10,
                                    color: const Color(0xFF666666),
                                    decoration: TextDecoration.underline,
                                    decorationColor: const Color(0xFFBBBBBB)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: widget.isMobile ? 5 : 7),

                    // Price
                    Text(
                      '₱${widget.product.price.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(
                          fontSize: priceSize,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0A0A0A)),
                    ),

                    // Stock badge
                    if (widget.product.stock == 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'OUT OF STOCK',
                        style: GoogleFonts.commissioner(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFCC0000),
                          letterSpacing: 1.5,
                        ),
                      ),
                    ] else if (widget.product.stock <= 5) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Only ${widget.product.stock} left',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ],

                    // Sold count
                    if (widget.product.totalSold > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${widget.product.totalSold} sold',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          color: const Color(0xFF999999),
                        ),
                      ),
                    ],

                    // Spacer pushes buttons to bottom
                    const Spacer(),
                  ],
                ),
              ),

              SizedBox(height: widget.isMobile ? 7 : 9),

              // Buttons - always at bottom
              Row(children: [
                Expanded(
                  child: _HoverButton(
                    label: 'VIEW',
                    filled: false,
                    fontSize: btnSize,
                    vPad: vPad,
                    onTap: widget.onTap,
                  ),
                ),
                SizedBox(width: widget.isMobile ? 6 : 8),
                Expanded(
                  child: _HoverButton(
                    label: widget.product.stock == 0 ? 'SOLD OUT' : 'ADD',
                    filled: true,
                    fontSize: btnSize,
                    vPad: vPad,
                    onTap: widget.onAddToCart,
                    disabled: widget.product.stock == 0,
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hoverable button
// ─────────────────────────────────────────────────────────────────────────────

class _HoverButton extends StatefulWidget {
  final String label;
  final bool filled;
  final double fontSize;
  final double vPad;
  final VoidCallback onTap;
  final bool disabled;

  const _HoverButton({
    required this.label,
    required this.filled,
    required this.fontSize,
    required this.vPad,
    required this.onTap,
    this.disabled = false,
  });

  @override
  State<_HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<_HoverButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    if (widget.disabled) {
      bg = const Color(0xFFEEEEEE);
      fg = const Color(0xFFAAAAAA);
      border = const Color(0xFFDDDDDD);
    } else if (widget.filled) {
      bg = _hovered ? const Color(0xFF333333) : const Color(0xFF0A0A0A);
      fg = Colors.white;
      border = const Color(0xFF0A0A0A);
    } else {
      bg = _hovered ? const Color(0xFFF0EFED) : Colors.white;
      fg = const Color(0xFF0A0A0A);
      border = const Color(0xFF0A0A0A);
    }

    return MouseRegion(
      cursor: widget.disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.disabled ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: widget.vPad),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: 1),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: GoogleFonts.commissioner(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Suggestion panel container
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionPanel extends StatelessWidget {
  final List<Widget> children;
  const _SuggestionPanel({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Suggestion section header label
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionHeader extends StatelessWidget {
  final String label;
  const _SuggestionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        label,
        style: GoogleFonts.commissioner(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: const Color(0xFF999999),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual suggestion row
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionRow extends StatefulWidget {
  final IconData icon;
  final String text;
  final String? subtitle;
  final VoidCallback onTap;

  const _SuggestionRow({
    required this.icon,
    required this.text,
    this.subtitle,
    required this.onTap,
  });

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
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
          duration: const Duration(milliseconds: 120),
          color: _hovered ? const Color(0xFFF5F5F5) : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: const Color(0xFF888888)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.text,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF0A0A0A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFFAAAAAA),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.north_west, size: 12, color: Color(0xFFCCCCCC)),
            ],
          ),
        ),
      ),
    );
  }
}
