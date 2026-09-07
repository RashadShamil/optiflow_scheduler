import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:optiflow_scheduler/core/services/api_service.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';

class TaskItem {
  final String id;
  TextEditingController nameController;
  TextEditingController quantityController;
  String? operationType;
  List<String> dependsOn;

  TaskItem({
    required this.id,
    required this.nameController,
    required this.quantityController,
    this.operationType,
    required this.dependsOn,
  });
}

class NewJobOrder extends StatefulWidget {
  final VoidCallback? onJobCreated;
  const NewJobOrder({super.key, this.onJobCreated});

  @override
  State<NewJobOrder> createState() => _NewJobOrderState();
}

class _NewJobOrderState extends State<NewJobOrder> {
  final TextEditingController _jobNameController = TextEditingController();
  final TextEditingController _clientNameController = TextEditingController();
  final TextEditingController _totalQuantityController = TextEditingController();
  String _priority = 'Medium';
  DateTime? _deadline;

  final List<TaskItem> _tasks = [];
  int _taskIdCounter = 1;

  List<Map<String, dynamic>> _operationTypes = [];
  bool _isLoadingOps = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _fetchOperationTypes();
  }

  Future<void> _fetchOperationTypes() async {
    final ops = await ApiService().fetchOperationTypes();
    if (mounted) {
      setState(() {
        _operationTypes = ops;
        _isLoadingOps = false;
      });
    }
  }

  void _addTask() {
    setState(() {
      _tasks.add(
        TaskItem(
          id: 'T${_taskIdCounter++}',
          nameController: TextEditingController(),
          quantityController: TextEditingController(),
          operationType: _operationTypes.isNotEmpty ? _operationTypes.first['id'] : null,
          dependsOn: [],
        ),
      );
    });
  }

  void _removeTask(int index) {
    setState(() {
      final removedTaskId = _tasks[index].id;
      _tasks.removeAt(index);
      for (var task in _tasks) {
        task.dependsOn.remove(removedTaskId);
      }
    });
  }

  Future<void> _selectDeadline(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.textPrimary,
            ), dialogTheme: DialogThemeData(backgroundColor: AppColors.surface),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _deadline) {
      setState(() {
        _deadline = picked;
      });
    }
  }

  Future<void> _showMultiSelect(BuildContext context, TaskItem currentTask) async {
    int currentIndex = _tasks.indexOf(currentTask);
    List<TaskItem> availableTasks = _tasks.sublist(0, currentIndex);

    if (availableTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No previous tasks available to depend on.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: AppColors.surfaceLight.withOpacity(0.5)),
              ),
              title: const Text(
                'Select Dependencies',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: ListBody(
                  children: availableTasks.map((task) {
                    final isChecked = currentTask.dependsOn.contains(task.id);
                    final titleText = task.nameController.text.isNotEmpty
                        ? task.nameController.text
                        : 'Unnamed Task (${task.id})';
                    return CheckboxListTile(
                      title: Text(
                        titleText,
                        style: const TextStyle(color: AppColors.textPrimary),
                      ),
                      value: isChecked,
                      activeColor: AppColors.primary,
                      checkColor: Colors.white,
                      side: const BorderSide(color: AppColors.textSecondary),
                      onChanged: (bool? value) {
                        setDialogState(() {
                          if (value == true) {
                            currentTask.dependsOn.add(task.id);
                          } else {
                            currentTask.dependsOn.remove(task.id);
                          }
                        });
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitOrder() async {
    if (_jobNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a job name'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() { _isSubmitting = true; });

    List<Map<String, dynamic>> tasksData = [];
    for (int i = 0; i < _tasks.length; i++) {
      final task = _tasks[i];
      // Guard: every task MUST have an operation type — without it the
      // CP-SAT optimizer crashes on AddExactlyOne([]) with an empty list.
      if (task.operationType == null || task.operationType!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Task "${task.nameController.text.isNotEmpty ? task.nameController.text : task.id}" '
                  'has no operation type selected. Please assign one before submitting.'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        setState(() { _isSubmitting = false; });
        return;
      }
      tasksData.add({
        'name': task.nameController.text.isNotEmpty ? task.nameController.text : "Task ${task.id}",
        'operation_type_id': task.operationType,
        'quantity_to_process': int.tryParse(task.quantityController.text) ??
                               int.tryParse(_totalQuantityController.text) ?? 0,
      });
    }


    List<Map<String, dynamic>> dependencies = [];
    for (int i = 0; i < _tasks.length; i++) {
      var task = _tasks[i];
      for (var depId in task.dependsOn) {
        int predIndex = _tasks.indexWhere((t) => t.id == depId);
        if (predIndex != -1) {
          dependencies.add({
            'predecessor_index': predIndex,
            'successor_index': i,
            'mandatory_wait_minutes': 0,
          });
        }
      }
    }

    Map<String, dynamic> orderData = {
      "title": _jobNameController.text,
      "client_name": _clientNameController.text.isEmpty ? "Unknown" : _clientNameController.text,
      "total_quantity": int.tryParse(_totalQuantityController.text) ?? 1,
      "deadline": _deadline?.toIso8601String() ?? DateTime.now().add(const Duration(days: 7)).toIso8601String(),
      "priority": _priority.toUpperCase(),
      "created_by": null, 
      "tasks": tasksData,
      "dependencies": dependencies,
    };

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/create_job'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(orderData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Job Order Submitted Successfully!'),
              backgroundColor: AppColors.success,
            ),
          );
          _jobNameController.clear();
          _clientNameController.clear();
          _totalQuantityController.clear();
          setState(() {
            _tasks.clear();
            _taskIdCounter = 1;
            _deadline = null;
          });
          widget.onJobCreated?.call(); // Notify parent to refresh list
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to submit: ${response.statusCode}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting order: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() { _isSubmitting = false; });
    }
  }

  @override
  void dispose() {
    _jobNameController.dispose();
    _clientNameController.dispose();
    _totalQuantityController.dispose();
    for (var task in _tasks) {
      task.nameController.dispose();
      task.quantityController.dispose();
    }
    super.dispose();
  }

  InputDecoration _customInputDecoration(String label, String? hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      filled: true,
      fillColor: AppColors.surfaceLight.withOpacity(0.4),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.surfaceLight.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'New Job Order',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 32),

          // --- SECTION 1: ORDER DETAILS ---
          const Text(
            'Section 1: Order Details',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.surfaceLight.withOpacity(0.5)),
          const SizedBox(height: 24),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _jobNameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: _customInputDecoration('Job Name', 'e.g., 500 Diaries'),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _clientNameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: _customInputDecoration('Client Name', 'e.g., Acme Corp'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _totalQuantityController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: _customInputDecoration('Total Quantity', 'e.g., 500'),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: _customInputDecoration('Priority', null),
                  dropdownColor: AppColors.surfaceLight,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                  icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                  items: ['High', 'Medium', 'Low'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _priority = newValue!;
                    });
                  },
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 1,
                child: GestureDetector(
                  onTap: () => _selectDeadline(context),
                  child: Container(
                    height: 56, // Match height of TextFields
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _deadline == null
                              ? 'Deadline'
                              : DateFormat('MMM d, yyyy').format(_deadline!),
                          style: TextStyle(
                            color: _deadline == null
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            fontSize: 16,
                          ),
                        ),
                        const Icon(
                          Icons.calendar_today,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 48),

          // --- SECTION 2: DYNAMIC TASK SEQUENCE BUILDER ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Section 2: Task Sequence (DAG)',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _addTask,
                icon: const Icon(Icons.add, color: Colors.white, size: 18),
                label: const Text(
                  'Add Task',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceLight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppColors.surfaceLight.withOpacity(0.8)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: AppColors.surfaceLight.withOpacity(0.5)),
          const SizedBox(height: 24),

          if (_tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.account_tree_outlined, size: 48, color: AppColors.textSecondary.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    Text(
                      'No tasks added yet. Click "Add Task" to begin.',
                      style: TextStyle(
                        color: AppColors.textSecondary.withOpacity(0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _tasks.length,
            itemBuilder: (context, index) {
              final task = _tasks[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight.withOpacity(0.2),
                  border: Border.all(color: AppColors.surfaceLight.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 8, right: 20),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withOpacity(0.2),
                          border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: task.nameController,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _customInputDecoration('Task Name', 'e.g., Print Cover'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: task.quantityController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _customInputDecoration('Qty', 'e.g., 500'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: _isLoadingOps 
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                        : DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: task.operationType,
                        decoration: _customInputDecoration('Operation Type', null),
                        dropdownColor: AppColors.surfaceLight,
                        icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
                        items: _operationTypes.map((op) {
                              return DropdownMenuItem<String>(
                                value: op['id'].toString(),
                                child: Text(op['name'].toString(), overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                        onChanged: (newValue) {
                          setState(() {
                            task.operationType = newValue;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        onTap: () => _showMultiSelect(context, task),
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  task.dependsOn.isEmpty
                                      ? 'Depends On'
                                      : '${task.dependsOn.length} Selected',
                                  style: TextStyle(
                                    color: task.dependsOn.isEmpty
                                        ? AppColors.textSecondary
                                        : AppColors.textPrimary,
                                    fontSize: 16,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.link, color: AppColors.primary, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      child: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.error,
                        ),
                        onPressed: () => _removeTask(index),
                        tooltip: 'Remove Task',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 40),

          Center(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: AppColors.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting 
                  ? const SizedBox(
                      width: 24, height: 24, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    )
                  : const Text(
                  'Submit Order',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
