import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/message_types.dart';
import '../../../core/messaging/message_bus.dart';
import '../../../core/messaging/message_types.dart';
import '../models/file_transfer_protocol.dart';
import '../models/file_transfer_session.dart';
import 'file_receiver.dart';

class FileTransferManager {
  final MessageBus? _messageBus;
  late final StreamSubscription? _subscription;
  
  static const MethodChannel _notificationChannel = MethodChannel('com.connecto.app/notifications');

  FileReceiver? _currentReceiver;

  FileTransferManager({
    MessageBus? messageBus,
  }) : _messageBus = messageBus {
    if (!Platform.isMacOS) return;

    _subscription = _messageBus?.messagesOfType(BusMessagePrefixes.fileTransfer).listen(_handleMessage);
  }

  void _sendMessage(Map<String, dynamic> message) {
    _messageBus?.send(message, route: MessageRoute.broadcast);
  }

  void _handleMessage(dynamic busMsg) {
    final message = busMsg.raw;
    try {
      final String? type = message['type'] as String?;
      if (type == null || !type.startsWith('file.transfer.')) return;

      switch (type) {
        case MessageTypes.fileTransferStart:
          debugPrint('[FT_START_RECEIVED] type=$type');
          _handleStart(FileTransferStart.fromJson(message));
          break;
        case MessageTypes.fileTransferChunk:
          debugPrint('[FT_CHUNK_RECEIVED] transferId=${message['transferId']} chunkIndex=${message['chunkIndex']}');
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
      debugPrint('[FileTransferManager] Error handling message: $e\n$stackTrace');
    }
  }

  void _handleStart(FileTransferStart start) {
    debugPrint('[ConnectoShare][FILE_TRANSFER_START] transferId=${start.transferId} fileName=${start.name} size=${start.size} isBatchedZip=${start.isBatchedZip} batchCount=${start.batchCount}');
    if (_currentReceiver != null && _currentReceiver!.isActive) {
      debugPrint('[ConnectoShare][FILE_TRANSFER_START] REJECTED — transfer already active!');
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
      onError: _onReceiverError,
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
      debugPrint('[FileTransferManager] Progress method channel error: $e');
    }
  }

  void _onReceiverFinished(String transferId, {FileTransferSession? session, List<String>? filePaths, String? folderPath}) {
    debugPrint('[ConnectoShare][FILE_TRANSFER_COMPLETE] transferId=$transferId filePaths=${filePaths?.length} isBatchedZip=${session?.isBatchedZip}');
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
    try {
      const channel = MethodChannel('com.connecto.app/fileTransferPopup');
      await channel.invokeMethod('showFileTransferPopup', {
        'filePaths': filePaths,
        'fileName': fileName,
        'isBatchedZip': isBatchedZip,
        'folderPath': folderPath,
      });
    } catch (e) {
      debugPrint('[FileTransferManager] Popup method channel error: $e');
    }
  }

  void _onReceiverError(String transferId, String reason) {
    debugPrint('[ConnectoShare][FILE_TRANSFER_ERROR] transferId=$transferId reason=$reason');
    if (_currentReceiver != null) {
      _currentReceiver = null;
    }

    if (Platform.isMacOS) {
      const channel = MethodChannel('com.connecto.app/fileTransferPopup');
      channel.invokeMethod('showFileTransferError', {
        'reason': reason,
      });
    }
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
      
      _notificationChannel.invokeMethod('showNotification', args);
    } catch (e) {
      // Ignore notification failures
    }
  }

  void dispose() {
    if (Platform.isMacOS) {
      _subscription?.cancel();
      _currentReceiver?.handleCancel(FileTransferCancel(
        transferId: 'dispose',
        reason: 'app_backgrounded',
      ));
    }
  }
}
