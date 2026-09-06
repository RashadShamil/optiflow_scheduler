import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single network gateway shared by the manager desktop and all mobile roles.
///
/// Application data never talks directly to production Supabase tables from
/// Flutter. Supabase is used here only to obtain the login access token; FastAPI
/// owns validation, approvals, task transitions, bookings and schedule rules.
class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://e22-co2060-optiflow.onrender.com',
  );

  static String get _api => '$baseUrl/api';

  Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = response.body;
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['detail'] != null) {
          message = body['detail'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<List<Map<String, dynamic>>> fetchResources({
    String? type,
    bool includeExternal = false,
  }) async {
    final query = <String, String>{};
    if (type != null) query['type'] = type;
    if (includeExternal) query['include_external'] = 'true';
    final uri = Uri.parse(
      '$_api/resources',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final response = await http.get(uri, headers: _headers);
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<List<Map<String, dynamic>>> fetchMachines() =>
      fetchResources(type: 'MACHINE');

  Future<List<Map<String, dynamic>>> fetchHumanResources({
    bool includeExternal = false,
  }) => fetchResources(type: 'HUMAN', includeExternal: includeExternal);

  Future<List<Map<String, dynamic>>> fetchBookableMachines() async {
    final response = await http.get(
      Uri.parse('$_api/machines/bookable'),
      headers: _headers,
    );
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<void> createResource(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_api/resources'),
      headers: _headers,
      body: jsonEncode(data),
    );
    _decode(response);
  }

  Future<void> updateResource(String id, Map<String, dynamic> data) async {
    final response = await http.patch(
      Uri.parse('$_api/resources/$id'),
      headers: _headers,
      body: jsonEncode(data),
    );
    _decode(response);
  }

  Future<void> deleteResource(String id) async {
    final response = await http.delete(
      Uri.parse('$_api/resources/$id'),
      headers: _headers,
    );
    _decode(response);
  }

  Future<List<Map<String, dynamic>>> fetchOperationTypes() async {
    final response = await http.get(
      Uri.parse('$_api/operation-types'),
      headers: _headers,
    );
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<List<Map<String, dynamic>>> fetchCapabilities() async {
    final response = await http.get(
      Uri.parse('$_api/capabilities'),
      headers: _headers,
    );
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<void> createCapability(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_api/capabilities'),
      headers: _headers,
      body: jsonEncode(data),
    );
    _decode(response);
  }

  Future<void> deleteCapability(String id) async {
    final response = await http.delete(
      Uri.parse('$_api/capabilities/$id'),
      headers: _headers,
    );
    _decode(response);
  }

  Future<List<Map<String, dynamic>>> fetchJobsWithTasks() async {
    final response = await http.get(Uri.parse('$_api/jobs'), headers: _headers);
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<Map<String, dynamic>> createJobOrder(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_api/jobs'),
      headers: _headers,
      body: jsonEncode(data),
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  Future<Map<String, dynamic>> optimizeJob(String jobId) async {
    final response = await http.post(
      Uri.parse('$_api/optimize/$jobId'),
      headers: _headers,
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  Future<void> dispatchTask(String taskId) async {
    final response = await http.post(
      Uri.parse('$_api/tasks/$taskId/dispatch'),
      headers: _headers,
    );
    _decode(response);
  }

  Future<List<Map<String, dynamic>>> fetchMyTasks() async {
    final response = await http.get(
      Uri.parse('$_api/me/tasks'),
      headers: _headers,
    );
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<void> acceptTask(String taskId) => _taskAction(taskId, 'accept');
  Future<void> startTask(String taskId) => _taskAction(taskId, 'start');
  Future<void> completeTask(String taskId) => _taskAction(taskId, 'complete');

  Future<void> _taskAction(String taskId, String action) async {
    final response = await http.post(
      Uri.parse('$_api/tasks/$taskId/$action'),
      headers: _headers,
    );
    _decode(response);
  }

  Future<Map<String, dynamic>> fetchSchedule() async {
    final response = await http.get(
      Uri.parse('$_api/schedule'),
      headers: _headers,
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  Future<Map<String, dynamic>> moveScheduledTask({
    required String taskId,
    required String resourceId,
    required DateTime startTime,
    bool lock = true,
  }) async {
    final response = await http.patch(
      Uri.parse('$_api/schedule/tasks/$taskId'),
      headers: _headers,
      body: jsonEncode({
        'resource_id': resourceId,
        'start_time': startTime.toUtc().toIso8601String(),
        'lock': lock,
      }),
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  Future<void> setTaskLock(String taskId, bool locked) async {
    final response = await http.patch(
      Uri.parse('$_api/schedule/tasks/$taskId/lock'),
      headers: _headers,
      body: jsonEncode({'locked': locked}),
    );
    _decode(response);
  }

  Future<Map<String, dynamic>> fetchMachineAvailability(
    String machineId,
    DateTime day,
  ) async {
    final date =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      '$_api/machines/$machineId/availability',
    ).replace(queryParameters: {'day': date});
    final response = await http.get(uri, headers: _headers);
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  Future<Map<String, dynamic>> requestMachineBooking({
    required String machineId,
    required DateTime startTime,
    required DateTime endTime,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('$_api/machine-bookings'),
      headers: _headers,
      body: jsonEncode({
        'machine_id': machineId,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'notes': notes,
      }),
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  Future<List<Map<String, dynamic>>> fetchMyBookings() async {
    final response = await http.get(
      Uri.parse('$_api/machine-bookings/mine'),
      headers: _headers,
    );
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<List<Map<String, dynamic>>> fetchBookingRequests({
    String? status,
  }) async {
    final uri = Uri.parse(
      '$_api/machine-bookings',
    ).replace(queryParameters: status == null ? null : {'status': status});
    final response = await http.get(uri, headers: _headers);
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<void> decideBooking(String bookingId, String status) async {
    final response = await http.patch(
      Uri.parse('$_api/machine-bookings/$bookingId'),
      headers: _headers,
      body: jsonEncode({'status': status}),
    );
    _decode(response);
  }

  Future<void> publishWorkOffer({
    required String taskId,
    required double payAmount,
    required int estimatedMinutes,
    String? notes,
  }) async {
    final response = await http.post(
      Uri.parse('$_api/tasks/$taskId/work-offer'),
      headers: _headers,
      body: jsonEncode({
        'pay_amount': payAmount,
        'estimated_minutes': estimatedMinutes,
        'notes': notes,
      }),
    );
    _decode(response);
  }

  Future<List<Map<String, dynamic>>> fetchOpenWorkOffers() async {
    final response = await http.get(
      Uri.parse('$_api/work-offers'),
      headers: _headers,
    );
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<List<Map<String, dynamic>>> fetchMyWorkOffers() async {
    final response = await http.get(
      Uri.parse('$_api/work-offers/mine'),
      headers: _headers,
    );
    return List<Map<String, dynamic>>.from(_decode(response) as List);
  }

  Future<void> claimWorkOffer(String offerId) async {
    final response = await http.post(
      Uri.parse('$_api/work-offers/$offerId/claim'),
      headers: _headers,
    );
    _decode(response);
  }

  Future<Map<String, dynamic>> fetchDashboardStats() async {
    final response = await http.get(
      Uri.parse('$_api/dashboard-stats'),
      headers: _headers,
    );
    return Map<String, dynamic>.from(_decode(response) as Map);
  }
}
