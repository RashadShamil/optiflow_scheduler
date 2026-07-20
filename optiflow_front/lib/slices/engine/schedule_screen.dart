import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:optiflow_scheduler/core/models/booking.dart';
import 'package:optiflow_scheduler/core/models/machine.dart';
import 'package:optiflow_scheduler/core/services/api_service.dart';
import 'package:optiflow_scheduler/core/utils/app_colors.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final ApiService _apiService = ApiService();
  // Renamed: holds ALL resources (machines + humans) for the Gantt rows
  List<Booking> _bookings = [];
  List<Machine> _resources = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() { _isLoading = true; });
    // fetchMachines() now returns ALL resource types (MACHINE + HUMAN)
    final resources = await _apiService.fetchMachines();
    final bookings  = await _apiService.fetchBookings();

    if (mounted) {
      setState(() {
        _resources = resources;
        _bookings  = bookings;
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelBooking(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.error),
          const SizedBox(width: 8),
          const Text('Cancel Booking?', style: TextStyle(color: AppColors.textPrimary)),
        ]),
        content: Text(
          'Cancel "${booking.jobTitle}" on this machine? This will free the slot and remove the conflict.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep It', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Booking', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await _apiService.deleteBooking(booking.id);
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled — conflict resolved.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _fetchData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not cancel — FastAPI may be offline.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final dayBookings = _bookings.where((b) {
      final d = b.startTime;
      return d.year == _selectedDate.year &&
          d.month == _selectedDate.month &&
          d.day == _selectedDate.day;
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 32),
          _buildDateNavigator(dayBookings),
          const SizedBox(height: 32),
          _buildTimeline(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Schedule",
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -1,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Live schedule for all resources — machines and workers",
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),
          ],
        ),
        Row(
          children: [
            // Refresh button
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 24),
              tooltip: 'Refresh schedule',
              onPressed: _fetchData,
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showNewBookingDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "New Booking",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showNewBookingDialog(BuildContext context) {
    if (_resources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No resources available. Please add machines or workers first."), backgroundColor: AppColors.warning),
      );
      return;
    }

    String? selectedMachineId = _resources.first.id;
    DateTime? startDateTime;
    DateTime? endDateTime;
    final nameController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: AppColors.surfaceLight.withOpacity(0.5)),
              ),
              title: const Text(
                "New Machine Booking",
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 20),
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User / Operator name
                    const Text("Operator Name", style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: "e.g. Sarah Chen",
                        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                        filled: true,
                        fillColor: AppColors.surfaceLight.withOpacity(0.4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Machine selection
                    const Text("Select Machine", style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: selectedMachineId,
                          dropdownColor: AppColors.surfaceLight,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                          items: _resources.map((m) {
                            return DropdownMenuItem<String>(
                              value: m.id,
                              child: Text(m.name),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setDialogState(() { selectedMachineId = val; });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Date/time selection
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateTimePicker(
                            ctx,
                            label: "Start Time",
                            value: startDateTime,
                            onPicked: (dt) => setDialogState(() => startDateTime = dt),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDateTimePicker(
                            ctx,
                            label: "End Time",
                            value: endDateTime,
                            onPicked: (dt) => setDialogState(() => endDateTime = dt),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8)],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    onPressed: isSubmitting ? null : () async {
                      if (nameController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter operator name"), backgroundColor: AppColors.error));
                        return;
                      }
                      if (selectedMachineId == null || startDateTime == null || endDateTime == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields"), backgroundColor: AppColors.error));
                        return;
                      }
                      if (endDateTime!.isBefore(startDateTime!)) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("End time must be after start time"), backgroundColor: AppColors.error));
                        return;
                      }

                      setDialogState(() => isSubmitting = true);
                      final success = await _apiService.createBooking(
                        machineId: selectedMachineId!,
                        userName: nameController.text,
                        startTime: startDateTime!.toUtc().toIso8601String(),
                        endTime: endDateTime!.toUtc().toIso8601String(),
                      );

                      if (!mounted) return;
                      Navigator.pop(ctx);
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Booking confirmed!"), backgroundColor: AppColors.success),
                        );
                        _fetchData(); // Refresh
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Booking failed — slot may already be taken."), backgroundColor: AppColors.error),
                        );
                      }
                    },
                    child: isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Confirm Booking", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateTimePicker(
    BuildContext ctx, {
    required String label,
    required DateTime? value,
    required Function(DateTime) onPicked,
  }) {
    return GestureDetector(
      onTap: () async {
        final date = await showDatePicker(
          context: ctx,
          initialDate: value ?? _selectedDate,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
          builder: (context, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: AppColors.primary,
                onPrimary: Colors.white,
                surface: AppColors.surface,
                onSurface: AppColors.textPrimary,
              ), dialogTheme: DialogThemeData(backgroundColor: AppColors.surface),
            ),
            child: child!,
          ),
        );
        if (date == null) return;

        if (!ctx.mounted) return;
        final time = await showTimePicker(
          context: ctx,
          initialTime: TimeOfDay.fromDateTime(value ?? DateTime.now()),
          builder: (context, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: AppColors.primary,
                onPrimary: Colors.white,
                surface: AppColors.surface,
                onSurface: AppColors.textPrimary,
              ),
            ),
            child: child!,
          ),
        );
        if (time == null) return;
        onPicked(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value != null ? DateFormat('MMM d, h:mm a').format(value) : "Pick date & time",
                    style: TextStyle(
                      color: value != null ? AppColors.textPrimary : AppColors.textSecondary.withOpacity(0.7),
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateNavigator(List<Booking> dayBookings) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary),
                  onPressed: () {
                    setState(() {
                      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                    });
                  },
                ),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('EEEE, MMMM d, y').format(_selectedDate),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: AppColors.textPrimary),
                  onPressed: () {
                    setState(() {
                      _selectedDate = _selectedDate.add(const Duration(days: 1));
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Today's Bookings",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${dayBookings.length}",
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (dayBookings.any((b) => b.status == 'CONFLICT'))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          "${dayBookings.where((b) => b.status == 'CONFLICT').length} conflict${dayBookings.where((b) => b.status == 'CONFLICT').length > 1 ? 's' : ''}",
                          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      "No conflicts",
                      style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Gantt timeline constants ──────────────────────────────────────────────
  // Show a full 24-hour window so tasks scheduled at any time of day are visible.
  // The optimizer uses datetime.now(utc) as the project start, so tasks can
  // start at any local hour depending on the machine's timezone.
  static const int _kStartHour = 0;  // 00:00
  static const int _kEndHour   = 24; // 24:00  (exclusive — last column is 23:00)
  static const int _kTotalHours = _kEndHour - _kStartHour; // 24 columns

  Widget _buildTimeline() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.surfaceLight.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildTimelineHeader(),
          Divider(height: 1, color: AppColors.surfaceLight.withOpacity(0.5)),
          if (_resources.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48.0),
              child: Column(
                children: [
                  Icon(Icons.precision_manufacturing_outlined, size: 48, color: AppColors.textSecondary.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text(
                    "No resources registered yet.\nGo to Admin → Resources to add one.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary.withOpacity(0.7), fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            )
          else
            ..._resources.map((resource) => _buildMachineTimelineRow(resource)),
          Divider(height: 1, color: AppColors.surfaceLight.withOpacity(0.5)),
          _buildTimelineFooter(),
        ],
      ),
    );
  }

  Widget _buildTimelineHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Row(
        children: [
          const SizedBox(width: 200),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              // Show every 2 hours (0, 2, 4 ... 22) = 12 labels across 24h
              children: List.generate(12, (index) {
                final hour = _kStartHour + (index * 2);
                final ampm = hour < 12 ? 'AM' : 'PM';
                final h12 = hour == 0 ? 12 : (hour <= 12 ? hour : hour - 12);
                return Expanded(
                  child: Center(
                    child: Text(
                      '$h12 $ampm',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMachineTimelineRow(Machine resource) {
    final resourceBookings = _bookings
        .where((b) => b.machineId == resource.id &&
            b.startTime.year  == _selectedDate.year &&
            b.startTime.month == _selectedDate.month &&
            b.startTime.day   == _selectedDate.day)
        .toList();

    final isHuman = resource.type == 'HUMAN';

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceLight.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  resource.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isHuman
                            ? AppColors.secondary.withOpacity(0.15)
                            : AppColors.primary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isHuman ? 'WORKER' : 'MACHINE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isHuman ? AppColors.secondary : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: resource.status == 'ACTIVE'
                            ? AppColors.success.withOpacity(0.15)
                            : resource.status == 'IDLE'
                                ? AppColors.warning.withOpacity(0.15)
                                : AppColors.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        resource.status,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: resource.status == 'ACTIVE'
                              ? AppColors.success
                              : resource.status == 'IDLE'
                                  ? AppColors.warning
                                  : AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Row(
                  children: List.generate(_kTotalHours, (index) {
                    // Highlight every other hour for readability; bold line at noon
                    final hour = _kStartHour + index;
                    return Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: index.isEven
                              ? Colors.transparent
                              : AppColors.surfaceLight.withOpacity(0.04),
                          border: Border(
                            left: BorderSide(
                              color: hour == 12
                                  ? AppColors.surfaceLight.withOpacity(0.5)
                                  : AppColors.surfaceLight.withOpacity(0.15),
                              width: hour == 12 ? 1.5 : 1.0,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                if (resourceBookings.isEmpty)
                  Positioned.fill(
                    child: Center(
                      child: Text(
                        'No tasks scheduled',
                        style: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.3),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                else
                  ...resourceBookings.map(
                    (booking) => _buildBookingBlock(booking),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingBlock(Booking booking) {
    // Use 24-hour window starting at _kStartHour (0 = midnight)
    final startHour = booking.startTime.hour + (booking.startTime.minute / 60.0);
    final offsetHours = startHour - _kStartHour; // offset from midnight
    if (offsetHours < 0 || offsetHours >= _kTotalHours) return const SizedBox();

    // Position as a fraction of the total 24-hour window
    final leftPercent  = (offsetHours / _kTotalHours) * 100.0;
    final widthPercent = (booking.durationHours / _kTotalHours) * 100.0;
    final isConflict = booking.status == "CONFLICT";

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final left  = totalWidth * (leftPercent  / 100.0);
        final width = totalWidth * (widthPercent / 100.0);

        Color color;
        if (isConflict) {
          color = AppColors.error;
        } else if (booking.priority == "High") {
          color = const Color(0xFF0EA5E9);
        } else if (booking.priority == "Medium") {
          color = AppColors.secondary;
        } else {
          color = const Color(0xFFF97316);
        }

        return Positioned(
          left: left,
          top: 8,
          bottom: 8,
          width: width.clamp(48.0, totalWidth < 48.0 ? 48.0 : totalWidth),
          child: GestureDetector(
            onTap: isConflict ? () => _cancelBooking(booking) : null,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(isConflict ? 0.95 : 0.85),
                borderRadius: BorderRadius.circular(8),
                border: isConflict
                    ? Border.all(color: Colors.white.withOpacity(0.4), width: 1.5)
                    : null,
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8)],
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isConflict)
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 10),
                            SizedBox(width: 3),
                            Text('CONFLICT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 9)),
                          ],
                        ),
                      Text(
                        booking.jobTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      Text(
                        "${booking.durationHours}h • ${booking.userName}",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ],
                  ),
                  // Cancel ✕ button only on CONFLICT
                  if (isConflict)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _cancelBooking(booking),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Colors.white24,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 11),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimelineFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hint text — gets its own full-width line so it never clips
          Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: AppColors.warning, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Timeline shows all 24 hours (local time) · Optimized tasks appear automatically after running the scheduler',
                  style: TextStyle(
                    color: AppColors.textSecondary.withOpacity(0.75),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Legend — Wrap so it reflows on narrow screens
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _buildLegendInd(const Color(0xFF0EA5E9), 'Machine Task'),
              _buildLegendInd(AppColors.secondary, 'Worker Task'),
              _buildLegendInd(AppColors.error, 'Conflict'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendInd(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      ],
    );
  }
}
