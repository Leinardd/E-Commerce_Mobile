import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';

class RiderEarningsScreen extends StatefulWidget {
  final String riderEmail;
  const RiderEarningsScreen({super.key, required this.riderEmail});

  @override
  State<RiderEarningsScreen> createState() => _RiderEarningsScreenState();
}

class _RiderEarningsScreenState extends State<RiderEarningsScreen> {
  List<Order> _delivered = [];
  double _totalEarnings = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final all = await OrderService.getByRider(widget.riderEmail);
    final delivered =
        all.where((o) => o.status == Order.delivered || o.status == Order.completed).toList();
    final total =
        delivered.fold<double>(0.0, (sum, o) => sum + o.commission);
    if (!mounted) return;
    setState(() {
      _delivered = delivered;
      _totalEarnings = total;
      _loading = false;
    });
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
          'MY EARNINGS',
          style: GoogleFonts.commissioner(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
            color: Colors.white,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF0A0A0A), strokeWidth: 1.5))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF0A0A0A),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: _summaryCard(),
                    ),
                  ),
                  if (_delivered.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Text(
                          'DELIVERY HISTORY',
                          style: GoogleFonts.commissioner(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            color: const Color(0xFF888888),
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _earningCard(_delivered[i]),
                          ),
                          childCount: _delivered.length,
                        ),
                      ),
                    ),
                  ] else
                    const SliverFillRemaining(child: _EmptyEarnings()),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL EARNINGS',
            style: GoogleFonts.commissioner(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₱${_totalEarnings.toStringAsFixed(2)}',
            style: GoogleFonts.commissioner(
              fontSize: 42,
              fontWeight: FontWeight.w200,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _summaryItem(
                  label: 'Deliveries',
                  value: '${_delivered.length}',
                  icon: Icons.check_circle_outline,
                  color: const Color(0xFF10B981),
                ),
              ),
              Expanded(
                child: _summaryItem(
                  label: 'Commission',
                  value:
                      '${(Order.commissionRate * 100).toInt()}%',
                  icon: Icons.percent,
                  color: const Color(0xFF3B82F6),
                ),
              ),
              Expanded(
                child: _summaryItem(
                  label: 'Avg / Order',
                  value: _delivered.isEmpty
                      ? '₱0'
                      : '₱${(_totalEarnings / _delivered.length).toStringAsFixed(0)}',
                  icon: Icons.trending_up,
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.commissioner(
            fontSize: 17,
            fontWeight: FontWeight.w400,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: Colors.white.withValues(alpha: 0.4),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _earningCard(Order order) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check,
                size: 20, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.productName,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0A0A0A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  order.deliveryAddress,
                  style: GoogleFonts.inter(
                      fontSize: 11, color: const Color(0xFF888888)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+ ₱${order.commission.toStringAsFixed(2)}',
                style: GoogleFonts.commissioner(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'of ₱${order.total.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                    fontSize: 10, color: const Color(0xFFAAAAAA)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyEarnings extends StatelessWidget {
  const _EmptyEarnings();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.payments_outlined,
                size: 36, color: Color(0xFFCCCCCC)),
          ),
          const SizedBox(height: 20),
          Text(
            'NO EARNINGS YET',
            style: GoogleFonts.commissioner(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFAAAAAA),
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Complete deliveries to start earning',
            style: GoogleFonts.inter(
                fontSize: 12, color: const Color(0xFFBBBBBB)),
          ),
        ],
      ),
    );
  }
}
