import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';
import 'rider_map_screen.dart';

class RiderDeliveryDetailScreen extends StatefulWidget {
  final Order order;
  const RiderDeliveryDetailScreen({super.key, required this.order});

  @override
  State<RiderDeliveryDetailScreen> createState() =>
      _RiderDeliveryDetailScreenState();
}

class _RiderDeliveryDetailScreenState
    extends State<RiderDeliveryDetailScreen> {
  late Order _order;
  bool _updating = false;

  static const List<String> _flow = [
    Order.shipped,
    Order.outForDelivery,
    Order.delivered,
  ];

  static const Map<String, String> _stepLabels = {
    Order.shipped:        'Order Accepted',
    Order.outForDelivery: 'Out for Delivery',
    Order.delivered:      'Delivered',
  };

  static const Map<String, String> _stepDescriptions = {
    Order.shipped:        'Pick up the package from the seller\'s location.',
    Order.outForDelivery: 'You are on your way to the buyer\'s address.',
    Order.delivered:      'Package successfully delivered to the buyer.',
  };

  static const Map<String, String> _nextActionLabel = {
    Order.shipped:        'MARK OUT FOR DELIVERY',
    Order.outForDelivery: 'MARK AS DELIVERED',
  };

  static const _stepColors = {
    Order.shipped:        Color(0xFF3B82F6),
    Order.outForDelivery: Color(0xFFF59E0B),
    Order.delivered:      Color(0xFF10B981),
  };

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  String? get _nextStatus {
    final idx = _flow.indexOf(_order.status);
    if (idx == -1 || idx >= _flow.length - 1) return null;
    return _flow[idx + 1];
  }

  Future<void> _advanceStatus() async {
    final next = _nextStatus;
    if (next == null) return;
    setState(() => _updating = true);
    await OrderService.updateStatus(_order.id, next);
    if (!mounted) return;
    setState(() {
      _order.status = next;
      _updating = false;
    });
    if (next == Order.delivered) {
      _snack(
          'Delivery completed! Commission: ₱${_order.commission.toStringAsFixed(2)}');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white)),
      backgroundColor: const Color(0xFF0A0A0A),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 16, color: Colors.white),
        ),
        title: Text(
          'DELIVERY DETAIL',
          style: GoogleFonts.commissioner(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _orderCard(),
            const SizedBox(height: 14),
            _timelineCard(),
            const SizedBox(height: 14),
            _addressCard(),
            const SizedBox(height: 14),
            _viewOnMapButton(),
            const SizedBox(height: 14),
            if (_order.status != Order.delivered) _actionButton(),
            if (_order.status == Order.delivered) _completedBanner(),
          ],
        ),
      ),
    );
  }

  // ── Order card ─────────────────────────────────────────────────────────────

  Widget _orderCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('ORDER DETAILS'),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F6F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shopping_bag_outlined,
                    size: 24, color: Color(0xFFAAAAAA)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _order.productName,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0A0A0A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Qty ${_order.quantity}  ·  ₱${_order.total.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: const Color(0xFF888888)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: const Color(0xFFF0F0F0)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'YOUR COMMISSION',
                style: GoogleFonts.commissioner(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: const Color(0xFF999999),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '₱${_order.commission.toStringAsFixed(2)}',
                  style: GoogleFonts.commissioner(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Timeline card ──────────────────────────────────────────────────────────

  Widget _timelineCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('DELIVERY PROGRESS'),
          const SizedBox(height: 20),
          ..._flow.asMap().entries.map((entry) {
            final idx = entry.key;
            final step = entry.value;
            final currentIdx = _flow.indexOf(_order.status);
            final isDone = idx < currentIdx;
            final isActive = idx == currentIdx;
            final isPending = idx > currentIdx;
            final isLast = idx == _flow.length - 1;
            final stepColor =
                _stepColors[step] ?? const Color(0xFF888888);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Indicator column
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isDone
                            ? stepColor
                            : isActive
                                ? stepColor
                                : Colors.transparent,
                        border: Border.all(
                          color: isPending
                              ? const Color(0xFFDDDDDD)
                              : stepColor,
                          width: 1.5,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDone
                            ? Icons.check
                            : isActive
                                ? Icons.circle
                                : Icons.circle_outlined,
                        size: isDone ? 13 : 10,
                        color: isDone || isActive
                            ? Colors.white
                            : const Color(0xFFDDDDDD),
                      ),
                    ),
                    if (!isLast)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 2,
                        height: isActive ? 52 : 36,
                        color: isDone
                            ? stepColor
                            : const Color(0xFFEEEEEE),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        bottom: isLast ? 0 : (isActive ? 16 : 12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stepLabels[step] ?? step,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isPending
                                ? const Color(0xFFCCCCCC)
                                : const Color(0xFF0A0A0A),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 4),
                          Text(
                            _stepDescriptions[step] ?? '',
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF888888),
                                height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── Address card ───────────────────────────────────────────────────────────

  Widget _addressCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader('DELIVERY ADDRESS'),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.location_on_outlined,
                    size: 16, color: Color(0xFFEF4444)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _order.deliveryAddress,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        color: const Color(0xFF0A0A0A),
                        height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── View on map button ─────────────────────────────────────────────────────

  Widget _viewOnMapButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RiderMapScreen(order: _order)));
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF0A0A0A),
          side: const BorderSide(color: Color(0xFFDDDDDD), width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.map_outlined, size: 18),
        label: Text(
          'VIEW ON MAP',
          style: GoogleFonts.commissioner(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }

  // ── Action button ──────────────────────────────────────────────────────────

  Widget _actionButton() {
    final label = _nextActionLabel[_order.status] ?? 'UPDATE STATUS';
    final currentColor =
        _stepColors[_order.status] ?? const Color(0xFF0A0A0A);
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _updating ? null : _advanceStatus,
        style: ElevatedButton.styleFrom(
          backgroundColor: currentColor,
          disabledBackgroundColor: const Color(0xFFCCCCCC),
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        child: _updating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 1.5),
              )
            : Text(
                label,
                style: GoogleFonts.commissioner(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _completedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle,
                color: Color(0xFF10B981), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivery Completed',
                  style: GoogleFonts.commissioner(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Commission earned: ₱${_order.commission.toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: const Color(0xFF555555)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }

  Widget _cardHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.commissioner(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.5,
        color: const Color(0xFF888888),
      ),
    );
  }
}
