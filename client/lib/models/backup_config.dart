class BackupConfig {
  final String id;
  final String localPath;
  final String destination;
  final String label;

  BackupConfig({
    required this.id,
    required this.localPath,
    required this.destination,
    required this.label,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'localPath': localPath,
        'destination': destination,
        'label': label,
      };

  factory BackupConfig.fromJson(Map<String, dynamic> json) => BackupConfig(
        id: json['id'] as String,
        localPath: json['localPath'] as String,
        destination: json['destination'] as String,
        label: json['label'] as String? ?? json['localPath'] as String,
      );
}
