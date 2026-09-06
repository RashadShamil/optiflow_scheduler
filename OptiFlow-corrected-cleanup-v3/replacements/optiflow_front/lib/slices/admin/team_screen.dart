import 'package:flutter/material.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<Map<String, dynamic>> _workers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final workers = await ApiService.instance.fetchHumanResources();
      if (mounted) setState(() { _workers = workers; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({Map<String, dynamic>? worker}) async {
    final name = TextEditingController(text: worker?['name']?.toString() ?? '');
    var status = worker?['status']?.toString() ?? 'ACTIVE';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(worker == null ? 'Add Worker' : 'Edit Worker'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Worker name')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: status,
                  items: const ['ACTIVE', 'IDLE', 'OFFLINE']
                      .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => status = value);
                  },
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (confirmed != true || name.text.trim().isEmpty) return;
    if (worker == null) {
      await ApiService.instance.createResource({'name': name.text.trim(), 'type': 'HUMAN', 'status': status});
    } else {
      await ApiService.instance.updateResource(worker['id'].toString(), {'name': name.text.trim(), 'status': status});
    }
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> worker) async {
    await ApiService.instance.deleteResource(worker['id'].toString());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.primary));

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Team', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                Text('Human resources available to the scheduler', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
            ElevatedButton.icon(onPressed: () => _save(), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add Worker')),
          ],
        ),
        const SizedBox(height: 24),
        ..._workers.map((worker) => Card(
              color: AppColors.surface,
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(worker['name']?.toString() ?? 'Worker', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                subtitle: Text(worker['status']?.toString() ?? 'UNKNOWN'),
                trailing: Wrap(
                  children: [
                    IconButton(onPressed: () => _save(worker: worker), icon: const Icon(Icons.edit_outlined)),
                    IconButton(onPressed: () => _delete(worker), icon: const Icon(Icons.delete_outline, color: AppColors.error)),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}
