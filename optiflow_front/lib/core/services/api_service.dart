import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:optiflow_scheduler/core/models/booking.dart';
import 'package:optiflow_scheduler/core/models/job.dart';
import 'package:optiflow_scheduler/core/models/machine.dart';

/// REST gateway used by the Windows/desktop manager experience.
///
/// Read-heavy dashboard widgets may still use SupabaseService directly, but all
/// backend business operations use the same /api namespace.
class ApiService {
  static String get baseUrl {
    // Render is used by web, Windows, emulator, and physical devices.
    return 'https://e22-co2060-optiflow.onrender.com/api';
  }

  Future<Map<String, dynamic>> optimizeJob(String jobId) async {
    final response = await http.post(Uri.parse('$baseUrl/optimize/$jobId'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_detail(response));
    }
    return Map<String, dynamic>.from(json.decode(response.body));
  }

  Future<void> publishJob(String jobId) async {
    final response = await http.post(Uri.parse('$baseUrl/jobs/$jobId/publish'));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_detail(response));
    }
  }

  Future<List<Map<String, dynamic>>> fetchOperationTypes() async {
    final response = await http.get(Uri.parse('$baseUrl/operation-types'));
    if (response.statusCode != 200) return [];
    return List<Map<String, dynamic>>.from(json.decode(response.body));
  }

  Future<List<Machine>> fetchMachines() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/resources'));
      if (response.statusCode != 200) return [];
      final data = List<Map<String, dynamic>>.from(json.decode(response.body));
      return data
          .where((row) => row['type']?.toString().toUpperCase() == 'MACHINE')
          .map(Machine.fromJson)
          .toList();
    } catch (e) {
      debugPrint('fetchMachines failed: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchHumanResources() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/resources'));
      if (response.statusCode != 200) return [];
      final data = List<Map<String, dynamic>>.from(json.decode(response.body));
      return data
          .where((row) => row['type']?.toString().toUpperCase() == 'HUMAN')
          .toList();
    } catch (e) {
      debugPrint('fetchHumanResources failed: $e');
      return [];
    }
  }

  Future<List<Job>> fetchJobs() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/jobs'));
      if (response.statusCode != 200) return [];
      final decoded = Map<String, dynamic>.from(json.decode(response.body));
      final rows = List<Map<String, dynamic>>.from(decoded['jobs'] ?? const []);
      return rows.map(Job.fromJson).toList();
    } catch (e) {
      debugPrint('fetchJobs failed: $e');
      return [];
    }
  }

  /// Manager schedule combines production tasks and external machine bookings.
  Future<List<Booking>> fetchBookings() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/schedule'));
      if (response.statusCode != 200) return [];
      final rows = List<Map<String, dynamic>>.from(json.decode(response.body));

      return rows.map((row) {
        final start = DateTime.parse(row['start_time'].toString()).toLocal();
        final end = DateTime.parse(row['end_time'].toString()).toLocal();
        final minutes = end.difference(start).inMinutes.clamp(1, 24 * 60);
        final hours = (minutes / 60).ceil().clamp(1, 24);
        final rawPriority = row['priority']?.toString().toUpperCase() ?? 'MEDIUM';
        final priority = rawPriority == 'HIGH'
            ? 'High'
            : rawPriority == 'LOW'
                ? 'Low'
                : 'Medium';

        return Booking(
          id: row['id']?.toString() ?? '',
          machineId: row['machine_id']?.toString() ?? '',
          machineName: row['machine_name']?.toString() ?? 'Unknown Machine',
          jobTitle: row['title']?.toString() ?? 'Scheduled Work',
          userName: row['user_name']?.toString() ?? 'System',
          startTime: start,
          durationHours: hours,
          priority: priority,
          status: row['status']?.toString() ?? 'CONFIRMED',
        );
      }).toList();
    } catch (e) {
      debugPrint('fetchBookings failed: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchDashboardStats() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/dashboard-stats'));
      if (response.statusCode != 200) return {};
      return Map<String, dynamic>.from(json.decode(response.body));
    } catch (e) {
      debugPrint('fetchDashboardStats failed: $e');
      return {};
    }
  }

  Future<List<Job>> fetchJobsFiltered(int days) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/analytics-jobs?days=$days'));
      if (response.statusCode != 200) return [];
      final rows = List<Map<String, dynamic>>.from(json.decode(response.body));
      return rows.map(Job.fromJson).toList();
    } catch (e) {
      debugPrint('fetchJobsFiltered failed: $e');
      return [];
    }
  }

  /// Manager-created manual booking. The operator must match a real profile or
  /// linked resource because machine_bookings.requested_by_user_id is required.
  Future<bool> createBooking({
    required String machineId,
    required String userName,
    required String startTime,
    required String endTime,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/machine-bookings/manual'),
        headers: const {'Content-Type': 'application/json'},
        body: json.encode({
          'machine_id': machineId,
          'user_name': userName,
          'start_time': startTime,
          'end_time': endTime,
        }),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('createBooking failed: $e');
      return false;
    }
  }

  Future<bool> deleteBooking(String bookingId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/machine-bookings/$bookingId'),
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('deleteBooking failed: $e');
      return false;
    }
  }

  String _detail(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {}
    return 'Request failed (${response.statusCode})';
  }
}
