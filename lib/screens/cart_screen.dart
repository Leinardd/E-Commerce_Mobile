import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/product.dart';
import '../services/cart_service.dart';
import 'checkout_screen.dart';
import 'product_detail_screen.dart';
import 'seller_store_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late CartService cartService;

  final Map<String, bool> _itemErrors = {};
  final Set<String> _selectedKeys = {};

  bool get _allSelected {
    final items = cartService.getCartItems();
    return items.isNotEmpty && items.every((i) => _selectedKeys.contains(i.variantKey));
  }

  bool get _selectedHasErrors => _itemErrors.entries
      .any((e) => e.value && _selectedKeys.contains(e.key));

  double get _selectedTotal => cartService
      .getCartItems()
      .where((i) => _selectedKeys.contains(i.variantKey))
      .fold(0.0, (sum, i) => sum + i.getTotal());

  int get _selectedCount => cartService
      .getCartItems()
      .where((i) => _selectedKeys.contains(i.variantKey))
      .fold(0, (sum, i) => sum + i.quantity);

  @override
  void initState() {
    super.initState();
    cartService = CartService();
    // Start with all items selected
    for (final item in cartService.getCartItems()) {
      _selectedKeys.add(item.variantKey);
    }
  }

  void _removeItem(String variantKey) {
    setState(() {
      cartService.removeByVariantKey(variantKey);
      _itemErrors.remove(variantKey);
      _selectedKeys.remove(variantKey);
    });
  }

  void _onItemError(String variantKey, bool hasError) {
    setState(() => _itemErrors[variantKey] = hasError);
  }

  void _onQuantityChanged() => setState(() {});

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selectedKeys.clear();
      } else {
        for (final item in cartService.getCartItems()) {
          _selectedKeys.add(item.variantKey);
        }
      }
    });
  }

  void _toggleItem(String variantKey) {
    setState(() {
      if (_selectedKeys.contains(variantKey)) {
        _selectedKeys.remove(variantKey);
      } else {
        _selectedKeys.add(variantKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final cartItems = cartService.getCartItems();

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
          'SHOPPING CART',
          style: GoogleFonts.commissioner(
            color: const Color(0xFF0A0A0A),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFEEEEEE), height: 1),
        ),
      ),
      body: cartItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_outlined,
                      size: 72, color: Colors.grey[300]),
                  const SizedBox(height: 20),
                  Text(
                    'YOUR CART IS EMPTY',
                    style: GoogleFonts.commissioner(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: const Color(0xFFAAAAAA),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Browse the shop and add items to get started.',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: const Color(0xFFBBBBBB)),
                  ),
                  const SizedBox(height: 28),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF0A0A0A)),
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 14),
                    ),
                    child: Text(
                      'CONTINUE SHOPPING',
                      style: GoogleFonts.commissioner(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: const Color(0xFF0A0A0A),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // ── Select All row ────────────────────────────────────────
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 16 : 40,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Color(0xFFEEEEEE))),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: _allSelected,
                          onChanged: (_) => _toggleAll(),
                          activeColor: const Color(0xFF0A0A0A),
                          side: const BorderSide(
                              color: Color(0xFFAAAAAA), width: 1.5),
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _toggleAll,
                        child: Text(
                          'Select All',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFF555555),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_selectedKeys.length} of ${cartItems.length} selected',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: const Color(0xFFAAAAAA),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Item list (grouped by seller) ─────────────────────────
                Expanded(
                  child: Builder(builder: (context) {
                    // Group by seller, preserving insertion order
                    final grouped = <String, List<CartItem>>{};
                    for (final item in cartItems) {
                      final sid = item.product.sellerId?.toString() ?? '';
                      grouped.putIfAbsent(sid, () => []).add(item);
                    }
                    // Flat list: _SellerInfo = seller header, CartItem = product row
                    final entries = <Object>[];
                    for (final group in grouped.values) {
                      final p = group.first.product;
                      final name = p.sellerName.isNotEmpty ? p.sellerName : 'Unknown Seller';
                      entries.add(_SellerInfo(
                        name: name,
                        sellerId: p.sellerId,
                        sellerLogoUrl: p.sellerLogoUrl,
                      ));
                      entries.addAll(group);
                    }

                    return ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 16 : 40,
                        vertical: 20,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry is _SellerInfo) {
                          return _SellerHeader(
                              info: entry, isFirst: index == 0);
                        }
                        final item = entry as CartItem;
                        final isLast = index == entries.length - 1;
                        final nextIsHeader =
                            !isLast && entries[index + 1] is _SellerInfo;
                        return Column(
                          children: [
                            _CartItemRow(
                              key: ValueKey(item.variantKey),
                              item: item,
                              isMobile: isMobile,
                              isSelected:
                                  _selectedKeys.contains(item.variantKey),
                              onToggleSelected: () =>
                                  _toggleItem(item.variantKey),
                              onRemove: () => _removeItem(item.variantKey),
                              onErrorChanged: _onItemError,
                              onQuantityChanged: _onQuantityChanged,
                            ),
                            if (!isLast && !nextIsHeader)
                              Divider(color: Colors.grey[200], height: 28)
                            else if (nextIsHeader)
                              const SizedBox(height: 20),
                          ],
                        );
                      },
                    );
                  }),
                ),

                // ── Summary + checkout ────────────────────────────────────
                Container(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 40,
                    20,
                    isMobile ? 16 : 40,
                    28,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                        top: BorderSide(color: Color(0xFFEEEEEE))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error banner (only when a selected item has an error)
                      if (_selectedHasErrors) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          color: const Color(0xFFFFF3F3),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 14, color: Color(0xFFCC0000)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Please fix quantity errors before checking out.',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFFCC0000),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Selected count + total of selected items
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$_selectedCount item${_selectedCount == 1 ? '' : 's'} selected',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFF888888),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'TOTAL',
                                style: GoogleFonts.commissioner(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  color: const Color(0xFF888888),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '₱${_selectedTotal.toStringAsFixed(0)}',
                                style: GoogleFonts.inter(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF0A0A0A),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Checkout button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: (_selectedKeys.isEmpty || _selectedHasErrors)
                              ? null
                              : () {
                                  final selectedItems = cartItems
                                      .where((i) => _selectedKeys
                                          .contains(i.variantKey))
                                      .toList();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => CheckoutScreen(
                                          selectedItems: selectedItems),
                                    ),
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A0A0A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            disabledBackgroundColor:
                                const Color(0xFFCCCCCC),
                            shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.zero),
                          ),
                          child: Text(
                            _selectedHasErrors
                                ? 'FIX QUANTITIES TO CHECKOUT'
                                : _selectedKeys.isEmpty
                                    ? 'SELECT ITEMS TO CHECKOUT'
                                    : 'CHECKOUT (${_selectedKeys.length})',
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
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cart item row — owns its own TextEditingController and error state
// ─────────────────────────────────────────────────────────────────────────────

class _CartItemRow extends StatefulWidget {
  final CartItem item;
  final bool isMobile;
  final bool isSelected;
  final VoidCallback onToggleSelected;
  final VoidCallback onRemove;
  final void Function(String variantKey, bool hasError) onErrorChanged;
  final VoidCallback onQuantityChanged;

  const _CartItemRow({
    super.key,
    required this.item,
    required this.isMobile,
    required this.isSelected,
    required this.onToggleSelected,
    required this.onRemove,
    required this.onErrorChanged,
    required this.onQuantityChanged,
  });

  @override
  State<_CartItemRow> createState() => _CartItemRowState();
}

class _CartItemRowState extends State<_CartItemRow> {
  late final TextEditingController _ctrl;
  String? _error;

  int get _stock => widget.item.product.stock;
  int get _qty => widget.item.quantity;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '$_qty');
  }

  @override
  void dispose() {
    // Clear any error tied to this item when it's removed from the tree.
    widget.onErrorChanged(widget.item.variantKey, false);
    _ctrl.dispose();
    super.dispose();
  }

  // Apply a new quantity from +/- buttons (always valid range).
  void _stepQty(int newQty) {
    newQty = newQty.clamp(1, _stock);
    widget.item.quantity = newQty;
    _ctrl.value = TextEditingValue(
      text: '$newQty',
      selection:
          TextSelection.fromPosition(TextPosition(offset: '$newQty'.length)),
    );
    setState(() => _error = null);
    widget.onErrorChanged(widget.item.variantKey, false);
    widget.onQuantityChanged();
  }

  // Validate and apply a quantity from keyboard input.
  void _applyQtyFromText(int qty) {
    final stock = _stock;
    if (qty > stock) {
      setState(() => _error = 'Quantity exceeds available stock.');
      widget.onErrorChanged(widget.item.variantKey, true);
      // Don't update cart item — leave it at last valid value.
    } else {
      final clamped = qty.clamp(1, stock);
      widget.item.quantity = clamped;
      setState(() => _error = null);
      widget.onErrorChanged(widget.item.variantKey, false);
      widget.onQuantityChanged();
    }
  }

  void _onTextChanged(String val) {
    if (val.isEmpty) {
      setState(() => _error = null);
      return;
    }
    final n = int.tryParse(val);
    if (n == null) return;
    _applyQtyFromText(n);
  }

  // On focus-out or submit: clamp to valid range and sync field.
  void _commitText() {
    final n = int.tryParse(_ctrl.text) ?? 1;
    final clamped = n.clamp(1, _stock);
    widget.item.quantity = clamped;
    _ctrl.value = TextEditingValue(
      text: '$clamped',
      selection: TextSelection.fromPosition(
          TextPosition(offset: '$clamped'.length)),
    );
    setState(() => _error = null);
    widget.onErrorChanged(widget.item.variantKey, false);
    widget.onQuantityChanged();
  }

  @override
  Widget build(BuildContext context) {
    final imgSize = widget.isMobile ? 80.0 : 96.0;
    final subtotal = widget.item.getTotal();
    final hasError = _error != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Checkbox ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 10),
              child: SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: widget.isSelected,
                  onChanged: (_) => widget.onToggleSelected(),
                  activeColor: const Color(0xFF0A0A0A),
                  side: const BorderSide(color: Color(0xFFAAAAAA), width: 1.5),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),

            // ── Product image ───────────────────────────────────────
            Container(
              width: imgSize,
              height: imgSize,
              color: const Color(0xFFF2F2F2),
              child: widget.item.product.imageUrl.isNotEmpty
                  ? Image.network(
                      widget.item.product.imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, p) =>
                          p == null ? child : const _ImgLoader(),
                      errorBuilder: (_, __, ___) => const _ImgPlaceholder(),
                    )
                  : const _ImgPlaceholder(),
            ),
            const SizedBox(width: 14),

            // ── Details ─────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + subtotal
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ProductDetailScreen(
                                  product: widget.item.product),
                            ),
                          ),
                          child: Text(
                            widget.item.product.name,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0A0A0A),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₱${subtotal.toStringAsFixed(0)}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0A0A0A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Unit price
                  Text(
                    '₱${widget.item.product.price.toStringAsFixed(0)} each',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF888888),
                    ),
                  ),

                  // Variant label
                  if (widget.item.selectedSize != null ||
                      widget.item.selectedColor != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (widget.item.selectedSize != null)
                          'Size: ${widget.item.selectedSize}',
                        if (widget.item.selectedColor != null)
                          widget.item.selectedColor!,
                      ].join(' · '),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF888888),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // ── Quantity control row ─────────────────────────
                  Row(
                    children: [
                      // Stepper + editable field
                      Container(
                        height: 34,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: hasError
                                ? const Color(0xFFCC0000)
                                : const Color(0xFFDDDDDD),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Minus
                            _StepButton(
                              icon: Icons.remove,
                              enabled: _qty > 1,
                              onTap: () => _stepQty(_qty - 1),
                            ),

                            // Editable quantity field
                            SizedBox(
                              width: 44,
                              child: TextField(
                                controller: _ctrl,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: hasError
                                      ? const Color(0xFFCC0000)
                                      : const Color(0xFF0A0A0A),
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: _onTextChanged,
                                onSubmitted: (_) => _commitText(),
                                onTapOutside: (_) => _commitText(),
                              ),
                            ),

                            // Plus
                            _StepButton(
                              icon: Icons.add,
                              enabled: _qty < _stock,
                              onTap: () => _stepQty(_qty + 1),
                            ),
                          ],
                        ),
                      ),

                      // Stock indicator
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          '$_stock in stock',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: _stock <= 5
                                ? const Color(0xFFCC0000)
                                : const Color(0xFFAAAAAA),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Remove button
                      GestureDetector(
                        onTap: widget.onRemove,
                        child: Text(
                          'Remove',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: const Color(0xFF888888),
                            decoration: TextDecoration.underline,
                            decorationColor: const Color(0xFF888888),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Validation error ──────────────────────────────
                  if (hasError) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 13, color: Color(0xFFCC0000)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            _error!,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: const Color(0xFFCC0000),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────

class _StepButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 34,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Icon(
            icon,
            size: 15,
            color: enabled
                ? const Color(0xFF0A0A0A)
                : const Color(0xFFCCCCCC),
          ),
        ),
      ),
    );
  }
}

