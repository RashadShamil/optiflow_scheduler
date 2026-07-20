class Machine {
  final String id;
  final String name;
  final String status; // "ACTIVE", "MAINTENANCE", "BROKEN", "IDLE"
  final String type;
  final String location;
  final String buildVolume;
  final String material;
  final String resolution;
  final int utilization;
  final int completedJobs;
  
  // Active Job Details (nullable)
  final String? currentJobTitle;
  final String? currentJobUser;
  final int? progress; // 0-100
  final String? timeLeft;

  Machine({
    required this.id,
    required this.name,
    required this.status,
    this.type = "FDM Printer",
    this.location = "Zone A - Station 1",
    this.buildVolume = "250 x 210 x 210 mm",
    this.material = "PLA, PETG, ABS",
    this.resolution = "0.05mm",
    this.utilization = 0,
    this.completedJobs = 0,
    this.currentJobTitle,
    this.currentJobUser,
    this.progress,
    this.timeLeft,
  });

  factory Machine.fromJson(Map<String, dynamic> json) {
    final String status = json['status'] ?? 'UNKNOWN';
    final String rawId = json['id']?.toString() ?? '';
    final String name = json['name']?.toString() ?? 'Unknown Resource';
    // Read the actual type from the database ('MACHINE' or 'HUMAN').
    // This is critical so the Gantt chart can show the correct badge.
    final String type = json['type']?.toString() ?? 'MACHINE';

    final bool isBusy = status == "ACTIVE";
    // Utilization: 100% if active, 50% if idle, 0% if offline
    final int utilization = status == "ACTIVE" ? 80 : status == "IDLE" ? 30 : 0;

    return Machine(
      id: rawId,
      name: name,
      status: status,
      type: type,
      location: "Workshop Floor",
      utilization: utilization,
      completedJobs: 0,

      currentJobTitle: isBusy ? "In Progress" : null,
      currentJobUser: null,
      progress: isBusy ? 50 : null,
      timeLeft: null,
    );
  }
}
