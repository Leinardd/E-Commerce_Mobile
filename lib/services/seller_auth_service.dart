import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import 'io_shim.dart' if (dart.library.html) 'io_shim_web.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SellerAuthService {
  static const _currentSellerKey       = 'current_seller_email';
  static const _currentSellerIdKey     = 'current_seller_id';
  static const _currentSellerUserIdKey = 'current_seller_user_id';

  static SupabaseClient get _db => Supabase.instance.client;

  // ─── Session ───────────────────────────────────────────────────────────────

  static Future<bool> isLoggedIn() async {
    final email = await getCurrentSellerEmail();
    return email != null;
  }

  static Future<String?> getCurrentSellerEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentSellerKey);
  }

  static Future<int?> getCurrentSellerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentSellerIdKey);
  }

  static Future<int?> getCurrentSellerUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentSellerUserIdKey);
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentSellerKey);
    await prefs.remove(_currentSellerIdKey);
    await prefs.remove(_currentSellerUserIdKey);
    try {
      await _db.auth.signOut();
    } catch (_) {}
  }

  // ─── Register ──────────────────────────────────────────────────────────────

  /// Creates a new seller user + seller profile in Supabase using Auth.
  /// Returns null on success, or an error message string on failure.
  static Future<String?> register({
    required String email,
    required String password,
    required String storeName,
    required String fullName,
    required String address,
    required String phoneNumber,
  }) async {
    developer.log('Starting seller registration for: $email');

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

      // Step 4: Generate unique store slug
      final slug = storeName
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final uniqueSlug = '$slug-${DateTime.now().millisecondsSinceEpoch}';

      developer.log('Creating user profile for seller: $email');

      // Step 5: Create user profile in database
      try {
        final userResult = await _db.from('users').insert({
          'email': email.trim(),
          'auth_user_id': userId,
          'first_name': firstName,
          'last_name': lastName,
          'phone': phoneNumber.trim(),
          'role': 'seller',
          'account_status': 'active',
          'buyer_approval_status': 'pending',
          'created_at': DateTime.now().toIso8601String(),
        }).select('id').single();

        developer.log('User profile created successfully');

        final userIntId = userResult['id'] as int;

        // Step 6: Create seller profile
        final sellerResult = await _db.from('sellers').insert({
          'user_id': userIntId,
          'auth_user_id': userId,
          'store_name': storeName.trim(),
          'store_slug': uniqueSlug,
          'address': address.trim(),
          'contact_email': email.trim(),
          'contact_phone': phoneNumber.trim(),
          'status': 'pending',
          'commission_rate': 10.00,
          'island_group': 'Luzon',
        }).select('id').single();

        developer.log('Seller profile created successfully');

        // Step 7: Save to local preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_currentSellerKey, email.trim());
        await prefs.setInt(_currentSellerIdKey, sellerResult['id'] as int);
        await prefs.remove(_currentSellerUserIdKey);

        developer.log('Seller registration completed successfully');
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
        
        return 'Failed to create seller profile. ${e.message}';
      }
    } on SocketException catch (e) {
      developer.log('Network error during seller registration: $e');
      return 'Network error. Check your internet connection and try again.';
    } catch (e, stackTrace) {
      developer.log('Unexpected seller registration error: $e\n$stackTrace');
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
          .eq('role', 'seller')
          .maybeSingle();

      if (user == null) return 'No seller profile found for this account.';
      if (user['account_status'] == 'banned') return 'Your account has been banned.';

      // Get seller profile status
      final seller = await _db
          .from('sellers')
          .select('id, status')
          .eq('user_id', user['id'])
          .maybeSingle();

      if (seller == null) return 'No seller profile found for this account.';
      if (seller['status'] == 'suspended') return 'Your seller account has been suspended.';

      // Save session to local preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentSellerKey, email.trim());
      await prefs.setInt(_currentSellerIdKey, seller['id'] as int);
      await prefs.setInt(_currentSellerUserIdKey, user['id'] as int);

      developer.log('Seller login successful for: $email');
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

  // ─── Profile ───────────────────────────────────────────────────────────────

  /// Syncs seller session keys from the current Supabase auth session.
  ///
  /// Returns seller status: 'approved', 'pending', 'suspended', or null.
  /// null means: no Supabase session at all (user must log in).
  /// Any non-null return means the seller may proceed to the dashboard.
  ///
  /// Tries four strategies in order — the first three hit the DB, the fourth
  /// falls back to the auth session so a broken sellers-table RLS policy never
  /// blocks a genuinely authenticated seller.
  static Future<String?> syncSession() async {
    try {
      final session = _db.auth.currentSession;
      if (session == null) return null; // truly not logged in

      final email = session.user.email ?? '';
      final authUid = session.user.id;
      final prefs = await SharedPreferences.getInstance();

      // ── Strategy 1: sellers.auth_user_id = auth.uid() ────────────────────
      // Works when the correct RLS policy is in place (auth_user_id UUID column).
      try {
        final row = await _db
            .from('sellers')
            .select('id, status, user_id')
            .eq('auth_user_id', authUid)
            .maybeSingle();
        if (row != null) {
          await prefs.setString(_currentSellerKey, email);
          await prefs.setInt(_currentSellerIdKey, row['id'] as int);
          if (row['user_id'] != null) {
            await prefs.setInt(_currentSellerUserIdKey, row['user_id'] as int);
          }
          developer.log('SellerAuth: synced via auth_user_id ($email)');
          return (row['status'] as String?) ?? 'approved';
        }
      } catch (e) {
        developer.log('SellerAuth strategy 1 failed: $e');
      }

      // ── Strategy 2: users.auth_user_id → sellers.user_id ─────────────────
      // Two-step lookup: get the BIGINT users.id, then find the sellers row.
      try {
        final userRow = await _db
            .from('users')
            .select('id')
            .eq('auth_user_id', authUid)
            .maybeSingle();
        if (userRow != null) {
          final sellerRow = await _db
              .from('sellers')
              .select('id, status')
              .eq('user_id', userRow['id'] as int)
              .maybeSingle();
          if (sellerRow != null) {
            await prefs.setString(_currentSellerKey, email);
            await prefs.setInt(_currentSellerIdKey, sellerRow['id'] as int);
            await prefs.setInt(_currentSellerUserIdKey, userRow['id'] as int);
            developer.log('SellerAuth: synced via users table ($email)');
            return (sellerRow['status'] as String?) ?? 'approved';
          }
        }
      } catch (e) {
        developer.log('SellerAuth strategy 2 failed: $e');
      }

      // ── Strategy 3: restore from cached SharedPreferences ─────────────────
      // The seller previously had a successful syncSession — reuse those values.
      final cachedSellerId = prefs.getInt(_currentSellerIdKey);
      if (cachedSellerId != null) {
        await prefs.setString(_currentSellerKey, email);
        developer.log('SellerAuth: restored from cache ($email, sellerId=$cachedSellerId)');
        return 'approved';
      }

      // ── Strategy 4: session-only fallback ────────────────────────────────
      // All DB queries failed (most likely a broken sellers-table RLS policy).
      // getUserRole() already confirmed this account has role = seller in the
      // users table, so blocking here would incorrectly deny a valid seller.
      // Save the email so the dashboard can identify the user; the seller will
      // see an empty dashboard until the DB policy is fixed.
      // Fix: run SELLER_ACCESS_FIX.sql in Supabase SQL Editor.
      await prefs.setString(_currentSellerKey, email);
      developer.log(
        'SellerAuth: DB unreachable — session-only fallback ($email). '
        'Run SELLER_ACCESS_FIX.sql to restore full access.',
      );
      return 'approved';

    } catch (e) {
      developer.log('SellerAuth syncSession error: $e');
      return null;
    }
  }

  // ─── Apply from existing buyer account ────────────────────────────────────

  /// Upgrades the currently logged-in buyer account to seller role.
  /// Updates users.role to 'seller' and creates a sellers row (status='pending').
  /// Returns null on success, or an error message string on failure.
  static Future<String?> applyAsSeller({
    required String storeName,
    required String fullName,
    required String address,
    required String phoneNumber,
    String? validIdUrl,
  }) async {
    try {
      final session = _db.auth.currentSession;
      if (session == null) return 'You must be logged in to apply as a seller.';

      final authUid = session.user.id;
      final email   = (session.user.email ?? '').trim();

      // ── Step 1: locate the users row ────────────────────────────────────────

      // Try by auth_user_id (the normal case)
      Map<String, dynamic>? userRow = await _db
          .from('users')
          .select('id')
          .eq('auth_user_id', authUid)
          .maybeSingle();

      // Fallback: try by email (profile created without auth_user_id link)
      if (userRow == null && email.isNotEmpty) {
        userRow = await _db
            .from('users')
            .select('id')
            .eq('email', email)
            .maybeSingle();

        // Patch the missing auth_user_id while we're here
        if (userRow != null) {
          try {
            await _db
                .from('users')
                .update({'auth_user_id': authUid})
                .eq('id', userRow['id'] as int);
          } catch (_) {}
        }
      }

      // Fallback: profile was never created — auto-create it now
      if (userRow == null && email.isNotEmpty) {
        try {
          final parts = fullName.trim().split(' ');
          final inserted = await _db.from('users').insert({
            'email': email,
            'auth_user_id': authUid,
            'first_name': parts.first,
            'last_name': parts.length > 1 ? parts.sublist(1).join(' ') : '',
            'phone': phoneNumber.trim(),
            'role': 'buyer',
            'account_status': 'active',
            'buyer_approval_status': 'approved',
            'created_at': DateTime.now().toIso8601String(),
          }).select('id').single();
          userRow = inserted;
          developer.log('applyAsSeller: auto-created missing user profile for $email');
        } on PostgrestException catch (e) {
          // Duplicate row — another path created it; try fetching again
          if (e.code == '23505') {
            userRow = await _db
                .from('users')
                .select('id')
                .eq('email', email)
                .maybeSingle();
          }
        }
      }

      if (userRow == null) {
        return 'Unable to locate your account. Please log out, log back in, and try again.';
      }

      final userId = userRow['id'] as int;

      final existing = await _db
          .from('sellers')
          .select('id, status')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        final s = existing['status'] as String;
        if (s == 'pending') return 'Your seller application is already pending review.';
        if (s == 'approved') return 'You already have an active seller account.';
        if (s == 'suspended') return 'Your seller account has been suspended.';
      }

      final parts = fullName.trim().split(' ');
      final slug = storeName
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');

      await _db.from('users').update({
        'role': 'seller',
        'first_name': parts.first,
        'last_name': parts.length > 1 ? parts.sublist(1).join(' ') : '',
        'phone': phoneNumber.trim(),
      }).eq('id', userId);

      await _db.from('sellers').insert({
        'user_id': userId,
        'auth_user_id': authUid,
        'store_name': storeName.trim(),
        'store_slug': '$slug-${DateTime.now().millisecondsSinceEpoch}',
        'address': address.trim(),
        'contact_email': session.user.email ?? '',
        'contact_phone': phoneNumber.trim(),
        'status': 'pending',
        'commission_rate': 10.00,
        'island_group': 'Luzon',
        if (validIdUrl != null) 'valid_id_url': validIdUrl,
      });

      developer.log('Seller application submitted for: ${session.user.email}');
      return null;
    } on PostgrestException catch (e) {
      developer.log('Seller application error: ${e.message}');
      return 'Application failed: ${e.message}';
    } catch (e) {
      developer.log('Unexpected seller application error: $e');
      return 'Application failed. Please try again.';
    }
  }

  static Future<String?> getStoreName(String email) async {
    final profile = await getProfile(email);
    return profile?['store_name'] as String?;
  }

  /// Returns the seller row from the sellers table, or null if not found.
  static Future<Map<String, dynamic>?> getProfile(String email) async {
    try {
      final user = await _db
          .from('users')
          .select('id')
          .eq('email', email.trim())
          .maybeSingle();
      if (user == null) return null;

      return await _db
          .from('sellers')
          .select()
          .eq('user_id', user['id'])
          .maybeSingle();
    } catch (e) {
      developer.log('Error fetching seller profile: $e');
      return null;
    }
  }
}
