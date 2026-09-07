/// Manager-side representation of a physical machine resource.
///
/// Fields that are not present in the current database remain neutral instead
/// of displaying fake 3D-printer specifications or invented production stats.
class Machine {
  final String id;
  final String name;
  final String status;
  final String type;
  final String location;
  final String buildVolume;
  final String material;
  final String resolution;
  final int utilization;
  final int completedJobs;
  final String? currentJobTitle;
  final String? currentJobUser;
  final int? progress;
  final String? timeLeft;

  Machine({
    required this.id,
    required this.name,
    required this.status,
    this.type = 'MACHINE',
    this.location = '',
    this.buildVolume = '',
    this.material = '',
    this.resolution = '',
    this.utilization = 0,
    this.completedJobs = 0,
    this.currentJobTitle,
    this.currentJobUser,
    this.progress,
    this.timeLeft,
  });

  factory Machine.fromJson(Map<String, dynamic> json) {
    return Machine(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown Machine',
      status: json['status']?.toString() ?? 'UNKNOWN',
      type: json['type']?.toString() ?? 'MACHINE',
      // Utilization/completed-jobs require historical metrics; do not invent them.
      utilization: (json['utilization'] as num?)?.toInt() ?? 0,
      completedJobs: (json['completed_jobs'] as num?)?.toInt() ?? 0,
    );
  }
}
