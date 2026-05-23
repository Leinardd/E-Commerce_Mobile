import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';
import '../../services/seller_auth_service.dart';

class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen> {
  String _filter = 'all';
  List<Order> _orders = [];
  bool _loading = true;

  static const _filters = [
    ('all',                'All'),
    (Order.pending,        'Pending'),
    (Order.confirmed,      'Confirmed'),
    (Order.preparing,      'Preparing'),
    (Order.readyForPickup, 'Ready'),
    (Order.completed,      'Completed'),
  ];

  static const _statusColors = {
    Order.pending:        Color(0xFFF59E0B),
    Order.confirmed:      Color(0xFF3B82F6),
    Order.preparing:      Color(0xFF6366F1),
    Order.readyForPickup: Color(0xFF8B5CF6),
    Order.shipped:        Color(0xFF14B8A6),
    Order.outForDelivery: Color(0xFF0EA5E9),
    Order.delivered:      Color(0xFF10B981),
    Order.completed:      Color(0xFF10B981),
    Order.cancelled:      Color(0xFFEF4444),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final email = await SellerAuthService.getCurrentSellerEmail();
    if (email == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final orders = await OrderService.getBySeller(email);
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _loading = false;
    });
  }

  List<Order> get _filtered => _filter == 'all'
      ? _orders
      : _orders.where((o) => o.status == _filter).toList();

  Future<void> _updateStatus(Order order, String newStatus) async {
    await OrderService.updateStatus(order.id, newStatus);
    _load();
  }

  Future<void> _cancelOrder(Order order) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          'CANCEL ORDER',
          style: GoogleFonts.commissioner(
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2.5,
          ),
        ),
        content: Text(
          'Cancel order for ${order.productName}?',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF555555)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('KEEP', style: TextStyle(color: Color(0xFF888888))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('CANCEL ORDER', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true) await _updateStatus(order, Order.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'ORDERS',
          style: GoogleFonts.commissioner(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 3,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF0A0A0A)))
          : Column(
              children: [
                _filterBar(),
                Expanded(
                  child: _filtered.isEmpty
                      ? _emptyState()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: const Color(0xFF0A0A0A),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
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

  Widget _filterBar() {
    return Container(
      color: const Color(0xFF0A0A0A),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(
          children: _filters.map((f) {
            final active = _filter == f.$1;
            final color = _statusColors[f.$1] ?? Colors.white;
            return GestureDetector(
              onTap: () => setState(() => _filter = f.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? (f.$1 == 'all' ? Colors.white : color)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f.$2,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active
                        ? (f.$1 == 'all' ? const Color(0xFF0A0A0A) : Colors.white)
                        : Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.receipt_long_outlined, size: 32, color: Color(0xFFCCCCCC)),
          ),
          const SizedBox(height: 20),
          Text(
            'NO ORDERS',
            style: GoogleFonts.commissioner(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: const Color(0xFFAAAAAA), letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text('Orders will appear here once placed',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFFBBBBBB))),
        ],
      ),
    );
  }

  Widget _orderCard(Order order) {
    final actions = _nextActions(order.status);
    final statusColor = _statusColors[order.status] ?? const Color(0xFF888888);

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.all(18),
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
                style: GoogleFonts.commissioner(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  color: const Color(0xFF999999), letterSpacing: 2,
                ),
              ),
              _statusPill(order.status, statusColor),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              if (order.productImageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: const Color(0xFFF2F2F2),
                    margin: const EdgeInsets.only(right: 14),
                    child: Image.network(
                      order.productImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_outlined, color: Color(0xFFCCCCCC), size: 22),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.productName,
                      style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF0A0A0A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Qty ${order.quantity}  ·  ₱${order.total.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF777777)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFF0F0F0)),
          const SizedBox(height: 12),

          _infoRow(Icons.person_outline, order.buyerEmail),
          const SizedBox(height: 8),
          _infoRow(Icons.location_on_outlined, order.deliveryAddress),
          const SizedBox(height: 8),
          _infoRow(Icons.calendar_today_outlined,
              '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}'),

          if (order.riderEmail != null && order.riderEmail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(Icons.delivery_dining_outlined, 'Rider: ${order.riderEmail}'),
          ],

          // Completed banner
          if (order.status == Order.completed || order.status == Order.delivered) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    order.status == Order.completed
                        ? 'PAYMENT RELEASED — COMPLETE'
                        : 'DELIVERED TO BUYER',
                    style: GoogleFonts.commissioner(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      letterSpacing: 1, color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Cancelled banner
          if (order.status == Order.cancelled) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'ORDER CANCELLED',
                    style: GoogleFonts.commissioner(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      letterSpacing: 1, color: const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Ready for pickup info
          if (order.status == Order.readyForPickup) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping_outlined, color: Color(0xFF8B5CF6), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'WAITING FOR RIDER TO ACCEPT',
                    style: GoogleFonts.commissioner(
                      fontSize: 9, fontWeight: FontWeight.w700,
                      letterSpacing: 1, color: const Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Action buttons
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: actions.asMap().entries.map((e) {
                final idx = e.key;
                final a = e.value; // (newStatus, isPrimary, label, isDestructive)
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: idx < actions.length - 1 ? 8 : 0),
                    child: ElevatedButton(
                      onPressed: () => a.$4
                          ? _cancelOrder(order)
                          : _updateStatus(order, a.$1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: a.$4
                            ? const Color(0xFFEF4444)
                            : a.$2
                                ? const Color(0xFF0A0A0A)
                                : Colors.white,
                        foregroundColor: a.$2 || a.$4 ? Colors.white : const Color(0xFF0A0A0A),
                        elevation: 0,
                        side: a.$2 || a.$4
                            ? null
                            : const BorderSide(color: Color(0xFFDDDDDD), width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(
                        a.$3,
                        style: GoogleFonts.commissioner(
                          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        Order.statusLabel(status).toUpperCase(),
        style: GoogleFonts.commissioner(
          fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1, color: color,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: const Color(0xFFCCCCCC)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF555555)),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Returns (newStatus, isPrimary, label, isDestructive)
  List<(String, bool, String, bool)> _nextActions(String status) {
    switch (status) {
      case Order.pending:
        return [
          (Order.confirmed, true, 'CONFIRM', false),
          ('', false, 'CANCEL', true),
        ];
      case Order.confirmed:
        return [
          (Order.preparing, true, 'MARK PREPARING', false),
          ('', false, 'CANCEL', true),
        ];
      case Order.preparing:
        return [(Order.readyForPickup, true, 'READY FOR PICKUP', false)];
      default:
        return [];
    }
  }
}
