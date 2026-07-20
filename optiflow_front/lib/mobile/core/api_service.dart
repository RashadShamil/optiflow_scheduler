import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// ApiService — the single gateway between Flutter and FastAPI.
///
/// Architecture rules:
///  • Base URL: http://10.0.2.2:8000  (Android Emulator → localhost)
///  • Routes on the `router` in route.py get prefix /api  (e.g. /api/tasks)
///  • Routes defined directly on `app` in main.py have NO prefix
///    (e.g. /machines, /jobs, /book_machine, /claim_job)
///  • Every request that mutates state injects the Supabase JWT token
///    via Authorization: Bearer <token>
/// ─────────────────────────────────────────────────────────────────────────────
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // Android Emulator uses 10.0.2.2 to reach the host machine's localhost.
  static const String _base = 'https://e22-co2060-optiflow.onrender.com';

  /// Build HTTP headers with optional Bearer auth token.
  Map<String, String> _headers({bool auth = true}) {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = AuthService.instance.accessToken;
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TASKS  (route.py → /api/tasks)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch tasks assigned to a specific resource (worker).
  Future<List<Map<String, dynamic>>> fetchTasks(String resourceId) async {
    final uri = Uri.parse('$_base/api/tasks?resource_id=$resourceId');
    final res = await http.get(uri, headers: _headers());
    _check(res);
    final decoded = json.decode(res.body);
    // The endpoint may return {"tasks": [...]} or a bare list.
    if (decoded is Map && decoded.containsKey('tasks')) {
      return List<Map<String, dynamic>>.from(decoded['tasks']);
    }
    return List<Map<String, dynamic>>.from(decoded);
  }

  /// Update the status of a task (SCHEDULED → IN_PROGRESS → COMPLETED).
  Future<void> updateTaskStatus(String taskId, String status) async {
    final uri = Uri.parse('$_base/api/tasks/$taskId/status');
    final res = await http.patch(
      uri,
      headers: _headers(),
      body: json.encode({'status': status}),
    );
    _check(res);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // JOBS  (main.py → /jobs, /claim_job, /jobs/{id}/submit)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch jobs filtered by status, e.g. "OPEN".
  Future<List<Map<String, dynamic>>> fetchJobs({String? status}) async {
    final query = status != null ? '?status=$status' : '';
    final uri = Uri.parse('$_base/jobs$query');
    final res = await http.get(uri, headers: _headers(auth: false));
    _check(res);
    final decoded = json.decode(res.body);
    if (decoded is Map && decoded.containsKey('jobs')) {
      return List<Map<String, dynamic>>.from(decoded['jobs']);
    }
    return List<Map<String, dynamic>>.from(decoded);
  }

  /// Claim an open job for the current user.
  Future<Map<String, dynamic>> claimJob({
    required String jobId,
    required String workerName,
  }) async {
    final uri = Uri.parse('$_base/claim_job');
    final res = await http.post(
      uri,
      headers: _headers(),
      body: json.encode({'job_id': jobId, 'student_name': workerName}),
    );
    _check(res);
    return Map<String, dynamic>.from(json.decode(res.body));
  }

  /// Submit a completed job with proof photo URL and worker notes.
  Future<void> submitJobProof({
    required String jobId,
    required String proofUrl,
    required String notes,
  }) async {
    final uri = Uri.parse('$_base/jobs/$jobId/submit');
    final res = await http.post(
      uri,
      headers: _headers(),
      body: json.encode({'proof_url': proofUrl, 'notes': notes}),
    );
    _check(res);
  }

  /// Publish a DRAFT job — changes its status to OPEN so workers can
  /// see and claim it in the Job Market. Called by manager-role users.
  Future<Map<String, dynamic>> publishJob(String jobId) async {
    final uri = Uri.parse('$_base/api/jobs/$jobId/publish');
    final res = await http.patch(uri, headers: _headers());
    _check(res);
    return Map<String, dynamic>.from(json.decode(res.body));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MACHINES / RESOURCES  (main.py → /machines, /book_machine)
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch all machines/resources.
  Future<List<Map<String, dynamic>>> fetchMachines() async {
    final uri = Uri.parse('$_base/machines');
    final res = await http.get(uri, headers: _headers(auth: false));
    _check(res);
    final decoded = json.decode(res.body);
    if (decoded is Map && decoded.containsKey('machines')) {
      return List<Map<String, dynamic>>.from(decoded['machines']);
    }
    return List<Map<String, dynamic>>.from(decoded);
  }

  /// Fetch a single machine by its ID (used from QR scan flow).
  Future<Map<String, dynamic>?> fetchMachineById(String machineId) async {
    final machines = await fetchMachines();
    try {
      return machines.firstWhere((m) => m['id'].toString() == machineId);
    } catch (_) {
      return null;
    }
  }

  /// Book a machine slot.
  Future<Map<String, dynamic>> bookMachine({
    required String machineId,
    required String userName,
    required String startTime,
    required String endTime,
  }) async {
    final uri = Uri.parse('$_base/book_machine');
    final res = await http.post(
      uri,
      headers: _headers(),
      body: json.encode({
        'machine_id': machineId,
        'user_name': userName,
        'start_time': startTime,
        'end_time': endTime,
      }),
    );
    _check(res);
    return Map<String, dynamic>.from(json.decode(res.body));
  }

  /// Report a machine incident — sets status to OFFLINE.
  Future<void> reportMachineOffline(String machineId) async {
    final uri = Uri.parse('$_base/machines/$machineId');
    final res = await http.patch(
      uri,
      headers: _headers(),
      body: json.encode({'status': 'OFFLINE'}),
    );
    _check(res);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  void _check(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String detail = res.body;
      try {
        final decoded = json.decode(res.body);
        detail = decoded['detail'] ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }
  }
}
