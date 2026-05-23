import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/order.dart';
import '../models/product.dart';
import '../services/address_service.dart';
import '../services/auth_service.dart';
import '../services/cart_service.dart';
import '../services/order_service.dart';
import '../services/product_service.dart';

class CheckoutScreen extends StatefulWidget {
  final List<CartItem> selectedItems;
  const CheckoutScreen({super.key, required this.selectedItems});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  late CartService cartService;

  // Address loaded from SharedPreferences (signup address)
  Map<String, String>? _savedAddress;

  // Address that will be used for this order
  Map<String, String>? _deliveryAddress;

  bool _loadingAddress = true;

  @override
  void initState() {
    super.initState();
    cartService = CartService();
    _loadSavedAddress();
  }

  Future<void> _loadSavedAddress() async {
    // Prefer Supabase (source of truth); fall back to local SharedPreferences.
    Map<String, String>? saved = await AddressService.fetchFromSupabase();
    if (saved != null && saved.values.every((v) => v.isEmpty)) saved = null;

    if (saved != null) {
      await AddressService.saveAddress(saved); // keep local cache in sync
    } else {
      saved = await AddressService.loadAddress();
      if (saved != null && saved.values.every((v) => v.isEmpty)) saved = null;
      // If found locally but not in Supabase yet, sync it up now.
      if (saved != null) {
        await AddressService.saveToSupabase(saved);
      }
    }
    if (mounted) {
      setState(() {
        _savedAddress = saved;
        _deliveryAddress = saved;
        _loadingAddress = false;
      });
    }
  }

  bool get _isAddressSet => _deliveryAddress != null;
  bool get _isUsingSavedAddress => _deliveryAddress == _savedAddress && _savedAddress != null;
  bool get _hasChangedAddress =>
      _savedAddress != null &&
      _deliveryAddress != null &&
      _deliveryAddress != _savedAddress;

