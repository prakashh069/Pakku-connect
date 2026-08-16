import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

import '../models/file_transfer_protocol.dart';
import '../models/file_transfer_session.dart';
import '../utils/filename_sanitizer.dart';

Future<List<String>> _extractZipIsolate(Map<String, dynamic> params) async {
  final String zipPath = params['zipPath'];
  final String tempDirPath = params['tempDirPath'];

  final bytes = File(zipPath).readAsBytesSync();
  final archive = ZipDecoder().decodeBytes(bytes);
  
  List<String> extractedPaths = [];
  
  for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
          final data = file.content as List<int>;
          
          String outName = filename;
          File outFile = File('$tempDirPath/$outName');
          int outCounter = 2;
          while (outFile.existsSync()) {
              final lastDot = filename.lastIndexOf('.');
              if (lastDot > 0) {
                  outName = '${filename.substring(0, lastDot)}_$outCounter${filename.substring(lastDot)}';
              } else {
                  outName = '${filename}_$outCounter';
              }
              outFile = File('$tempDirPath/$outName');
              outCounter++;
          }
          
          outFile.writeAsBytesSync(data);
          extractedPaths.add(outFile.path);
      }
  }
  
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
      print("[FT-RECEIVER] start");
      if (start.isBatchedZip) {
          print("[PHASE8] BATCH START");
          print("[PHASE8] EXPECTED FILES: ${start.batchCount ?? 0}");
      }
      final tempDir = Directory('${Directory.systemTemp.path}/connecto_transfers/${start.transferId}');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      print("[FileReceiver] temp directory created");
      print("[PHASE7] Temp directory created");

      _tempFile = File('${tempDir.path}/${_session!.filename}');
      _fileSink = _tempFile!.openWrite();

      _session!.state = FileTransferState.readyReceived;
      
      sendMessage(FileTransferReady(transferId: start.transferId).toJson());
      print("[FT-RECEIVER] ready sent");
      print("[PHASE7] READY SENT");

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

      print("[FileReceiver] chunk received ${chunk.chunkIndex}");
      print("[PHASE7] CHUNK RECEIVED ${chunk.chunkIndex}");
      
      if (newProgress - _lastReportedProgress >= 0.05 || _session!.receivedChunks == _session!.totalChunks) {
          _lastReportedProgress = newProgress;
          print("[PHASE8] PROGRESS UPDATE: ${(newProgress * 100).toInt()}%");
          onProgress(_session!.transferId, newProgress);
      }

      sendMessage(FileTransferChunkAck(
        transferId: chunk.transferId,
        chunkIndex: chunk.chunkIndex,
      ).toJson());
      print("[PHASE7] ACK SENT ${chunk.chunkIndex}");

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
    print("[PHASE7] COMPLETE RECEIVED MAC");
    print("[PHASE7] FINISH TRANSFER START");
    _cancelTimers();
    _session!.state = FileTransferState.verifying;
    await _fileSink?.flush();
    await _fileSink?.close();
    _fileSink = null;

    try {
      if (_tempFile == null || !await _tempFile!.exists()) {
        throw Exception("Temp file missing");
      }

      print("[PHASE7] SHA256 VERIFY START");
      final hash = await sha256.bind(_tempFile!.openRead()).first;
      final computedSha256 = hash.toString();

      if (computedSha256 != _session!.sha256) {
        print("[PHASE7] SHA256 MISMATCH");
        _handleError(FileTransferErrorReasons.sha256Mismatch);
        return;
      }
      print("[PHASE7] SHA256 VERIFIED");

      bool isImage = _session!.mime.startsWith('image/');
      bool isBatchedZip = _session!.isBatchedZip;

      final tempDir = Directory('${Directory.systemTemp.path}/connecto_transfers/${_session!.transferId}');
      
      _session!.state = FileTransferState.completed;
      sendMessage(FileTransferComplete(
        transferId: _session!.transferId,
        sha256Match: true,
      ).toJson());
      print("[PHASE7] COMPLETE SENT TO ANDROID");
      print("[PHASE7] COMPLETION EVENT SENT");

      List<String>? extractedPaths;
      String? folderPath;
      
      if (isBatchedZip) {
          print("[PHASE8] ZIP EXTRACTION START (ISOLATE)");
          
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
          
          print("[PHASE8] BATCH COMPLETE");
          print("[PHASE8] SHOWING BATCH POPUP");
          print("[PHASE8] FILE COUNT: ${extractedPaths?.length}");
      }
      
      print("[PHASE7] IMAGE DETECTED: $isImage");
      if (isImage && extractedPaths == null) {
        print("[PHASE7] FILE PATH SENT: ${_tempFile!.path}");
      }

      // showNotification will only be called by FileTransferManager for non-batch or when batch is complete
      onFinished(_session!.transferId, session: _session!, filePaths: extractedPaths ?? [_tempFile!.path], folderPath: folderPath);
    } catch (e) {
      print("[PHASE7] FINISH ERROR: $e");
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
