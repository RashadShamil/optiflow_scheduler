import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Read-oriented Supabase service used by the manager dashboard.
///
/// The current tasks table has multiple foreign keys to resources. Instead of
/// relying on ambiguous PostgREST nested joins, this service performs explicit
/// reads and joins the small manager datasets in memory.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _db => Supabase.instance.client;

  Map<String, dynamic>? _statsCache;
  DateTime? _statsCacheTime;

  void invalidateCache() {
    _statsCache = null;
    _statsCacheTime = null;
  }

  Future<List<Map<String, dynamic>>> fetchResources() async {
    try {
      final rows = await _db.from('resources').select('*').order('name');
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[SupabaseService] fetchResources: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchMachines() async {
    final rows = await fetchResources();
    return rows
        .where((r) => r['type']?.toString().toUpperCase() == 'MACHINE')
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchHumanResources() async {
    final rows = await fetchResources();
    return rows
        .where((r) => r['type']?.toString().toUpperCase() == 'HUMAN')
        .toList();
  }

  Future<void> updateMachine({
    required String id,
    required String name,
    required String type,
    required String status,
  }) async {
    await _db
        .from('resources')
        .update({'name': name, 'type': type, 'status': status})
        .eq('id', id);
    invalidateCache();
  }

  Future<void> deleteMachine(String id) async {
    await _db.from('resources').delete().eq('id', id);
    invalidateCache();
  }

  Future<void> updateTeamMember({
    required String id,
    required String name,
    required String status,
  }) async {
    await _db
        .from('resources')
        .update({'name': name, 'status': status})
        .eq('id', id);
    invalidateCache();
  }

  Future<List<Map<String, dynamic>>> fetchJobs() async {
    try {
      final rows = await _db
          .from('jobs')
          .select('*')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[SupabaseService] fetchJobs: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _rawTasks() async {
    try {
      final rows = await _db.from('tasks').select('*');
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[SupabaseService] _rawTasks: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchOperationTypes() async {
    try {
      final rows = await _db.from('operation_types').select('*').order('name');
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (e) {
      debugPrint('[SupabaseService] fetchOperationTypes: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchJobsWithTasks() async {
    try {
      final results = await Future.wait([
        fetchJobs(),
        _rawTasks(),
        fetchResources(),
        fetchOperationTypes(),
      ]);
      final jobs = results[0];
      final tasks = results[1];
      final resources = results[2];
      final operations = results[3];

      final resourceById = {for (final r in resources) r['id'].toString(): r};
      final opById = {for (final o in operations) o['id'].toString(): o};
      final grouped = <String, List<Map<String, dynamic>>>{};

      for (final task in tasks) {
        final resourceId =
            task['assigned_machine_id'] ?? task['assigned_resource_id'];
        final decorated = <String, dynamic>{
          ...task,
          'resources': resourceId == null
              ? null
              : resourceById[resourceId.toString()],
          'operation_types': opById[task['operation_type_id']?.toString()],
        };
        grouped.putIfAbsent(task['job_id'].toString(), () => []).add(decorated);
      }

      return jobs
          .map(
            (job) => <String, dynamic>{
              ...job,
              'tasks':
                  grouped[job['id'].toString()] ?? <Map<String, dynamic>>[],
            },
          )
          .toList();
    } catch (e) {
      debugPrint('[SupabaseService] fetchJobsWithTasks: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllTasks() async {
    try {
      final results = await Future.wait([
        _rawTasks(),
        fetchJobs(),
        fetchResources(),
        fetchOperationTypes(),
      ]);
      final tasks = results[0];
      final jobs = results[1];
      final resources = results[2];
      final operations = results[3];

      final jobById = {for (final j in jobs) j['id'].toString(): j};
      final resourceById = {for (final r in resources) r['id'].toString(): r};
      final opById = {for (final o in operations) o['id'].toString(): o};

      return tasks.map((task) {
        final resourceId =
            task['assigned_machine_id'] ?? task['assigned_resource_id'];
        return <String, dynamic>{
          ...task,
          'jobs': jobById[task['job_id']?.toString()],
          'resources': resourceId == null
              ? null
              : resourceById[resourceId.toString()],
          'operation_types': opById[task['operation_type_id']?.toString()],
        };
      }).toList();
    } catch (e) {
      debugPrint('[SupabaseService] fetchAllTasks: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchCapabilities() async {
    try {
      final results = await Future.wait([
        _db.from('resource_capabilities').select('*'),
        fetchResources(),
        fetchOperationTypes(),
      ]);
      final capabilities = List<Map<String, dynamic>>.from(results[0] as List);
      final resources = List<Map<String, dynamic>>.from(results[1] as List);
      final operations = List<Map<String, dynamic>>.from(results[2] as List);

      final resourceById = {for (final r in resources) r['id'].toString(): r};
      final opById = {for (final o in operations) o['id'].toString(): o};

      return capabilities
          .map(
            (cap) => <String, dynamic>{
              ...cap,
              'resources': resourceById[cap['resource_id']?.toString()],
              'operation_types': opById[cap['operation_type_id']?.toString()],
            },
          )
          .toList();
    } catch (e) {
      debugPrint('[SupabaseService] fetchCapabilities: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchDashboardStats() async {
    if (_statsCache != null &&
        _statsCacheTime != null &&
        DateTime.now().difference(_statsCacheTime!).inSeconds < 60) {
      return _statsCache!;
    }

    try {
      final results = await Future.wait([
        fetchMachines(),
        fetchJobs(),
        fetchAllTasks(),
      ]);
      final machines = results[0];
      final jobs = results[1];
      final tasks = results[2];

      final active = machines.where((m) => m['status'] == 'ACTIVE').toList();
      final idle = machines.where((m) => m['status'] == 'IDLE').toList();
      final offline = machines
          .where(
            (m) => m['status'] == 'OFFLINE' || m['status'] == 'MAINTENANCE',
          )
          .toList();
      final pending = tasks.where((t) => t['status'] == 'PENDING').toList();
      final inProgress = tasks
          .where((t) => t['status'] == 'IN_PROGRESS')
          .toList();
      final completed = tasks.where((t) => t['status'] == 'COMPLETED').toList();

      final tasksByType = <String, int>{};
      for (final task in tasks) {
        final name =
            (task['operation_types'] as Map?)?['name']?.toString() ?? 'Other';
        tasksByType[name] = (tasksByType[name] ?? 0) + 1;
      }

      final now = DateTime.now();
      final overdue = jobs.where((job) {
        if (job['status'] == 'COMPLETED' || job['status'] == 'REVIEW')
          return false;
        final raw = job['deadline'];
        if (raw == null) return false;
        try {
          return DateTime.parse(raw.toString()).isBefore(now);
        } catch (_) {
          return false;
        }
      }).toList();

      final stats = <String, dynamic>{
        'active_machines': active.length,
        'idle_machines': idle.length,
        'offline_machines': offline,
        'total_machines': machines.length,
        'total_jobs': jobs.length,
        'total_tasks': tasks.length,
        'pending_tasks': pending.length,
        'in_progress_tasks': inProgress.length,
        'completed_tasks': completed.length,
        'tasks_by_op_type': tasksByType,
        'recent_tasks': completed.take(5).toList(),
        'new_jobs': jobs.take(5).toList(),
        'overdue_jobs': overdue,
        'uptime_pct': machines.isEmpty
            ? 0.0
            : active.length / machines.length * 100.0,
      };
      _statsCache = stats;
      _statsCacheTime = DateTime.now();
      return stats;
    } catch (e) {
      debugPrint('[SupabaseService] fetchDashboardStats: $e');
      return {};
    }
  }
}