  Future<void> _showAddressSheet() async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (_) => _AddressPickerSheet(existing: _deliveryAddress),
    );
    if (result != null && mounted) {
      setState(() => _deliveryAddress = result);
      await AddressService.saveAddress(result);
      await AddressService.saveToSupabase(result);
      if (mounted) setState(() => _savedAddress = result);
    }
  }

  void _restoreSavedAddress() => setState(() => _deliveryAddress = _savedAddress);

  Future<void> _placeOrders() async {
    final addr = _deliveryAddress!;
    final addressStr = [
      addr['houseNumber'], addr['streetName'],
      addr['barangay'], addr['city'],
      addr['province'], addr['region'],
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    final buyerEmail = await AuthService.getUserEmail();
    if (buyerEmail == null) return;

    for (final item in widget.selectedItems) {
      final sellerEmail =
          await ProductService.getSellerEmailById(item.product.sellerId) ?? '';
      developer.log('[Checkout] sellerId=${item.product.sellerId}  sellerEmail=$sellerEmail');

      await OrderService.place(Order(
        sellerEmail: sellerEmail,
        buyerEmail: buyerEmail,
        productId: '${item.product.id}',
        productName: item.product.name,
        productImageUrl: item.product.imageUrl,
        unitPrice: item.product.price,
        quantity: item.quantity,
        deliveryAddress: addressStr,
        createdAt: DateTime.now(),
        status: Order.pending,
      ));
    }
    // Cart items are intentionally kept after checkout so the buyer can
    // re-order the same items without adding them again.
  }

  void _showOrderConfirmation() {
    final cartItems = widget.selectedItems;
    final totalPrice = cartItems.fold<double>(0, (sum, i) => sum + i.getTotal());
    final addr = _deliveryAddress!;
    final nav = Navigator.of(context);
    final scaffold = ScaffoldMessenger.of(context);

    final line1 = [addr['houseNumber'], addr['streetName']]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    final line2 = [addr['barangay'], addr['city']]
        .where((s) => s != null && s.isNotEmpty)
        .join(', ');
    final line3 = [addr['province'], addr['region']]
        .where((s) => s != null && s.isNotEmpty)
        .join(', ');

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: const Text(
          'ORDER SUMMARY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: Color(0xFF0A0A0A),
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ITEMS',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: Color(0xFF888888),
                ),
              ),
              const SizedBox(height: 8),
              ...cartItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0A0A0A),
                        ),
                      ),
                      if (item.selectedSize != null ||
                          item.selectedColor != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (item.selectedSize != null) item.selectedSize!,
                            if (item.selectedColor != null) item.selectedColor!,
                          ].join(' · '),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF888888),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '₱${item.product.price.toStringAsFixed(0)} × ${item.quantity}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF888888),
                            ),
                          ),
                          Text(
                            '₱${item.getTotal().toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0A0A0A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                  Text(
                    '₱${totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(height: 1, color: const Color(0xFFEEEEEE)),
              const SizedBox(height: 16),
              const Text(
                'DELIVERY ADDRESS',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: Color(0xFF888888),
                ),
              ),
              const SizedBox(height: 8),
              if (line1.isNotEmpty)
                Text(line1,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF0A0A0A))),
              if (line2.isNotEmpty)
                Text(line2,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF555555))),
              if (line3.isNotEmpty)
                Text(line3,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF555555))),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text(
              'CANCEL',
              style: TextStyle(
                  fontSize: 9, letterSpacing: 1.5, color: Color(0xFF888888)),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(dialogCtx).pop();
              try {
                await _placeOrders();
                nav.pop();
                scaffold.showSnackBar(
                  const SnackBar(
                    content: Text('Order placed successfully!'),
                    backgroundColor: Color(0xFF0A0A0A),
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                );
              } catch (e) {
                developer.log('[CheckoutScreen] _placeOrders error: $e');
                scaffold.showSnackBar(
                  SnackBar(
                    content: Text('Failed to place order: $e'),
                    backgroundColor: const Color(0xFFCC0000),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0A0A0A),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero),
            ),
            child: const Text(
              'CONFIRM ORDER',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final cartItems = widget.selectedItems;
    final totalPrice = cartItems.fold<double>(0, (sum, i) => sum + i.getTotal());

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: Color(0xFF0A0A0A), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'CHECKOUT',
          style: TextStyle(
            color: Color(0xFF0A0A0A),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
      ),
      body: cartItems.isEmpty
          ? const Center(
              child: Text(
                'Your cart is empty.',
                style: TextStyle(fontSize: 13, color: Color(0xFF999999)),
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 20 : 48,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Order Summary ────────────────────────────────
                    _sectionHeader('ORDER SUMMARY'),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFEEEEEE)),
                      ),
                      child: Column(
                        children: [
                          ...cartItems.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.product.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF0A0A0A),
                                    ),
                                  ),
                                  if (item.selectedSize != null ||
                                      item.selectedColor != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (item.selectedSize != null)
                                          item.selectedSize!,
                                        if (item.selectedColor != null)
                                          item.selectedColor!,
                                      ].join(' · '),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF888888),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '₱${item.product.price.toStringAsFixed(0)} × ${item.quantity}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF888888),
                                        ),
                                      ),
                                      Text(
                                        '₱${item.getTotal().toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0A0A0A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(height: 1, color: const Color(0xFFEEEEEE)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TOTAL',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  color: Color(0xFF0A0A0A),
                                ),
                              ),
                              Text(
                                '₱${totalPrice.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0A0A0A),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Delivery Address ─────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader('DELIVERY ADDRESS'),
                        if (_isAddressSet && !_loadingAddress)
                          GestureDetector(
                            onTap: _showAddressSheet,
                            child: const Text(
                              'CHANGE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                                color: Color(0xFF888888),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    if (_loadingAddress)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Color(0xFF0A0A0A),
                            ),
                          ),
                        ),
                      )
                    else if (!_isAddressSet)
                      _addAddressButton()
                    else
                      _addressCard(),

                    // "Restore saved address" — shown when user changed to
                    // a different address but a signup address still exists
                    if (_hasChangedAddress)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: GestureDetector(
                          onTap: _restoreSavedAddress,
                          child: const Text(
                            'Restore saved address',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF888888),
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF888888),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 40),

                    // ── Place Order ──────────────────────────────────
                    if (!_loadingAddress)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed:
                              _isAddressSet ? _showOrderConfirmation : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0A0A0A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            disabledBackgroundColor: const Color(0xFFCCCCCC),
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          child: Text(
                            _isAddressSet
                                ? 'PLACE ORDER'
                                : 'ADD ADDRESS TO CONTINUE',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _addAddressButton() {
    return GestureDetector(
      onTap: _showAddressSheet,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDDDDD)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, size: 13, color: Color(0xFF888888)),
            SizedBox(width: 8),
            Text(
              'ADD NEW ADDRESS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: Color(0xFF888888),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addressCard() {
    final addr = _deliveryAddress!;
    final line1 = [addr['houseNumber'], addr['streetName']]
        .where((s) => s != null && s.isNotEmpty)
        .join(' ');
    final line2 = [addr['barangay'], addr['city']]
        .where((s) => s != null && s.isNotEmpty)
        .join(', ');
    final line3 = [addr['province'], addr['region']]
        .where((s) => s != null && s.isNotEmpty)
        .join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: const Color(0xFFF6F6F6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "SAVED" badge — only when showing the signup address
          if (_isUsingSavedAddress)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                color: const Color(0xFF0A0A0A),
                child: const Text(
                  'SAVED',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (line1.isNotEmpty)
            Text(
              line1,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0A0A0A),
              ),
            ),
          if (line2.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              line2,
              style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
            ),
          ],
          if (line3.isNotEmpty)
            Text(
              line3,
              style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0A0A0A),
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 10),
        Container(width: 28, height: 1, color: const Color(0xFF0A0A0A)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Address picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddressPickerSheet extends StatefulWidget {
  final Map<String, String>? existing;
  const _AddressPickerSheet({this.existing});

  @override
  State<_AddressPickerSheet> createState() => _AddressPickerSheetState();
}

class _AddressPickerSheetState extends State<_AddressPickerSheet> {
  final _houseCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();

  List<dynamic> regions = [];
  List<dynamic> provinces = [];
  List<dynamic> cities = [];
  List<dynamic> barangays = [];

  String? regionCode, regionName;
  String? provinceCode, provinceName;
  String? cityCode, cityName;
  String? barangayCode, barangayName;

  bool loadingRegions = true;
  bool loadingProvinces = false;
  bool loadingCities = false;
  bool loadingBarangays = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _houseCtrl.text = e['houseNumber'] ?? '';
      _streetCtrl.text = e['streetName'] ?? '';
      regionCode = e['regionCode'];
      regionName = e['region'];
      provinceCode = e['provinceCode'];
      provinceName = e['province'];
      cityCode = e['cityCode'];
      cityName = e['city'];
      barangayCode = e['barangayCode'];
      barangayName = e['barangay'];
    }
    _load('https://psgc.gitlab.io/api/regions/', (data) {
      regions = data;
      loadingRegions = false;
    });
    if (regionCode != null) _reloadChain();
  }

  @override
  void dispose() {
    _houseCtrl.dispose();
    _streetCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String url, void Function(List<dynamic>) onSuccess) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body) as List;
        data.sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String));
        setState(() => onSuccess(data));
      }
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _reloadChain() {
    if (regionCode != null) {
      loadingProvinces = true;
      _load('https://psgc.gitlab.io/api/regions/$regionCode/provinces/',
          (data) {
        provinces = data;
        loadingProvinces = false;
      });
    }
    if (provinceCode != null) {
      loadingCities = true;
      _load(
          'https://psgc.gitlab.io/api/provinces/$provinceCode/cities-municipalities/',
          (data) {
        cities = data;
        loadingCities = false;
      });
    }
    if (cityCode != null) {
      loadingBarangays = true;
      _load(
          'https://psgc.gitlab.io/api/cities-municipalities/$cityCode/barangays/',
          (data) {
        barangays = data;
        loadingBarangays = false;
      });
    }
  }

  void _onRegionChanged(String code, String name) {
    setState(() {
      regionCode = code;
      regionName = name;
      provinceCode = provinceName = null;
      cityCode = cityName = null;
      barangayCode = barangayName = null;
      provinces = cities = barangays = [];
      loadingProvinces = true;
    });
    _load('https://psgc.gitlab.io/api/regions/$code/provinces/', (data) {
      provinces = data;
      loadingProvinces = false;
    });
  }

  void _onProvinceChanged(String code, String name) {
    setState(() {
      provinceCode = code;
      provinceName = name;
      cityCode = cityName = null;
      barangayCode = barangayName = null;
      cities = barangays = [];
      loadingCities = true;
    });
    _load(
        'https://psgc.gitlab.io/api/provinces/$code/cities-municipalities/',
        (data) {
      cities = data;
      loadingCities = false;
    });
  }

  void _onCityChanged(String code, String name) {
    setState(() {
      cityCode = code;
      cityName = name;
      barangayCode = barangayName = null;
      barangays = [];
      loadingBarangays = true;
    });
    _load(
        'https://psgc.gitlab.io/api/cities-municipalities/$code/barangays/',
        (data) {
      barangays = data;
      loadingBarangays = false;
    });
  }

  bool get _canConfirm =>
      _houseCtrl.text.trim().isNotEmpty &&
      _streetCtrl.text.trim().isNotEmpty &&
      regionCode != null &&
      provinceCode != null &&
      cityCode != null &&
      barangayCode != null;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 14, bottom: 4),
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 12, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.existing != null ? 'EDIT ADDRESS' : 'ADD NEW ADDRESS',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: Color(0xFF0A0A0A),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close,
                      size: 18, color: Color(0xFF888888)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Container(height: 1, color: const Color(0xFFEEEEEE)),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: _textField('HOUSE / UNIT NO.', _houseCtrl)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _textField('STREET NAME', _streetCtrl)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Container(height: 1, color: const Color(0xFFEEEEEE)),
                  const SizedBox(height: 8),
                  const Text(
                    'LOCATION',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _dropdown(
                    label: 'REGION',
                    loading: loadingRegions,
                    items: regions,
                    value: regionCode,
                    hint: 'Select region',
                    enabled: true,
                    onChanged: _onRegionChanged,
                  ),
                  const SizedBox(height: 24),
                  _dropdown(
                    label: 'PROVINCE',
                    loading: loadingProvinces,
                    items: provinces,
                    value: provinceCode,
                    hint: regionCode == null
                        ? 'Select region first'
                        : 'Select province',
                    enabled: regionCode != null && !loadingProvinces,
                    onChanged: _onProvinceChanged,
                  ),
                  const SizedBox(height: 24),
                  _dropdown(
                    label: 'CITY / MUNICIPALITY',
                    loading: loadingCities,
                    items: cities,
                    value: cityCode,
                    hint: provinceCode == null
                        ? 'Select province first'
                        : 'Select city',
                    enabled: provinceCode != null && !loadingCities,
                    onChanged: _onCityChanged,
                  ),
                  const SizedBox(height: 24),
                  _dropdown(
                    label: 'BARANGAY',
                    loading: loadingBarangays,
                    items: barangays,
                    value: barangayCode,
                    hint: cityCode == null
                        ? 'Select city first'
                        : 'Select barangay',
                    enabled: cityCode != null && !loadingBarangays,
                    onChanged: (code, name) => setState(() {
                      barangayCode = code;
                      barangayName = name;
                    }),
                  ),
                  if (_canConfirm) ...[
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: const Color(0xFFF6F6F6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ADDRESS PREVIEW',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: Color(0xFF888888),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_houseCtrl.text.trim()} ${_streetCtrl.text.trim()}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF0A0A0A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$barangayName, $cityName',
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF555555)),
                          ),
                          Text(
                            '$provinceName, $regionName',
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF555555)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _canConfirm
                          ? () => Navigator.of(context).pop({
                                'houseNumber': _houseCtrl.text.trim(),
                                'streetName': _streetCtrl.text.trim(),
                                'barangay': barangayName ?? '',
                                'city': cityName ?? '',
                                'province': provinceName ?? '',
                                'region': regionName ?? '',
                                'barangayCode': barangayCode ?? '',
                                'cityCode': cityCode ?? '',
                                'provinceCode': provinceCode ?? '',
                                'regionCode': regionCode ?? '',
                              })
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A0A0A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        disabledBackgroundColor: const Color(0xFFCCCCCC),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                      child: const Text(
                        'SAVE ADDRESS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Color(0xFF888888),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 14, color: Color(0xFF0A0A0A)),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.only(bottom: 8),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFDDDDDD), width: 1),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF0A0A0A), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown({
    required String label,
    required bool loading,
    required List<dynamic> items,
    required String? value,
    required String hint,
    required bool enabled,
    required void Function(String code, String name) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Color(0xFF888888),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFDDDDDD), width: 1),
            ),
          ),
          padding: const EdgeInsets.only(bottom: 2),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                )
              : DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  underline: const SizedBox(),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: enabled
                        ? const Color(0xFF888888)
                        : const Color(0xFFCCCCCC),
                  ),
                  hint: Text(
                    hint,
                    style: TextStyle(
                      fontSize: 14,
                      color: enabled
                          ? const Color(0xFFBBBBBB)
                          : const Color(0xFFDDDDDD),
                    ),
                  ),
                  disabledHint: Text(
                    hint,
                    style: const TextStyle(
                        fontSize: 14, color: Color(0xFFDDDDDD)),
                  ),
                  items: enabled
                      ? items
                          .map<DropdownMenuItem<String>>(
                            (item) => DropdownMenuItem<String>(
                              value: item['code'] as String,
                              child: Text(
                                item['name'] as String,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF0A0A0A),
                                ),
                              ),
                            ),
                          )
                          .toList()
                      : null,
                  onChanged: enabled
                      ? (code) {
                          if (code == null) return;
                          final item =
                              items.firstWhere((i) => i['code'] == code);
                          onChanged(code, item['name'] as String);
                        }
                      : null,
                ),
        ),
      ],
    );
  }
}
