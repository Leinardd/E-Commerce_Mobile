import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
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
  final _profileKey = GlobalKey<BuyerProfileScreenState>();

  @override
  void initState() {
    super.initState();
    _ensureCartLoaded();
  }

  // Safety net: if the Supabase session was auto-restored on app restart
  // without going through the login screen, _currentUserEmail is null and
  // addToCart would silently skip persisting. Load the cart here so the
  // singleton is always ready when the buyer screen is first shown.
  Future<void> _ensureCartLoaded() async {
    final cart = CartService();
    if (cart.currentUserEmail != null) return; // already loaded by login flow
    final email = await AuthService.getUserEmail();
    if (email != null) await cart.loadForUser(email);
  }

  void _onTabTap(int i) {
    setState(() => _index = i);
    if (i == 2) {
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
          BuyerProfileScreen(key: _profileKey),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _index,
        onTap: _onTabTap,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.currentIndex, required this.onTap});

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
        items: const [
          BottomNavigationBarItem(
            icon: _NavIcon(icon: Icons.home_outlined),
            activeIcon: _NavIcon(icon: Icons.home),
            label: 'HOME',
          ),
          BottomNavigationBarItem(
            icon: _NavIcon(icon: Icons.storefront_outlined),
            activeIcon: _NavIcon(icon: Icons.storefront),
            label: 'SHOP',
          ),
          BottomNavigationBarItem(
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
