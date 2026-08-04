import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/call_manager.dart';
import '../../../core/models/call.dart';
import '../../../core/constants/app_theme.dart';

class CallPopup extends StatelessWidget {
  const CallPopup({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    return Consumer<CallManager>(
      builder: (context, manager, _) {
        final call = manager.currentCall;
        if (call == null || call.state == CallState.ended) {
          return const SizedBox.shrink();
        }

        return Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              width: 340,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.accent, width: 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    call.direction == CallDirection.incoming
                        ? Icons.phone_in_talk
                        : Icons.phone_forwarded,
                    color: colors.accent,
                    size: 42,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    call.contactName ?? call.phoneNumber,
                    style: TextStyle(
                      color: colors.lightText,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    call.phoneNumber,
                    style: TextStyle(color: colors.lightText.withAlpha(178)),
                  ),
                  if (manager.lastNativeError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      manager.lastNativeError!,
                      style: TextStyle(color: colors.danger, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (call.state == CallState.ringing)
                    if (call.direction == CallDirection.incoming)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.call_end),
                            label: const Text('Decline'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.danger,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: manager.rejectCall,
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.call),
                            label: const Text('Accept'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.success,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: manager.answerCall,
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          Text(
                            'Calling...',
                            style: TextStyle(
                              color: colors.accent,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.call_end),
                            label: const Text('Cancel'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.danger,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: manager.cancelOutgoingCall,
                          ),
                        ],
                      )
                  else
                    Text(
                      'Call answered on phone',
                      style: TextStyle(color: colors.lightText),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
