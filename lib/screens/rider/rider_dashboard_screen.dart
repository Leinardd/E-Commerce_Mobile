import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/order.dart';
import '../../services/order_service.dart';
import '../../services/rider_auth_service.dart';
import '../../services/unified_auth_service.dart';
import 'rider_available_orders_screen.dart';
import 'rider_delivery_detail_screen.dart';
import 'rider_earnings_screen.dart';
import 'rider_map_screen.dart';

class RiderDashboardScreen extends StatefulWidget {
  const RiderDashboardScreen({super.key});

  @override
  State<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends State<RiderDashboardScreen> {
  String? _email;
  String? _name;
  int _availableCount = 0;
  int _activeCount = 0;
  int _deliveredCount = 0;
  double _earnings = 0;
  List<Order> _activeDeliveries = [];
  bool _loading = true;

  static const _statusColors = {
    Order.shipped:        Color(0xFF3B82F6),
    Order.outForDelivery: Color(0xFFF59E0B),
    Order.delivered:      Color(0xFF10B981),
    Order.completed:      Color(0xFF10B981),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final role = await UnifiedAuthService.getUserRole();
    if (role != UserRole.rider) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          role == UserRole.none ? '/login' : '/unauthorized',
          arguments: 'You do not have rider access.',
        );
      }
      return;
    }

    var email = await RiderAuthService.getCurrentRiderEmail();
    if (email == null) {
      final status = await RiderAuthService.syncSession();
      if (status == null) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      email = await RiderAuthService.getCurrentRiderEmail();
    }

    if (email == null || !mounted) {
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    try {
      developer.log('[RIDER_DASHBOARD] Loading data for: $email');
      final fullName = await RiderAuthService.getFullName(email);
      final availableOrders = await OrderService.getAvailableForRider();
      final activeOrders =
          await OrderService.getActiveDeliveriesByRider(email);
      final completedCount = await OrderService.riderCompletedCount(email);
      final earnings = await OrderService.riderEarnings(email);

      if (!mounted) return;
      setState(() {
        _email = email;
        _name = fullName;
        _availableCount = availableOrders.length;
        _activeDeliveries = activeOrders;
        _activeCount = activeOrders.length;
        _deliveredCount = completedCount;
        _earnings = earnings;
        _loading = false;
      });
    } catch (e, stackTrace) {
      developer.log('[RIDER_DASHBOARD] ERROR: $e\n$stackTrace');
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Failed to load dashboard: $e');
    }
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
      await RiderAuthService.logout();
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
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
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF0A0A0A), strokeWidth: 1.5))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF0A0A0A),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _header()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: _statsGrid(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                      child: _quickActions(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: _activeDeliveriesSection(),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              ),
            ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _header() {
    return Container(
      color: const Color(0xFF0A0A0A),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 16, 28),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VARÓN  ·  RIDER',
                      style: GoogleFonts.commissioner(
                        fontSize: 8,
                        color: Colors.white.withValues(alpha: 0.35),
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _name ?? _email ?? 'Rider',
                      style: GoogleFonts.commissioner(
                        fontSize: 22,
                        fontWeight: FontWeight.w200,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Online',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'logout') _logout();
                },
                color: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'logout',
                    child: Text('Sign Out',
                        style: GoogleFonts.inter(
                            fontSize: 13, color: const Color(0xFF0A0A0A))),
                  ),
                ],
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  child: Center(
                    child: Text(
                      (_name ?? _email ?? 'R').substring(0, 1).toUpperCase(),
                      style: GoogleFonts.commissioner(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  Widget _statsGrid() {
    return Row(
      children: [
        _statCard(
          label: 'Available',
          value: '$_availableCount',
          icon: Icons.inbox_outlined,
          color: const Color(0xFFF59E0B),
        ),
        const SizedBox(width: 10),
        _statCard(
          label: 'Active',
          value: '$_activeCount',
          icon: Icons.delivery_dining,
          color: const Color(0xFF3B82F6),
        ),
        const SizedBox(width: 10),
        _statCard(
          label: 'Delivered',
          value: '$_deliveredCount',
          icon: Icons.check_circle_outline,
          color: const Color(0xFF10B981),
        ),
        const SizedBox(width: 10),
        _statCard(
          label: 'Earnings',
          value:
              '₱${_earnings >= 1000 ? '${(_earnings / 1000).toStringAsFixed(1)}k' : _earnings.toStringAsFixed(0)}',
          icon: Icons.payments_outlined,
          color: const Color(0xFF10B981),
        ),
      ],
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 15, color: color),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: GoogleFonts.commissioner(
                fontSize: 18,
                fontWeight: FontWeight.w300,
                color: const Color(0xFF0A0A0A),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: GoogleFonts.commissioner(
                fontSize: 7,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF999999),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick actions ──────────────────────────────────────────────────────────

  Widget _quickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('QUICK ACTIONS'),
        const SizedBox(height: 12),
        _actionCard(
          icon: Icons.inbox_outlined,
          title: 'Available Orders',
          subtitle: 'Browse and accept new deliveries',
          badge: _availableCount,
          badgeColor: const Color(0xFFF59E0B),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const RiderAvailableOrdersScreen()));
            _load();
          },
        ),
        const SizedBox(height: 10),
        const SizedBox(height: 10),
        _actionCard(
          icon: Icons.map_outlined,
          title: 'Live Map',
          subtitle: 'View your location and delivery routes',
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const RiderMapScreen()));
          },
        ),
        const SizedBox(height: 10),
        _actionCard(
          icon: Icons.payments_outlined,
          title: 'My Earnings',
          subtitle: 'Track commissions and delivery history',
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    RiderEarningsScreen(riderEmail: _email!)));
          },
        ),
      ],
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    int badge = 0,
    Color badgeColor = const Color(0xFF0A0A0A),
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.commissioner(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0A0A0A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: const Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ),
            if (badge > 0) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$badge new',
                  style: GoogleFonts.commissioner(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            const Icon(Icons.arrow_forward_ios,
                size: 13, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }

  // ── Active deliveries ──────────────────────────────────────────────────────

  Widget _activeDeliveriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('MY ACTIVE DELIVERIES'),
        const SizedBox(height: 12),
        if (_activeDeliveries.isEmpty)
          _emptyDeliveries()
        else
          ..._activeDeliveries
              .map((o) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _deliveryCard(o),
                  ))
              .toList(),
      ],
    );
  }

  Widget _emptyDeliveries() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delivery_dining,
                size: 28, color: Color(0xFFCCCCCC)),
          ),
          const SizedBox(height: 14),
          Text(
            'No active deliveries',
            style: GoogleFonts.commissioner(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFFAAAAAA),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Accept an order to start delivering',
            style:
                GoogleFonts.inter(fontSize: 11, color: const Color(0xFFCCCCCC)),
          ),
        ],
      ),
    );
  }

  Widget _deliveryCard(Order order) {
    final statusColor =
        _statusColors[order.status] ?? const Color(0xFF888888);
    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RiderDeliveryDetailScreen(order: order)));
        _load();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child:
                  Icon(Icons.shopping_bag_outlined, size: 20, color: statusColor),
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
                  const SizedBox(height: 7),
                  _statusPill(order.status, statusColor),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₱${order.commission.toStringAsFixed(2)}',
                  style: GoogleFonts.commissioner(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF10B981),
                  ),
                ),
                Text(
                  'commission',
                  style: GoogleFonts.inter(
                      fontSize: 9, color: const Color(0xFFAAAAAA)),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios,
                size: 12, color: Color(0xFFCCCCCC)),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        Order.statusLabel(status).toUpperCase(),
        style: GoogleFonts.commissioner(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }

  Widget _sectionLabel(String title) {
    return Text(
      title,
      style: GoogleFonts.commissioner(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF888888),
        letterSpacing: 3,
      ),
    );
  }
}
