import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/chat_service.dart';
import 'buyer_chat_list_screen.dart';
import 'home_screen.dart';
import 'shop_screen.dart';
import 'buyer_profile_screen.dart';

class BuyerMainScreen extends StatefulWidget {
  const BuyerMainScreen({super.key});

  @override
  State<BuyerMainScreen> createState() => _BuyerMainScreenState();
}

class _BuyerMainScreenState extends State<BuyerMainScreen> {
  int _index = 0;
  int _unreadCount = 0;
  String? _email;
  Timer? _unreadTimer;
  final _profileKey = GlobalKey<BuyerProfileScreenState>();

  @override
  void initState() {
    super.initState();
    _ensureCartLoaded();
    _startUnreadPolling();
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    super.dispose();
  }

  // Safety net: if the Supabase session was auto-restored on app restart
  // without going through the login screen, _currentUserEmail is null and
  // addToCart would silently skip persisting. Load the cart here so the
  // singleton is always ready when the buyer screen is first shown.
  Future<void> _ensureCartLoaded() async {
    final cart = CartService();
    if (cart.currentUserEmail != null) return;
    final email = await AuthService.getUserEmail();
    if (email != null) {
      await cart.loadForUser(email);
      if (mounted) setState(() => _email = email);
    }
  }

  void _startUnreadPolling() {
    _refreshUnread();
    // Poll every 30 seconds so the badge stays fresh without a full Realtime
    // subscription here (conversation screen handles per-room realtime).
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshUnread();
    });
  }

  Future<void> _refreshUnread() async {
    final email = _email ?? await AuthService.getUserEmail();
    if (email == null) return;
    if (_email == null && mounted) setState(() => _email = email);
    final count = await ChatService().getBuyerTotalUnread(email);
    if (mounted) setState(() => _unreadCount = count);
  }

  void _onTabTap(int i) {
    setState(() => _index = i);
    if (i == 2) {
      // Messages tab: reset badge immediately when opened
      setState(() => _unreadCount = 0);
    }
    if (i == 3) {
      // Profile tab: always reload so order counts reflect latest data.
      _profileKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: _index,
        children: [
          const HomeScreen(),
          const ShopScreen(),
          const BuyerChatListScreen(),
          BuyerProfileScreen(key: _profileKey),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _index,
        onTap: _onTabTap,
        unreadCount: _unreadCount,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadCount;

  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: onTap,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF0A0A0A),
        unselectedItemColor: const Color(0xFFAAAAAA),
        selectedLabelStyle: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        items: [
          const BottomNavigationBarItem(
            icon: _NavIcon(icon: Icons.home_outlined),
            activeIcon: _NavIcon(icon: Icons.home),
            label: 'HOME',
          ),
          const BottomNavigationBarItem(
            icon: _NavIcon(icon: Icons.storefront_outlined),
            activeIcon: _NavIcon(icon: Icons.storefront),
            label: 'SHOP',
          ),
          BottomNavigationBarItem(
            icon: _BadgeIcon(
              icon: Icons.chat_bubble_outline,
              count: unreadCount,
            ),
            activeIcon: _BadgeIcon(
              icon: Icons.chat_bubble,
              count: unreadCount,
            ),
            label: 'MESSAGES',
          ),
          const BottomNavigationBarItem(
            icon: _NavIcon(icon: Icons.person_outline),
            activeIcon: _NavIcon(icon: Icons.person),
            label: 'PROFILE',
          ),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  const _NavIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Icon(icon, size: 22),
    );
  }
}

class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  const _BadgeIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, size: 22),
          if (count > 0)
            Positioned(
              top: -4,
              right: -6,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Color(0xFF0A0A0A),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 7,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
