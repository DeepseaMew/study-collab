import 'package:cloud_firestore/cloud_firestore.dart';

class SessionFile {
  final String id;
  final String sessionId;
  final String fileName;
  final int sizeBytes;
  final String mimeType;
  final String storagePath;
  final String downloadUrl;
  final String ownerId;
  final String ownerName;
  final DateTime uploadedAt;

  const SessionFile({
    required this.id,
    required this.sessionId,
    required this.fileName,
    required this.sizeBytes,
    this.mimeType = 'application/octet-stream',
    required this.storagePath,
    required this.downloadUrl,
    required this.ownerId,
    required this.ownerName,
    required this.uploadedAt,
  });

  String get displaySize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeBytes < 1024 * 1024 * 1024) return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get extension {
    final parts = fileName.split('.');
    if (parts.length < 2) return '';
    return parts.last.toLowerCase();
  }

  bool get isPdf   => extension == 'pdf';
  bool get isImage => ['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(extension);
  bool isOwnedBy(String userId) => ownerId == userId;

  factory SessionFile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String sessionId,
  ) {
    final data = doc.data();
    if (data == null) throw Exception('SessionFile document ${doc.id} has no data');
    return SessionFile(
      id: doc.id,
      sessionId: sessionId,
      fileName: data['fileName'] as String? ?? '',
      sizeBytes: data['sizeBytes'] as int? ?? 0,
      mimeType: data['mimeType'] as String? ?? 'application/octet-stream',
      storagePath: data['storagePath'] as String? ?? '',
      downloadUrl: data['downloadUrl'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? '',
      uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'fileName': fileName,
      'sizeBytes': sizeBytes,
      'mimeType': mimeType,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
    };
  }

  SessionFile copyWith({
    String? fileName,
    String? downloadUrl,
    String? ownerName,
  }) {
    return SessionFile(
      id: id,
      sessionId: sessionId,
      fileName: fileName ?? this.fileName,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      storagePath: storagePath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      ownerId: ownerId,
      ownerName: ownerName ?? this.ownerName,
      uploadedAt: uploadedAt,
    );
  }
}