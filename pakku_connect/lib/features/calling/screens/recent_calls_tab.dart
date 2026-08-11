import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_theme.dart';
import '../../../core/models/recent_call.dart';
import '../../../shared/widgets/contact_avatar.dart';
import '../services/call_manager.dart';
import '../services/recent_calls_manager.dart';

class RecentCallsTab extends StatefulWidget {
  const RecentCallsTab({super.key});

  @override
  State<RecentCallsTab> createState() => _RecentCallsTabState();
}

class _RecentCallsTabState extends State<RecentCallsTab> {
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildEmptyState(CustomColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: colors.lightText.withAlpha(50)),
          const SizedBox(height: 16),
          Text(
            'No recent calls yet.',
            style: TextStyle(
              color: colors.lightText.withAlpha(128),
              fontStyle: FontStyle.italic,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds == 0) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) {
      return '$s sec';
    } else if (s == 0) {
      return '$m min';
    } else {
      return '$m min $s sec';
    }
  }

  Widget _buildCallRow(BuildContext context, RecentCall call, CustomColors colors) {
    final bool isMissed = call.type == 'missed';
    
    // Determine icon based on type
    IconData iconData;
    Color iconColor;

    switch (call.type) {
      case 'incoming':
        iconData = Icons.call_received;
        iconColor = Colors.green;
        break;
      case 'outgoing':
        iconData = Icons.call_made;
        iconColor = colors.lightText.withAlpha(178);
        break;
      case 'missed':
        iconData = Icons.call_missed;
        iconColor = Colors.red;
        break;
      case 'rejected':
      case 'blocked':
        iconData = Icons.block;
        iconColor = Colors.redAccent;
        break;
      case 'voicemail':
        iconData = Icons.voicemail;
        iconColor = colors.accent;
        break;
      default:
        // generic call icon
        iconData = Icons.phone;
        iconColor = colors.lightText.withAlpha(178);
    }

    final displayName = call.name.isNotEmpty ? call.name : call.number;
    
    final callDate = DateTime.fromMillisecondsSinceEpoch(call.timestamp);
    final timeFormatted = DateFormat('h:mm a').format(callDate);
    final dateFormatted = DateFormat('MMM d').format(callDate);
    final durationFormatted = _formatDuration(call.duration);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          context.read<CallManager>().dial(
            call.number,
            contactName: call.name.isNotEmpty ? call.name : null,
          );
        },
        hoverColor: colors.accent.withAlpha(20),
        splashColor: colors.accent.withAlpha(30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              ContactAvatar(name: displayName, radius: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        color: isMissed
                            ? Colors.red 
                            : colors.lightText,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Icon(iconData, size: 14, color: iconColor),
                        const SizedBox(width: 6),
                        if (call.name.isNotEmpty) ...[
                          Text(
                            call.number,
                            style: TextStyle(color: colors.lightText.withAlpha(178), fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          '$dateFormatted at $timeFormatted',
                          style: TextStyle(color: colors.lightText.withAlpha(178), fontSize: 13),
                        ),
                        if (durationFormatted.isNotEmpty && !isMissed) ...[
                          const SizedBox(width: 8),
                          Text(
                            '•',
                            style: TextStyle(color: colors.lightText.withAlpha(100), fontSize: 13),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            durationFormatted,
                            style: TextStyle(color: colors.lightText.withAlpha(178), fontSize: 13),
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.call, color: colors.accent),
                onPressed: () {
                  context.read<CallManager>().dial(
                    call.number,
                    contactName: call.name.isNotEmpty ? call.name : null,
                  );
                },
                tooltip: 'Call again',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    final recentCallsManager = context.watch<RecentCallsManager>();
    
    final history = recentCallsManager.calls.where((call) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return call.name.toLowerCase().contains(q) || call.number.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          history.isEmpty
              ? (_searchQuery.isNotEmpty
                  ? Center(
                      child: Text(
                        'No matching calls found',
                        style: TextStyle(
                          color: colors.lightText.withAlpha(128),
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : _buildEmptyState(colors))
              : Padding(
                  padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 80.0, bottom: 8.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      itemCount: history.length,
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      separatorBuilder: (context, index) => Divider(
                        color: colors.background, // Divider color matching background to blend in
                        height: 1,
                        indent: 72,
                      ),
                      itemBuilder: (context, index) {
                        final call = history[index];
                        return _buildCallRow(context, call, colors);
                      },
                    ),
                  ),
                ),
          if (_isSearching)
            Positioned(
              top: 24,
              left: 24,
              right: 80, // Space for the search toggle icon
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: TextStyle(color: colors.lightText),
                  decoration: InputDecoration(
                    hintText: 'Search calls...',
                    hintStyle: TextStyle(color: colors.lightText.withAlpha(100)),
                    border: InputBorder.none,
                    icon: Icon(Icons.search, color: colors.lightText.withAlpha(150)),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 24,
            right: 24,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(_isSearching ? Icons.close : Icons.search, color: colors.lightText),
                    onPressed: () {
                      setState(() {
                        if (_isSearching) {
                          _isSearching = false;
                          _searchController.clear();
                          _searchQuery = '';
                        } else {
                          _isSearching = true;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