class _ImgLoader extends StatelessWidget {
  const _ImgLoader();

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Color(0xFF0A0A0A)),
        ),
      );
}

class _ImgPlaceholder extends StatelessWidget {
  const _ImgPlaceholder();

  @override
  Widget build(BuildContext context) => const Center(
        child: Icon(Icons.image_outlined, size: 28, color: Color(0xFFCCCCCC)),
      );
}

class _SellerInfo {
  final String name;
  final dynamic sellerId;
  final String sellerLogoUrl;
  const _SellerInfo({required this.name, this.sellerId, this.sellerLogoUrl = ''});
}

class _SellerHeader extends StatelessWidget {
  final _SellerInfo info;
  final bool isFirst;

  const _SellerHeader({required this.info, this.isFirst = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SellerStoreScreen(
              sellerId: info.sellerId,
              sellerName: info.name,
              sellerLogoUrl: info.sellerLogoUrl,
            ),
          )),
      child: Padding(
        padding: EdgeInsets.only(bottom: 14, top: isFirst ? 0 : 4),
        child: SizedBox(
          height: 36,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.storefront_outlined,
                  size: 13, color: Color(0xFF555555)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  info.name.toUpperCase(),
                  style: GoogleFonts.commissioner(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: const Color(0xFF555555),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 14, color: Color(0xFF999999)),
            ],
          ),
        ),
      ),
    );
  }
}
