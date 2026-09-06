import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';

import '../core/app_theme.dart';
import '../models/task_model.dart';

/// Worker task details and the Accept -> Start -> Complete workflow.
class TaskBottomSheet extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onStatusChanged;

  const TaskBottomSheet({
    super.key,
    required this.task,
    required this.onStatusChanged,
  });

  @override
  State<TaskBottomSheet> createState() => _TaskBottomSheetState();
}

class _TaskBottomSheetState extends State<TaskBottomSheet> {
  bool _loading = false;

  Future<void> _run(Future<void> Function() action) async {
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      await action();
      if (!mounted) return;
      widget.onStatusChanged();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bottomSheet,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: SheetHandle()),
          const SizedBox(height: 20),
          Text(
            task.name,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            task.jobTitle,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _row(Icons.flag_outlined, 'Priority', task.priority),
          _row(Icons.category_outlined, 'Operation', task.operationName),
          _row(
            Icons.inventory_2_outlined,
            'Quantity',
            '${task.quantityToProcess} units',
          ),
          _row(
            Icons.schedule_rounded,
            'Scheduled',
            '${task.formattedDate} ${task.formattedTime}'.trim(),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: _actionButton(task),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(TaskModel task) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (task.status == 'OFFERED' || task.status == 'SCHEDULED') {
      return ElevatedButton(
        onPressed: () => _run(() => ApiService.instance.acceptTask(task.id)),
        style: AppTheme.pillButtonStyle(bg: const Color(0xFF222222)),
        child: const Text('Accept Task'),
      );
    }
    if (task.status == 'ACCEPTED') {
      return ElevatedButton(
        onPressed: () => _run(() => ApiService.instance.startTask(task.id)),
        style: AppTheme.pillButtonStyle(bg: const Color(0xFF222222)),
        child: const Text('Start Work'),
      );
    }
    if (task.status == 'IN_PROGRESS') {
      return ElevatedButton(
        onPressed: () => _run(() => ApiService.instance.completeTask(task.id)),
        style: AppTheme.pillButtonStyle(bg: AppColors.primary),
        child: const Text('Mark Completed'),
      );
    }
    return const Center(
      child: Text(
        'Completed',
        style: TextStyle(
          color: AppColors.completed,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDisabled,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
