import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/product.dart';
import '../models/product_variant.dart';
import 'size_guide_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data types
// ─────────────────────────────────────────────────────────────────────────────

// ProductSizeType and SizeOption are now defined in size_guide_widget.dart.

class ColorOption {
  final String label;
  final int hex;
  final bool outOfStock;
  const ColorOption(this.label, this.hex, {this.outOfStock = false});
}

// ─────────────────────────────────────────────────────────────────────────────
// VariantPickerSheet
// ─────────────────────────────────────────────────────────────────────────────

class VariantPickerSheet extends StatefulWidget {
  final Product product;
  final bool needsSize;
  final String? initialSize;
  final String? initialColor;
  final int initialQuantity;
  final List<ProductVariant> variants;
  final void Function(String? size, String? color, int quantity) onAddToCart;
  final void Function(String? size, String? color, int quantity)? onBuyNow;

  const VariantPickerSheet({
    super.key,
    required this.product,
    this.needsSize = true,
    this.initialSize,
    this.initialColor,
    this.initialQuantity = 1,
    this.variants = const [],
    required this.onAddToCart,
    this.onBuyNow,
  });

  // ── Public static helpers — delegate to SizeGuide ─────────────────────────

  static ProductSizeType sizeTypeForCategory(String category) =>
      SizeGuide.typeFor(category);

  static bool needsSizeForCategory(String category) =>
      SizeGuide.hasSizeGuide(category);

  static List<SizeOption> sizesForCategory(String category) =>
      SizeGuide.sizesFor(category);

  static void showSizeGuideModal(BuildContext context, String category) =>
      SizeGuide.showModal(context, category);

  // Categories where color selection is not shown
  static const _noColorCategories = {'barong'};

  static bool needsColorForCategory(String category) =>
      !_noColorCategories.contains(category.toLowerCase().trim());

  /// Show the variant picker bottom sheet. Size requirement is auto-detected.
  static Future<void> show(
    BuildContext context, {
    required Product product,
    List<ProductVariant> variants = const [],
    String? initialSize,
    String? initialColor,
    int initialQuantity = 1,
    required void Function(String? size, String? color, int quantity) onAddToCart,
    void Function(String? size, String? color, int quantity)? onBuyNow,
  }) {
    final needsSize = variants.isNotEmpty
        ? variants.any((v) => v.size != null && v.size!.isNotEmpty)
        : needsSizeForCategory(product.category);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: false,
      isDismissible: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(ctx).padding.top + 56),
        child: VariantPickerSheet(
          product: product,
          needsSize: needsSize,
          variants: variants,
          initialSize: initialSize,
          initialColor: initialColor,
          initialQuantity: initialQuantity,
          onAddToCart: onAddToCart,
          onBuyNow: onBuyNow,
        ),
      ),
    );
  }

  @override
  State<VariantPickerSheet> createState() => _VariantPickerSheetState();
}

class _VariantPickerSheetState extends State<VariantPickerSheet> {
  late String? _size;
  late String? _color;
  late int _qty;
  late final TextEditingController _qtyController;

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

  static const _fallbackColors = [
    ColorOption('Black', 0xFF0A0A0A),
    ColorOption('White', 0xFFF5F5F5),
    ColorOption('Navy',  0xFF1E2D55),
    ColorOption('Khaki', 0xFFB5A898),
    ColorOption('Olive', 0xFF6B6B47),
  ];

  bool get _productOos => widget.product.stock == 0;

  List<ColorOption> get _colorOptions {
    final dbColors = widget.variants
        .where((v) => v.color != null && v.color!.isNotEmpty)
        .map((v) => v.color!)
        .toSet()
        .toList();
    if (dbColors.isNotEmpty) {
      return dbColors
          .map((c) => ColorOption(c, _hexFor(c), outOfStock: _productOos))
          .toList();
    }
    if (!VariantPickerSheet.needsColorForCategory(widget.product.category)) return [];
    return _fallbackColors;
  }

