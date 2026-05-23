import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/order.dart';
import '../../services/notification_service.dart';
import '../../services/order_service.dart';
import '../../services/seller_auth_service.dart';
import '../../services/seller_product_service.dart';
import '../../services/unified_auth_service.dart';
import '../../services/chat_service.dart';
import 'seller_chat_inbox_screen.dart';
import 'seller_notifications_screen.dart';
import 'seller_orders_screen.dart';
import 'seller_products_screen.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  String? _email;
  String? _storeName;
  int _productCount = 0;
  Map<String, int> _statusCounts = {};
  double _revenue = 0;
  List<Order> _recentOrders = [];
  bool _loading = true;
  int _unreadNotifications = 0;
  int _chatUnreadCount = 0;

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
    final role = await UnifiedAuthService.getUserRole();
    if (role != UserRole.seller) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          role == UserRole.none ? '/login' : '/unauthorized',
          arguments: 'You do not have seller access.',
        );
      }
      return;
    }

    final email = await SellerAuthService.getCurrentSellerEmail();
    if (email == null) {
      final status = await SellerAuthService.syncSession();
      if (status == null) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
    }

    final resolvedEmail =
        email ?? await SellerAuthService.getCurrentSellerEmail();
    if (resolvedEmail == null) {
      if (mounted) Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    final results = await Future.wait([
      SellerAuthService.getStoreName(resolvedEmail),
      SellerProductService.getByEmail(resolvedEmail),
      OrderService.sellerStatusCounts(resolvedEmail),
      OrderService.sellerRevenue(resolvedEmail),
      OrderService.getBySeller(resolvedEmail),
      NotificationService.getUnreadCount(),
      ChatService().getSellerTotalUnread(resolvedEmail),
    ]);

    if (!mounted) return;
    setState(() {
      _email = resolvedEmail;
      _storeName = results[0] as String?;
      _productCount = (results[1] as List).length;
      _statusCounts = results[2] as Map<String, int>;
      _revenue = results[3] as double;
      _recentOrders = (results[4] as List<Order>).take(5).toList();
      _unreadNotifications = results[5] as int;
      _chatUnreadCount = results[6] as int;
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
      await SellerAuthService.logout();
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F3F0),
      appBar: _buildAppBar(),
      body: _loading ? _loadingView() : _body(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0A0A0A),
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VARÓN',
            style: GoogleFonts.commissioner(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w300,
              letterSpacing: 6,
            ),
          ),
          Text(
            'SELLER PORTAL',
            style: GoogleFonts.commissioner(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 7,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.5,
            ),
          ),
        ],
      ),
      actions: [
        // Notifications bell
        GestureDetector(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(
                builder: (_) => const SellerNotificationsScreen(),
              ))
              .then((_) => _load()),
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.notifications_none_outlined,
                    color: Colors.white, size: 22),
                if (_unreadNotifications > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEF4444),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _unreadNotifications > 9
                              ? '9+'
                              : '$_unreadNotifications',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'logout') _logout();
          },
          color: Colors.white,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'logout',
              child: Text(
                'Sign Out',
                style: GoogleFonts.inter(
                    fontSize: 13, color: const Color(0xFF0A0A0A)),
              ),
            ),
          ],
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
            ),
            child: Center(
              child: Text(
                (_storeName ?? _email ?? '?').substring(0, 1).toUpperCase(),
                style: GoogleFonts.commissioner(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _loadingView() {
    return const Center(
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        color: Color(0xFF0A0A0A),
      ),
    );
  }

  Widget _body() {
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF0A0A0A),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _storeCard(),
            const SizedBox(height: 16),
            _statsRow(),
            const SizedBox(height: 24),
            _sectionLabel('ORDER STATUS'),
            const SizedBox(height: 12),
            _orderStatusCard(),
            const SizedBox(height: 24),
            _sectionLabel('MANAGE'),
            const SizedBox(height: 12),
            _actionCard(
              icon: Icons.inventory_outlined,
              title: 'Products',
              subtitle: 'Add, edit & manage listings',
              count: _productCount,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(
                    builder: (_) => const SellerProductsScreen(),
                  ))
                  .then((_) => _load()),
            ),
            const SizedBox(height: 10),
            _actionCard(
              icon: Icons.receipt_long_outlined,
              title: 'Orders',
              subtitle: 'View & update order status',
              count: _statusCounts[Order.pending] ?? 0,
              countLabel: 'pending',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(
                    builder: (_) => const SellerOrdersScreen(),
                  ))
                  .then((_) => _load()),
            ),
            const SizedBox(height: 10),
            _actionCard(
              icon: Icons.chat_bubble_outline,
              title: 'Chat Inbox',
              subtitle: 'Reply to buyer messages',
              count: _chatUnreadCount,
              countLabel: 'unread',
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(
                    builder: (_) => const SellerChatInboxScreen(),
                  ))
                  .then((_) => _load()),
            ),
            if (_recentOrders.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _sectionLabel('RECENT ORDERS'),
                  GestureDetector(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(
                          builder: (_) => const SellerOrdersScreen(),
                        ))
                        .then((_) => _load()),
                    child: Text(
                      'SEE ALL',
                      style: GoogleFonts.commissioner(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF888888),
                        letterSpacing: 1.5,
                        decoration: TextDecoration.underline,
                        decorationColor: const Color(0xFFCCCCCC),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _recentOrdersCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _storeCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Color(0xFF0A0A0A),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (_storeName ?? '?').substring(0, 1).toUpperCase(),
                style: GoogleFonts.commissioner(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _storeName ?? '—',
                  style: GoogleFonts.commissioner(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0A0A0A),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _email ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'ACTIVE',
              style: GoogleFonts.commissioner(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF10B981),
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    return Row(
      children: [
        _statCard(
          label: 'PRODUCTS',
          value: '$_productCount',
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFF3B82F6),
        ),
        const SizedBox(width: 10),
        _statCard(
          label: 'REVENUE',
          value: '₱${_revenue >= 1000 ? '${(_revenue / 1000).toStringAsFixed(1)}k' : _revenue.toStringAsFixed(0)}',
          icon: Icons.payments_outlined,
          color: const Color(0xFF10B981),
        ),
        const SizedBox(width: 10),
        _statCard(
          label: 'PENDING',
          value: '${_statusCounts[Order.pending] ?? 0}',
          icon: Icons.hourglass_top_outlined,
          color: const Color(0xFFF59E0B),
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
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: GoogleFonts.commissioner(
                fontSize: 20,
                fontWeight: FontWeight.w300,
                color: const Color(0xFF0A0A0A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.commissioner(
                fontSize: 7,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF999999),
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderStatusCard() {
    final statuses = [
      (Order.pending,        Icons.hourglass_top_outlined,       'PENDING'),
      (Order.confirmed,      Icons.check_outlined,               'CONFIRMED'),
      (Order.preparing,      Icons.inventory_2_outlined,         'PREPARING'),
      (Order.readyForPickup, Icons.local_shipping_outlined,      'READY'),
      (Order.completed,      Icons.check_circle_outline,         'DONE'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Row(
        children: statuses.map((s) {
          final color =
              _statusColors[s.$1] ?? const Color(0xFF888888);
          final count = _statusCounts[s.$1] ?? 0;
          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(s.$2, size: 16, color: color),
                ),
                const SizedBox(height: 8),
                Text(
                  '$count',
                  style: GoogleFonts.commissioner(
                    fontSize: 18,
                    fontWeight: FontWeight.w300,
                    color: const Color(0xFF0A0A0A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.$3,
                  style: GoogleFonts.commissioner(
                    fontSize: 6,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF999999),
                    letterSpacing: 0.8,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    int count = 0,
    String countLabel = '',
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
            if (count > 0) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count $countLabel',
                  style: GoogleFonts.commissioner(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF59E0B),
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

  Widget _recentOrdersCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: _recentOrders.asMap().entries.map((e) {
          final i = e.key;
          final o = e.value;
          return Column(
            children: [
              _orderRow(o),
              if (i < _recentOrders.length - 1)
                const Divider(
                    height: 1, indent: 16, endIndent: 16,
                    color: Color(0xFFF0F0F0)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _orderRow(Order order) {
    final color = _statusColors[order.status] ?? const Color(0xFF888888);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.productName,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF0A0A0A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  order.buyerEmail,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF999999),
                  ),
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
                '₱${order.total.toStringAsFixed(0)}',
                style: GoogleFonts.commissioner(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0A0A0A),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                Order.statusLabel(order.status).toUpperCase(),
                style: GoogleFonts.commissioner(
                  fontSize: 7,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
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
