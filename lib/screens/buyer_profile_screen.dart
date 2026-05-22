import 'package:flutter/material.dart';
import '../models/order.dart';
import '../services/auth_service.dart';
import '../services/order_service.dart';
import '../services/unified_auth_service.dart';
import 'buyer_orders_screen.dart';
import 'rider/rider_dashboard_screen.dart';
import 'rider_application_form_screen.dart';
import 'seller/seller_dashboard_screen.dart';
import 'seller_application_form_screen.dart';

class BuyerProfileScreen extends StatefulWidget {
  const BuyerProfileScreen({super.key});

  @override
  State<BuyerProfileScreen> createState() => BuyerProfileScreenState();
}

class BuyerProfileScreenState extends State<BuyerProfileScreen> {
  void reload() => _load();
  String? _email;
  Map<String, int> _counts = {};
  UserRole _userRole = UserRole.buyer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final email = await AuthService.getUserEmail();
    if (email == null || !mounted) {
      setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      OrderService.getByBuyer(email),
      UnifiedAuthService.getUserRole(),
    ]);
    if (!mounted) return;
    final orders = results[0] as List;
    setState(() {
      _email = email;
      _userRole = results[1] as UserRole;
      _counts = {
        'purchased': orders.length,
        Order.toShip: orders.where((o) => o.status == Order.toShip).length,
        Order.toReceive: orders.where((o) => o.status == Order.toReceive).length,
      };
      _loading = false;
    });
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
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  Future<void> _openSellerApplication() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SellerApplicationFormScreen()),
    );
  }

  Future<void> _openRiderApplication() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RiderApplicationFormScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initials = (_email?.isNotEmpty == true)
        ? _email!.substring(0, 1).toUpperCase()
        : '?';

    final orderItems = <Map<String, dynamic>>[
      {'icon': Icons.shopping_bag_outlined, 'label': 'PURCHASED', 'count': '${_counts['purchased'] ?? 0}'},
      {'icon': Icons.local_shipping_outlined, 'label': 'TO SHIP', 'count': '${_counts[Order.toShip] ?? 0}'},
      {'icon': Icons.move_to_inbox_outlined, 'label': 'TO RECEIVE', 'count': '${_counts[Order.toReceive] ?? 0}'},
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'MY ACCOUNT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: Color(0xFF0A0A0A),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFEEEEEE), height: 1),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFF0A0A0A),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFF0A0A0A),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // ── Avatar + email ────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          color: const Color(0xFF0A0A0A),
                          child: Center(
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ACCOUNT',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF999999),
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _email ?? '—',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF0A0A0A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),

                  // ── Order status counts ───────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ORDER STATUS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0A0A0A),
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(width: 24, height: 1, color: const Color(0xFF0A0A0A)),
                        const SizedBox(height: 28),
                        Row(
                          children: orderItems
                              .map(
                                (item) => Expanded(
                                  child: GestureDetector(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const BuyerOrdersScreen(),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          item['count'] as String,
                                          style: const TextStyle(
                                            fontSize: 26,
                                            fontWeight: FontWeight.w300,
                                            color: Color(0xFF0A0A0A),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Icon(
                                          item['icon'] as IconData,
                                          size: 20,
                                          color: const Color(0xFF0A0A0A),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item['label'] as String,
                                          style: const TextStyle(
                                            fontSize: 7,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF888888),
                                            letterSpacing: 1,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),

                  // ── Actions ───────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: _ProfileAction(
                      icon: Icons.receipt_long_outlined,
                      label: 'VIEW ALL ORDERS',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BuyerOrdersScreen(),
                        ),
                      ),
                    ),
                  ),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: _buildSellerSection(),
                  ),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    child: _buildRiderSection(),
                  ),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),

                  // ── Sign out ──────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: _logout,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: Color(0xFF0A0A0A), width: 1),
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero),
                        ),
                        child: const Text(
                          'SIGN OUT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.5,
                            color: Color(0xFF0A0A0A),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSellerSection() {
    if (_userRole == UserRole.seller) {
      return _ProfileAction(
        icon: Icons.storefront_outlined,
        label: 'SELLER DASHBOARD',
        dark: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SellerDashboardScreen()),
        ),
      );
    }
    return _ProfileAction(
      icon: Icons.storefront_outlined,
      label: 'APPLY AS SELLER',
      onTap: _openSellerApplication,
    );
  }

  Widget _buildRiderSection() {
    if (_userRole == UserRole.rider) {
      return _ProfileAction(
        icon: Icons.delivery_dining,
        label: 'RIDER DASHBOARD',
        dark: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const RiderDashboardScreen()),
        ),
      );
    }
    return _ProfileAction(
      icon: Icons.delivery_dining,
      label: 'APPLY AS RIDER',
      onTap: _openRiderApplication,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable action row
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool dark;
  final VoidCallback onTap;

  const _ProfileAction({
    required this.icon,
    required this.label,
    this.dark = false,
    required this.onTap,
  });

  @override
  State<_ProfileAction> createState() => _ProfileActionState();
}

class _ProfileActionState extends State<_ProfileAction> {
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
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: fg,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios,
                size: 11,
                color: widget.dark
                    ? const Color(0xFF888888)
                    : const Color(0xFFAAAAAA),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
