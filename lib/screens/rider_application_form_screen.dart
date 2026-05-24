import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/rider_auth_service.dart';

class RiderApplicationFormScreen extends StatefulWidget {
  const RiderApplicationFormScreen({super.key});

  @override
  State<RiderApplicationFormScreen> createState() =>
      _RiderApplicationFormScreenState();
}

class _RiderApplicationFormScreenState
    extends State<RiderApplicationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();

  XFile?     _licenseFile;
  Uint8List? _licenseBytes;

  bool _submitting = false;
  bool _submitted  = false;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLicense() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _licenseFile  = file;
      _licenseBytes = bytes;
    });
  }

  Future<String?> _uploadLicense(String authUid) async {
    if (_licenseBytes == null || _licenseFile == null) return null;
    try {
      final ext  = _licenseFile!.path.split('.').last.toLowerCase();
      final path = '$authUid/license_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supabase.instance.client.storage
          .from('rider-licenses')
          .uploadBinary(
            path,
            _licenseBytes!,
            fileOptions: const FileOptions(upsert: true),
          );
      return Supabase.instance.client.storage
          .from('rider-licenses')
          .getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_licenseFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please upload a photo of your driver's license."),
          backgroundColor: Color(0xFFCC0000),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    final session = Supabase.instance.client.auth.currentSession;
    final licenseImageUrl = session != null
        ? await _uploadLicense(session.user.id)
        : null;

    final error = await RiderAuthService.applyAsRider(
      fullName: _fullNameCtrl.text.trim(),
      phoneNumber: _phoneCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      driversLicense: _licenseCtrl.text.trim(),
      licenseImageUrl: licenseImageUrl,
    );

    if (!mounted) return;

    if (error != null) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFF0A0A0A),
          behavior: SnackBarBehavior.floating,
          shape:
              const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() {
      _submitting = false;
      _submitted = true;
    });
  }

  Future<void> _logoutAndGoToLogin() async {
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
      try {
        await Supabase.instance.client.auth.signOut();
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(_submitted),
          icon: const Icon(Icons.arrow_back_ios,
              size: 16, color: Color(0xFF0A0A0A)),
        ),
        title: const Text(
          'BECOME A RIDER',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: Color(0xFF0A0A0A),
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFEEEEEE), height: 1),
        ),
      ),
      body: _submitted ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              color: const Color(0xFF0A0A0A),
              child: const Icon(Icons.delivery_dining,
                  color: Colors.white, size: 30),
            ),
            const SizedBox(height: 28),
            const Text(
              'APPLICATION SUBMITTED',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: Color(0xFF0A0A0A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Your rider application is pending admin review. '
              'Log in again to check your application status.',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF666666), height: 1.7),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _logoutAndGoToLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A0A0A),
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                ),
                child: const Text(
                  'LOG IN',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Apply to become a delivery rider on Varón. Your application '
              'will be reviewed by our team before activation.',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF666666), height: 1.7),
            ),
            const SizedBox(height: 32),

            // ── Personal Information ──────────────────────────────────────
            _sectionLabel('PERSONAL INFORMATION'),
            const SizedBox(height: 16),
            _field(
              label: 'FULL NAME',
              controller: _fullNameCtrl,
              hint: 'e.g. Juan dela Cruz',
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Full name is required'
                  : null,
            ),
            const SizedBox(height: 16),
            _field(
              label: 'PHONE NUMBER',
              controller: _phoneCtrl,
              hint: 'e.g. 09XXXXXXXXX',
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Phone number is required';
                }
                if (v.trim().length < 10) return 'Enter a valid phone number';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _field(
              label: 'ADDRESS',
              controller: _addressCtrl,
              hint: 'Street, City, Province',
              maxLines: 2,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Address is required'
                  : null,
            ),

            const SizedBox(height: 32),

            // ── Driver's License ──────────────────────────────────────────
            _sectionLabel("DRIVER'S LICENSE"),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFFFF3E0),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: Color(0xFFE65100)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A valid driver\'s license number is required to '
                      'apply as a rider. Applications without a license '
                      'number will be rejected.',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE65100),
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _field(
              label: "DRIVER'S LICENSE NUMBER",
              controller: _licenseCtrl,
              hint: 'e.g. N01-12-345678',
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return "Driver's license number is required";
                }
                if (v.trim().length < 6) {
                  return 'Enter a valid license number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            const Text(
              "DRIVER'S LICENSE PHOTO",
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: Color(0xFF555555),
              ),
            ),
            const SizedBox(height: 8),
            _licenseUploadBox(),

            const SizedBox(height: 40),
            Container(height: 1, color: const Color(0xFFEEEEEE)),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0A0A0A),
                  disabledBackgroundColor: const Color(0xFFCCCCCC),
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'SUBMIT APPLICATION',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.5,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _licenseUploadBox() {
    if (_licenseBytes != null) {
      return Stack(
        children: [
          Container(
            width: double.infinity,
            height: 190,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF0A0A0A)),
            ),
            child: Image.memory(_licenseBytes!, fit: BoxFit.cover),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => setState(() {
                _licenseFile  = null;
                _licenseBytes = null;
              }),
              child: Container(
                width: 28,
                height: 28,
                color: const Color(0xFF0A0A0A),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: _pickLicense,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFDDDDDD)),
          color: const Color(0xFFFAFAFA),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.credit_card_outlined, size: 34, color: Color(0xFFAAAAAA)),
            SizedBox(height: 10),
            Text(
              "TAP TO UPLOAD DRIVER'S LICENSE",
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: Color(0xFFAAAAAA),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Front side • JPG or PNG',
              style: TextStyle(fontSize: 10, color: Color(0xFFBBBBBB)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: Color(0xFF0A0A0A),
          ),
        ),
        const SizedBox(height: 8),
        Container(width: 24, height: 1, color: const Color(0xFF0A0A0A)),
      ],
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: Color(0xFF555555),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(fontSize: 13, color: Color(0xFF0A0A0A)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(fontSize: 13, color: Color(0xFFCCCCCC)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFFDDDDDD)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Color(0xFF0A0A0A), width: 1.5),
            ),
            errorBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Colors.redAccent, width: 1.5),
            ),
            errorStyle: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }
}
