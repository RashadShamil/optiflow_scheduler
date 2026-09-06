/// Individual manager-approved HUMAN task offered to external workers.
class WorkOfferModel {
  final String id;
  final String taskId;
  final String title;
  final String jobTitle;
  final String operation;
  final int quantity;
  final double payAmount;
  final int estimatedMinutes;
  final String status;

  const WorkOfferModel({
    required this.id,
    required this.taskId,
    required this.title,
    required this.jobTitle,
    required this.operation,
    required this.quantity,
    required this.payAmount,
    required this.estimatedMinutes,
    required this.status,
  });

  factory WorkOfferModel.fromJson(Map<String, dynamic> json) {
    final task = json['tasks'] is Map
        ? Map<String, dynamic>.from(json['tasks'] as Map)
        : <String, dynamic>{};
    final job = task['jobs'] is Map
        ? Map<String, dynamic>.from(task['jobs'] as Map)
        : <String, dynamic>{};
    final operation = task['operation_types'] is Map
        ? Map<String, dynamic>.from(task['operation_types'] as Map)
        : <String, dynamic>{};
    return WorkOfferModel(
      id: json['id']?.toString() ?? '',
      taskId: task['id']?.toString() ?? '',
      title: task['name']?.toString() ?? 'Manual Task',
      jobTitle: job['title']?.toString() ?? 'Print Job',
      operation: operation['name']?.toString() ?? 'Manual work',
      quantity: (task['quantity_to_process'] as num?)?.toInt() ?? 0,
      payAmount: (json['pay_amount'] as num?)?.toDouble() ?? 0,
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'OPEN',
    );
  }
}
