import 'package:flutter/material.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';

import '../core/app_theme.dart';
import '../core/auth_service.dart';
import '../models/task_model.dart';
import '../widgets/shimmer_card.dart';
import '../widgets/task_bottom_sheet.dart';
import '../widgets/task_card.dart';

/// Shared "My Work" screen for internal workers and external task claimants.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<TaskModel> _tasks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ApiService.instance.fetchMyTasks();
      final tasks = rows.map(TaskModel.fromJson).toList();
      const order = {
        'OFFERED': 0,
        'ACCEPTED': 1,
        'IN_PROGRESS': 2,
        'SCHEDULED': 3,
        'COMPLETED': 4,
      };
      tasks.sort((a, b) => (order[a.status] ?? 9).compareTo(order[b.status] ?? 9));
      if (mounted) {
        setState(() {
          _tasks = tasks;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _openTask(TaskModel task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskBottomSheet(task: task, onStatusChanged: _loadTasks),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Work', style: TextStyle(fontWeight: FontWeight.w900)),
            Text(
              AuthService.instance.displayName,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: _loadTasks, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTasks,
        color: AppColors.primary,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: const [
          ShimmerCard(width: double.infinity, height: 150),
          SizedBox(height: 16),
          ShimmerCard(width: double.infinity, height: 150),
        ],
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 100),
          const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.offline),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _loadTasks, style: AppTheme.pillButtonStyle(), child: const Text('Retry')),
        ],
      );
    }

    if (_tasks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.done_all_rounded, size: 64, color: AppColors.completed),
          SizedBox(height: 16),
          Text('No assigned work', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          Text('Accepted and dispatched tasks will appear here.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 100),
      children: _tasks.map((task) => TaskCard(task: task, onTap: () => _openTask(task))).toList(),
    );
  }
}
