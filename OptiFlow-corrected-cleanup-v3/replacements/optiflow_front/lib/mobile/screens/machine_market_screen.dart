import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';

import '../core/app_theme.dart';
import '../models/machine_model.dart';

/// External customer view of machines that the manager marked as bookable.
class MachineMarketScreen extends StatefulWidget {
  const MachineMarketScreen({super.key});

  @override
  State<MachineMarketScreen> createState() => _MachineMarketScreenState();
}

class _MachineMarketScreenState extends State<MachineMarketScreen> {
  List<MachineModel> _machines = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ApiService.instance.fetchBookableMachines();
      if (mounted) {
        setState(() {
          _machines = rows.map(MachineModel.fromJson).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Machine Shop', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: _machines.length,
                    itemBuilder: (_, index) {
                      final machine = _machines[index];
                      return GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => MachineBookingPage(machine: machine)),
                        ),
                        child: Container(
                          decoration: AppTheme.cardDecoration(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusCard)),
                                  child: machine.imageUrl == null
                                      ? const Center(child: Icon(Icons.precision_manufacturing_rounded, size: 52))
                                      : Image.network(
                                          machine.imageUrl!,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const Center(
                                            child: Icon(Icons.precision_manufacturing_rounded, size: 52),
                                          ),
                                        ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(machine.name, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 6),
                                    Text('Rs. ${machine.pricePerHour.toStringAsFixed(0)}/hr'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// Booking-request page used both from the machine grid and QR scanning.
class MachineBookingPage extends StatefulWidget {
  final MachineModel? machine;
  final String? machineId;

  const MachineBookingPage({super.key, this.machine, this.machineId});

  @override
  State<MachineBookingPage> createState() => _MachineBookingPageState();
}

class _MachineBookingPageState extends State<MachineBookingPage> {
  MachineModel? _machine;
  DateTime _day = DateTime.now();
  DateTime? _start;
  DateTime? _end;
  List<Map<String, dynamic>> _busy = [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _machine = widget.machine;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (_machine == null) {
        final rows = await ApiService.instance.fetchBookableMachines();
        for (final row in rows) {
          if (row['id']?.toString() == widget.machineId) {
            _machine = MachineModel.fromJson(row);
            break;
          }
        }
      }
      if (_machine == null) throw Exception('This QR code is not a bookable machine.');
      final availability = await ApiService.instance.fetchMachineAvailability(_machine!.id, _day);
      if (mounted) {
        setState(() {
          _busy = List<Map<String, dynamic>>.from(availability['busy'] as List? ?? const []);
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? _day,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? DateTime.now()),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _request() async {
    if (_machine == null || _start == null || _end == null || !_end!.isAfter(_start!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a valid start and end time.')));
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await ApiService.instance.requestMachineBooking(
        machineId: _machine!.id,
        startTime: _start!,
        endTime: _end!,
      );
      if (!mounted) return;
      final quote = (result['quoted_amount'] as num?)?.toDouble() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request sent for manager approval · Quote Rs. ${quote.toStringAsFixed(0)}')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_machine?.name ?? 'Machine Booking')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text('Rs. ${_machine!.pricePerHour.toStringAsFixed(0)}/hour', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _day,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 180)),
                        );
                        if (picked != null) {
                          setState(() => _day = picked);
                          await _load();
                        }
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(DateFormat('EEE, MMM d').format(_day)),
                    ),
                    const SizedBox(height: 16),
                    const Text('Busy slots', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    if (_busy.isEmpty)
                      const Text('No approved bookings or production tasks on this day.')
                    else
                      ..._busy.map((row) {
                        final start = DateTime.tryParse((row['start_time'] ?? row['scheduled_start_time']).toString())?.toLocal();
                        final end = DateTime.tryParse((row['end_time'] ?? row['scheduled_end_time']).toString())?.toLocal();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.block_outlined),
                          title: Text('${start == null ? '?' : DateFormat('h:mm a').format(start)} – ${end == null ? '?' : DateFormat('h:mm a').format(end)}'),
                          subtitle: Text(row['source']?.toString() ?? 'BUSY'),
                        );
                      }),
                    const Divider(height: 32),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start'),
                      subtitle: Text(_start == null ? 'Choose time' : DateFormat('MMM d, h:mm a').format(_start!)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final value = await _pickDateTime(_start);
                        if (value != null) setState(() => _start = value);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('End'),
                      subtitle: Text(_end == null ? 'Choose time' : DateFormat('MMM d, h:mm a').format(_end!)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final value = await _pickDateTime(_end ?? _start);
                        if (value != null) setState(() => _end = value);
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submitting ? null : _request,
                      child: _submitting ? const CircularProgressIndicator() : const Text('Request Booking'),
                    ),
                    const SizedBox(height: 8),
                    const Text('The machine is reserved only after manager approval.', textAlign: TextAlign.center),
                  ],
                ),
    );
  }
}
