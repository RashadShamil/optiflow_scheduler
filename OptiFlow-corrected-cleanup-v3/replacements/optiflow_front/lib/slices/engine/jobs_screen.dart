import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';

/// Manager job/DAG workspace.
///
/// A job is created first. Nothing is scheduled until the manager explicitly
/// presses Optimize. Each task states whether it needs a machine, a human, or
/// both; the capability matrix decides the actual resources.
class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  final Set<String> _expanded = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    setState(() => _loading = true);
    try {
      final jobs = await ApiService.instance.fetchJobsWithTasks();
      if (mounted) setState(() { _jobs = jobs; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _optimize(String jobId) async {
    setState(() => _busy.add(jobId));
    try {
      final result = await ApiService.instance.optimizeJob(jobId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Schedule ${result['quality']} · ${result['scheduled_tasks']} movable tasks · ${result['shop_hours']}',
          ),
        ),
      );
      await _loadJobs();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(jobId));
    }
  }

  Future<void> _dispatch(Map<String, dynamic> task) async {
    try {
      await ApiService.instance.dispatchTask(task['id'].toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task sent to worker mobile app.')));
      }
      await _loadJobs();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _publishExternal(Map<String, dynamic> task) async {
    final pay = TextEditingController();
    final minutes = TextEditingController(text: task['processing_time_minutes']?.toString() ?? '60');
    final notes = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish External Human Task'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('This publishes only "${task['name']}" — not the entire print job.'),
              const SizedBox(height: 14),
              TextField(
                controller: pay,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Payment (Rs.)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Estimated minutes'),
              ),
              const SizedBox(height: 12),
              TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve & Publish')),
        ],
      ),
    );

    if (confirmed != true) return;
    final amount = double.tryParse(pay.text);
    final estimate = int.tryParse(minutes.text);
    if (amount == null || amount <= 0 || estimate == null || estimate <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid payment and estimated time.')));
      return;
    }

    try {
      await ApiService.instance.publishWorkOffer(
        taskId: task['id'].toString(),
        payAmount: amount,
        estimatedMinutes: estimate,
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Human task published to external workers.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const Text('Jobs', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        const Text(
          'Create the process DAG first. Optimize only when you want the scheduler to place it.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (_, constraints) {
            if (constraints.maxWidth >= 1100) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _jobList()),
                  const SizedBox(width: 24),
                  Expanded(child: _NewJobForm(onCreated: _loadJobs)),
                ],
              );
            }
            return Column(children: [_jobList(), const SizedBox(height: 24), _NewJobForm(onCreated: _loadJobs)]);
          },
        ),
      ],
    );
  }

  Widget _jobList() {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Existing Jobs (${_jobs.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                IconButton(onPressed: _loadJobs, icon: const Icon(Icons.refresh_rounded)),
              ],
            ),
            const Divider(),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_jobs.isEmpty)
              const Padding(padding: EdgeInsets.all(32), child: Text('No jobs yet.'))
            else
              ..._jobs.map(_jobTile),
          ],
        ),
      ),
    );
  }

  Widget _jobTile(Map<String, dynamic> job) {
    final id = job['id'].toString();
    final tasks = (job['tasks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final expanded = _expanded.contains(id);
    final busy = _busy.contains(id);

    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Row(
            children: [
              Expanded(child: Text(job['title']?.toString() ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.w800))),
              _badge(job['priority']?.toString() ?? 'MEDIUM'),
            ],
          ),
          subtitle: Text('${job['client_name'] ?? 'Unknown client'} · ${job['status'] ?? 'DRAFT'} · ${tasks.length} tasks'),
          trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          onTap: () => setState(() => expanded ? _expanded.remove(id) : _expanded.add(id)),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surfaceLight.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(10)),
            child: Column(
              children: [
                ...tasks.map((task) => _taskRow(task)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: busy || tasks.isEmpty ? null : () => _optimize(id),
                    icon: busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(busy ? 'Optimizing...' : 'Optimize / Re-optimize'),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _taskRow(Map<String, dynamic> task) {
    final machine = task['machine_required'] == true;
    final human = task['human_required'] == true;
    final status = task['status']?.toString() ?? 'PENDING';
    final humanOnly = human && !machine;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.chevron_right, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task['name']?.toString() ?? 'Task', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${machine ? 'Machine' : ''}${machine && human ? ' + ' : ''}${human ? 'Human' : ''} · $status${task['schedule_locked'] == true ? ' · LOCKED' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          if (humanOnly)
            IconButton(
              tooltip: 'Publish to external workers',
              onPressed: () => _publishExternal(task),
              icon: const Icon(Icons.public_rounded, size: 20),
            ),
          if (task['assigned_human_id'] != null && status == 'SCHEDULED')
            IconButton(
              tooltip: 'Send to worker mobile app',
              onPressed: () => _dispatch(task),
              icon: const Icon(Icons.send_to_mobile_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary)),
      );
}

class _TaskDraft {
  final name = TextEditingController();
  final quantity = TextEditingController();
  final processingMinutes = TextEditingController();
  String? operationId;
  bool machineRequired = false;
  bool humanRequired = false;
  final Set<int> dependencies = {};

  void dispose() {
    name.dispose();
    quantity.dispose();
    processingMinutes.dispose();
  }
}

class _NewJobForm extends StatefulWidget {
  final VoidCallback onCreated;

  const _NewJobForm({required this.onCreated});

  @override
  State<_NewJobForm> createState() => _NewJobFormState();
}

class _NewJobFormState extends State<_NewJobForm> {
  final _title = TextEditingController();
  final _client = TextEditingController();
  final _quantity = TextEditingController();
  final List<_TaskDraft> _tasks = [];
  List<Map<String, dynamic>> _operations = [];
  DateTime? _deadline;
  String _priority = 'MEDIUM';
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadOperations();
  }

  Future<void> _loadOperations() async {
    try {
      final operations = await ApiService.instance.fetchOperationTypes();
      if (mounted) setState(() => _operations = operations);
    } catch (_) {}
  }

  void _addTask() {
    final task = _TaskDraft();
    if (_operations.isNotEmpty) task.operationId = _operations.first['id'].toString();
    setState(() => _tasks.add(task));
  }

  void _removeTask(int index) {
    final removed = _tasks.removeAt(index);
    removed.dispose();
    for (final task in _tasks) {
      task.dependencies.remove(index);
      final shifted = task.dependencies.where((value) => value > index).toList();
      for (final value in shifted) {
        task.dependencies.remove(value);
        task.dependencies.add(value - 1);
      }
    }
    setState(() {});
  }

  Future<void> _chooseDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline ?? DateTime(date.year, date.month, date.day, 17)),
    );
    if (selectedTime == null) return;
    setState(() => _deadline = DateTime(date.year, date.month, date.day, selectedTime.hour, selectedTime.minute));
  }

  Future<void> _chooseDependencies(int taskIndex) async {
    if (taskIndex == 0) return;
    final selected = Set<int>.from(_tasks[taskIndex].dependencies);
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Task dependencies'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(taskIndex, (index) {
                final label = _tasks[index].name.text.trim().isEmpty ? 'Task ${index + 1}' : _tasks[index].name.text.trim();
                return CheckboxListTile(
                  value: selected.contains(index),
                  title: Text(label),
                  onChanged: (checked) => setDialogState(() {
                    if (checked == true) {
                      selected.add(index);
                    } else {
                      selected.remove(index);
                    }
                  }),
                );
              }),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, selected), child: const Text('Done')),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _tasks[taskIndex].dependencies..clear()..addAll(result));
  }

  Future<void> _submit() async {
    final totalQuantity = int.tryParse(_quantity.text);
    if (_title.text.trim().isEmpty || totalQuantity == null || totalQuantity <= 0 || _deadline == null || _tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter title, quantity, deadline and at least one task.')));
      return;
    }

    for (var i = 0; i < _tasks.length; i++) {
      final task = _tasks[i];
      final quantity = int.tryParse(task.quantity.text);
      if (task.name.text.trim().isEmpty || task.operationId == null || quantity == null || quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Complete Task ${i + 1}.')));
        return;
      }
      if (!task.machineRequired && !task.humanRequired) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Choose Machine, Human, or both for Task ${i + 1}.')));
        return;
      }
    }

    final dependencies = <Map<String, dynamic>>[];
    for (var successor = 0; successor < _tasks.length; successor++) {
      for (final predecessor in _tasks[successor].dependencies) {
        dependencies.add({
          'predecessor_index': predecessor,
          'successor_index': successor,
          'mandatory_wait_minutes': 0,
        });
      }
    }

    setState(() => _submitting = true);
    try {
      await ApiService.instance.createJobOrder({
        'title': _title.text.trim(),
        'client_name': _client.text.trim().isEmpty ? null : _client.text.trim(),
        'total_quantity': totalQuantity,
        'priority': _priority,
        'deadline': _deadline!.toUtc().toIso8601String(),
        'tasks': _tasks.map((task) => {
              'name': task.name.text.trim(),
              'operation_type_id': task.operationId,
              'quantity_to_process': int.parse(task.quantity.text),
              'processing_time_minutes': int.tryParse(task.processingMinutes.text),
              'machine_required': task.machineRequired,
              'human_required': task.humanRequired,
            }).toList(),
        'dependencies': dependencies,
      });

      _title.clear();
      _client.clear();
      _quantity.clear();
      for (final task in _tasks) task.dispose();
      setState(() {
        _tasks.clear();
        _deadline = null;
        _priority = 'MEDIUM';
      });
      widget.onCreated();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _client.dispose();
    _quantity.dispose();
    for (final task in _tasks) task.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New Job', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Job title')),
            const SizedBox(height: 12),
            TextField(controller: _client, decoration: const InputDecoration(labelText: 'Client')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: TextField(controller: _quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total quantity'))),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: const ['LOW', 'MEDIUM', 'HIGH', 'URGENT']
                        .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _priority = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _chooseDeadline,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_deadline == null ? 'Choose deadline' : DateFormat('MMM d, yyyy · h:mm a').format(_deadline!)),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Process DAG', style: TextStyle(fontWeight: FontWeight.w800)),
                TextButton.icon(onPressed: _operations.isEmpty ? null : _addTask, icon: const Icon(Icons.add), label: const Text('Add Task')),
              ],
            ),
            ...List.generate(_tasks.length, _taskEditor),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting ? const CircularProgressIndicator() : const Text('Create Job (Do Not Optimize Yet)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskEditor(int index) {
    final task = _tasks[index];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceLight.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('Task ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(onPressed: () => _removeTask(index), icon: const Icon(Icons.close, size: 18)),
            ],
          ),
          TextField(controller: task.name, decoration: const InputDecoration(labelText: 'Task name')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: task.operationId,
            decoration: const InputDecoration(labelText: 'Operation type'),
            items: _operations
                .map((operation) => DropdownMenuItem(value: operation['id'].toString(), child: Text(operation['name'].toString())))
                .toList(),
            onChanged: (value) => setState(() => task.operationId = value),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: TextField(controller: task.quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity'))),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: task.processingMinutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Manual duration min (optional)'),
                ),
              ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: task.machineRequired,
            title: const Text('Requires machine'),
            onChanged: (value) => setState(() => task.machineRequired = value ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: task.humanRequired,
            title: const Text('Requires human worker'),
            onChanged: (value) => setState(() => task.humanRequired = value ?? false),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: index == 0 ? null : () => _chooseDependencies(index),
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(task.dependencies.isEmpty ? 'No predecessors' : '${task.dependencies.length} predecessors'),
            ),
          ),
        ],
      ),
    );
  }
}
