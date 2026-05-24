import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import 'io_shim.dart' if (dart.library.html) 'io_shim_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RiderAuthService {
  static const _currentRiderKey       = 'current_rider_email';
  static const _currentRiderIdKey     = 'current_rider_id';
  static const _currentRiderUserIdKey = 'current_rider_user_id';

  static SupabaseClient get _db => Supabase.instance.client;

  // ─── Session ───────────────────────────────────────────────────────────────

  static Future<bool> isLoggedIn() async {
    return (await getCurrentRiderEmail()) != null;
  }

  static Future<String?> getCurrentRiderEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentRiderKey);
  }

  static Future<int?> getCurrentRiderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentRiderIdKey);
  }

  static Future<int?> getCurrentRiderUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentRiderUserIdKey);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentRiderKey);
    await prefs.remove(_currentRiderIdKey);
    await prefs.remove(_currentRiderUserIdKey);
    try {
      await _db.auth.signOut();
    } catch (_) {}
  }

  // ─── Register ──────────────────────────────────────────────────────────────

  /// Creates a new rider user + rider profile in Supabase using Auth.
  /// Returns null on success, or an error message string on failure.
  static Future<String?> register({
    required String email,
    required String password,
    required String fullName,
    required String phoneNumber,
    required String address,
    required String driversLicense,
  }) async {
    developer.log('Starting rider registration for: $email');

    if (password.length < 6) {
      return 'Password must be at least 6 characters long.';
    }
    
    try {
      final authResponse = await _db.auth.signUp(
        email: email.trim(),
        password: password,
      );

      final userId = authResponse.user?.id;
      if (userId == null) {
        developer.log('ERROR: User ID is null after signup response!');
        return 'Signup succeeded but no auth user ID was returned. Check your email confirmation settings.';
      }

      developer.log('Auth signup successful for: $email');

      // Step 3: Split fullName
      final parts = fullName.trim().split(' ');
      final firstName = parts.first;
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      developer.log('Creating user profile for rider: $email');

      // Step 4: Create user profile in database
      try {
        final userResult = await _db.from('users').insert({
          'email': email.trim(),
          'auth_user_id': userId,
          'first_name': firstName,
          'last_name': lastName,
          'phone': phoneNumber.trim(),
          'role': 'rider',
          'account_status': 'active',
          'buyer_approval_status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        }).select('id').single();

        developer.log('User profile created successfully');

        final userIntId = userResult['id'] as int;

        // Step 5: Create rider profile
        final riderResult = await _db.from('riders').insert({
          'user_id': userIntId,
          'auth_user_id': userId,
          'license_number': driversLicense.trim(),
          'vehicle_type': 'motorcycle',
          'address': address.trim(),
          'status': 'pending',
        }).select('id').single();

        developer.log('Rider profile created successfully');

        // Step 6: Save to local preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_currentRiderKey, email.trim());
        await prefs.setInt(_currentRiderIdKey, riderResult['id'] as int);
        await prefs.remove(_currentRiderUserIdKey);

        developer.log('Rider registration completed successfully');
        return null;
      } on AuthException catch (e) {
        developer.log('Auth signup error: ${e.message} (code: ${e.statusCode})');
        developer.log('Full exception: ${e.toString()}');
        if (e.statusCode == '429' ||
            e.message.toLowerCase().contains('rate limit') ||
            e.message.toLowerCase().contains('too many requests')) {
          return 'Supabase is limiting signup emails right now. Wait a few minutes or disable email confirmation in Supabase Auth for development.';
        }
        if (e.message.toLowerCase().contains('already registered')) {
          return 'This email is already registered.';
        }
        if (e.message.toLowerCase().contains('password') || e.message.toLowerCase().contains('weak')) {
          return 'Password is too weak. Use at least 6 characters.';
        }
        return 'Registration failed: ${e.message}';
      } on PostgrestException catch (e) {
        developer.log('Profile creation error: ${e.message}');
        
        return 'Failed to create rider profile. ${e.message}';
      }
    } on SocketException catch (e) {
      developer.log('Network error during rider registration: $e');
      return 'Network error. Check your internet connection and try again.';
    } catch (e, stackTrace) {
      developer.log('Unexpected rider registration error: $e\n$stackTrace');
      return 'Registration failed: An unexpected error occurred.';
    }
  }

  // ─── Login ─────────────────────────────────────────────────────────────────

  /// Returns null on success, or an error message string on failure.
  /// Uses Supabase Auth for proper authentication instead of table-based passwords.
  static Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      final authResponse = await _db.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final authUser = authResponse.user;
      if (authUser == null) {
        return 'Login failed: No user returned from authentication.';
      }

      // Get user profile from database to verify role and check account status
      final user = await _db
          .from('users')
          .select('id, email, account_status, role')
          .eq('auth_user_id', authUser.id)
          .eq('role', 'rider')
          .maybeSingle();

      if (user == null) return 'No rider profile found for this account.';
      if (user['account_status'] == 'banned') return 'Your account has been banned.';

      // Get rider profile status
      final rider = await _db
          .from('riders')
          .select('id, status')
          .eq('user_id', user['id'])
          .maybeSingle();

      if (rider == null) return 'No rider profile found for this account.';
      if (rider['status'] == 'pending') return 'Your rider account is pending approval.';
      if (rider['status'] == 'suspended') return 'Your rider account has been suspended.';

      // Save session to local preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentRiderKey, email.trim());
      await prefs.setInt(_currentRiderIdKey, rider['id'] as int);
      await prefs.setInt(_currentRiderUserIdKey, user['id'] as int);

      developer.log('Rider login successful for: $email');
      return null;
    } on AuthException catch (e) {
      developer.log('Auth login error: ${e.message} (code: ${e.statusCode})');
      if (e.message.toLowerCase().contains('invalid credentials') ||
          e.message.toLowerCase().contains('invalid login credentials')) {
        return 'Incorrect email or password.';
      }
      return 'Login failed: ${e.message}';
    } on PostgrestException catch (e) {
      developer.log('Database error during login: ${e.message}');
      return 'Failed to load profile: ${e.message}';
    } on SocketException catch (e) {
      developer.log('Network error during login: $e');
      return 'Network error. Check your internet connection and try again.';
    } catch (e, stackTrace) {
      developer.log('Unexpected login error: $e\n$stackTrace');
      return 'Login failed: An unexpected error occurred.';
    }
  }

  /// Syncs rider session keys from the current Supabase auth session.
  /// Call this after unified login to populate SharedPreferences for the rider dashboards.
  /// Returns rider status ('approved', 'pending', 'suspended') or null on failure.
  static Future<String?> syncSession() async {
    try {
      final session = _db.auth.currentSession;
      if (session == null) return null;

      final email = session.user.email;
      if (email == null) return null;

      final user = await _db
          .from('users')
          .select('id')
          .eq('auth_user_id', session.user.id)
          .maybeSingle();
      if (user == null) return null;

      final rider = await _db
          .from('riders')
          .select('id, status')
          .eq('user_id', user['id'] as int)
          .maybeSingle();
      if (rider == null) return null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentRiderKey, email);
      await prefs.setInt(_currentRiderIdKey, rider['id'] as int);
      await prefs.setInt(_currentRiderUserIdKey, user['id'] as int);

      developer.log('Rider session synced for: $email (status: ${rider['status']})');
      return rider['status'] as String? ?? 'pending';
    } catch (e) {
      developer.log('Error syncing rider session: $e');
      return null;
    }
  }

  // ─── Apply from existing buyer account ────────────────────────────────────

  /// Upgrades the currently logged-in buyer account to rider role.
  /// Updates users.role to 'rider' and creates a riders row (status='pending').
  /// Returns null on success, or an error message string on failure.
  static Future<String?> applyAsRider({
    required String fullName,
    required String phoneNumber,
    required String address,
    required String driversLicense,
    String? licenseImageUrl,
  }) async {
    try {
      final session = _db.auth.currentSession;
      if (session == null) return 'You must be logged in to apply as a rider.';

      final authUid = session.user.id;

      final userRow = await _db
          .from('users')
          .select('id')
          .eq('auth_user_id', authUid)
          .maybeSingle();

      if (userRow == null) return 'User profile not found.';
      final userId = userRow['id'] as int;

      final existing = await _db
          .from('riders')
          .select('id, status')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        final s = existing['status'] as String;
        if (s == 'pending') return 'Your rider application is already pending review.';
        if (s == 'approved') return 'You already have an active rider account.';
        if (s == 'suspended') return 'Your rider account has been suspended.';
      }

      final parts = fullName.trim().split(' ');

      await _db.from('users').update({
        'role': 'rider',
        'first_name': parts.first,
        'last_name': parts.length > 1 ? parts.sublist(1).join(' ') : '',
        'phone': phoneNumber.trim(),
      }).eq('id', userId);

      await _db.from('riders').insert({
        'user_id': userId,
        'auth_user_id': authUid,
        'license_number': driversLicense.trim(),
        'vehicle_type': 'motorcycle',
        'address': address.trim(),
        'status': 'pending',
        if (licenseImageUrl != null) 'license_image_url': licenseImageUrl,
      });

      developer.log('Rider application submitted for: ${session.user.email}');
      return null;
    } on PostgrestException catch (e) {
      developer.log('Rider application error: ${e.message}');
      return 'Application failed: ${e.message}';
    } catch (e) {
      developer.log('Unexpected rider application error: $e');
      return 'Application failed. Please try again.';
    }
  }

  // ─── Profile ───────────────────────────────────────────────────────────────

  /// Returns the rider row from the riders table, or null if not found.
  static Future<Map<String, dynamic>?> getProfile(String email) async {
    try {
      final user = await _db
          .from('users')
          .select('id')
          .eq('email', email.trim())
          .maybeSingle();
      if (user == null) return null;

      return await _db
          .from('riders')
          .select()
          .eq('user_id', user['id'])
          .maybeSingle();
    } catch (e) {
      developer.log('Error fetching rider profile: $e');
      return null;
    }
  }

  static Future<String?> getFullName(String email) async {
    try {
      final user = await _db
          .from('users')
          .select('first_name, last_name')
          .eq('email', email.trim())
          .maybeSingle();
      if (user == null) return null;
      return '${user['first_name']} ${user['last_name']}';
    } catch (e) {
      developer.log('Error fetching rider full name: $e');
      return null;
    }
  }
}
