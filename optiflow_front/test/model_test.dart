import 'package:flutter_test/flutter_test.dart';
import 'package:optiflow_scheduler/mobile/models/job_model.dart';
import 'package:optiflow_scheduler/mobile/models/task_model.dart';

void main() {
  test('TaskModel parses backend mobile task shape', () {
    final task = TaskModel.fromJson({
      'id': 'task-1',
      'status': 'SCHEDULED',
      'job_title': 'Annual Report',
      'operation_type_name': 'Folding',
      'resource_name': 'Folder 1',
      'quantity_to_process': 500,
    });

    expect(task.id, 'task-1');
    expect(task.jobTitle, 'Annual Report');
    expect(task.operationTypeId, 'Folding');
    expect(task.quantityToProcess, 500);
  });

  test('JobModel parses paid work offer fields', () {
    final offer = JobModel.fromJson({
      'id': 'offer-1',
      'title': 'Fold brochures',
      'client_name': 'OptiFlow',
      'total_quantity': 1000,
      'status': 'OPEN',
      'pay_amount': 2500,
      'estimated_minutes': 90,
    });

    expect(offer.payAmount, 2500);
    expect(offer.estimatedMinutes, 90);
  });
}
