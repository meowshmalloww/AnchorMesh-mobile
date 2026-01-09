class DisasterEvent {
  final String id;
  final String type; // 'earthquake', 'weather', etc.
  final String title;
  final String description;
  final String severity; // 'Low', 'Medium', 'High', 'Extreme'
  final DateTime time;
  final double latitude;
  final double longitude;
  final String? sourceUrl;

  DisasterEvent({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.severity,
    required this.time,
    required this.latitude,
    required this.longitude,
    this.sourceUrl,
  });

  factory DisasterEvent.fromJson(Map<String, dynamic> json) {
    // This is a generic factory, usually you'd have specific ones or mapping logic
    return DisasterEvent(
      id: json['id'] ?? '',
      type: json['type'] ?? 'unknown',
      title: json['title'] ?? 'Unknown Event',
      description: json['description'] ?? '',
      severity: json['severity'] ?? 'Unknown',
      time: DateTime.tryParse(json['time'] ?? '') ?? DateTime.now(),
      latitude: (json['lat'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['lon'] as num?)?.toDouble() ?? 0.0,
      sourceUrl: json['url'],
    );
  }
}
