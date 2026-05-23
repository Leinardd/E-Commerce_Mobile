import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';
import '../../services/rider_auth_service.dart';

class RiderAvailableOrdersScreen extends StatefulWidget {
  const RiderAvailableOrdersScreen({super.key});

  @override
  State<RiderAvailableOrdersScreen> createState() =>
      _RiderAvailableOrdersScreenState();
}

class _RiderAvailableOrdersScreenState
    extends State<RiderAvailableOrdersScreen> {
  List<Order> _orders = [];
  bool _loading = true;
  final Set<String> _accepting = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final orders = await OrderService.getAvailableForRider();
    if (!mounted) return;
    setState(() {
      _orders = orders;
      _loading = false;
    });
  }

  Future<void> _accept(Order order) async {
    final email = await RiderAuthService.getCurrentRiderEmail();
    if (email == null) return;
    setState(() => _accepting.add(order.id));
    await OrderService.acceptOrder(order.id, email);
    if (!mounted) return;
    setState(() => _accepting.remove(order.id));
    _snack('Order accepted — check My Active Deliveries');
    _load();
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
          'AVAILABLE ORDERS',
          style: GoogleFonts.commissioner(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
            color: Colors.white,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Container(
            color: const Color(0xFF1A1A1A),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                const Icon(Icons.local_shipping_outlined, size: 13, color: Color(0xFF888888)),
                const SizedBox(width: 6),
                Text(
                  'Orders ready for pickup from seller',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF888888)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon:
                const Icon(Icons.refresh, color: Colors.white, size: 20),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF0A0A0A), strokeWidth: 1.5))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF0A0A0A),
              child: _orders.isEmpty
                  ? _emptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (_, i) => _orderCard(_orders[i]),
                    ),
            ),
    );
  }

  Widget _emptyState() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.inbox_outlined,
                    size: 36, color: Color(0xFFCCCCCC)),
              ),
              const SizedBox(height: 20),
              Text(
                'NO ORDERS AVAILABLE',
                style: GoogleFonts.commissioner(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFAAAAAA),
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Pull to refresh or check back later',
                style: GoogleFonts.inter(
                    fontSize: 12, color: const Color(0xFFBBBBBB)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _orderCard(Order order) {
    final isAccepting = _accepting.contains(order.id);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F6F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shopping_bag_outlined,
                    size: 22, color: Color(0xFFAAAAAA)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.productName,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF0A0A0A),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Qty ${order.quantity}  ·  ₱${order.total.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: const Color(0xFF888888)),
                    ),
                  ],
                ),
              ),
              // Commission badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '₱${order.commission.toStringAsFixed(2)}',
                      style: GoogleFonts.commissioner(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'commission',
                    style: GoogleFonts.inter(
                        fontSize: 9, color: const Color(0xFFAAAAAA)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFF0F0F0)),
          const SizedBox(height: 12),

          // Delivery address
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 15, color: Color(0xFFAAAAAA)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.deliveryAddress,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF555555),
                      height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Accept button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: isAccepting ? null : () => _accept(order),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A0A0A),
                disabledBackgroundColor: const Color(0xFF555555),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: isAccepting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 1.5),
                    )
                  : Text(
                      'ACCEPT ORDER',
                      style: GoogleFonts.commissioner(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
