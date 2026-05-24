import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

class PayMongoService {
  static final _fn = Supabase.instance.client.functions;

  /// Normalises a PH phone number to E.164 format (+63XXXXXXXXXX).
  static String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('63') && digits.length == 12) return '+$digits';
    if (digits.startsWith('0') && digits.length == 11) return '+63${digits.substring(1)}';
    if (digits.length == 10) return '+63$digits';
    return raw.startsWith('+') ? raw : '+$digits';
  }

  /// Creates a PayMongo Checkout Session via the Supabase Edge Function.
  /// Returns {'id', 'checkout_url'}.
  static Future<Map<String, String>> createCheckoutSession({
    required String name,
    required String email,
    required String phone,
    required List<Map<String, dynamic>> lineItems,
    String description = 'VARÓN Online Store Order',
  }) async {
    final payload = {
      'data': {
        'attributes': {
          'billing': {
            'name': name,
            'email': email,
            'phone': _normalizePhone(phone),
          },
          'line_items': lineItems,
          'payment_method_types': ['gcash', 'card', 'paymaya', 'qrph'],
          'success_url': 'https://varon.store/checkout/success',
          'cancel_url': 'https://varon.store/checkout/cancel',
          'description': description,
        }
      }
    };

    final res = await _fn.invoke(
      'paymongo',
      body: {'action': 'create_session', 'payload': payload},
    );

    debugPrint('[PayMongo] createCheckoutSession → status ${res.status}');

    if (res.status != 200) {
      debugPrint('[PayMongo] error: ${res.data}');
      throw 'Payment service error (${res.status}). Please try again.';
    }

    final data = res.data as Map<String, dynamic>;
    final sessionData = data['data'] as Map<String, dynamic>;
    final attrs = sessionData['attributes'] as Map<String, dynamic>;

    return {
      'id': sessionData['id'] as String,
      'checkout_url': attrs['checkout_url'] as String,
    };
  }

  /// Polls the Checkout Session status via the Supabase Edge Function.
  /// Returns: 'succeeded' | 'pending' | 'failed' | 'expired'
  static Future<String> getSessionPaymentStatus(String sessionId) async {
    final res = await _fn.invoke(
      'paymongo',
      body: {'action': 'get_session', 'payload': {'session_id': sessionId}},
    );

    debugPrint('[PayMongo] getSessionPaymentStatus → status ${res.status}');

    if (res.status != 200) {
      throw 'Failed to verify payment (${res.status}). Please try again.';
    }

    final data = res.data as Map<String, dynamic>;
    final attrs =
        (data['data'] as Map<String, dynamic>)['attributes'] as Map<String, dynamic>;
    final sessionStatus = attrs['status'] as String? ?? 'active';

    if (sessionStatus == 'expired') return 'expired';

    final paymentIntent = attrs['payment_intent'];
    if (paymentIntent == null) return 'pending';

    final intentStatus =
        ((paymentIntent as Map<String, dynamic>)['attributes']
            as Map<String, dynamic>)['status'] as String? ??
        'pending';

    if (intentStatus == 'succeeded') return 'succeeded';
    if (intentStatus == 'failed' || intentStatus == 'timed_out') return 'failed';
    return 'pending';
  }
}
