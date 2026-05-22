import 'dart:convert';
import 'dart:developer' as developer;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddressService {
  static const String _key = 'saved_address';

  static Future<void> saveAddress(Map<String, String> address) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(address));
  }

  static Future<Map<String, String>?> loadAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearAddress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Saves the address to Supabase `user_addresses`.
  /// Pass [userId] explicitly when calling from a context where
  /// [auth.currentUser] may not yet reflect the active session
  /// (e.g. right after verifyOTP).
  static Future<void> saveToSupabase(
    Map<String, String> address, {
    String? userId,
  }) async {
    try {
      final client = Supabase.instance.client;
      final uid = userId ?? client.auth.currentUser?.id;
      developer.log('[AddressService] saveToSupabase: uid=$uid');
      if (uid == null) {
        developer.log('[AddressService] saveToSupabase skipped — no user id');
        return;
      }

      await client.from('user_addresses').upsert(
        {
          'user_id': uid,
          'house_number': address['houseNumber'] ?? '',
          'street_name': address['streetName'] ?? '',
          'barangay': address['barangay'] ?? '',
          'barangay_code': address['barangayCode'] ?? '',
          'city': address['city'] ?? '',
          'city_code': address['cityCode'] ?? '',
          'province': address['province'] ?? '',
          'province_code': address['provinceCode'] ?? '',
          'region': address['region'] ?? '',
          'region_code': address['regionCode'] ?? '',
        },
        onConflict: 'user_id',
      );
      developer.log('[AddressService] saveToSupabase success');
    } catch (e) {
      developer.log('[AddressService] saveToSupabase error: $e');
    }
  }

  /// Fetches the saved address from Supabase for the authenticated user.
  static Future<Map<String, String>?> fetchFromSupabase() async {
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      developer.log('[AddressService] fetchFromSupabase: uid=$userId');
      if (userId == null) {
        developer.log('[AddressService] fetchFromSupabase skipped — no session');
        return null;
      }

      final data = await client
          .from('user_addresses')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      developer.log('[AddressService] fetchFromSupabase row=$data');
      if (data == null) return null;

      return {
        'houseNumber': (data['house_number'] as String?) ?? '',
        'streetName': (data['street_name'] as String?) ?? '',
        'barangay': (data['barangay'] as String?) ?? '',
        'barangayCode': (data['barangay_code'] as String?) ?? '',
        'city': (data['city'] as String?) ?? '',
        'cityCode': (data['city_code'] as String?) ?? '',
        'province': (data['province'] as String?) ?? '',
        'provinceCode': (data['province_code'] as String?) ?? '',
        'region': (data['region'] as String?) ?? '',
        'regionCode': (data['region_code'] as String?) ?? '',
      };
    } catch (e) {
      developer.log('[AddressService] fetchFromSupabase error: $e');
      return null;
    }
  }
}
