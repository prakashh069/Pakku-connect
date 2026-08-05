import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/call_manager.dart';
import '../../../core/models/call.dart';
import '../../../core/constants/app_theme.dart';

class CallPopup extends StatelessWidget {
  const CallPopup({super.key});

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    }
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    return Consumer<CallManager>(
      builder: (context, manager, _) {
        final call = manager.currentCall;
        
        return AnimatedOpacity(
          opacity: call == null ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 300),
          child: call == null
              ? const SizedBox.shrink()
              : Material(
                  color: Colors.black54,
                  child: Center(
                    child: Container(
                      width: 360,
                      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: colors.accent.withValues(alpha: 0.3), width: 1),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildAvatar(call, colors),
                          const SizedBox(height: 20),
                          Text(
                            call.contactName ?? call.phoneNumber,
                            style: TextStyle(
                              color: colors.lightText,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            call.phoneNumber,
                            style: TextStyle(
                              color: colors.lightText.withValues(alpha: 0.6),
                              fontSize: 15,
                              letterSpacing: 1.0,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (manager.lastNativeError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              manager.lastNativeError!,
                              style: TextStyle(color: colors.danger, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 32),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _buildStateContent(call, manager, colors, context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildAvatar(Call call, CustomColors colors) {
    final initials = (call.contactName != null && call.contactName!.isNotEmpty)
        ? call.contactName!.substring(0, 1).toUpperCase()
        : '?';
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: colors.accent.withValues(alpha: 0.5), width: 2),
      ),
      child: Center(
        child: call.contactName == null
            ? Icon(Icons.person, size: 48, color: colors.accent)
            : Text(
                initials,
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildStateContent(Call call, CallManager manager, CustomColors colors, BuildContext context) {
    if (call.state == CallState.ringing) {
      if (call.direction == CallDirection.incoming) {
        return Row(
          key: const ValueKey('ringing_incoming'),
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCircularButton(
              icon: Icons.call_end,
              label: 'Decline',
              color: colors.danger,
              onPressed: manager.rejectCall,
            ),
            _buildCircularButton(
              icon: Icons.call,
              label: 'Accept',
              color: colors.success,
              onPressed: manager.answerCall,
            ),
          ],
        );
      } else {
        return Column(
          key: const ValueKey('ringing_outgoing'),
          children: [
            Text(
              'Calling...',
              style: TextStyle(
                color: colors.accent,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            _buildCircularButton(
              icon: Icons.call_end,
              label: 'Cancel',
              color: colors.danger,
              onPressed: manager.cancelOutgoingCall,
            ),
          ],
        );
      }
    } else if (call.state == CallState.answeredRemotely) {
      return Column(
        key: const ValueKey('answered'),
        children: [
          Text(
            call.direction == CallDirection.outgoing ? 'Calling...' : 'Connected',
            style: TextStyle(
              color: call.direction == CallDirection.outgoing ? colors.accent : colors.success,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          if (call.direction == CallDirection.incoming) ...[
            Text(
              _formatDuration(manager.callDuration),
              style: TextStyle(
                color: colors.lightText,
                fontSize: 36,
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 24),
          ] else
            const SizedBox(height: 32),
          _buildCircularButton(
            icon: Icons.call_end,
            label: manager.isEnding ? 'Ending...' : 'End Call',
            color: colors.danger,
            onPressed: manager.isEnding ? null : manager.endCall,
          ),
        ],
      );
    } else if (call.state == CallState.ended) {
      return Column(
        key: const ValueKey('ended'),
        children: [
          Text(
            'Call Ended',
            style: TextStyle(
              color: colors.lightText.withValues(alpha: 0.8),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (call.direction == CallDirection.incoming) ...[
            const SizedBox(height: 8),
            Text(
              _formatDuration(manager.callDuration),
              style: TextStyle(
                color: colors.lightText.withValues(alpha: 0.5),
                fontSize: 24,
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildCircularButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(18),
            elevation: 4,
          ),
          child: Icon(icon, size: 28),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
