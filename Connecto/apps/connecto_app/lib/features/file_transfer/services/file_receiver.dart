import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../models/file_transfer_protocol.dart';
import '../models/file_transfer_session.dart';
import '../utils/filename_sanitizer.dart';

import 'package:path/path.dart' as p;

Future<List<String>> _extractZipIsolate(Map<String, dynamic> params) async {
  final String zipPath = params['zipPath'];
  final String tempDirPath = params['tempDirPath'];

  final inputStream = InputFileStream(zipPath);
  final archive = ZipDecoder().decodeStream(inputStream);
  
  List<String> extractedPaths = [];
  final String canonicalTempDir = p.canonicalize(tempDirPath);
  
  int entryCount = 0;
  int totalUncompressedSize = 0;
  const int maxEntries = 10000;
  const int maxTotalUncompressedSize = 2 * 1024 * 1024 * 1024; // 2 GB
  
  for (final file in archive) {
      entryCount++;
      if (entryCount > maxEntries) {
          inputStream.close();
          throw Exception("ZIP archive exceeded maximum allowed entries.");
      }
      
      if (file.isFile) {
          if (file.isSymbolicLink) {
              print('[PHASE11B] Rejected symbolic link ZIP entry: ${file.name}');
              continue;
          }
          
          final candidatePath = p.canonicalize(p.join(tempDirPath, file.name));
          if (!p.isWithin(canonicalTempDir, candidatePath)) {
              print('[PHASE11B] Rejected malicious/invalid ZIP entry: ${file.name}');
              continue;
          }
          
          if (file.size < 0) continue;
          totalUncompressedSize += file.size as int;
          if (totalUncompressedSize > maxTotalUncompressedSize) {
              inputStream.close();
              throw Exception("ZIP archive exceeded maximum allowed uncompressed size.");
          }
          
          File outFile = File(candidatePath);
          int outCounter = 2;
          String baseName = p.basenameWithoutExtension(outFile.path);
          String ext = p.extension(outFile.path);
          String dir = outFile.parent.path;
          
          while (outFile.existsSync()) {
              outFile = File(p.join(dir, '${baseName}_$outCounter$ext'));
              outCounter++;
          }
          
          outFile.parent.createSync(recursive: true);
          
          final outputStream = OutputFileStream(outFile.path);
          file.writeContent(outputStream);
          outputStream.close();
          
          extractedPaths.add(outFile.path);
      }
  }
  
  inputStream.close();
  return extractedPaths;
}

class FileReceiver {
  final Function(Map<String, dynamic>) sendMessage;
  final Function(String title, String body, {String? filePath, String? fileName, String? mimeType, bool? isImage}) showNotification;
  final void Function(String transferId, {FileTransferSession? session, List<String>? filePaths, String? folderPath}) onFinished;
  final void Function(String transferId, double progress) onProgress;

  FileTransferSession? _session;
  File? _tempFile;
  IOSink? _fileSink;
  Timer? _chunkTimer;
  Timer? _globalTimer;

  static const _chunkTimeout = Duration(seconds: 30);
  static const _globalTimeout = Duration(minutes: 10);

  double _lastReportedProgress = 0.0;

  FileReceiver({
    required this.sendMessage,
    required this.showNotification,
    required this.onFinished,
    required this.onProgress,
  });

  bool get isActive => _session != null && !_session!.isFinished;
  FileTransferSession? get session => _session;

  Future<void> handleStart(FileTransferStart start) async {
    if (isActive) {
      sendMessage(FileTransferError(
        transferId: start.transferId,
        reason: FileTransferErrorReasons.transferAlreadyActive,
      ).toJson());
      return;
    }

    if (!FileTransferMimeTypes.isAllowed(start.mime)) {
      sendMessage(FileTransferError(
        transferId: start.transferId,
        reason: FileTransferErrorReasons.unsupportedMime,
      ).toJson());
      return;
    }

    if (start.size > 500 * 1024 * 1024) {
      sendMessage(FileTransferError(
        transferId: start.transferId,
        reason: FileTransferErrorReasons.fileTooLarge,
      ).toJson());
      return;
    }

    _session = FileTransferSession(
      transferId: start.transferId,
      filename: FilenameSanitizer.sanitize(start.name),
      mime: start.mime,
      size: start.size,
      sha256: start.sha256,
      totalChunks: start.totalChunks,
      batchId: start.batchId,
      batchCount: start.batchCount,
      batchIndex: start.batchIndex,
      batchTotal: start.batchTotal,
      isBatchedZip: start.isBatchedZip,
    );

    try {
      final tempDir = Directory('${Directory.systemTemp.path}/connecto_transfers/${start.transferId}');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      _tempFile = File('${tempDir.path}/${_session!.filename}');
      _fileSink = _tempFile!.openWrite();

      _session!.state = FileTransferState.readyReceived;
      
      sendMessage(FileTransferReady(transferId: start.transferId).toJson());

      _lastReportedProgress = 0.0;
      _resetTimers();
    } catch (e) {
      _handleError(FileTransferErrorReasons.writeFailure);
    }
  }

