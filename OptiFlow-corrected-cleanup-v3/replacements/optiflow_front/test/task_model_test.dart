import 'package:flutter_test/flutter_test.dart';
import 'package:optiflow_scheduler/mobile/models/task_model.dart';

void main() {
  test('TaskModel maps joined API data', () {
    final task = TaskModel.fromJson({
      'id': 't1',
      'job_id': 'j1',
      'name': 'Fold brochures',
      'status': 'OFFERED',
      'quantity_to_process': 100,
      'jobs': {'id': 'j1', 'title': 'Brochures', 'priority': 'HIGH'},
      'operation_types': {'name': 'Folding'},
    });

    expect(task.name, 'Fold brochures');
    expect(task.jobTitle, 'Brochures');
    expect(task.operationName, 'Folding');
    expect(task.priority, 'HIGH');
    expect(task.status, 'OFFERED');
  });
}
