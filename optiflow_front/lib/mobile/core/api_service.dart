import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

/// Authenticated REST gateway for the mobile worker/outsider experience.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const String _base = 'https://e22-co2060-optiflow.onrender.com/api';

  Map<String, String> _headers({bool auth = true}) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = AuthService.instance.accessToken;
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<List<Map<String, dynamic>>> fetchTasks([String? ignoredResourceId]) async {
    final response = await http.get(
      Uri.parse('$_base/mobile/tasks'),
      headers: _headers(),
    );
    _check(response);
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  Future<void> updateTaskStatus(String taskId, String status) async {
    final response = await http.patch(
      Uri.parse('$_base/mobile/tasks/$taskId/status'),
      headers: _headers(),
      body: json.encode({'status': status}),
    );
    _check(response);
  }

  /// Kept under the existing method name so the QA sheet does not need a UI
  /// rewrite. The argument is now correctly treated as a task ID.
  Future<void> submitJobProof({
    required String jobId,
    required String proofUrl,
    required String notes,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/mobile/tasks/$jobId/complete'),
      headers: _headers(),
      body: json.encode({'proof_url': proofUrl, 'notes': notes}),
    );
    _check(response);
  }

  /// Existing Job Market UI now reads approved external work offers rather than
  /// exposing normal internal jobs to every mobile account.
  Future<List<Map<String, dynamic>>> fetchJobs({String? status}) async {
    final response = await http.get(
      Uri.parse('$_base/mobile/work-offers'),
      headers: _headers(),
    );
    _check(response);
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  Future<Map<String, dynamic>> claimJob({
    required String jobId,
    required String workerName,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/mobile/work-offers/$jobId/claim'),
      headers: _headers(),
    );
    _check(response);
    return Map<String, dynamic>.from(json.decode(response.body));
  }

  Future<List<Map<String, dynamic>>> fetchMachines() async {
    final response = await http.get(
      Uri.parse('$_base/mobile/machines'),
      headers: _headers(),
    );
    _check(response);
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  Future<Map<String, dynamic>?> fetchMachineById(String machineId) async {
    final machines = await fetchMachines();
    for (final machine in machines) {
      if (machine['id']?.toString() == machineId) return machine;
    }
    return null;
  }

  Future<Map<String, dynamic>> bookMachine({
    required String machineId,
    required String userName,
    required String startTime,
    required String endTime,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/machine-bookings'),
      headers: _headers(),
      body: json.encode({
        'machine_id': machineId,
        'start_time': startTime,
        'end_time': endTime,
      }),
    );
    _check(response);
    return Map<String, dynamic>.from(json.decode(response.body));
  }

  Future<void> reportMachineOffline(String machineId) async {
    final response = await http.patch(
      Uri.parse('$_base/mobile/machines/$machineId/status'),
      headers: _headers(),
      body: json.encode({'status': 'OFFLINE'}),
    );
    _check(response);
  }

  void _check(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String detail = response.body;
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['detail'] != null) {
        detail = decoded['detail'].toString();
      }
    } catch (_) {}
    throw Exception(detail);
  }
}