  List<SizeOption> get _sizeOptions {
    final dbSizes = widget.variants
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
      return dbSizes.map((s) => SizeOption(s, outOfStock: _productOos)).toList();
    }
    return VariantPickerSheet.sizesForCategory(widget.product.category);
  }

  @override
  void initState() {
    super.initState();
    _size  = widget.initialSize;
    _color = widget.initialColor;
    _qty   = widget.initialQuantity.clamp(1, 99);
    _qtyController = TextEditingController(text: '$_qty');
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  bool get _canConfirm => !widget.needsSize || _size != null;

  void _setQty(int value) {
    final v = value.clamp(1, 99);
    setState(() => _qty = v);
    _qtyController
      ..text = '$v'
      ..selection = TextSelection.fromPosition(TextPosition(offset: '$v'.length));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(onClose: () => Navigator.of(context).pop()),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProductRow(),
                  const SizedBox(height: 20),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 24),
                  if (widget.needsSize) ...[
                    _buildSizeSection(),
                    const SizedBox(height: 24),
                  ],
                  if (_colorOptions.isNotEmpty) ...[
                    _buildColorSection(),
                    const SizedBox(height: 24),
                  ],
                  _buildQuantitySection(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Product row ──────────────────────────────────────────────────────────────

  Widget _buildProductRow() {
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            border: Border.all(color: const Color(0xFFE8E8E8)),
          ),
          child: widget.product.imageUrl.isNotEmpty
              ? Image.network(
                  widget.product.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.image_outlined, size: 28, color: Color(0xFFCCCCCC)),
                )
              : const Icon(Icons.image_outlined,
                  size: 28, color: Color(0xFFCCCCCC)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.product.name,
                style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0A0A0A),
                    height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                widget.product.category.toUpperCase(),
                style: GoogleFonts.commissioner(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFAAAAAA),
                    letterSpacing: 1.5),
              ),
              const SizedBox(height: 6),
              Text(
                '₱${widget.product.price.toStringAsFixed(0)}',
                style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0A0A0A)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Size section ─────────────────────────────────────────────────────────────

  Widget _buildSizeSection() {
    final sizes = _sizeOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'SIZE',
                  style: GoogleFonts.commissioner(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: const Color(0xFF888888)),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: _size != null
                      ? Text(
                          _size!,
                          key: ValueKey(_size),
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF0A0A0A)),
                        )
                      : Text(
                          '· required',
                          key: const ValueKey('req'),
                          style: GoogleFonts.inter(
                              fontSize: 9, color: const Color(0xFFB84040)),
                        ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () => VariantPickerSheet.showSizeGuideModal(
                  context, widget.product.category),
              child: Text(
                'SIZE GUIDE',
                style: GoogleFonts.inter(
                    fontSize: 9,
                    color: const Color(0xFF888888),
                    letterSpacing: 1,
                    decoration: TextDecoration.underline,
                    decorationColor: const Color(0xFF888888)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sizes.map((opt) {
            final selected = _size == opt.label;
            final disabled = opt.outOfStock;
            return GestureDetector(
              onTap: disabled ? null : () => setState(() => _size = opt.label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF0A0A0A)
                      : disabled
                          ? const Color(0xFFF8F8F8)
                          : Colors.white,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF0A0A0A)
                        : disabled
                            ? const Color(0xFFEEEEEE)
                            : const Color(0xFFDDDDDD),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      opt.label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : disabled
                                ? const Color(0xFFCCCCCC)
                                : const Color(0xFF0A0A0A),
                        decoration: disabled
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      ),
                    ),
                    if (disabled)
                      Positioned.fill(
                        child: CustomPaint(painter: _StrikethroughPainter()),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Color section ────────────────────────────────────────────────────────────

  Widget _buildColorSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'COLOR',
              style: GoogleFonts.commissioner(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: const Color(0xFF888888)),
            ),
            const SizedBox(width: 8),
            if (_color != null)
              Text(
                _color!,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0A0A0A)),
              )
            else
              Text(
                '· optional',
                style: GoogleFonts.inter(
                    fontSize: 9, color: const Color(0xFFAAAAAA)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: _colorOptions.map((opt) {
            final selected = _color == opt.label;
            final disabled = opt.outOfStock;
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Tooltip(
                message: opt.label,
                child: GestureDetector(
                  onTap: disabled
                      ? null
                      : () =>
                          setState(() => _color = selected ? null : opt.label),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(opt.hex),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF0A0A0A)
                            : disabled
                                ? const Color(0xFFEEEEEE)
                                : const Color(0xFFDDDDDD),
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check,
                            size: 14,
                            color: opt.hex == 0xFFF5F5F5
                                ? const Color(0xFF0A0A0A)
                                : Colors.white,
                          )
                        : disabled
                            ? const Icon(Icons.close,
                                size: 12, color: Color(0xFFCCCCCC))
                            : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Quantity section ─────────────────────────────────────────────────────────

  Widget _buildQuantitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUANTITY',
          style: GoogleFonts.commissioner(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: const Color(0xFF888888)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _QtyButton(
              icon: Icons.remove,
              enabled: _qty > 1,
              onTap: () => _setQty(_qty - 1),
            ),
            // Editable quantity field
            Container(
              width: 64,
              height: 40,
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFCCCCCC)),
                  bottom: BorderSide(color: Color(0xFFCCCCCC)),
                ),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: _qtyController,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0A0A0A)),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 2),
                ),
                onChanged: (val) {
                  final n = int.tryParse(val);
                  if (n != null && n >= 1) setState(() => _qty = n.clamp(1, 99));
                },
                onSubmitted: (val) => _setQty(int.tryParse(val) ?? 1),
                onTapOutside: (_) =>
                    _setQty(int.tryParse(_qtyController.text) ?? 1),
              ),
            ),
            _QtyButton(
              icon: Icons.add,
              enabled: _qty < 99,
              onTap: () => _setQty(_qty + 1),
            ),
          ],
        ),
      ],
    );
  }

  // ── Sticky footer ────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad > 0 ? bottomPad : 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.onBuyNow != null) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _canConfirm
                    ? () {
                        Navigator.of(context).pop();
                        widget.onBuyNow!(_size, _color, _qty);
                      }
                    : null,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: _canConfirm
                          ? const Color(0xFF0A0A0A)
                          : const Color(0xFFCCCCCC)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                ),
                child: Text(
                  'BUY NOW',
                  style: GoogleFonts.commissioner(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: _canConfirm
                        ? const Color(0xFF0A0A0A)
                        : const Color(0xFFAAAAAA),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: ElevatedButton(
                onPressed: _canConfirm
                    ? () {
                        Navigator.of(context).pop();
                        widget.onAddToCart(_size, _color, _qty);
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A0A0A),
                  disabledBackgroundColor: const Color(0xFFE0E0E0),
                  disabledForegroundColor: const Color(0xFF999999),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                ),
                child: Text(
                  _canConfirm
                      ? 'ADD TO CART  ·  $_qty ${_qty == 1 ? 'item' : 'items'}'
                      : 'SELECT A SIZE TO CONTINUE',
                  style: GoogleFonts.commissioner(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header with drag handle + close button
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Container(
                width: 36,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F5F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Color(0xFF555555)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quantity +/− button
// ─────────────────────────────────────────────────────────────────────────────

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _QtyButton(
      {required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled ? Colors.white : const Color(0xFFFAFAFA),
          border: Border.all(
            color: enabled ? const Color(0xFFCCCCCC) : const Color(0xFFEEEEEE),
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? const Color(0xFF0A0A0A) : const Color(0xFFCCCCCC),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OOS diagonal line painter
// ─────────────────────────────────────────────────────────────────────────────

class _StrikethroughPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      Paint()
        ..color = const Color(0xFFCCCCCC)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_StrikethroughPainter _) => false;
}

// Size guide sheet is now SizeGuideSheet in size_guide_widget.dart.
