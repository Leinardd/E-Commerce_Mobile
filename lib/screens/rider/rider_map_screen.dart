import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/order.dart';
import '../../services/geocoding_service.dart';

class RiderMapScreen extends StatefulWidget {
  final Order? order;
  const RiderMapScreen({super.key, this.order});

  @override
  State<RiderMapScreen> createState() => _RiderMapScreenState();
}

class _RiderMapScreenState extends State<RiderMapScreen>
    with TickerProviderStateMixin {
  final _mapController = MapController();

  LatLng? _riderPos;
  LatLng? _dropoffPos;
  StreamSubscription<Position>? _posStream;

  bool _isOnline = true;
  bool _loadingLocation = true;
  bool _mapReady = false;
  bool _centeredOnRider = true;
  bool _geocoding = false;
  String? _locationError;

  // Default: Manila, Philippines
  static const _manila = LatLng(14.5995, 120.9842);

  @override
  void initState() {
    super.initState();
    _initLocation();
    if (widget.order != null) _geocodeDropoff();
  }

  @override
  void dispose() {
    _posStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ── Location ───────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setLocationError('Location services are disabled on this device.');
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _setLocationError(
          perm == LocationPermission.deniedForever
              ? 'Location permanently denied — enable it in Settings.'
              : 'Location permission denied.');
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _riderPos = ll;
        _loadingLocation = false;
      });
      if (_mapReady) _mapController.move(ll, 15);

      _posStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((p) {
        if (!mounted) return;
        final ll = LatLng(p.latitude, p.longitude);
        setState(() => _riderPos = ll);
        if (_centeredOnRider && _mapReady) {
          _mapController.move(ll, 15);
        }
      });
    } catch (e) {
      _setLocationError('Could not get location.');
    }
  }

  void _setLocationError(String msg) {
    if (!mounted) return;
    setState(() {
      _locationError = msg;
      _loadingLocation = false;
      _riderPos = _manila;
    });
  }

  // ── Geocoding ──────────────────────────────────────────────────────────────

  Future<void> _geocodeDropoff() async {
    final addr = widget.order?.deliveryAddress ?? '';
    if (addr.isEmpty) return;
    setState(() => _geocoding = true);
    final pos = await GeocodingService.geocode(addr);
    if (!mounted) return;
    setState(() {
      _dropoffPos = pos;
      _geocoding = false;
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _recenter() {
    final pos = _riderPos ?? _manila;
    if (_mapReady) _mapController.move(pos, 15);
    setState(() => _centeredOnRider = true);
  }

  Future<void> _openNavigation() async {
    final pos = _dropoffPos;
    if (pos == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${pos.latitude},${pos.longitude}'
      '&travelmode=driving',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildTopBar(),
          if (_locationError != null) _buildErrorBanner(),
          Positioned(
            right: 16,
            bottom: widget.order != null ? 196 : 40,
            child: Column(
              children: [
                _buildFab(
                  icon: Icons.my_location,
                  color: _centeredOnRider
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF0A0A0A),
                  onTap: _recenter,
                ),
                if (widget.order != null && _dropoffPos != null) ...[
                  const SizedBox(height: 10),
                  _buildFab(
                    icon: Icons.navigation,
                    color: const Color(0xFF10B981),
                    onTap: _openNavigation,
                  ),
                ],
              ],
            ),
          ),
          if (widget.order != null) _buildDeliveryPanel(),
        ],
      ),
    );
  }

  // ── Map ────────────────────────────────────────────────────────────────────

  Widget _buildMap() {
    final riderPos = _riderPos ?? _manila;
    final markers = <Marker>[
      _riderMarker(riderPos),
      if (_dropoffPos != null) _pinMarker(_dropoffPos!, const Color(0xFFEF4444), 'D'),
    ];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: riderPos,
        initialZoom: 14,
        maxZoom: 19,
        onMapReady: () => setState(() {
          _mapReady = true;
          if (_riderPos != null) _mapController.move(_riderPos!, 15);
        }),
        onMapEvent: (event) {
          if (event is MapEventMoveStart &&
              event.source != MapEventSource.mapController) {
            setState(() => _centeredOnRider = false);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.e_comm',
          maxZoom: 19,
        ),
        if (_riderPos != null && _dropoffPos != null)
          PolylineLayer(
            polylines: [
              Polyline(
                points: [_riderPos!, _dropoffPos!],
                strokeWidth: 3.5,
                color: const Color(0xFF3B82F6),
                isDotted: true,
              ),
            ],
          ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Marker _riderMarker(LatLng pos) => Marker(
        point: pos,
        width: 44,
        height: 44,
        child: Container(
          decoration: BoxDecoration(
            color: _isOnline ? const Color(0xFF3B82F6) : const Color(0xFF999999),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: (_isOnline
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF999999))
                    .withValues(alpha: 0.45),
                blurRadius: 14,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(Icons.navigation, color: Colors.white, size: 20),
        ),
      );

  Marker _pinMarker(LatLng pos, Color color, String label) => Marker(
        point: pos,
        width: 38,
        height: 54,
        alignment: Alignment.bottomCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            CustomPaint(
              size: const Size(14, 12),
              painter: _PinTailPainter(color),
            ),
          ],
        ),
      );

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.82),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 28),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(38, 38),
                  ),
                  icon: const Icon(Icons.arrow_back_ios_new, size: 15),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RIDER MAP',
                        style: GoogleFonts.commissioner(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 3,
                        ),
                      ),
                      Text(
                        _loadingLocation
                            ? 'Getting location…'
                            : _isOnline
                                ? 'Live tracking active'
                                : 'You are offline',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                // Online / Offline toggle
                GestureDetector(
                  onTap: () => setState(() => _isOnline = !_isOnline),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: _isOnline
                          ? const Color(0xFF10B981)
                          : Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isOnline ? 'ONLINE' : 'OFFLINE',
                          style: GoogleFonts.commissioner(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── FAB ────────────────────────────────────────────────────────────────────

  Widget _buildFab({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  // ── Error banner ───────────────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Positioned(
      top: 110,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6B35),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.location_off, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _locationError!,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _locationError = null),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  // ── Delivery panel ─────────────────────────────────────────────────────────

  Widget _buildDeliveryPanel() {
    final order = widget.order!;
    const statusColors = {
      Order.shipped:        Color(0xFF3B82F6),
      Order.outForDelivery: Color(0xFFF59E0B),
      Order.delivered:      Color(0xFF10B981),
      Order.completed:      Color(0xFF10B981),
    };
    final statusColor =
        statusColors[order.status] ?? const Color(0xFF888888);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Color(0x28000000),
              blurRadius: 24,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Order summary row
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.shopping_bag_outlined,
                      size: 22, color: statusColor),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          Order.statusLabel(order.status).toUpperCase(),
                          style: GoogleFonts.commissioner(
                            fontSize: 7,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${order.commission.toStringAsFixed(2)}',
                      style: GoogleFonts.commissioner(
                        fontSize: 17,
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
              ],
            ),

            const SizedBox(height: 14),
            Container(height: 1, color: const Color(0xFFF2F2F2)),
            const SizedBox(height: 12),

            // Drop-off address row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.location_on_outlined,
                      size: 15, color: Color(0xFFEF4444)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DROP-OFF',
                        style: GoogleFonts.commissioner(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: const Color(0xFF999999),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        order.deliveryAddress,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF333333),
                          height: 1.45,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_geocoding)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Color(0xFF3B82F6)),
                    ),
                  ),
                if (!_geocoding && _dropoffPos == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: GestureDetector(
                      onTap: _geocodeDropoff,
                      child: Text(
                        'Pin',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: const Color(0xFF3B82F6),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            if (_dropoffPos != null) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _openNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A0A0A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.navigation, size: 16),
                  label: Text(
                    'NAVIGATE',
                    style: GoogleFonts.commissioner(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Pin tail painter ────────────────────────────────────────────────────────

class _PinTailPainter extends CustomPainter {
  final Color color;
  const _PinTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
