import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api_service.dart';
import '../core/app_theme.dart';
import '../models/task_model.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// TaskBottomSheet — slides up when a worker taps a task card.
///
/// Shows massive typography task detail, then:
///  • SCHEDULED  → "Start Task"  button  → PATCH status to IN_PROGRESS
///  • IN_PROGRESS → "Complete Task" button → opens QA proof sub-sheet
///  • COMPLETED  → disabled "Done" badge
/// ─────────────────────────────────────────────────────────────────────────────
class TaskBottomSheet extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onStatusChanged;

  const TaskBottomSheet({
    super.key,
    required this.task,
    required this.onStatusChanged,
  });

  @override
  State<TaskBottomSheet> createState() => _TaskBottomSheetState();
}

class _TaskBottomSheetState extends State<TaskBottomSheet> {
  bool _loading = false;

  Future<void> _updateStatus(String newStatus) async {
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      await ApiService.instance.updateTaskStatus(widget.task.id, newStatus);
      if (mounted) {
        widget.onStatusChanged();
        Navigator.of(context).pop();
        _showSnack('Task marked as ${newStatus.replaceAll('_', ' ')} ✓');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error: ${e.toString().replaceFirst('Exception: ', '')}',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openQASheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QAProofSheet(task: widget.task, onDone: () {
        widget.onStatusChanged();
        Navigator.of(context).pop(); // close the task sheet too
      }),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor:
          isError ? AppColors.offline : const Color(0xFF222222),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    ));
  }

  Widget _buildActionButton() {
    if (widget.task.status == 'SCHEDULED') {
      return ElevatedButton(
        onPressed: _loading ? null : () => _updateStatus('IN_PROGRESS'),
        style: AppTheme.pillButtonStyle(
          bg: const Color(0xFF222222),
        ),
        child: _loading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 22),
                  SizedBox(width: 8),
                  Text('Start Task'),
                ],
              ),
      );
    }

    if (widget.task.status == 'IN_PROGRESS') {
      return ElevatedButton(
        onPressed: _loading ? null : _openQASheet,
        style: AppTheme.pillButtonStyle(bg: AppColors.primary),
        child: _loading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_rounded, size: 22),
                  SizedBox(width: 8),
                  Text('Complete & Submit Proof'),
                ],
              ),
      );
    }

    // COMPLETED — disabled badge
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.completed.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_rounded,
              color: AppColors.completed, size: 20),
          const SizedBox(width: 8),
          Text(
            'Completed',
            style: TextStyle(
              color: AppColors.completed,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bottomSheet,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: 16),

          // ── Huge quantity ──────────────────────────────────────────────────
          Text(
            '${t.quantityToProcess}',
            style: const TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -4,
              height: 0.9,
            ),
          ),
          Text(
            'units',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),

          // ── Job title ──────────────────────────────────────────────────────
          Text(
            t.jobTitle,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 24),

          // ── Detail rows ────────────────────────────────────────────────────
          _detailRow(Icons.precision_manufacturing_outlined,
              'Operation', t.operationTypeId),
          const SizedBox(height: 14),
          _detailRow(Icons.schedule_rounded, 'Scheduled',
              '${t.formattedDate} at ${t.formattedTime}'),
          const SizedBox(height: 14),
          _detailRow(Icons.memory_rounded, 'Machine', t.resourceName),

          const SizedBox(height: 32),
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textDisabled,
                    fontWeight: FontWeight.w500)),
            Text(value,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QA Proof Sub-sheet — camera capture + notes, then POST to /jobs/{id}/submit
// ─────────────────────────────────────────────────────────────────────────────
class _QAProofSheet extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onDone;
  const _QAProofSheet({required this.task, required this.onDone});

  @override
  State<_QAProofSheet> createState() => _QAProofSheetState();
}

class _QAProofSheetState extends State<_QAProofSheet> {
  XFile? _image;
  final _notesCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked != null && mounted) {
      setState(() => _image = picked);
    }
  }

  Future<void> _submit() async {
    HapticFeedback.lightImpact();
    setState(() => _loading = true);
    try {
      // In production, upload _image to Supabase Storage and use the real URL.
      // For now we pass a descriptive mock URL.
      final proofUrl = _image != null
          ? 'local://${_image!.name}'
          : 'no_photo_provided';

      await ApiService.instance.submitJobProof(
        jobId: widget.task.id, // ApiService correctly maps this to the task completion endpoint
        proofUrl: proofUrl,
        notes: _notesCtrl.text.trim().isEmpty
            ? 'No notes.'
            : _notesCtrl.text.trim(),
      );

      if (mounted) {
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Proof submitted! Manager will review.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: const Color(0xFF222222),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.offline,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          28, 0, 28, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: 16),
          const Text(
            'Quality\nAssurance',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -1,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Snap a proof photo and add any notes.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 28),

          // Photo picker
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFFF7F7F9),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                border: Border.all(
                  color: _image != null
                      ? AppColors.completed
                      : const Color(0xFFEBEBEB),
                  width: _image != null ? 2 : 1,
                ),
              ),
              child: _image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      child: Image.file(
                        File(_image!.path),
                        fit: BoxFit.cover,
                      ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_rounded,
                            size: 36, color: AppColors.textDisabled),
                        SizedBox(height: 8),
                        Text('Tap to Snap a Photo',
                            style: TextStyle(
                                color: AppColors.textDisabled,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // Notes field
          TextField(
            controller: _notesCtrl,
            maxLines: 3,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Notes for manager (optional)...',
              hintStyle: const TextStyle(color: AppColors.textDisabled),
              filled: true,
              fillColor: const Color(0xFFF7F7F9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: AppTheme.pillButtonStyle(),
              child: _loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('Submit for Review'),
            ),
          ),
        ],
      ),
    );
  }
}
