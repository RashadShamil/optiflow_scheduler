import 'package:intl/intl.dart';

/// Task presented to a mobile worker or an outsider who claimed a work offer.
class TaskModel {
  final String id;
  final String status;
  final String jobTitle;
  final String operationTypeId;
  final String resourceName;
  final int quantityToProcess;
  final DateTime? scheduledStart;

  const TaskModel({
    required this.id,
    required this.status,
    required this.jobTitle,
    required this.operationTypeId,
    required this.resourceName,
    required this.quantityToProcess,
    this.scheduledStart,
  });

  factory TaskModel.fromJson(Map<String, dynamic> json) {
    DateTime? parsedTime;
    try {
      final raw = json['scheduled_start_time'];
      if (raw != null) parsedTime = DateTime.parse(raw.toString()).toLocal();
    } catch (_) {}

    return TaskModel(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'SCHEDULED',
      jobTitle: json['job_title']?.toString() ??
          (json['jobs'] as Map?)?['title']?.toString() ??
          'Untitled Job',
      operationTypeId: json['operation_type_name']?.toString() ??
          json['operation_type_id']?.toString() ??
          'Operation',
      resourceName: json['resource_name']?.toString() ??
          (json['resources'] as Map?)?['name']?.toString() ??
          'Unassigned',
      quantityToProcess: (json['quantity_to_process'] as num?)?.toInt() ?? 0,
      scheduledStart: parsedTime,
    );
  }

  String get formattedTime =>
      scheduledStart == null ? 'Ready' : DateFormat('h:mm a').format(scheduledStart!);

  String get formattedDate => scheduledStart == null
      ? 'Available now'
      : DateFormat('MMM d, yyyy').format(scheduledStart!);
}
