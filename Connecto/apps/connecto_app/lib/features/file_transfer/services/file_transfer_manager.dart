import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import '../../../core/constants/message_types.dart';
import '../../../core/services/platform_transport.dart';
import '../models/file_transfer_protocol.dart';
import '../models/file_transfer_session.dart';
import 'file_receiver.dart';

class FileTransferManager {
  final PlatformTransport _transport;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  
  static const MethodChannel _notificationChannel = MethodChannel('com.connecto.app/notifications');

  FileReceiver? _currentReceiver;

  FileTransferManager(this._transport) {
    print("[PHASE7] FileTransferManager initialized");
    if (!Platform.isMacOS) return;

    _subscription = _transport.messages.listen(_handleMessage);
  }

  void _handleMessage(Map<String, dynamic> message) {
    try {
      final String? type = message['type'] as String?;
      if (type == null || !type.startsWith('file.transfer.')) return;
      
      print("[FT-MAC] websocket message received type=$type");

      switch (type) {
        case MessageTypes.fileTransferStart:
          _handleStart(FileTransferStart.fromJson(message));
          break;
        case MessageTypes.fileTransferChunk:
          _currentReceiver?.handleChunk(FileTransferChunk.fromJson(message));
          break;
        case MessageTypes.fileTransferError:
          _currentReceiver?.handleError(FileTransferError.fromJson(message));
          break;
        case MessageTypes.fileTransferCancel:
          _currentReceiver?.handleCancel(FileTransferCancel.fromJson(message));
          break;
      }
    } catch (e, stackTrace) {
      print("[FT-MAC] Error handling message: $e");
      print("[FT-MAC] Stack trace: $stackTrace");
    }
  }

  void _handleStart(FileTransferStart start) {
    print("[PHASE7] START RECEIVED");
    if (_currentReceiver != null && _currentReceiver!.isActive) {
      _sendMessage(FileTransferError(
        transferId: start.transferId,
        reason: FileTransferErrorReasons.transferAlreadyActive,
      ).toJson());
      return;
    }

    _currentReceiver = FileReceiver(
      sendMessage: _sendMessage,
      showNotification: _showNotification,
      onFinished: _onReceiverFinished,
      onProgress: _onProgress,
    );
    
    _currentReceiver!.handleStart(start);
  }

  void _onProgress(String transferId, double progress) {
    if (_currentReceiver == null || _currentReceiver!.session == null) return;
    
    final session = _currentReceiver!.session!;
    bool isBatchedZip = session.isBatchedZip;
    int? batchCount = session.batchCount;
    String fileName = session.filename;

    try {
      const channel = MethodChannel('com.connecto.app/fileTransferPopup');
      channel.invokeMethod('updateFileTransferProgress', {
        'progress': progress,
        'fileName': fileName,
        'isBatchedZip': isBatchedZip,
        'batchCount': batchCount,
      });
    } catch (e) {
      print("[PHASE8] PROGRESS METHOD CHANNEL ERROR: $e");
    }
  }

  void _onReceiverFinished(String transferId, {FileTransferSession? session, List<String>? filePaths, String? folderPath}) {
    if (_currentReceiver != null) {
      _currentReceiver = null;
    }

    if (session == null || filePaths == null || filePaths.isEmpty) return;

    bool isImage = session.mime.startsWith('image/');
    bool isBatchedZip = session.isBatchedZip;

    if (Platform.isMacOS) {
        _showPopup(filePaths, session.filename, isBatchedZip, folderPath);
    } else {
        _showNotification(
            'Connecto', 
            'File received: ${session.filename}\nSaved to Downloads',
            filePath: filePaths.first,
            fileName: session.filename,
            mimeType: session.mime,
            isImage: isImage,
        );
    }
  }

  void _showPopup(List<String> filePaths, String fileName, bool isBatchedZip, String? folderPath) async {
    print("[PHASE7] POPUP CREATED (isBatchedZip=$isBatchedZip)");
    try {
      const channel = MethodChannel('com.connecto.app/fileTransferPopup');
      await channel.invokeMethod('showFileTransferPopup', {
        'filePaths': filePaths,
        'fileName': fileName,
        'isBatchedZip': isBatchedZip,
        'folderPath': folderPath,
      });
    } catch (e) {
      print("[PHASE7] POPUP METHOD CHANNEL ERROR: $e");
    }
  }

  void _sendMessage(Map<String, dynamic> message) {
    _transport.send(message);
  }

  void _showNotification(String title, String body, {String? filePath, String? fileName, String? mimeType, bool? isImage}) {
    try {
      final Map<String, dynamic> args = {
        'title': title,
        'body': body,
      };
      
      if (filePath != null) args['filePath'] = filePath;
      if (fileName != null) args['fileName'] = fileName;
      if (mimeType != null) args['mimeType'] = mimeType;
      if (isImage != null) args['isImage'] = isImage;
      
      print("[PHASE7] METHOD CHANNEL INVOKED");
      print("title: $title, body: $body, filePath: $filePath, fileName: $fileName, mimeType: $mimeType, isImage: $isImage");
      
      _notificationChannel.invokeMethod('showNotification', args);
    } catch (e) {
      // Ignore notification failures
    }
  }

  void dispose() {
    if (Platform.isMacOS) {
      _subscription.cancel();
      _currentReceiver?.handleCancel(FileTransferCancel(
        transferId: 'dispose',
        reason: 'app_backgrounded',
      ));
    }
  }
}
