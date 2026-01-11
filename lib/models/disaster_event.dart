class DisasterEvent {
  final String id;
  final String
  type; // 'earthquake', 'weather', 'tornado', 'flood', 'fire', 'hurricane'
  final String title;
  final String description;
  final String severity; // 'Low', 'Medium', 'High', 'Extreme'
  final DateTime time;
  final double latitude;
  final double longitude;
  final String? sourceUrl;

  // Severity-specific fields for auto-unlock thresholds
  final double? magnitude; // Earthquake magnitude (Richter)
  final int? category; // Hurricane category (1-5)
  final int? efScale; // Tornado EF scale (0-5)

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
    this.magnitude,
    this.category,
    this.efScale,
  });

  factory DisasterEvent.fromJson(Map<String, dynamic> json) {
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
      magnitude: (json['magnitude'] as num?)?.toDouble(),
      category: json['category'] as int?,
      efScale: json['efScale'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'description': description,
    'severity': severity,
    'time': time.toIso8601String(),
    'lat': latitude,
    'lon': longitude,
    'url': sourceUrl,
    'magnitude': magnitude,
    'category': category,
    'efScale': efScale,
  };

  /// Check if this event meets auto-unlock SOS thresholds
  bool get meetsAutoUnlockThreshold {
    switch (type.toLowerCase()) {
      case 'earthquake':
        return (magnitude ?? 0) >= 6.0;
      case 'hurricane':
        return (category ?? 0) >= 3;
      case 'tornado':
        return (efScale ?? 0) >= 2;
      case 'flood':
        return severity == 'Extreme' || severity == 'High';
      case 'fire':
      case 'wildfire':
        return severity == 'Extreme' || severity == 'High';
      default:
        return severity == 'Extreme';
    }
  }
}
