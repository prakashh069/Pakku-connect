import '../../../core/constants/message_types.dart';

class FileTransferStart {
  final String transferId;
  final String name;
  final String mime;
  final int size;
  final int totalChunks;
  final String sha256;
  final String? batchId;
  final int? batchCount;
  final int? batchIndex;
  final int? batchTotal;
  final bool isBatchedZip;

  FileTransferStart({
    required this.transferId,
    required this.name,
    required this.mime,
    required this.size,
    required this.totalChunks,
    required this.sha256,
    this.batchId,
    this.batchCount,
    this.batchIndex,
    this.batchTotal,
    this.isBatchedZip = false,
  });

  factory FileTransferStart.fromJson(Map<String, dynamic> json) {
    return FileTransferStart(
      transferId: json['transferId'] as String,
      name: json['name'] as String,
      mime: json['mime'] as String,
      size: json['size'] as int,
      totalChunks: json['totalChunks'] as int,
      sha256: json['sha256'] as String,
      batchId: json['batchId'] as String?,
      batchCount: json['batchCount'] as int?,
      batchIndex: json['batchIndex'] as int?,
      batchTotal: json['batchTotal'] as int?,
      isBatchedZip: json['isBatchedZip'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'type': MessageTypes.fileTransferStart,
      'transferId': transferId,
      'name': name,
      'mime': mime,
      'size': size,
      'totalChunks': totalChunks,
      'sha256': sha256,
      'isBatchedZip': isBatchedZip,
    };
    if (batchId != null) map['batchId'] = batchId;
    if (batchCount != null) map['batchCount'] = batchCount;
    if (batchIndex != null) map['batchIndex'] = batchIndex;
    if (batchTotal != null) map['batchTotal'] = batchTotal;
    return map;
  }
}

class FileTransferReady {
  final String transferId;

  FileTransferReady({required this.transferId});

  factory FileTransferReady.fromJson(Map<String, dynamic> json) {
    return FileTransferReady(
      transferId: json['transferId'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': MessageTypes.fileTransferReady,
        'transferId': transferId,
      };
}

class FileTransferChunk {
  final String transferId;
  final int chunkIndex;
  final int totalChunks;
  final String payload;

  FileTransferChunk({
    required this.transferId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.payload,
  });

  factory FileTransferChunk.fromJson(Map<String, dynamic> json) {
    return FileTransferChunk(
      transferId: json['transferId'] as String,
      chunkIndex: json['chunkIndex'] as int,
      totalChunks: json['totalChunks'] as int,
      payload: json['payload'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': MessageTypes.fileTransferChunk,
        'transferId': transferId,
        'chunkIndex': chunkIndex,
        'totalChunks': totalChunks,
        'payload': payload,
      };
}

class FileTransferChunkAck {
  final String transferId;
  final int chunkIndex;

  FileTransferChunkAck({
    required this.transferId,
    required this.chunkIndex,
  });

  factory FileTransferChunkAck.fromJson(Map<String, dynamic> json) {
    return FileTransferChunkAck(
      transferId: json['transferId'] as String,
      chunkIndex: json['chunkIndex'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': MessageTypes.fileTransferChunkAck,
        'transferId': transferId,
        'chunkIndex': chunkIndex,
      };
}

class FileTransferComplete {
  final String transferId;
  final bool sha256Match;

  FileTransferComplete({
    required this.transferId,
    required this.sha256Match,
  });

  factory FileTransferComplete.fromJson(Map<String, dynamic> json) {
    return FileTransferComplete(
      transferId: json['transferId'] as String,
      sha256Match: json['sha256Match'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': MessageTypes.fileTransferComplete,
        'transferId': transferId,
        'sha256Match': sha256Match,
      };
}

class FileTransferError {
  final String transferId;
  final String reason;

  FileTransferError({
    required this.transferId,
    required this.reason,
  });

  factory FileTransferError.fromJson(Map<String, dynamic> json) {
    return FileTransferError(
      transferId: json['transferId'] as String,
      reason: json['reason'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': MessageTypes.fileTransferError,
        'transferId': transferId,
        'reason': reason,
      };
}

class FileTransferCancel {
  final String transferId;
  final String reason;

  FileTransferCancel({
    required this.transferId,
    required this.reason,
  });

  factory FileTransferCancel.fromJson(Map<String, dynamic> json) {
    return FileTransferCancel(
      transferId: json['transferId'] as String,
      reason: json['reason'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': MessageTypes.fileTransferCancel,
        'transferId': transferId,
        'reason': reason,
      };
}

class FileTransferMimeTypes {
  static const pdf = 'application/pdf';
  static const txt = 'text/plain';
  static const rtf = 'application/rtf';
  static const md = 'text/markdown';
  static const odt = 'application/vnd.oasis.opendocument.text';
  static const doc = 'application/msword';
  static const docx = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  static const xls = 'application/vnd.ms-excel';
  static const xlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const csv = 'text/csv';
  static const ppt = 'application/vnd.ms-powerpoint';
  static const pptx = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
  static const epub = 'application/epub+zip';
  static const jpeg = 'image/jpeg';
  static const jpg = 'image/jpg';
  static const png = 'image/png';
  static const webp = 'image/webp';
  static const gif = 'image/gif';
  static const bmp = 'image/bmp';
  static const mp4 = 'video/mp4';
  
  static const generic = 'application/octet-stream';

  static bool isAllowed(String mime) {
    if (mime.startsWith('text/')) return true;
    if (mime.startsWith('image/')) return true;
    if (mime == 'application/zip') return true;
    return [
      pdf, rtf, odt, doc, docx, 
      xls, xlsx, ppt, pptx, 
      epub, mp4, generic
    ].contains(mime);
  }
}

class FileTransferErrorReasons {
  static const sha256Mismatch = 'sha256_mismatch';
  static const chunkOutOfOrder = 'chunk_out_of_order';
  static const timeout = 'timeout';
  static const unsupportedMime = 'unsupported_mime';
  static const fileTooLarge = 'file_too_large';
  static const writeFailure = 'write_failure';
  static const transferAlreadyActive = 'transfer_already_active';
}
