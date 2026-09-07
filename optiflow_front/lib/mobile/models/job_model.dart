import 'package:intl/intl.dart';

/// Paid external work offer shown in the existing Job Market UI.
class JobModel {
  final String id;
  final String title;
  final String clientName;
  final int totalQuantity;
  final String status;
  final DateTime? deadline;
  final double? payAmount;
  final int? estimatedMinutes;

  const JobModel({
    required this.id,
    required this.title,
    required this.clientName,
    required this.totalQuantity,
    required this.status,
    this.deadline,
    this.payAmount,
    this.estimatedMinutes,
  });

  factory JobModel.fromJson(Map<String, dynamic> json) {
    DateTime? parsedDeadline;
    try {
      final raw = json['deadline'];
      if (raw != null) parsedDeadline = DateTime.parse(raw.toString()).toLocal();
    } catch (_) {}

    return JobModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'External Work',
      clientName: json['client_name']?.toString() ?? 'OptiFlow',
      totalQuantity: (json['total_quantity'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'OPEN',
      deadline: parsedDeadline,
      payAmount: (json['pay_amount'] as num?)?.toDouble(),
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
    );
  }

  String get formattedDeadline =>
      deadline == null ? 'No deadline' : 'Due ${DateFormat('MMM d').format(deadline!)}';
}
