import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';

class BuyerOrdersScreen extends StatefulWidget {
  const BuyerOrdersScreen({super.key});

  @override
  State<BuyerOrdersScreen> createState() => _BuyerOrdersScreenState();
}

class _BuyerOrdersScreenState extends State<BuyerOrdersScreen> {
  String _filter = 'all';
  List<Order> _orders = [];
  bool _loading = true;
  Set<String> _reviewedOrders = {};

  // Tab key → matching statuses
  static const _tabStatuses = <String, List<String>>{
    'all':       [],
    'to_ship':   [Order.pending, Order.confirmed, Order.preparing],
    'shipped':   [Order.readyForPickup, Order.shipped],
    'to_receive':[Order.outForDelivery],
    'completed': [Order.delivered, Order.completed],
    'cancelled': [Order.cancelled],
  };

  static const _filters = [
    ('all',        'ALL'),
    ('to_ship',    'TO SHIP'),
    ('shipped',    'SHIPPED'),
    ('to_receive', 'TO RECEIVE'),
    ('completed',  'COMPLETED'),
    ('cancelled',  'CANCELLED'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _loadReviewedOrders();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final email = await AuthService.getUserEmail();
    if (email == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final orders = await OrderService.getByBuyer(email);
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _loading = false;
    });
  }

