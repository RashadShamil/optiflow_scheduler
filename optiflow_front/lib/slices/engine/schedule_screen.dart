import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';

/// Editable multi-resource Gantt chart.
///
/// The same task appears on both rows when it needs a machine and a human.
/// Dragging a task changes its time and/or the resource represented by the target
/// row. FastAPI validates capability, conflicts, DAG order and shop hours before
/// saving the move. Successful manual moves are locked so later optimizer runs
/// preserve the manager's decision until explicitly unlocked.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  List<Map<String, dynamic>> _resources = [];
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _bookings = [];
  Map<String, dynamic> _shop = {};
  final Map<String, GlobalKey> _timelineKeys = {};
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;

  int get _openHour => (_shop['open_hour'] as num?)?.toInt() ?? 8;
  int get _closeHour => (_shop['close_hour'] as num?)?.toInt() ?? 18;
  int get _dayMinutes => (_closeHour - _openHour) * 60;
  double get _timelineWidth => (_closeHour - _openHour) * 105.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final payload = await ApiService.instance.fetchSchedule();
      if (mounted) {
        setState(() {
          _resources = List<Map<String, dynamic>>.from(
            payload['resources'] as List? ?? const [],
          );
          _tasks = List<Map<String, dynamic>>.from(
            payload['tasks'] as List? ?? const [],
          );
          _bookings = List<Map<String, dynamic>>.from(
            payload['bookings'] as List? ?? const [],
          );
          _shop = Map<String, dynamic>.from(
            payload['shop'] as Map? ?? const {},
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  bool _sameDay(DateTime value) =>
      value.year == _selectedDate.year &&
      value.month == _selectedDate.month &&
      value.day == _selectedDate.day;

  DateTime? _localTime(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  List<Map<String, dynamic>> _tasksForResource(String resourceId) {
    return _tasks.where((task) {
      final start = _localTime(task['scheduled_start_time']);
      if (start == null || !_sameDay(start)) return false;
      return task['assigned_machine_id']?.toString() == resourceId ||
          task['assigned_human_id']?.toString() == resourceId;
    }).toList();
  }

  List<Map<String, dynamic>> _bookingsForResource(String resourceId) {
    return _bookings.where((booking) {
      final start = _localTime(booking['start_time']);
      return booking['machine_id']?.toString() == resourceId &&
          start != null &&
          _sameDay(start);
    }).toList();
  }

  Future<void> _moveTask({
    required Map<String, dynamic> task,
    required Map<String, dynamic> resource,
    required double localDx,
  }) async {
    final rawMinutes = (localDx / _timelineWidth * _dayMinutes).round();
    final snapped = ((rawMinutes / 15).round() * 15)
        .clamp(0, _dayMinutes - 15)
        .toInt();
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _openHour,
    ).add(Duration(minutes: snapped));

    try {
      await ApiService.instance.moveScheduledTask(
        taskId: task['id'].toString(),
        resourceId: resource['id'].toString(),
        startTime: start,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schedule moved and locked for future optimizer runs.'),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _showTask(Map<String, dynamic> task) async {
    final job = task['jobs'] is Map ? task['jobs'] as Map : const {};
    final locked = task['schedule_locked'] == true;
    final start = _localTime(task['scheduled_start_time']);
    final end = _localTime(task['scheduled_end_time']);

    final unlock = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task['name']?.toString() ?? 'Task'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Job: ${job['title'] ?? '—'}'),
            Text('Priority: ${job['priority'] ?? 'MEDIUM'}'),
            Text('Status: ${task['status'] ?? '—'}'),
            if (start != null && end != null)
              Text(
                '${DateFormat('MMM d, h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}',
              ),
            const SizedBox(height: 10),
            Text(
              locked
                  ? 'Locked: future optimization will not move this task.'
                  : 'Unlocked: future optimization may rearrange this task.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          if (locked && task['status'] == 'SCHEDULED')
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unlock for Optimizer'),
            ),
        ],
      ),
    );

    if (unlock == true) {
      await ApiService.instance.setTaskLock(task['id'].toString(), false);
      await _load();
    }
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Schedule',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                ),
                Text(
                  'Drag movable tasks across time or compatible machine/worker rows · ${_shop['timezone'] ?? ''}',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _dateNavigator(),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceLight),
            ),
            child: Column(
              children: [_timeHeader(), ..._resources.map(_resourceRow)],
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Wrap(
          spacing: 18,
          children: [
            Text(
              'Tip: drag a scheduled block. The backend rejects invalid capability/conflict/DAG moves.',
            ),
            Text('Approved customer machine bookings are fixed gray blocks.'),
          ],
        ),
      ],
    );
  }

  Widget _dateNavigator() {
    return Row(
      children: [
        IconButton(
          onPressed: () => setState(
            () =>
                _selectedDate = _selectedDate.subtract(const Duration(days: 1)),
          ),
          icon: const Icon(Icons.chevron_left),
        ),
        SizedBox(
          width: 220,
          child: Center(
            child: Text(
              DateFormat('EEEE, MMM d, y').format(_selectedDate),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        IconButton(
          onPressed: () => setState(
            () => _selectedDate = _selectedDate.add(const Duration(days: 1)),
          ),
          icon: const Icon(Icons.chevron_right),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => setState(() => _selectedDate = DateTime.now()),
          child: const Text('Today'),
        ),
      ],
    );
  }

  Widget _timeHeader() {
    return Row(
      children: [
        const SizedBox(
          width: 210,
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'RESOURCE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        SizedBox(
          width: _timelineWidth,
          height: 52,
          child: Row(
            children: List.generate(_closeHour - _openHour + 1, (index) {
              final hour = _openHour + index;
              return SizedBox(
                width: index == _closeHour - _openHour ? 0 : 105,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    DateFormat('h a').format(DateTime(2026, 1, 1, hour)),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _resourceRow(Map<String, dynamic> resource) {
    final resourceId = resource['id'].toString();
    final key = _timelineKeys.putIfAbsent(resourceId, () => GlobalKey());
    final tasks = _tasksForResource(resourceId);
    final bookings = resource['type'] == 'MACHINE'
        ? _bookingsForResource(resourceId)
        : <Map<String, dynamic>>[];

    return Container(
      height: 76,
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.surfaceLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 210,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    resource['type'] == 'MACHINE'
                        ? Icons.precision_manufacturing_rounded
                        : Icons.person_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          resource['name']?.toString() ?? 'Resource',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${resource['type']} · ${resource['status']}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          DragTarget<Map<String, dynamic>>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) {
              final box = key.currentContext?.findRenderObject() as RenderBox?;
              if (box == null) return;
              final local = box.globalToLocal(details.offset);
              _moveTask(
                task: details.data,
                resource: resource,
                localDx: local.dx,
              );
            },
            builder: (_, candidate, __) => Container(
              key: key,
              width: _timelineWidth,
              height: 76,
              decoration: BoxDecoration(
                color: candidate.isNotEmpty
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : null,
              ),
              child: Stack(
                children: [
                  _gridLines(),
                  ...bookings.map(_bookingBlock),
                  ...tasks.map((task) => _taskBlock(task, resourceId)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gridLines() {
    return Row(
      children: List.generate(
        _closeHour - _openHour,
        (_) => Container(
          width: 105,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: AppColors.surfaceLight.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _taskBlock(Map<String, dynamic> task, String resourceId) {
    final start = _localTime(task['scheduled_start_time']);
    final end = _localTime(task['scheduled_end_time']);
    if (start == null || end == null) return const SizedBox.shrink();

    final startMinute = (start.hour - _openHour) * 60 + start.minute;
    final duration = end.difference(start).inMinutes;
    final left = (startMinute / _dayMinutes * _timelineWidth)
        .clamp(0.0, _timelineWidth)
        .toDouble();
    final availableWidth = (_timelineWidth - left)
        .clamp(1.0, _timelineWidth)
        .toDouble();
    final width = (duration / _dayMinutes * _timelineWidth)
        .clamp(1.0, availableWidth)
        .toDouble();
    final status = task['status']?.toString() ?? 'SCHEDULED';
    final movable = status == 'SCHEDULED';
    final job = task['jobs'] is Map ? task['jobs'] as Map : const {};
    final priority = job['priority']?.toString() ?? 'MEDIUM';
    final color = switch (priority) {
      'URGENT' => AppColors.error,
      'HIGH' => AppColors.warning,
      'LOW' => AppColors.textSecondary,
      _ => AppColors.primary,
    };

    final block = GestureDetector(
      onTap: () => _showTask(task),
      child: Container(
        width: width,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(7),
          border: task['schedule_locked'] == true
              ? Border.all(color: Colors.white70)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              task['name']?.toString() ?? 'Task',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '$status${task['schedule_locked'] == true ? ' · 🔒' : ''}',
              maxLines: 1,
              style: const TextStyle(color: Colors.white70, fontSize: 9),
            ),
          ],
        ),
      ),
    );

    return Positioned(
      left: left,
      top: 12,
      child: movable
          ? LongPressDraggable<Map<String, dynamic>>(
              data: task,
              feedback: Material(
                color: Colors.transparent,
                child: Opacity(opacity: 0.9, child: block),
              ),
              childWhenDragging: Opacity(opacity: 0.25, child: block),
              child: block,
            )
          : block,
    );
  }

  Widget _bookingBlock(Map<String, dynamic> booking) {
    final start = _localTime(booking['start_time']);
    final end = _localTime(booking['end_time']);
    if (start == null || end == null) return const SizedBox.shrink();
    final startMinute = (start.hour - _openHour) * 60 + start.minute;
    final duration = end.difference(start).inMinutes;
    final left = (startMinute / _dayMinutes * _timelineWidth)
        .clamp(0.0, _timelineWidth)
        .toDouble();
    final availableWidth = (_timelineWidth - left)
        .clamp(1.0, _timelineWidth)
        .toDouble();
    final width = (duration / _dayMinutes * _timelineWidth)
        .clamp(1.0, availableWidth)
        .toDouble();

    return Positioned(
      left: left,
      top: 16,
      child: Container(
        width: width,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: Colors.blueGrey,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          'BOOKED · ${booking['requested_by_name'] ?? 'External'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
