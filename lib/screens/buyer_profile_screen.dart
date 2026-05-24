import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
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
  String? _avatarUrl;
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
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    setState(() {
      _email = email;
      _userRole = results[1] as UserRole;
      _displayName = results[2] as String?;
      _avatarUrl = meta?['avatar_url'] as String?;
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
    final initialLast = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final phone = Supabase.instance.client.auth.currentUser?.phone ?? '';

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(
        initialFirstName: initialFirst,
        initialLastName: initialLast,
        initialEmail: _email ?? '',
        initialPhone: phone,
        initialAvatarUrl: _avatarUrl ?? '',
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
                          decoration: const BoxDecoration(color: Color(0xFF0A0A0A)),
                          clipBehavior: Clip.antiAlias,
                          child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                              ? Image.network(
                                  _avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Text(initials,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                )
                              : Center(
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
  final String initialEmail;
  final String initialPhone;
  final String initialAvatarUrl;

  const _EditProfileSheet({
    required this.initialFirstName,
    required this.initialLastName,
    required this.initialEmail,
    required this.initialPhone,
    this.initialAvatarUrl = '',
  });

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;

  String? _avatarUrl;
  bool _uploadingAvatar = false;
  bool _editingEmail = false;
  bool _editingPhone = false;
  bool _savingName  = false;
  bool _savingEmail = false;
  bool _savingPhone = false;
  String? _nameError;
  String? _emailError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    _firstCtrl  = TextEditingController(text: widget.initialFirstName);
    _lastCtrl   = TextEditingController(text: widget.initialLastName);
    _emailCtrl  = TextEditingController(text: widget.initialEmail);
    _phoneCtrl  = TextEditingController(text: widget.initialPhone);
    _avatarUrl  = widget.initialAvatarUrl.isNotEmpty ? widget.initialAvatarUrl : null;
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not signed in');

      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final path = '$userId/avatar.$ext';

      await Supabase.instance.client.storage.from('avatars').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: true, contentType: 'image/$ext'),
      );

      final url = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(path);

      // Bust the cache by appending a timestamp
      final busted = '$url?t=${DateTime.now().millisecondsSinceEpoch}';

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {'avatar_url': busted}),
      );

      if (mounted) setState(() { _avatarUrl = busted; _uploadingAvatar = false; });
    } catch (e) {
      if (mounted) setState(() => _uploadingAvatar = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: const Color(0xFFCC0000),
          behavior: SnackBarBehavior.floating,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          margin: const EdgeInsets.all(16),
        ));
      }
    }
  }

  bool get _nameChanged =>
      _firstCtrl.text.trim() != widget.initialFirstName ||
      _lastCtrl.text.trim() != widget.initialLastName;

  Future<void> _saveName() async {
    if (_firstCtrl.text.trim().isEmpty) {
      setState(() => _nameError = 'First name cannot be empty.');
      return;
    }
    setState(() { _savingName = true; _nameError = null; });
    final err = await AuthService.updateDisplayName(
      _firstCtrl.text.trim(),
      _lastCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _savingName = false);
    if (err != null) {
      setState(() => _nameError = err);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _saveEmail() async {
    final newEmail = _emailCtrl.text.trim();
    if (newEmail.isEmpty) {
      setState(() => _emailError = 'Email cannot be empty.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(newEmail)) {
      setState(() => _emailError = 'Enter a valid email address.');
      return;
    }
    setState(() { _savingEmail = true; _emailError = null; });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(email: newEmail));
      if (!mounted) return;
      setState(() { _savingEmail = false; _editingEmail = false; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Confirmation link sent to your new email. Please verify to complete the change.'),
        backgroundColor: Color(0xFF0A0A0A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 5),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingEmail = false;
        _emailError = e.toString().replaceAll('AuthException: ', '');
      });
    }
  }

  Future<void> _savePhone() async {
    final phone = _phoneCtrl.text.trim();
    setState(() { _savingPhone = true; _phoneError = null; });
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(phone: phone));
      if (!mounted) return;
      setState(() { _savingPhone = false; _editingPhone = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingPhone = false;
        _phoneError = e.toString().replaceAll('AuthException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
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
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text(
              'Account Information',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF0A0A0A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Update your account details',
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF888888)),
            ),
            const SizedBox(height: 24),
            Container(height: 1, color: const Color(0xFFEEEEEE)),
            const SizedBox(height: 24),

            // ── Profile photo ──────────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                child: Stack(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF0A0A0A),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _uploadingAvatar
                          ? const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : _avatarUrl != null && _avatarUrl!.isNotEmpty
                              ? Image.network(
                                  _avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.person,
                                    size: 40,
                                    color: Colors.white54,
                                  ),
                                )
                              : const Icon(
                                  Icons.person,
                                  size: 40,
                                  color: Colors.white54,
                                ),
                    ),
                    // Camera badge
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFEEEEEE), width: 1.5),
                        ),
                        child: const Icon(Icons.camera_alt, size: 14, color: Color(0xFF0A0A0A)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                'Tap to change photo',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFAAAAAA)),
              ),
            ),
            const SizedBox(height: 24),

            // First + Last name row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _nameField('FIRST NAME', _firstCtrl)),
                const SizedBox(width: 12),
                Expanded(child: _nameField('LAST NAME', _lastCtrl)),
              ],
            ),
            if (_nameError != null) ...[
              const SizedBox(height: 6),
              Text(_nameError!, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFCC0000))),
            ],
            const SizedBox(height: 20),

            // Email row
            _labelText('EMAIL ADDRESS'),
            const SizedBox(height: 8),
            _changeRow(
              controller: _emailCtrl,
              editing: _editingEmail,
              saving: _savingEmail,
              error: _emailError,
              keyboardType: TextInputType.emailAddress,
              onChangeTap: () => setState(() { _editingEmail = true; _emailError = null; }),
              onCancelTap: () => setState(() {
                _editingEmail = false;
                _emailCtrl.text = widget.initialEmail;
                _emailError = null;
              }),
              onSaveTap: _saveEmail,
            ),
            const SizedBox(height: 20),

            // Phone row
            _labelText('PHONE NUMBER'),
            const SizedBox(height: 8),
            _changeRow(
              controller: _phoneCtrl,
              editing: _editingPhone,
              saving: _savingPhone,
              error: _phoneError,
              keyboardType: TextInputType.phone,
              hint: '+63',
              onChangeTap: () => setState(() { _editingPhone = true; _phoneError = null; }),
              onCancelTap: () => setState(() {
                _editingPhone = false;
                _phoneCtrl.text = widget.initialPhone;
                _phoneError = null;
              }),
              onSaveTap: _savePhone,
            ),
            const SizedBox(height: 28),

            // Save name button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: (_savingName || !_nameChanged) ? null : _saveName,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A0A0A),
                  disabledBackgroundColor: const Color(0xFFEEEEEE),
                  disabledForegroundColor: const Color(0xFF999999),
                  elevation: 0,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                child: _savingName
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'SAVE CHANGES',
                        style: GoogleFonts.commissioner(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: _nameChanged ? Colors.white : const Color(0xFF999999),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelText(String text) => Text(
        text,
        style: GoogleFonts.commissioner(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
          color: const Color(0xFF888888),
        ),
      );

  Widget _nameField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelText(label),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          enabled: !_savingName,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() => _nameError = null),
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0A0A0A)),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFDDDDDD)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFF0A0A0A)),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFEEEEEE)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _changeRow({
    required TextEditingController controller,
    required bool editing,
    required bool saving,
    required String? error,
    required VoidCallback onChangeTap,
    required VoidCallback onCancelTap,
    required VoidCallback onSaveTap,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: editing && !saving,
                keyboardType: keyboardType,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0A0A0A)),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: hint,
                  hintStyle: GoogleFonts.inter(fontSize: 14, color: const Color(0xFFCCCCCC)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: error != null ? const Color(0xFFCC0000) : const Color(0xFFDDDDDD)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Color(0xFF0A0A0A)),
                  ),
                  disabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Color(0xFFEEEEEE)),
                  ),
                  filled: !editing,
                  fillColor: const Color(0xFFF6F6F6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (!editing)
              _actionBtn('Change', onChangeTap, dark: true)
            else if (saving)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0A0A0A))),
              )
            else ...[
              _actionBtn('Save', onSaveTap, dark: true),
              const SizedBox(width: 6),
              _actionBtn('Cancel', onCancelTap, dark: false),
            ],
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 5),
          Text(error, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFCC0000))),
        ],
      ],
    );
  }

  Widget _actionBtn(String label, VoidCallback onTap, {required bool dark}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: dark ? const Color(0xFF0A0A0A) : const Color(0xFFF0F0F0),
        child: Text(
          label,
          style: GoogleFonts.commissioner(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: dark ? Colors.white : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }
}

