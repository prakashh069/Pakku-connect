import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connecto/core/constants/app_theme.dart';
import 'package:connecto/features/calling/services/call_manager.dart';
import 'package:connecto/core/services/websocket_service.dart';

class KeypadTab extends StatefulWidget {
  final bool isActive;
  const KeypadTab({super.key, this.isActive = true});

  @override
  State<KeypadTab> createState() => _KeypadTabState();
}

class _KeypadTabState extends State<KeypadTab> {
  String _number = '';
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(KeypadTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _onKeyPress(String key) {
    setState(() {
      _number += key;
    });
  }

  void _onBackspace() {
    if (_number.isNotEmpty) {
      setState(() {
        _number = _number.substring(0, _number.length - 1);
      });
    }
  }

  void _onBackspaceLongPress() {
    setState(() {
      _number = '';
    });
  }

  void _onCall() {
    if (_number.isNotEmpty) {
      final ws = context.read<WebSocketService>();
      if (!ws.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Cannot place call: Phone is not connected')),
        );
        return;
      }
      context.read<CallManager>().dial(_number);
    }
  }

  KeyEventResult _handleFocusKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      final char = event.character;
      final keyLabel = event.logicalKey.keyLabel;

      if (char != null && RegExp(r'^[0-9*#+]$').hasMatch(char)) {
        _onKeyPress(char);
        return KeyEventResult.handled;
      } else if (RegExp(r'^[0-9*#+]$').hasMatch(keyLabel)) {
        _onKeyPress(keyLabel);
        return KeyEventResult.handled;
      } else if (keyLabel.startsWith('Numpad ')) {
        final numpadChar = keyLabel.replaceAll('Numpad ', '');
        if (RegExp(r'^[0-9]$').hasMatch(numpadChar)) {
          _onKeyPress(numpadChar);
          return KeyEventResult.handled;
        } else if (numpadChar == 'Add') {
          _onKeyPress('+');
          return KeyEventResult.handled;
        } else if (numpadChar == 'Multiply') {
          _onKeyPress('*');
          return KeyEventResult.handled;
        }
      }

      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        _onBackspace();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _onCall();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;

    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleFocusKey,
        child: Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: 500), // wider to fit side buttons
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 100.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Number display
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32.0, vertical: 16.0),
                          alignment: Alignment.bottomCenter,
                          height: 80, // reduced height
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _number,
                              style: TextStyle(
                                fontSize: 42, // slightly smaller
                                fontWeight: FontWeight.w400,
                                color: colors.lightText,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Keypad and actions side-by-side
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Left invisible spacer to balance the right side buttons
                            const SizedBox(width: 80),

                            // Center: standard 3x4 grid
                            Column(
                              children: [
                                _buildKeypadRow(
                                    ['1', '2', '3'], ['', 'ABC', 'DEF'], colors),
                                const SizedBox(height: 12),
                                _buildKeypadRow(
                                    ['4', '5', '6'], ['GHI', 'JKL', 'MNO'], colors),
                                const SizedBox(height: 12),
                                _buildKeypadRow(
                                    ['7', '8', '9'], ['PQRS', 'TUV', 'WXYZ'], colors),
                                const SizedBox(height: 12),
                                _buildKeypadRow(
                                    ['*', '0', '#'], ['', '+', ''], colors),
                              ],
                            ),

                            const SizedBox(
                                width: 16), // space between grid and buttons

                            // Right side: backspace and call button
                            Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                const SizedBox(
                                    height:
                                        76), // 64 (button height) + 12 (spacing) to align with row 2

                                // Backspace button
                                SizedBox(
                                  width: 64,
                                  height: 64,
                                  child: _number.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(Icons.backspace,
                                              color: colors.lightText.withAlpha(150)),
                                          iconSize: 26,
                                          onPressed: _onBackspace,
                                          onLongPress: _onBackspaceLongPress,
                                        )
                                      : const SizedBox(), // empty box if no number
                                ),

                                const SizedBox(height: 12),

                                // Call button
                                GestureDetector(
                                  onTap: _onCall,
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: colors.success,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.call,
                                        color: Colors.white, size: 28),
                                  ),
                                ),

                                const SizedBox(
                                    height: 76), // 64 + 12 to match grid height total
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadRow(
      List<String> keys, List<String> letters, CustomColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _KeypadButton(
            keyChar: keys[index],
            subText: letters[index],
            colors: colors,
            onPressed: () => _onKeyPress(keys[index]),
          ),
        );
      }),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String keyChar;
  final String subText;
  final CustomColors colors;
  final VoidCallback onPressed;

  const _KeypadButton({
    required this.keyChar,
    required this.subText,
    required this.colors,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: colors.surface,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              keyChar,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w400,
                color: colors.lightText,
              ),
            ),
            if (subText.isNotEmpty)
              Text(
                subText,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: colors.lightText.withAlpha(100),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
