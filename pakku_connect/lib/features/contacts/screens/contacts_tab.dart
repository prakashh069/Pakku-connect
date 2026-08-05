import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../calling/services/call_manager.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/models/contact.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  List<RemoteContact> _all = [];
  List<RemoteContact> _filtered = [];
  bool _loading = true;
  bool _hasError = false;
  final _search = TextEditingController();
  WebSocketService? _wsService;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wsService = context.read<WebSocketService>();
      _wsService?.onContactsReceived = _onContactsReceived;
      _requestContactsWithTimeout();
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    if (_wsService?.onContactsReceived == _onContactsReceived) {
      _wsService?.onContactsReceived = null;
    }
    _search.dispose();
    super.dispose();
  }

  void _requestContactsWithTimeout() {
    _timeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _hasError = false;
      });
    }
    _wsService?.requestContacts();
    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
          _hasError = true;
        });
      }
    });
  }

  void _onContactsReceived(List<RemoteContact> contacts) {
    _timeoutTimer?.cancel();
    if (mounted) {
      setState(() {
        _all = contacts;
        _filter(_search.text);
        _loading = false;
        _hasError = false;
      });
    }
  }

  void _filter(String q) {
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(_all);
      } else {
        _filtered = _all.where((c) {
          final name = c.displayName.toLowerCase();
          final phones = c.phones.map((p) => p.number).join(' ');
          return name.contains(q.toLowerCase()) || phones.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: TextField(
          controller: _search,
          onChanged: _filter,
          style: TextStyle(color: colors.lightText),
          decoration: InputDecoration(
            hintText: 'Search contacts...',
            hintStyle: TextStyle(color: colors.lightText.withAlpha(128)),
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colors.lightText),
            onPressed: _requestContactsWithTimeout,
          )
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _hasError
                            ? 'Failed to load contacts from Android'
                            : 'No contacts found',
                        style: TextStyle(color: colors.lightText),
                      ),
                      if (_hasError) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _requestContactsWithTimeout,
                          icon: Icon(Icons.refresh, color: colors.accent),
                          label: Text('Retry',
                              style: TextStyle(color: colors.accent)),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (context, i) {
                    final c = _filtered[i];
                    return ListTile(
                      leading: Icon(Icons.person, color: colors.accent),
                      title: Text(c.displayName,
                          style: TextStyle(color: colors.lightText)),
                      subtitle: c.phones.isNotEmpty
                          ? Text(c.phones.first.number,
                              style: TextStyle(
                                  color: colors.lightText.withAlpha(178)))
                          : null,
                      onTap: () {
                        if (c.phones.isNotEmpty) {
                          context.read<CallManager>().dial(
                            c.phones.first.number,
                            contactName: c.displayName,
                          );
                        }
                      },
                    );
                  },
                ),
    );
  }
}

