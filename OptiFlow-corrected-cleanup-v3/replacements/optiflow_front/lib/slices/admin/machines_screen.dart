import 'package:flutter/material.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';

/// Manager CRUD for machine resources, including external-rental settings.
class MachinesScreen extends StatefulWidget {
  const MachinesScreen({super.key});

  @override
  State<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends State<MachinesScreen> {
  List<Map<String, dynamic>> _machines = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final machines = await ApiService.instance.fetchMachines();
      if (mounted) setState(() { _machines = machines; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({Map<String, dynamic>? machine}) async {
    final name = TextEditingController(text: machine?['name']?.toString() ?? '');
    final price = TextEditingController(text: machine?['price_per_hour']?.toString() ?? '');
    final image = TextEditingController(text: machine?['image_url']?.toString() ?? '');
    var status = machine?['status']?.toString() ?? 'ACTIVE';
    var bookable = machine?['bookable'] == true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(machine == null ? 'Add Machine' : 'Edit Machine'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Machine name')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  items: const ['ACTIVE', 'IDLE', 'MAINTENANCE', 'OFFLINE']
                      .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => status = value);
                  },
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'External price per hour (Rs.)'),
                ),
                const SizedBox(height: 12),
                TextField(controller: image, decoration: const InputDecoration(labelText: 'Image URL (optional)')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: bookable,
                  title: const Text('Allow external booking requests'),
                  onChanged: (value) => setDialogState(() => bookable = value),
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
    final data = {
      'name': name.text.trim(),
      'status': status,
      'price_per_hour': double.tryParse(price.text) ?? 0,
      'image_url': image.text.trim().isEmpty ? null : image.text.trim(),
      'bookable': bookable,
    };

    if (machine == null) {
      await ApiService.instance.createResource({'type': 'MACHINE', ...data});
    } else {
      await ApiService.instance.updateResource(machine['id'].toString(), data);
    }
    await _load();
  }

  Future<void> _delete(Map<String, dynamic> machine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove machine?'),
        content: Text('Remove "${machine['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ApiService.instance.deleteResource(machine['id'].toString());
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
                Text('Machines', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                Text('Scheduler resources and external rental settings', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
            ElevatedButton.icon(onPressed: () => _save(), icon: const Icon(Icons.add), label: const Text('Add Machine')),
          ],
        ),
        const SizedBox(height: 24),
        ..._machines.map((machine) => Card(
              color: AppColors.surface,
              child: ListTile(
                leading: const Icon(Icons.precision_manufacturing_rounded, color: AppColors.primary),
                title: Text(machine['name']?.toString() ?? 'Machine', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${machine['status'] ?? 'UNKNOWN'} · Rs. ${machine['price_per_hour'] ?? 0}/hr · ${machine['bookable'] == true ? 'Externally bookable' : 'Internal only'}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(onPressed: () => _save(machine: machine), icon: const Icon(Icons.edit_outlined)),
                    IconButton(onPressed: () => _delete(machine), icon: const Icon(Icons.delete_outline, color: AppColors.error)),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}