  Future<void> handleChunk(FileTransferChunk chunk) async {
    if (_session == null || _session!.transferId != chunk.transferId) return;
    
    if (_session!.state == FileTransferState.cancelled || _session!.state == FileTransferState.failed) return;

    if (chunk.chunkIndex < _session!.receivedChunks) {
      // Duplicate chunk, silent discard but ack again to be safe
      sendMessage(FileTransferChunkAck(
        transferId: chunk.transferId,
        chunkIndex: chunk.chunkIndex,
      ).toJson());
      return;
    }

    if (chunk.chunkIndex > _session!.receivedChunks) {
      _handleError(FileTransferErrorReasons.chunkOutOfOrder);
      return;
    }

    _session!.state = FileTransferState.transferring;
    _resetTimers();

    try {
      final bytes = base64Decode(chunk.payload);
      _fileSink?.add(bytes);
      
      _session!.receivedChunks++;
      _session!.receivedBytes += bytes.length;
      double newProgress = _session!.progress;

      if (newProgress - _lastReportedProgress >= 0.05 || _session!.receivedChunks == _session!.totalChunks) {
          _lastReportedProgress = newProgress;
          onProgress(_session!.transferId, newProgress);
      }

      sendMessage(FileTransferChunkAck(
        transferId: chunk.transferId,
        chunkIndex: chunk.chunkIndex,
      ).toJson());

      if (_session!.receivedChunks == _session!.totalChunks) {
        await _finishTransfer();
      }
    } catch (e) {
      _handleError(FileTransferErrorReasons.writeFailure);
    }
  }

  void handleCancel(FileTransferCancel cancel) {
    if (_session != null && _session!.transferId == cancel.transferId) {
      _session!.state = FileTransferState.cancelled;
      _cleanup();
    }
  }

  void handleError(FileTransferError error) {
    if (_session != null && _session!.transferId == error.transferId) {
      _session!.state = FileTransferState.failed;
      _cleanup();
    }
  }

  Future<void> _finishTransfer() async {
    _cancelTimers();
    _session!.state = FileTransferState.verifying;
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;

    try {
      if (_tempFile == null || !await _tempFile!.exists()) {
        throw Exception("Temp file missing");
      }

      final hash = await sha256.bind(_tempFile!.openRead()).first;
      final computedSha256 = hash.toString();

      if (computedSha256 != _session!.sha256) {
        _handleError(FileTransferErrorReasons.sha256Mismatch);
        return;
      }

      bool isBatchedZip = _session!.isBatchedZip;

      final tempDir = Directory('${Directory.systemTemp.path}/connecto_transfers/${_session!.transferId}');
      
      _session!.state = FileTransferState.completed;
      sendMessage(FileTransferComplete(
        transferId: _session!.transferId,
        sha256Match: true,
      ).toJson());

      List<String>? extractedPaths;
      String? folderPath;
      
      if (isBatchedZip) {
          if (!tempDir.existsSync()) {
              tempDir.createSync(recursive: true);
          }
          
          extractedPaths = await compute(_extractZipIsolate, {
              'zipPath': _tempFile!.path,
              'tempDirPath': tempDir.path
          });
          
          // Delete the zip file after extraction
          if (_tempFile!.existsSync()) {
              _tempFile!.deleteSync();
          }
      }

      // showNotification will only be called by FileTransferManager for non-batch or when batch is complete
      onFinished(_session!.transferId, session: _session!, filePaths: extractedPaths ?? [_tempFile!.path], folderPath: folderPath);
    } catch (e) {
      debugPrint('[FileReceiver] Transfer completion error: $e');
      _handleError(FileTransferErrorReasons.writeFailure);
    }
  }

  void _handleError(String reason) {
    if (_session == null) return;
    _session!.state = FileTransferState.failed;
    sendMessage(FileTransferError(
      transferId: _session!.transferId,
      reason: reason,
    ).toJson());
    _cleanup();
  }

  void _resetTimers() {
    _chunkTimer?.cancel();
    _chunkTimer = Timer(_chunkTimeout, () {
      _handleError(FileTransferErrorReasons.timeout);
    });

    if (_globalTimer == null || !_globalTimer!.isActive) {
      _globalTimer = Timer(_globalTimeout, () {
        _handleError(FileTransferErrorReasons.timeout);
      });
    }
  }

  void _cancelTimers() {
    _chunkTimer?.cancel();
    _chunkTimer = null;
    _globalTimer?.cancel();
    _globalTimer = null;
  }

  Future<void> _cleanup() async {
    _cancelTimers();
    await _fileSink?.close();
    _fileSink = null;
    await _cleanupTempDir();
    if (_session != null) {
      onFinished(_session!.transferId);
    }
  }

  Future<void> _cleanupTempDir() async {
    if (_session == null) return;
    try {
      final tempDir = Directory('${Directory.systemTemp.path}/connecto_transfers/${_session!.transferId}');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }
}
