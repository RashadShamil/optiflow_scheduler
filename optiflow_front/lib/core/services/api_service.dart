import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:optiflow_scheduler/core/models/booking.dart';
import 'package:http/http.dart' as http;
import 'package:optiflow_scheduler/core/models/job.dart';
import 'package:optiflow_scheduler/core/models/machine.dart';

class ApiService {
  static String get baseUrl {
    if (!kIsWeb) {
      // If we are native (e.g. Android Emulator), you might need 10.0.2.2.
      // But for desktop/web, 127.0.0.1 is standard.
      return "https://e22-co2060-optiflow.onrender.com/api";
    }
    return "https://e22-co2060-optiflow.onrender.com/api";
  }

  // ==========================================
  // ENGINE SLICE
  // ==========================================
  Future<Map<String, dynamic>> optimizeJob(String jobId) async {
    try {
      final response = await http.post(Uri.parse("$baseUrl/optimize/$jobId"));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception("Failed to optimize job");
      }
    } catch (e) {
      print("Error optimizing job: $e");
      return {"status": "error"};
    }
  }

  // ==========================================
  // ORDER SLICE
  // ==========================================
  Future<Map<String, dynamic>> createJob(Map<String, dynamic> jobData) async {
    try {
      final response = await http.post(
        Uri.parse("${baseUrl.replaceAll('/api', '')}/create_job"),
        headers: {"Content-Type": "application/json"},
        body: json.encode(jobData),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception("Failed to create job: ${response.statusCode}");
      }
    } catch (e) {
      print("Error creating job: $e");
      return {"status": "error"};
    }
  }

  /// Publish a DRAFT job so workers can see it in the mobile Job Market.
  /// Calls PATCH /api/jobs/{jobId}/publish → sets status to OPEN.
  Future<Map<String, dynamic>> publishJob(String jobId) async {
    try {
      final response = await http.patch(
        Uri.parse("$baseUrl/jobs/$jobId/publish"),
        headers: {"Content-Type": "application/json"},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        final body = json.decode(response.body);
        throw Exception(body['detail'] ?? "Failed to publish job");
      }
    } catch (e) {
      print("Error publishing job: $e");
      rethrow;
    }
  }

  Future<void> createTask(Map<String, dynamic> taskData) async {
    // POST /api/tasks
  }


  Future<List<Map<String, dynamic>>> fetchOperationTypes() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/operation-types"));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      } else {
        throw Exception("Failed to load operation types");
      }
    } catch (e) {
      print("Error fetching operation types: $e");
      return [];
    }
  }

  // ==========================================
  // WORKER SLICE
  // ==========================================
  Future<List<dynamic>> getTasksForResource(String resourceId) async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/tasks?resource_id=$resourceId"));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception("Failed to load tasks for resource");
      }
    } catch (e) {
      print("Error fetching tasks for resource: $e");
      return [];
    }
  }

  Future<void> updateTaskStatus(String taskId, String status) async {
    // PATCH /api/tasks/{task_id}/status {"status": status}
  }

  // ==========================================
  // ADMIN SLICE
  // ==========================================
  Future<List<Machine>> fetchMachines() async {
    try {
      // Fetch ALL resources (MACHINE and HUMAN) so that tasks assigned to human
      // workers also appear as rows on the Gantt chart.
      final response = await http.get(Uri.parse("$baseUrl/resources"));

      if (response.statusCode == 200) {
        final dynamic data = json.decode(response.body);
        List<dynamic> resourcesJson = [];
        if (data is List) {
          resourcesJson = data; // No type filter — include MACHINE and HUMAN
        } else if (data is Map) {
          resourcesJson = data['resources'] ?? data['machines'] ?? [];
        }
        return resourcesJson.map((json) => Machine.fromJson(json)).toList();
      } else {
        throw Exception("Failed to load resources");
      }
    } catch (e) {
      print("Error fetching resources: $e");
      return [];
    }
  }

  Future<void> createResource(Map<String, dynamic> resourceData) async {
    // POST /api/resources
  }

  Future<void> createCapability(Map<String, dynamic> capabilityData) async {
    // POST /api/capabilities
  }

  Future<List<Job>> fetchJobs() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/jobs"));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> jobsJson = data['jobs'] ?? [];
        return jobsJson.map((json) => Job.fromJson(json)).toList();
      } else {
        throw Exception("Failed to load jobs");
      }
    } catch (e) {
      print("Error fetching jobs: $e");
      return [];
    }
  }

  Future<List<Booking>> fetchBookings() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/schedule"));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Booking> bookings = [];

        for (final item in data) {
          // Skip tasks that have not been assigned to a resource yet
          // (unoptimized tasks) — they would render as empty Gantt blocks.
          final resourceId = item['assigned_resource_id']?.toString();
          if (resourceId == null || resourceId.isEmpty) continue;

          final startTime = item['scheduled_start_time'] != null
              ? DateTime.parse(item['scheduled_start_time']).toLocal()
              : DateTime.now();
          final endTime = item['scheduled_end_time'] != null
              ? DateTime.parse(item['scheduled_end_time']).toLocal()
              : startTime.add(const Duration(hours: 1));

          // Use minutes for better resolution; Gantt renders in hours but
          // ensure at least 1 hour block so tiny tasks are still visible.
          final durationMinutes = endTime.difference(startTime).inMinutes;
          final durationHours   = (durationMinutes / 60).ceil().clamp(1, 24);

          // Color: 'High' = blue (machine), 'Medium' = teal (human worker)
          final resourceType = item['resources']?['type']?.toString() ?? 'MACHINE';
          final priority = resourceType == 'HUMAN' ? 'Medium' : 'High';

          bookings.add(Booking(
            id:           item['id']?.toString() ?? '',
            machineId:    resourceId,
            machineName:  item['resources']?['name']?.toString() ?? 'Unknown Resource',
            jobTitle:     item['jobs']?['title']?.toString() ?? item['name']?.toString() ?? 'Unknown Job',
            userName:     item['resources']?['name']?.toString() ?? 'System',
            startTime:    startTime,
            durationHours: durationHours,
            priority:     priority,
            status:       item['status'] == 'CONFLICT' ? 'CONFLICT' : 'CONFIRMED',
          ));
        }
        return bookings;
      } else {
        throw Exception("Failed to load schedule");
      }
    } catch (e) {
      print("Error fetching schedule: $e");
      return [];
    }
  }


  Future<List<Map<String, dynamic>>> fetchHumanResources() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/resources"));
      if (response.statusCode == 200) {
        final dynamic raw = json.decode(response.body);
        List<dynamic> data;
        if (raw is List) {
          data = raw;
        } else if (raw is Map) {
          data = raw['resources'] ?? raw['data'] ?? [];
        } else {
          data = [];
        }
        return data
            .where((r) => r['type'] == 'HUMAN')
            .map((e) => e as Map<String, dynamic>)
            .toList();
      }
      return [];
    } catch (e) {
      print("Error fetching human resources: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllTasks() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/tasks"));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
      return [];
    } catch (e) {
      print("Error fetching all tasks: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchDashboardStats() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/dashboard-stats"));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return {};
    } catch (e) {
      print("Error fetching dashboard stats: $e");
      return {};
    }
  }

  Future<List<Job>> fetchJobsFiltered(int days) async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/analytics-jobs?days=$days"));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((j) => Job.fromJson(j)).toList();
      }
      return [];
    } catch (e) {
      print("Error fetching filtered jobs: $e");
      return [];
    }
  }

  Future<bool> createBooking({
    required String machineId,
    required String userName,
    required String startTime,
    required String endTime,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/book_machine"),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          "machine_id": machineId,
          "user_name": userName,
          "start_time": startTime,
          "end_time": endTime,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Error creating booking: $e");
      return false;
    }
  }

  /// Cancels / deletes a booking by ID.
  Future<bool> deleteBooking(String bookingId) async {
    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/bookings/$bookingId"),
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print("Error deleting booking: $e");
      return false;
    }
  }
}
