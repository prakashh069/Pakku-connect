import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../calling/services/call_manager.dart';
import '../../../core/constants/app_theme.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  List<Contact> _all = [];
  List<Contact> _filtered = [];
  bool _loading = true;
  bool _denied = false;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      setState(() {
        _loading = false;
        _denied = true;
      });
      return;
    }
    setState(() {
      _loading = true;
      _denied = false;
    });
    _all = await FlutterContacts.getContacts(withProperties: true);
    _filtered = List.from(_all);
    setState(() => _loading = false);
  }

  void _filter(String q) {
    setState(() {
      _filtered = _all.where((c) {
        final name = c.displayName.toLowerCase();
        final phones = c.phones.map((p) => p.number).join(' ');
        return name.contains(q.toLowerCase()) || phones.contains(q);
      }).toList();
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
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.accent))
          : _denied
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Contacts permission denied',
                          style: TextStyle(color: colors.danger)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                      const TextButton(
                        onPressed: openAppSettings,
                        child: Text('Open Settings'),
                      ),
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
                          context.read<CallManager>().dial(c.phones.first.number);
                        }
                      },
                    );
                  },
                ),
    );
  }
}
