import 'package:flutter/material.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';
import 'package:optiflow_scheduler/slices/admin/approvals_screen.dart';
import 'package:optiflow_scheduler/slices/admin/capabilities_screen.dart';
import 'package:optiflow_scheduler/slices/admin/machines_screen.dart';
import 'package:optiflow_scheduler/slices/admin/team_screen.dart';
import 'package:optiflow_scheduler/slices/engine/jobs_screen.dart';
import 'package:optiflow_scheduler/slices/engine/schedule_screen.dart';

import 'widgets/sidebar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  bool _loading = true;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final stats = await ApiService.instance.fetchDashboardStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          Sidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: (index) => setState(() => _selectedIndex = index),
          ),
          Expanded(child: _page()),
        ],
      ),
    );
  }

  Widget _page() {
    return switch (_selectedIndex) {
      1 => const MachinesScreen(),
      2 => const JobsScreen(),
      3 => const ScheduleScreen(),
      4 => const TeamScreen(),
      5 => const CapabilitiesScreen(),
      6 => const ApprovalsScreen(),
      _ => _dashboard(),
    };
  }

  Widget _dashboard() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final offline = (_stats['offline_machines'] as List?)?.length ?? 0;
    final cards = [
      ('Total Jobs', _stats['total_jobs'] ?? 0, Icons.inventory_2_rounded),
      (
        'Pending Tasks',
        _stats['pending_tasks'] ?? 0,
        Icons.pending_actions_rounded,
      ),
      (
        'Active Machines',
        _stats['active_machines'] ?? 0,
        Icons.precision_manufacturing_rounded,
      ),
      ('Offline Machines', offline, Icons.warning_amber_rounded),
      (
        'Booking Approvals',
        _stats['pending_booking_approvals'] ?? 0,
        Icons.approval_rounded,
      ),
      (
        'Open External Work',
        _stats['open_external_work_offers'] ?? 0,
        Icons.work_outline_rounded,
      ),
    ];

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dashboard',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Live print-shop operations',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
              IconButton(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: cards
                .map((card) => _metricCard(card.$1, card.$2, card.$3))
                .toList(),
          ),
          const SizedBox(height: 28),
          _alerts(),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _operationSummary()),
              const SizedBox(width: 20),
              Expanded(child: _recentActivity()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, dynamic value, IconData icon) {
    return Container(
      width: 240,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _alerts() {
    final overdue = (_stats['overdue_jobs'] as List?) ?? [];
    final offline = (_stats['offline_machines'] as List?) ?? [];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attention Needed',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (overdue.isEmpty && offline.isEmpty)
            const Text(
              'No active alerts.',
              style: TextStyle(color: AppColors.success),
            )
          else ...[
            ...offline.map(
              (item) => _alertRow(
                Icons.power_off_rounded,
                '${item['name']} is ${item['status']}',
              ),
            ),
            ...overdue.map(
              (item) => _alertRow(
                Icons.schedule_rounded,
                '${item['title']} is overdue (${item['priority']})',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _operationSummary() {
    final raw = (_stats['tasks_by_op_type'] as Map?) ?? const {};
    final entries = raw.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));
    return _panel(
      'Tasks by Operation',
      entries.isEmpty
          ? const [
              Text(
                'No task data yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ]
          : entries
                .take(8)
                .map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(child: Text(entry.key.toString())),
                        Text(
                          entry.value.toString(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
    );
  }

  Widget _recentActivity() {
    final tasks = (_stats['recent_tasks'] as List?) ?? const [];
    final jobs = (_stats['new_jobs'] as List?) ?? const [];
    final children = <Widget>[];
    for (final raw in tasks.take(4)) {
      final task = Map<String, dynamic>.from(raw as Map);
      final job = task['jobs'] is Map ? (task['jobs'] as Map)['title'] : null;
      children.add(
        _activityRow(
          Icons.check_circle_outline_rounded,
          '${task['name']} completed${job == null ? '' : ' · $job'}',
        ),
      );
    }
    for (final raw in jobs.take(4)) {
      final job = Map<String, dynamic>.from(raw as Map);
      children.add(
        _activityRow(Icons.add_task_rounded, 'New job: ${job['title']}'),
      );
    }
    return _panel(
      'Recent Activity',
      children.isEmpty
          ? const [
              Text(
                'No recent activity.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ]
          : children,
    );
  }

  Widget _activityRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 17, color: AppColors.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );

  Widget _panel(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.surfaceLight),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );

  Widget _alertRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.warning),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    ),
  );
}
