import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/seller_auth_service.dart';

class SellerApplicationFormScreen extends StatefulWidget {
  const SellerApplicationFormScreen({super.key});

  @override
  State<SellerApplicationFormScreen> createState() =>
      _SellerApplicationFormScreenState();
}

class _SellerApplicationFormScreenState
    extends State<SellerApplicationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameCtrl = TextEditingController();
  final _storeNameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  XFile?    _validIdFile;
  Uint8List? _validIdBytes;

  bool _submitting = false;
  bool _submitted  = false;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _storeNameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickId() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _validIdFile  = file;
      _validIdBytes = bytes;
    });
  }

  Future<String?> _uploadValidId(String authUid) async {
    if (_validIdBytes == null || _validIdFile == null) return null;
    try {
      final ext  = _validIdFile!.path.split('.').last.toLowerCase();
      final path = '$authUid/valid_id_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supabase.instance.client.storage
          .from('seller-ids')
          .uploadBinary(
            path,
            _validIdBytes!,
            fileOptions: const FileOptions(upsert: true),
          );
      return Supabase.instance.client.storage
          .from('seller-ids')
          .getPublicUrl(path);
    } catch (e) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_validIdFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload a valid ID to continue.'),
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
    final validIdUrl = session != null
        ? await _uploadValidId(session.user.id)
        : null;

    final error = await SellerAuthService.applyAsSeller(
      storeName: _storeNameCtrl.text.trim(),
      fullName: _fullNameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phoneNumber: _phoneCtrl.text.trim(),
      validIdUrl: validIdUrl,
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
          'BECOME A SELLER',
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
              child: const Icon(Icons.storefront_outlined,
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
              'Your seller application is pending admin review. '
              'Log in again to check your application status.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF666666),
                height: 1.7,
              ),
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
              'Apply to sell on Varón. Your application will be reviewed '
              'by our team before your seller account is activated.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF666666),
                height: 1.7,
              ),
            ),
            const SizedBox(height: 32),

            // ── Store Information ─────────────────────────────────────────
            _sectionLabel('STORE INFORMATION'),
            const SizedBox(height: 16),
            _field(
              label: 'STORE NAME',
              controller: _storeNameCtrl,
              hint: 'Your shop name as displayed to buyers',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Store name is required' : null,
            ),

            const SizedBox(height: 32),

            // ── Personal Information ──────────────────────────────────────
            _sectionLabel('PERSONAL INFORMATION'),
            const SizedBox(height: 16),
            _field(
              label: 'FULL NAME',
              controller: _fullNameCtrl,
              hint: 'e.g. Juan dela Cruz',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
            ),
            const SizedBox(height: 16),
            _field(
              label: 'ADDRESS',
              controller: _addressCtrl,
              hint: 'Street, City, Province',
              maxLines: 2,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Address is required' : null,
            ),
            const SizedBox(height: 16),
            _field(
              label: 'PHONE NUMBER',
              controller: _phoneCtrl,
              hint: 'e.g. 09XXXXXXXXX',
              keyboardType: TextInputType.phone,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Phone number is required';
                if (v.trim().length < 10) return 'Enter a valid phone number';
                return null;
              },
            ),

            const SizedBox(height: 32),

            // ── Valid ID ──────────────────────────────────────────────────
            _sectionLabel('VALID ID'),
            const SizedBox(height: 8),
            const Text(
              'Upload any government-issued ID (e.g. PhilSys, Driver\'s License, Passport)',
              style: TextStyle(fontSize: 11, color: Color(0xFF888888), height: 1.55),
            ),
            const SizedBox(height: 14),
            _idUploadBox(),

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
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
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

  Widget _idUploadBox() {
    if (_validIdBytes != null) {
      return Stack(
        children: [
          Container(
            width: double.infinity,
            height: 190,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF0A0A0A)),
            ),
            child: Image.memory(_validIdBytes!, fit: BoxFit.cover),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => setState(() {
                _validIdFile  = null;
                _validIdBytes = null;
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
      onTap: _pickId,
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
            Icon(Icons.upload_file_outlined, size: 34, color: Color(0xFFAAAAAA)),
            SizedBox(height: 10),
            Text(
              'TAP TO UPLOAD VALID ID',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: Color(0xFFAAAAAA),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'JPG or PNG • max 10 MB',
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
