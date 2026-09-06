import 'package:intl/intl.dart';

/// One human-executable DAG task shown on a worker/external user's phone.
class TaskModel {
  final String id;
  final String jobId;
  final String name;
  final String jobTitle;
  final String priority;
  final String operationName;
  final String status;
  final int quantityToProcess;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;

  const TaskModel({
    required this.id,
    required this.jobId,
    required this.name,
    required this.jobTitle,
    required this.priority,
    required this.operationName,
    required this.status,
    required this.quantityToProcess,
    this.scheduledStart,
    this.scheduledEnd,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    final job = json['jobs'] is Map
        ? Map<String, dynamic>.from(json['jobs'] as Map)
        : <String, dynamic>{};
    final operation = json['operation_types'] is Map
        ? Map<String, dynamic>.from(json['operation_types'] as Map)
        : <String, dynamic>{};

    DateTime? parse(dynamic value) {
      if (value == null) return null;
      return DateTime.tryParse(value.toString())?.toLocal();
    }

    return TaskModel(
      id: json['id']?.toString() ?? '',
      jobId: json['job_id']?.toString() ?? job['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Task',
      jobTitle: job['title']?.toString() ?? 'Print Job',
      priority: job['priority']?.toString() ?? 'MEDIUM',
      operationName: operation['name']?.toString() ?? 'Operation',
      status: json['status']?.toString().toUpperCase() ?? 'PENDING',
      quantityToProcess: (json['quantity_to_process'] as num?)?.toInt() ?? 0,
      scheduledStart: parse(json['scheduled_start_time']),
      scheduledEnd: parse(json['scheduled_end_time']),
    );
  }

  String get formattedDate => scheduledStart == null
      ? 'Not scheduled'
      : DateFormat('EEE, MMM d').format(scheduledStart!);

  String get formattedTime => scheduledStart == null
      ? ''
      : DateFormat('h:mm a').format(scheduledStart!);
}