  Future<void> _loadReviewedOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('reviewed_orders') ?? [];
    if (mounted) setState(() => _reviewedOrders = ids.toSet());
  }

  Future<void> _submitReview(Order order, int rating, String text) async {
    final prefs = await SharedPreferences.getInstance();
    final email = await AuthService.getUserEmail();
    final displayName = await AuthService.getUserDisplayName();
    final author = displayName?.isNotEmpty == true
        ? displayName!
        : (email?.split('@').first ?? 'Anonymous');

    final key = 'reviews_${order.productId}';
    final existing = prefs.getString(key);
    final reviews = existing != null
        ? (jsonDecode(existing) as List).cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];
    reviews.insert(0, {
      'author': author,
      'rating': rating,
      'text': text,
      'date': DateTime.now().toIso8601String(),
    });
    await prefs.setString(key, jsonEncode(reviews));

    final reviewed = prefs.getStringList('reviewed_orders') ?? [];
    if (!reviewed.contains(order.id)) reviewed.add(order.id);
    await prefs.setStringList('reviewed_orders', reviewed);

    if (mounted) setState(() => _reviewedOrders = reviewed.toSet());
  }

  void _openReviewSheet(Order order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => _ReviewSheet(
        productName: order.productName,
        onSubmit: (rating, text) async {
          await _submitReview(order, rating, text);
        },
      ),
    );
  }

  List<Order> get _filtered {
    if (_filter == 'all') return _orders;
    final statuses = _tabStatuses[_filter] ?? [];
    return _orders.where((o) => statuses.contains(o.status)).toList();
  }

  Future<void> _confirmReceipt(Order order) async {
    await OrderService.updateStatus(order.id, Order.completed);
    _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Receipt confirmed — thank you for your order!'),
        backgroundColor: Color(0xFF0A0A0A),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  Future<void> _cancelOrder(Order order) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => const _CancelReasonSheet(),
    );
    if (reason == null) return;
    try {
      await OrderService.updateStatus(
        order.id,
        Order.cancelled,
        cancelReason: reason,
      );
      await ProductService.incrementStock(order.productId, order.quantity);
      CartService().restoreProductStock(order.productId, order.quantity);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order cancelled.'),
          backgroundColor: Color(0xFF0A0A0A),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel order: $e'),
          backgroundColor: const Color(0xFFCC0000),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF0A0A0A), size: 16),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'MY ORDERS',
          style: TextStyle(
            color: Color(0xFF0A0A0A),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF0A0A0A)))
          : Column(
              children: [
                // Filter tabs
                Container(
                  color: Colors.white,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: _filters.map((f) {
                        final active = _filter == f.$1;
                        return GestureDetector(
                          onTap: () => setState(() => _filter = f.$1),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: active
                                ? const BoxDecoration(color: Color(0xFF0A0A0A))
                                : BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(color: const Color(0xFFDDDDDD))),
                            child: Text(
                              f.$2,
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: active ? Colors.white : const Color(0xFF555555),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Container(height: 1, color: const Color(0xFFEEEEEE)),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFFCCCCCC)),
                              SizedBox(height: 20),
                              Text(
                                'NO ORDERS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFAAAAAA),
                                  letterSpacing: 3,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Your orders will appear here',
                                style: TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: const Color(0xFF0A0A0A),
                          child: ListView.separated(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 16 : 48,
                              vertical: 20,
                            ),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (_, i) => _orderCard(_filtered[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _orderCard(Order order) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                order.id.length > 8
                    ? 'ORDER #${order.id.substring(order.id.length - 8).toUpperCase()}'
                    : 'ORDER #${order.id.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF888888),
                  letterSpacing: 2,
                ),
              ),
              _statusBadge(order.status),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              if (order.productImageUrl.isNotEmpty)
                Container(
                  width: 52,
                  height: 52,
                  color: const Color(0xFFF2F2F2),
                  margin: const EdgeInsets.only(right: 14),
                  child: Image.network(
                    order.productImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.image_outlined, color: Color(0xFFCCCCCC), size: 20),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.productName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0A0A0A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Qty: ${order.quantity}  ·  ₱${order.total.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF777777)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFF0F0F0)),
          const SizedBox(height: 12),

          _infoRow('ADDRESS', order.deliveryAddress),
          const SizedBox(height: 6),
          _infoRow(
            'DATE',
            '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}',
          ),

          // Progress bar
          const SizedBox(height: 16),
          _progressBar(order.status, cancelReason: order.cancelReason),

          // Cancel — only while pending (before seller confirms)
          if (order.status == Order.pending) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _cancelOrder(order),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFCCCCCC)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                child: const Text(
                  'CANCEL ORDER',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: Color(0xFF888888),
                  ),
                ),
              ),
            ),
          ],

          // Confirm receipt — when delivered
          if (order.status == Order.delivered) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _confirmReceipt(order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A0A0A),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                child: const Text(
                  'ORDER RECEIVED',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 2),
                ),
              ),
            ),
          ],

          if (order.status == Order.completed) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF0A0A0A),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.white, size: 14),
                  SizedBox(width: 8),
                  Text(
                    'DELIVERED — TRANSACTION COMPLETE',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_reviewedOrders.contains(order.id))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check, size: 12, color: Color(0xFF888888)),
                    SizedBox(width: 6),
                    Text(
                      'REVIEW SUBMITTED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: Color(0xFF888888),
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _openReviewSheet(order),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF0A0A0A)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  child: const Text(
                    'WRITE A REVIEW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _progressBar(String status, {String? cancelReason}) {
    if (status == Order.cancelled) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: const Color(0xFFFFEEEE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cancel_outlined, size: 13, color: Color(0xFFCC0000)),
                SizedBox(width: 6),
                Text(
                  'ORDER CANCELLED',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFFCC0000),
                  ),
                ),
              ],
            ),
            if (cancelReason != null && cancelReason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Reason: $cancelReason',
                style: const TextStyle(fontSize: 11, color: Color(0xFFCC0000)),
              ),
            ],
          ],
        ),
      );
    }

    // 4 visual steps
    const steps = ['placed', 'preparing', 'delivering', 'done'];
    const labels = ['PLACED', 'PREPARING', 'DELIVERING', 'DONE'];

    int currentStep(String s) {
      switch (s) {
        case Order.pending:
        case Order.confirmed:
          return 0;
        case Order.preparing:
        case Order.readyForPickup:
        case Order.shipped:
          return 1;
        case Order.outForDelivery:
        case Order.delivered:
          return 2;
        case Order.completed:
          return 3;
        // Legacy
        case Order.toPay:
        case Order.toShip:
          return 0;
        case Order.toReceive:
        case Order.riderAccepted:
        case Order.pickedUp:
        case Order.inTransit:
        case Order.nearLocation:
          return 2;
        default:
          return 0;
      }
    }

    final current = currentStep(status);

    return Row(
      children: List.generate(steps.length, (i) {
        final done = i <= current;
        final isLast = i == steps.length - 1;
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? const Color(0xFF0A0A0A) : const Color(0xFFDDDDDD),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 6,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: done ? const Color(0xFF0A0A0A) : const Color(0xFFCCCCCC),
                    ),
                  ),
                ],
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.only(bottom: 16),
                    color: i < current ? const Color(0xFF0A0A0A) : const Color(0xFFDDDDDD),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _statusBadge(String status) {
    final Color bg;
    final Color fg;
    switch (status) {
      case Order.completed:
        bg = const Color(0xFF0A0A0A);
        fg = Colors.white;
      case Order.cancelled:
        bg = const Color(0xFFFFEEEE);
        fg = const Color(0xFFCC0000);
      case Order.delivered:
        bg = const Color(0xFFE8F5E9);
        fg = const Color(0xFF2E7D32);
      case Order.outForDelivery:
        bg = const Color(0xFFE3F2FD);
        fg = const Color(0xFF1565C0);
      default:
        bg = const Color(0xFFF0F0F0);
        fg = const Color(0xFF555555);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: bg,
      child: Text(
        Order.statusLabel(status).toUpperCase(),
        style: TextStyle(
          fontSize: 7,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: fg,
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: Color(0xFFAAAAAA),
              letterSpacing: 1.5,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 11, color: Color(0xFF555555)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cancel reason bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CancelReasonSheet extends StatefulWidget {
  const _CancelReasonSheet();

  @override
  State<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends State<_CancelReasonSheet> {
  static const _presets = [
    'I changed my mind',
    'Found a better price elsewhere',
    'Ordered by mistake',
    'Delivery time is too long',
    'Payment issue',
    'Others',
  ];

  String? _selected;
  final _otherCtrl = TextEditingController();

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_selected == null) return false;
    if (_selected == 'Others') return _otherCtrl.text.trim().isNotEmpty;
    return true;
  }

  void _confirm() {
    if (!_canConfirm) return;
    final reason = _selected == 'Others' ? _otherCtrl.text.trim() : _selected!;
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 32,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CANCEL ORDER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: Color(0xFF0A0A0A),
            ),
          ),
          Container(
            width: 28,
            height: 1,
            color: const Color(0xFF0A0A0A),
            margin: const EdgeInsets.only(top: 10, bottom: 20),
          ),
          const Text(
            'WHY ARE YOU CANCELLING?',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 14),
          ..._presets.map((reason) {
            final selected = _selected == reason;
            return GestureDetector(
              onTap: () => setState(() => _selected = reason),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF0A0A0A) : Colors.white,
                  border: Border.all(
                    color: selected ? const Color(0xFF0A0A0A) : const Color(0xFFDDDDDD),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        reason,
                        style: TextStyle(
                          fontSize: 12,
                          color: selected ? Colors.white : const Color(0xFF0A0A0A),
                        ),
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check, size: 14, color: Colors.white),
                  ],
                ),
              ),
            );
          }),
          if (_selected == 'Others') ...[
            const SizedBox(height: 4),
            TextField(
              controller: _otherCtrl,
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              style: const TextStyle(fontSize: 13, color: Color(0xFF0A0A0A)),
              decoration: const InputDecoration(
                hintText: 'Please describe your reason...',
                hintStyle: TextStyle(fontSize: 12, color: Color(0xFFBBBBBB)),
                contentPadding: EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Color(0xFFDDDDDD)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Color(0xFFDDDDDD)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Color(0xFF0A0A0A)),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _canConfirm ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCC0000),
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: const Color(0xFFEEEEEE),
                disabledForegroundColor: const Color(0xFFAAAAAA),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              child: const Text(
                'CONFIRM CANCELLATION',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text(
                'KEEP ORDER',
                style: TextStyle(fontSize: 9, letterSpacing: 1.5, color: Color(0xFF888888)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Write a review bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  final String productName;
  final Future<void> Function(int rating, String text) onSubmit;

  const _ReviewSheet({required this.productName, required this.onSubmit});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 0;
  final _ctrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _ctrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    await widget.onSubmit(_rating, _ctrl.text.trim());
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 32,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WRITE A REVIEW',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: Color(0xFF0A0A0A),
            ),
          ),
          Container(
            width: 28,
            height: 1,
            color: const Color(0xFF0A0A0A),
            margin: const EdgeInsets.only(top: 10, bottom: 6),
          ),
          Text(
            widget.productName,
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              color: const Color(0xFF0A0A0A),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'YOUR RATING',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(5, (i) {
              return GestureDetector(
                onTap: () => setState(() => _rating = i + 1),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    i < _rating ? Icons.star : Icons.star_border,
                    size: 32,
                    color: const Color(0xFF0A0A0A),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          const Text(
            'YOUR REVIEW',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Color(0xFF888888),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13, color: Color(0xFF0A0A0A)),
            decoration: const InputDecoration(
              hintText: 'Share your experience with this product...',
              hintStyle: TextStyle(fontSize: 13, color: Color(0xFFBBBBBB)),
              contentPadding: EdgeInsets.all(14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Color(0xFFDDDDDD)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Color(0xFF0A0A0A)),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_rating > 0 && _ctrl.text.trim().isNotEmpty && !_submitting)
                  ? _submit
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A0A0A),
                foregroundColor: Colors.white,
                elevation: 0,
                disabledBackgroundColor: const Color(0xFFEEEEEE),
                disabledForegroundColor: const Color(0xFFAAAAAA),
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.white),
                    )
                  : const Text(
                      'SUBMIT REVIEW',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
