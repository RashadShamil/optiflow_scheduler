import 'package:flutter/material.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';

class CapabilitiesScreen extends StatefulWidget {
  const CapabilitiesScreen({super.key});

  @override
  State<CapabilitiesScreen> createState() => _CapabilitiesScreenState();
}

class _CapabilitiesScreenState extends State<CapabilitiesScreen> {
  List<Map<String, dynamic>> _capabilities = [];
  List<Map<String, dynamic>> _resources = [];
  List<Map<String, dynamic>> _operations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.fetchCapabilities(),
        ApiService.instance.fetchResources(includeExternal: true),
        ApiService.instance.fetchOperationTypes(),
      ]);
      if (mounted) {
        setState(() {
          _capabilities = results[0];
          _resources = results[1];
          _operations = results[2];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCapability() async {
    if (_resources.isEmpty || _operations.isEmpty) return;

    var resourceId = _resources.first['id'].toString();
    var operationId = _operations.first['id'].toString();
    final rate = TextEditingController();
    final setup = TextEditingController(text: '0');
    final cost = TextEditingController(text: '0');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Capability'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: resourceId,
                  decoration: const InputDecoration(labelText: 'Resource'),
                  items: _resources
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id'].toString(),
                          child: Text(item['name'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setDialogState(() => resourceId = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: operationId,
                  decoration: const InputDecoration(labelText: 'Operation'),
                  items: _operations
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id'].toString(),
                          child: Text(item['name'].toString()),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => operationId = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Processing rate / hour',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: setup,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Setup time (minutes)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cost / hour'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final parsedRate = double.tryParse(rate.text);
    final parsedSetup = int.tryParse(setup.text);
    final parsedCost = double.tryParse(cost.text);
    if (parsedRate == null ||
        parsedRate <= 0 ||
        parsedSetup == null ||
        parsedSetup < 0 ||
        parsedCost == null ||
        parsedCost < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid capability values.')),
        );
      }
      return;
    }

    await ApiService.instance.createCapability({
      'resource_id': resourceId,
      'operation_type_id': operationId,
      'processing_rate_per_hr': parsedRate,
      'setup_time_minutes': parsedSetup,
      'cost_per_hour': parsedCost,
    });
    await _load();
  }

  Future<void> _delete(String id) async {
    await ApiService.instance.deleteCapability(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Skills Matrix',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Tell the optimizer which resources can perform each operation',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: _addCapability,
              icon: const Icon(Icons.add),
              label: const Text('Add Capability'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_capabilities.isEmpty)
          const Text(
            'No capabilities configured.',
            style: TextStyle(color: AppColors.textSecondary),
          )
        else
          Card(
            color: AppColors.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Resource')),
                  DataColumn(label: Text('Operation')),
                  DataColumn(label: Text('Rate / hr')),
                  DataColumn(label: Text('Setup')),
                  DataColumn(label: Text('Cost / hr')),
                  DataColumn(label: Text('')),
                ],
                rows: _capabilities.map((capability) {
                  final resource = capability['resources'] as Map?;
                  final operation = capability['operation_types'] as Map?;
                  return DataRow(
                    cells: [
                      DataCell(Text(resource?['name']?.toString() ?? '—')),
                      DataCell(Text(operation?['name']?.toString() ?? '—')),
                      DataCell(
                        Text('${capability['processing_rate_per_hr'] ?? '—'}'),
                      ),
                      DataCell(
                        Text('${capability['setup_time_minutes'] ?? 0} min'),
                      ),
                      DataCell(Text('${capability['cost_per_hour'] ?? 0}')),
                      DataCell(
                        IconButton(
                          onPressed: () => _delete(capability['id'].toString()),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}
