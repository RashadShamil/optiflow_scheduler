import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/task_model.dart';

/// Compact worker task card used by both internal and external users.
class TaskCard extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onTap;

  const TaskCard({super.key, required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (task.status) {
      'OFFERED' => AppColors.primary,
      'ACCEPTED' => AppColors.primary,
      'IN_PROGRESS' => AppColors.primary,
      'COMPLETED' => AppColors.completed,
      _ => AppColors.textSecondary,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: AppTheme.cardDecoration(),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        task.priority,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(task.jobTitle, style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 8),
                  Text(
                    '${task.operationName} · ${task.status}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textDisabled),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${task.quantityToProcess}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(task.formattedTime, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
