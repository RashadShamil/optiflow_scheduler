/// Customer-facing machine information returned by FastAPI.
class MachineModel {
  final String id;
  final String name;
  final String status;
  final String? imageUrl;
  final double pricePerHour;

  const MachineModel({
    required this.id,
    required this.name,
    required this.status,
    required this.pricePerHour,
    this.imageUrl,
  });

  factory MachineModel.fromJson(Map<String, dynamic> json) => MachineModel(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Machine',
    status: json['status']?.toString() ?? 'UNKNOWN',
    pricePerHour: (json['price_per_hour'] as num?)?.toDouble() ?? 0,
    imageUrl: json['image_url']?.toString(),
  );
}
