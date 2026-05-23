import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  String? _displayName;
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
      AuthService.getUserDisplayName(),
    ]);
    if (!mounted) return;
    final orders = results[0] as List;
    setState(() {
      _email = email;
      _userRole = results[1] as UserRole;
      _displayName = results[2] as String?;
      const toShipStatuses = {Order.pending, Order.confirmed, Order.preparing};
      const toReceiveStatuses = {Order.readyForPickup, Order.shipped, Order.outForDelivery};
      _counts = {
        'purchased': orders.length,
        'to_ship':    orders.where((o) => toShipStatuses.contains(o.status)).length,
        'to_receive': orders.where((o) => toReceiveStatuses.contains(o.status)).length,
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

  Future<void> _openEditProfile() async {
    final currentName = _resolvedDisplayName ?? '';
    final parts = currentName.split(' ');
    final initialFirst = parts.isNotEmpty ? parts.first : '';
    final initialLast =
        parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        initialFirstName: initialFirst,
        initialLastName: initialLast,
      ),
    );
    if (updated == true) _load();
  }

  /// Read name directly from Supabase Auth metadata — synchronous, no await.
  String? get _resolvedDisplayName {
    if (_displayName != null && _displayName!.isNotEmpty) return _displayName;
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    if (meta != null) {
      final first = (meta['first_name'] as String?)?.trim() ?? '';
      final last  = (meta['last_name']  as String?)?.trim() ?? '';
      final full  = '$first $last'.trim();
      if (full.isNotEmpty) return full;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = _resolvedDisplayName;
    final initials = (name?.isNotEmpty == true)
        ? name!.trim().split(' ').map((w) => w.isEmpty ? '' : w[0].toUpperCase()).take(2).join()
        : (_email?.isNotEmpty == true ? _email!.substring(0, 1).toUpperCase() : '?');

    final orderItems = <Map<String, dynamic>>[
      {'icon': Icons.shopping_bag_outlined, 'label': 'PURCHASED', 'count': '${_counts['purchased'] ?? 0}'},
      {'icon': Icons.local_shipping_outlined, 'label': 'TO SHIP',    'count': '${_counts['to_ship'] ?? 0}'},
      {'icon': Icons.move_to_inbox_outlined,  'label': 'TO RECEIVE', 'count': '${_counts['to_receive'] ?? 0}'},
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
                              if (name != null) ...[
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0A0A0A),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                _email ?? '—',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF888888),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Edit profile icon
                        GestureDetector(
                          onTap: _openEditProfile,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F4F4),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.edit_outlined,
                              size: 16,
                              color: Color(0xFF555555),
                            ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Edit profile bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final String initialFirstName;
  final String initialLastName;

  const _EditProfileSheet({
    required this.initialFirstName,
    required this.initialLastName,
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  bool _saving = false;
  bool _loadingCooldown = true;
  DateTime? _nextChangeDate;

  @override
  void initState() {
    super.initState();
    _firstCtrl = TextEditingController(text: widget.initialFirstName);
    _lastCtrl  = TextEditingController(text: widget.initialLastName);
    _loadCooldown();
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCooldown() async {
    final date = await AuthService.getNameNextChangeDate();
    if (mounted) {
      setState(() {
        _nextChangeDate    = date;
        _loadingCooldown   = false;
      });
    }
  }

  bool get _onCooldown =>
      _nextChangeDate != null && DateTime.now().isBefore(_nextChangeDate!);

  Future<void> _save() async {
    if (_saving || _onCooldown) return;
    setState(() => _saving = true);
    final err = await AuthService.updateDisplayName(
      _firstCtrl.text,
      _lastCtrl.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: const Color(0xFF0A0A0A),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        margin: const EdgeInsets.all(16),
      ));
    } else {
      Navigator.of(context).pop(true); // signal reload
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'EDIT PROFILE',
            style: GoogleFonts.commissioner(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              color: const Color(0xFF0A0A0A),
            ),
          ),
          const SizedBox(height: 4),
          Container(width: 24, height: 1, color: const Color(0xFF0A0A0A)),
          const SizedBox(height: 20),

          // Cooldown banner
          if (_loadingCooldown)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF0A0A0A),
                  ),
                ),
              ),
            )
          else if (_onCooldown) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_clock_outlined,
                      size: 16, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Name change is locked.\nYou can update again on ${_formatDate(_nextChangeDate!.toLocal())}.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF92400E),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // First name
          _Field(
            label: 'FIRST NAME',
            controller: _firstCtrl,
            enabled: !_onCooldown && !_saving,
          ),
          const SizedBox(height: 14),

          // Last name
          _Field(
            label: 'LAST NAME',
            controller: _lastCtrl,
            enabled: !_onCooldown && !_saving,
          ),
          const SizedBox(height: 6),

          // 31-day note
          if (!_onCooldown)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'You can only change your name once every 31 days.',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: const Color(0xFFAAAAAA),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _onCooldown || _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A0A0A),
                disabledBackgroundColor: const Color(0xFFCCCCCC),
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'SAVE CHANGES',
                      style: GoogleFonts.commissioner(
                        fontSize: 10,
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

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;

  const _Field({
    required this.label,
    required this.controller,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.commissioner(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
            color: const Color(0xFF999999),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF0A0A0A),
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFDDDDDD)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFF0A0A0A)),
            ),
            disabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFEEEEEE)),
            ),
            filled: !enabled,
            fillColor: const Color(0xFFF8F8F8),
          ),
        ),
      ],
    );
  }
}
