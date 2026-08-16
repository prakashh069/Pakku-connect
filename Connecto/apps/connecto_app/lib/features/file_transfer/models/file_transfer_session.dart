enum FileTransferState {
  idle,
  startSent,
  readyReceived,
  transferring,
  verifying,
  completed,
  failed,
  cancelled,
}

class FileTransferSession {
  final String transferId;
  final String filename;
  final String mime;
  final int size;
  final String sha256;
  final int totalChunks;
  final String? batchId;
  final int? batchCount;
  final int? batchIndex;
  final int? batchTotal;
  final bool isBatchedZip;
  
  int receivedChunks;
  int receivedBytes;
  final DateTime startedAt;
  FileTransferState state;

  FileTransferSession({
    required this.transferId,
    required this.filename,
    required this.mime,
    required this.size,
    required this.sha256,
    required this.totalChunks,
    this.batchId,
    this.batchCount,
    this.batchIndex,
    this.batchTotal,
    this.isBatchedZip = false,
    this.receivedChunks = 0,
    this.receivedBytes = 0,
    DateTime? startedAt,
    this.state = FileTransferState.idle,
  }) : startedAt = startedAt ?? DateTime.now();

  bool get isTransferring => 
      state == FileTransferState.startSent ||
      state == FileTransferState.readyReceived ||
      state == FileTransferState.transferring;

  bool get isFinished => 
      state == FileTransferState.completed ||
      state == FileTransferState.failed ||
      state == FileTransferState.cancelled;

  double get progress => size > 0 ? receivedBytes / size : 0.0;
}
