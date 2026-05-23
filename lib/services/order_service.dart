import 'dart:developer' as developer;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';

class OrderService {
  static SupabaseClient get _db => Supabase.instance.client;

  static List<Order> _parse(List rows) =>
      rows.map((r) => Order.fromJson(r as Map<String, dynamic>)).toList();

  // ── Core ──────────────────────────────────────────────────────────────────

  static Future<void> place(Order order) async {
    try {
      await _db.from('orders').insert(order.toSupabaseJson());
    } catch (e) {
      developer.log('[OrderService] place error: $e');
      rethrow;
    }
  }

  static Future<void> updateStatus(String orderId, String newStatus) async {
    try {
      await _db.from('orders').update({'status': newStatus}).eq('id', orderId);
    } catch (e) {
      developer.log('[OrderService] updateStatus error: $e');
      rethrow;
    }
  }

  // ── Buyer ─────────────────────────────────────────────────────────────────

  static Future<List<Order>> getByBuyer(String buyerEmail) async {
    try {
      final rows = await _db
          .from('orders')
          .select()
          .eq('buyer_email', buyerEmail)
          .order('created_at', ascending: false);
      return _parse(rows as List);
    } catch (e) {
      developer.log('[OrderService] getByBuyer error: $e');
      return [];
    }
  }

  // ── Seller ────────────────────────────────────────────────────────────────

  static Future<List<Order>> getBySeller(String sellerEmail) async {
    try {
      final rows = await _db
          .from('orders')
          .select()
          .eq('seller_email', sellerEmail)
          .order('created_at', ascending: false);
      return _parse(rows as List);
    } catch (e) {
      developer.log('[OrderService] getBySeller error: $e');
      return [];
    }
  }

  static Future<Map<String, int>> sellerStatusCounts(String sellerEmail) async {
    final orders = await getBySeller(sellerEmail);
    int count(String s) => orders.where((o) => o.status == s).length;
    return {
      Order.pending:        count(Order.pending),
      Order.confirmed:      count(Order.confirmed),
      Order.preparing:      count(Order.preparing),
      Order.readyForPickup: count(Order.readyForPickup),
      Order.completed:      count(Order.completed),
    };
  }

  static Future<double> sellerRevenue(String sellerEmail) async {
    final orders = await getBySeller(sellerEmail);
    return orders
        .where((o) => o.status == Order.completed || o.status == Order.delivered)
        .fold<double>(0.0, (sum, o) => sum + o.total);
  }

  // ── Rider ─────────────────────────────────────────────────────────────────

  static Future<List<Order>> getAvailableForRider() async {
    try {
      final rows = await _db
          .from('orders')
          .select()
          .eq('status', Order.readyForPickup)
          .isFilter('rider_email', null)
          .order('created_at', ascending: false);
      return _parse(rows as List);
    } catch (e) {
      developer.log('[OrderService] getAvailableForRider error: $e');
      return [];
    }
  }

  static Future<void> acceptOrder(String orderId, String riderEmail) async {
    await _db.from('orders').update({
      'rider_email': riderEmail,
      'status': Order.shipped,
    }).eq('id', orderId);
  }

  static Future<List<Order>> getByRider(String riderEmail) async {
    try {
      final rows = await _db
          .from('orders')
          .select()
          .eq('rider_email', riderEmail)
          .order('created_at', ascending: false);
      return _parse(rows as List);
    } catch (e) {
      developer.log('[OrderService] getByRider error: $e');
      return [];
    }
  }

  static Future<List<Order>> getActiveDeliveriesByRider(String riderEmail) async {
    try {
      final rows = await _db
          .from('orders')
          .select()
          .eq('rider_email', riderEmail)
          .inFilter('status', [Order.shipped, Order.outForDelivery])
          .order('created_at', ascending: false);
      return _parse(rows as List);
    } catch (e) {
      developer.log('[OrderService] getActiveDeliveriesByRider error: $e');
      return [];
    }
  }

  static Future<int> riderCompletedCount(String riderEmail) async {
    final orders = await getByRider(riderEmail);
    return orders
        .where((o) => o.status == Order.delivered || o.status == Order.completed)
        .length;
  }

  static Future<double> riderEarnings(String riderEmail) async {
    final orders = await getByRider(riderEmail);
    return orders
        .where((o) => o.status == Order.delivered || o.status == Order.completed)
        .fold<double>(0.0, (sum, o) => sum + o.commission);
  }
}
