import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import 'io_shim.dart' if (dart.library.html) 'io_shim_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'address_service.dart';
import 'cart_service.dart';

class AuthService {
  static const _loginKey      = 'is_logged_in';
  static const _userEmailKey  = 'user_email';
  static const _userIdKey     = 'user_id';

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static SupabaseClient get _db => Supabase.instance.client;

  // ─── Session ───────────────────────────────────────────────────────────────

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loginKey) ?? false;
  }

  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userEmailKey);
  }

  /// Returns "First Last" — reads from Supabase Auth metadata first
  /// (set during signup), then falls back to the users table.
  static Future<String?> getUserDisplayName() async {
    // Auth metadata is always available client-side with no RLS risk.
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    if (meta != null) {
      final first = (meta['first_name'] as String?)?.trim() ?? '';
      final last  = (meta['last_name']  as String?)?.trim() ?? '';
      final full  = '$first $last'.trim();
      if (full.isNotEmpty) return full;
    }

    // Fallback: query the users table.
    final email = await getUserEmail();
    if (email == null) return null;
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('first_name, last_name')
          .eq('email', email)
          .maybeSingle();
      if (row == null) return null;
      final first = (row['first_name'] as String?)?.trim() ?? '';
      final last  = (row['last_name']  as String?)?.trim() ?? '';
      final full  = '$first $last'.trim();
      return full.isEmpty ? null : full;
    } catch (_) {
      return null;
    }
  }

  static const _nameChangedAtKey = 'name_changed_at';

  /// Returns the DateTime when the user can next change their name,
  /// or null if they can change it now.
  /// Cooldown is tracked in SharedPreferences — no SQL migration required.
  static Future<DateTime?> getNameNextChangeDate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_nameChangedAtKey);
    if (raw == null) return null;
    final last = DateTime.tryParse(raw);
    if (last == null) return null;
    final next = last.add(const Duration(days: 31));
    return DateTime.now().isBefore(next) ? next : null;
  }

  /// Updates the display name.
  /// Uses Supabase Auth updateUser (always allowed for the current user)
  /// and attempts to sync the users table. Enforces a 31-day cooldown
  /// tracked in SharedPreferences.
  static Future<String?> updateDisplayName(
      String firstName, String lastName) async {
    if (firstName.trim().isEmpty) return 'First name cannot be empty.';

    // Cooldown check
    final nextChange = await getNameNextChangeDate();
    if (nextChange != null) {
      return 'You can change your name again on '
          '${_monthName(nextChange.toLocal().month)} '
          '${nextChange.toLocal().day}, '
          '${nextChange.toLocal().year}.';
    }

    try {
      // Update Supabase Auth metadata — this always works for the signed-in user.
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: {
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
        }),
      );

      // Best-effort sync to the users table (may be blocked by RLS, that's OK).
      try {
        final email = await getUserEmail();
        if (email != null) {
          await Supabase.instance.client.from('users').update({
            'first_name': firstName.trim(),
            'last_name': lastName.trim(),
          }).eq('email', email);
        }
      } catch (_) {}

      // Record the timestamp so the cooldown kicks in.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _nameChangedAtKey, DateTime.now().toIso8601String());

      return null; // success
    } catch (e) {
      developer.log('[AuthService] updateDisplayName error: $e');
      return 'Unable to update name. Please try again.';
    }
  }

  static String _monthName(int m) => const [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ][m];

  static Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_userIdKey);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loginKey, false);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userIdKey);
    await AddressService.clearAddress();
    CartService().clearInMemory(); // clear in-memory cart; ShPrefs data kept for re-login
  }

  // ─── Login ─────────────────────────────────────────────────────────────────

  /// Returns null on success, or an error message string on failure.
  /// Uses Supabase Auth for proper authentication.
  static Future<String?> login(String email, String password) async {
    try {
      developer.log('═══════════════════════════════════════');
      developer.log('Starting LOGIN for: $email');
      developer.log('Supabase URL: ${SupabaseConfig.supabaseUrl}');
      developer.log('═══════════════════════════════════════');
      
      // STEP 1: Authenticate with Supabase Auth
      developer.log('STEP 1: Calling Supabase Auth signInWithPassword...');
      final authResponse = await _db.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final authUser = authResponse.user;
      final session = authResponse.session;
      
      developer.log('Auth Response: user=$authUser, session=$session');
      
      if (authUser == null || session == null) {
        developer.log('ERROR: Auth returned null user or session');
        return 'Login failed: Invalid auth response from Supabase.';
      }

      developer.log('✅ Auth SUCCESS! User ID: ${authUser.id}');

      // STEP 2: Try to fetch user profile from users table
      developer.log('STEP 2: Fetching user profile from users table...');
      developer.log('Query: select * from users where id=${authUser.id}');
      
      try {
        final user = await _db
            .from('users')
            .select('*')
            .eq('auth_user_id', authUser.id)
            .maybeSingle();

        if (user == null) {
          developer.log('⚠️ WARNING: User profile not found in users table');
          developer.log('Auth succeeded but profile is missing. Creating minimal profile...');
          
          // Try to create a minimal profile
          try {
            await _db.from('users').insert({
              'email': email.trim(),
              'auth_user_id': authUser.id,
              'role': 'buyer',
              'account_status': 'active',
              'buyer_approval_status': 'approved',
            });
            developer.log('✅ Created minimal user profile');
          } catch (insertError) {
            developer.log('Could not auto-create profile: $insertError');
          }
          
          // Allow login anyway
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(_loginKey, true);
          await prefs.setString(_userEmailKey, email.trim());
          await prefs.remove(_userIdKey);
          await CartService().loadForUser(email.trim());
          developer.log('✅ PARTIAL LOGIN SUCCESS (profile created or will be created later)');
          return null;
        }

        developer.log('✅ Profile found: $user');
        
        final accountStatus = user['account_status'];
        if (accountStatus == 'banned') {
          developer.log('❌ Account is BANNED');
          return 'Your account has been banned.';
        }

        // STEP 3: Save to SharedPreferences
        developer.log('STEP 3: Saving session to SharedPreferences...');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_loginKey, true);
        await prefs.setString(_userEmailKey, email.trim());
        
        // Try to save numeric ID if it exists
        if (user['id'] != null) {
          try {
            // If id is a string UUID, don't save as int
            if (user['id'] is String) {
              await prefs.setString('${_userIdKey}_uuid', user['id']);
            } else if (user['id'] is int) {
              await prefs.setInt(_userIdKey, user['id']);
            }
          } catch (_) {
            // Ignore if we can't save the ID
          }
        }

        await CartService().loadForUser(email.trim());
        developer.log('═══════════════════════════════════════');
        developer.log('✅ LOGIN SUCCESSFUL!');
        developer.log('Email: $email');
        developer.log('User ID: ${authUser.id}');
        developer.log('═══════════════════════════════════════');
        return null;
        
      } on PostgrestException catch (e) {
        developer.log('❌ Database error during profile fetch');
        developer.log('Code: ${e.code}');
        developer.log('Message: ${e.message}');
        developer.log('Details: ${e.details}');
        developer.log('Full exception: ${e.toString()}');
        
        // Allow login anyway - profile table may not exist or RLS may block it
        developer.log('⚠️ Allowing login despite database error');
        developer.log('User authenticated successfully - this is just a profile fetch issue');
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_loginKey, true);
        await prefs.setString(_userEmailKey, email.trim());
        await prefs.remove(_userIdKey);
        await CartService().loadForUser(email.trim());
        return null; // Allow login to proceed
      }
      
    } on AuthException catch (e) {
      developer.log('❌ Supabase Auth Exception');
      developer.log('Status Code: ${e.statusCode}');
      developer.log('Message: ${e.message}');
      developer.log('Full exception: ${e.toString()}');

      final msg = e.message.toLowerCase();

      if (e.statusCode == '404' ||
          msg.contains('404') ||
          msg.contains('empty response')) {
        return 'Cannot reach Supabase. Your project may be paused — '
            'go to supabase.com/dashboard and restore it, then try again.';
      }

      if (e.statusCode == '401' ||
          msg.contains('invalid login credentials') ||
          msg.contains('invalid credentials')) {
        return 'Email or password is incorrect.';
      }

      if (msg.contains('invalid api key') || msg.contains('apikey')) {
        return 'Invalid API key. Open supabase.com/dashboard → Settings → API '
            'and copy the anon public key into your .env file.';
      }

      if (msg.contains('user not found')) {
        return 'No account found with this email.';
      }

      if (msg.contains('email not confirmed')) {
        return 'Please confirm your email before logging in.';
      }

      return 'Login failed: ${e.message}';
      
    } on SocketException catch (e) {
      developer.log('❌ Network Error: $e');
      return 'Network error. Check your internet connection.';
      
    } catch (e, stackTrace) {
      developer.log('❌ Unexpected Error Type: ${e.runtimeType}');
      developer.log('Error: $e');
      developer.log('Stack trace: $stackTrace');
      
      final errorStr = e.toString();
      
      // Check if it's a 404 error
      if (errorStr.contains('404')) {
        developer.log('⚠️ Detected 404 error - users table may not exist or RLS policy is blocking access');
        developer.log('Supabase URL: ${SupabaseConfig.supabaseUrl}');
        developer.log('Allow login anyway since auth succeeded');
        
        // If auth succeeded but profile fetch failed with 404, allow login
        return null;
      }
      
      return 'Login failed: $e';
    }
  }

  /// Deprecated: Use login() instead. This method uses old password-based authentication.
  @Deprecated('Use login() method instead. This uses Supabase Auth.')
  static Future<String?> loginWithPassword(String email, String password) async {
    return login(email, password);
  }

  // ─── Sign Up ───────────────────────────────────────────────────────────────

  /// Returns null on success, or an error message string on failure.
  /// Handles all three steps: auth signup, profile creation, and session persistence.
  static Future<String?> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final normalizedEmail = email.trim();
    developer.log('Starting signup for: $normalizedEmail');

    if (!_emailPattern.hasMatch(normalizedEmail)) {
      return 'Enter a valid email address.';
    }

    if (password.length < 6) {
      return 'Password must be at least 6 characters long.';
    }
    
    try {
      // Pass profile data as metadata so the DB trigger can create the
      // users row even when email confirmation is enabled (no session yet).
      final authResponse = await _db.auth.signUp(
        email: normalizedEmail,
        password: password,
        data: {
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'phone': phone.trim(),
        },
      );

      final userId = authResponse.user?.id;
      if (userId == null) {
        developer.log('ERROR: User ID is null after signup response!');
        return 'Signup succeeded but no auth user ID was returned. Check your email confirmation settings.';
      }

      developer.log('Auth signup successful for: $normalizedEmail');
      developer.log('Creating profile for auth user: $userId');

      // If Supabase requires email confirmation, session is null.
      // Signal the caller to show the OTP verification screen.
      if (authResponse.session == null) {
        developer.log('Email confirmation required for: $normalizedEmail');
        return 'VERIFY_EMAIL';
      }

      // Session available (email confirmation disabled) — create profile now.
      try {
        await _db.from('users').insert({
          'email': normalizedEmail,
          'auth_user_id': userId,
          'first_name': firstName.trim(),
          'last_name': lastName.trim(),
          'phone': phone.trim(),
          'role': 'buyer',
          'account_status': 'active',
          'password': '',
          'created_at': DateTime.now().toIso8601String(),
        });
        developer.log('Profile created successfully for: $normalizedEmail');
      } on PostgrestException catch (e) {
        if (e.code == '23505' || e.code == '42501') {
          developer.log('Profile handled by trigger (code: ${e.code})');
        } else {
          developer.log('Profile creation error: ${e.message} (code: ${e.code})');
          return 'Failed to create user profile. ${e.message}';
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_loginKey, true);
      await prefs.setString(_userEmailKey, normalizedEmail);
      await prefs.remove(_userIdKey);
      developer.log('Session saved for: $normalizedEmail');

      developer.log('Signup completed successfully for: $normalizedEmail');
      
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
        return 'An account with this email already exists.';
      }
      if (e.message.toLowerCase().contains('password') || e.message.toLowerCase().contains('weak')) {
        return 'Password is too weak. Use at least 6 characters.';
      }
      if (e.message.trim().isEmpty) {
        return 'Sign up failed. Check that your email is valid and try again.';
      }
      return 'Sign up failed: ${e.message}';
    } on SocketException catch (e) {
      developer.log('Network error during signup: $e');
      return 'Network error. Check your internet connection and try again.';
    } catch (e, stackTrace) {
      developer.log('Unexpected signup error: $e\n$stackTrace');
      return 'Sign up failed: An unexpected error occurred. Please try again.';
    }
  }

  // ─── Email OTP Verification ────────────────────────────────────────────────

  /// Verifies the 6-digit OTP sent to the user's email after signup.
  /// Returns null on success, or an error message string on failure.
  static Future<String?> verifyEmailOtp({
    required String email,
    required String token,
  }) async {
    try {
      final response = await _db.auth.verifyOTP(
        email: email.trim(),
        token: token.trim(),
        type: OtpType.signup,
      );

      if (response.session != null) {
        final userId = response.user?.id;
        // Create the profile row now that the user is fully authenticated.
        if (userId != null) {
          try {
            await _db.from('users').insert({
              'email': email.trim(),
              'auth_user_id': userId,
              'role': 'buyer',
              'account_status': 'active',
              'password': '',
            });
          } on PostgrestException catch (e) {
            // 23505 = duplicate (trigger already created it) — OK.
            if (e.code != '23505') {
              developer.log('Profile insert after OTP error: ${e.message}');
            }
          }

          // Session is active — sync the locally saved address to Supabase
          // before we sign out, so it persists across devices and app restarts.
          final localAddress = await AddressService.loadAddress();
          if (localAddress != null &&
              localAddress.values.any((v) => v.isNotEmpty)) {
            await AddressService.saveToSupabase(localAddress);
            developer.log('Address synced to Supabase during OTP verification');
          }
        }
        // Sign out after verification so user must log in manually.
        await _db.auth.signOut();
      }

      return null;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('expired')) return 'Code has expired. Please request a new one.';
      if (msg.contains('invalid')) return 'Invalid code. Please check and try again.';
      return e.message;
    } catch (e) {
      return 'Verification failed. Please try again.';
    }
  }

  /// Resends the OTP verification email.
  static Future<String?> resendVerificationEmail(String email) async {
    try {
      await _db.auth.resend(type: OtpType.signup, email: email.trim());
      return null;
    } on AuthException catch (e) {
      if (e.statusCode == '429') return 'Too many requests. Please wait before resending.';
      return e.message;
    } catch (e) {
      return 'Failed to resend. Please try again.';
    }
  }

  // ─── Profile ───────────────────────────────────────────────────────────────

  // ─── Password Reset ────────────────────────────────────────────────────────

  /// Sends a 6-digit OTP to the email for password reset.
  static Future<String?> sendPasswordResetOtp(String email) async {
    try {
      await _db.auth.resetPasswordForEmail(email.trim());
      return null;
    } on AuthException catch (e) {
      if (e.statusCode == '429') return 'Too many requests. Please wait before trying again.';
      return e.message;
    } catch (e) {
      return 'Failed to send reset code. Please try again.';
    }
  }

  /// Verifies the password reset OTP. Returns null on success.
  static Future<String?> verifyPasswordResetOtp({
    required String email,
    required String token,
  }) async {
    try {
      await _db.auth.verifyOTP(
        email: email.trim(),
        token: token.trim(),
        type: OtpType.recovery,
      );
      return null;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('expired')) return 'Code has expired. Please request a new one.';
      if (msg.contains('invalid')) return 'Invalid code. Please check and try again.';
      return e.message;
    } catch (e) {
      return 'Verification failed. Please try again.';
    }
  }

  /// Updates the authenticated user's password after OTP verification.
  static Future<String?> updatePassword(String newPassword) async {
    try {
      await _db.auth.updateUser(UserAttributes(password: newPassword));
      await _db.auth.signOut();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Failed to update password. Please try again.';
    }
  }

  // ─── Profile ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getUserProfile() async {
    final email = await getUserEmail();
    if (email == null) return null;
    try {
      return await _db
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();
    } catch (e) {
      developer.log('Error fetching profile: $e');
      return null;
    }
  }
}
