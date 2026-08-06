import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calling/services/call_manager.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/services/websocket_service.dart';
import '../../../core/models/contact.dart';
import '../../../shared/widgets/contact_avatar.dart';
import '../services/favorites_service.dart';

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
  final ScrollController _scrollController = ScrollController();
  
  // A-Z indexing map: letter -> GlobalKey (for scrolling)
  final Map<String, GlobalKey> _letterKeys = {};
  
  @override
  void initState() {
    super.initState();
    _initLetterKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wsService = context.read<WebSocketService>();
      _wsService?.onContactsReceived = _onContactsReceived;
      _requestContactsWithTimeout();
    });
  }

  void _initLetterKeys() {
    for (int i = 0; i < 26; i++) {
      final letter = String.fromCharCode(65 + i);
      _letterKeys[letter] = GlobalKey();
    }
    _letterKeys['#'] = GlobalKey();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    if (_wsService?.onContactsReceived == _onContactsReceived) {
      _wsService?.onContactsReceived = null;
    }
    _search.dispose();
    _scrollController.dispose();
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
      
      // Sort contacts alphabetically
      _filtered.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    });
  }

  void _scrollToLetter(String letter) {
    final key = _letterKeys[letter];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Map<String, List<RemoteContact>> _groupContacts(List<RemoteContact> contacts) {
    final Map<String, List<RemoteContact>> groups = {};
    for (final c in contacts) {
      String initial = c.displayName.trim().isNotEmpty 
          ? c.displayName.trim().substring(0, 1).toUpperCase() 
          : '#';
      if (!RegExp(r'[A-Z]').hasMatch(initial)) {
        initial = '#';
      }
      if (!groups.containsKey(initial)) {
        groups[initial] = [];
      }
      groups[initial]!.add(c);
    }
    return groups;
  }

  Widget _buildSearchBar(CustomColors colors) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: colors.background.withAlpha(100),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.surface),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(Icons.search, color: colors.lightText.withAlpha(128), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: _filter,
                      style: TextStyle(color: colors.lightText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        hintStyle: TextStyle(color: colors.lightText.withAlpha(128), fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_search.text.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.close, color: colors.lightText.withAlpha(128), size: 16),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        _search.clear();
                        _filter('');
                      },
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: _loading ? null : _requestContactsWithTimeout,
            icon: Icon(Icons.sync, color: colors.accent, size: 18),
            label: Text('Sync Contacts', style: TextStyle(color: colors.accent, fontSize: 14)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: colors.accent.withAlpha(20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesSection(CustomColors colors, FavoritesService favService) {
    final favorites = _filtered.where((c) => favService.isFavorite(c.id)).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text('Favorites', style: TextStyle(color: colors.lightText, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        if (favorites.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Text('No favorites yet. Tap ⭐ to add favorites.', 
              style: TextStyle(color: colors.lightText.withAlpha(128), fontStyle: FontStyle.italic)),
          )
        else
          ...favorites.map((c) => _buildContactRow(c, colors, favService)),
        const Divider(height: 32),
      ],
    );
  }

  Widget _buildRecentCallsSection(CustomColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text('Recent Calls', style: TextStyle(color: colors.lightText, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Text('Coming Soon.\nRecent Calls will appear here.', 
            style: TextStyle(color: colors.lightText.withAlpha(128), fontStyle: FontStyle.italic)),
        ),
        const Divider(height: 32),
      ],
    );
  }

  Widget _buildContactRow(RemoteContact c, CustomColors colors, FavoritesService favService) {
    final isFav = favService.isFavorite(c.id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (c.phones.isNotEmpty) {
            context.read<CallManager>().dial(
              c.phones.first.number,
              contactName: c.displayName,
            );
          }
        },
        hoverColor: colors.accent.withAlpha(20),
        splashColor: colors.accent.withAlpha(30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              ContactAvatar(name: c.displayName, radius: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.displayName, style: TextStyle(color: colors.lightText, fontSize: 15, fontWeight: FontWeight.w500)),
                    if (c.phones.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(c.phones.first.number, style: TextStyle(color: colors.lightText.withAlpha(178), fontSize: 13)),
                    ]
                  ],
                ),
              ),
              IconButton(
                icon: Icon(isFav ? Icons.star : Icons.star_border, 
                  color: isFav ? Colors.amber : colors.lightText.withAlpha(100),
                  size: 20,
                ),
                onPressed: () => favService.toggleFavorite(c.id),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStickyHeaderList(Map<String, List<RemoteContact>> grouped, CustomColors colors, FavoritesService favService) {
    final letters = ['#', ...List.generate(26, (i) => String.fromCharCode(65 + i))];
    
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: _buildSearchBar(colors)),
        SliverToBoxAdapter(child: _buildFavoritesSection(colors, favService)),
        SliverToBoxAdapter(child: _buildRecentCallsSection(colors)),
        ...letters.where((letter) => grouped.containsKey(letter)).map((letter) {
          final groupContacts = grouped[letter]!;
          return SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyHeaderDelegate(
                  letter: letter,
                  key: _letterKeys[letter]!,
                  colors: colors,
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildContactRow(groupContacts[index], colors, favService),
                  childCount: groupContacts.length,
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildAlphabetIndex(Map<String, List<RemoteContact>> grouped, CustomColors colors) {
    final letters = ['#', ...List.generate(26, (i) => String.fromCharCode(65 + i))];
    
    return SizedBox(
      width: 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: letters.map((letter) {
          final hasContacts = grouped.containsKey(letter);
          return Expanded(
            child: GestureDetector(
              onTap: hasContacts ? () => _scrollToLetter(letter) : null,
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: hasContacts ? FontWeight.bold : FontWeight.normal,
                    color: hasContacts ? colors.accent : colors.lightText.withAlpha(60),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<CustomColors>()!;
    final favService = context.watch<FavoritesService>();

    if (_loading && _all.isEmpty) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('Contacts')),
        body: Center(child: CircularProgressIndicator(color: colors.accent)),
      );
    }

    final grouped = _groupContacts(_filtered);

    return Scaffold(
      backgroundColor: colors.background,
      body: Row(
        children: [
          Expanded(
            child: _filtered.isEmpty && _search.text.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _hasError ? 'Failed to load contacts from Android' : 'No contacts found',
                          style: TextStyle(color: colors.lightText),
                        ),
                        if (_hasError) ...[
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _requestContactsWithTimeout,
                            icon: Icon(Icons.sync, color: colors.accent),
                            label: Text('Retry', style: TextStyle(color: colors.accent)),
                          ),
                        ],
                      ],
                    ),
                  )
                : RawScrollbar(
                    controller: _scrollController,
                    thickness: 4,
                    thumbColor: colors.lightText.withAlpha(50),
                    radius: const Radius.circular(2),
                    child: _buildStickyHeaderList(grouped, colors, favService),
                  ),
          ),
          if (_filtered.isNotEmpty) _buildAlphabetIndex(grouped, colors),
        ],
      ),
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String letter;
  final GlobalKey key;
  final CustomColors colors;

  _StickyHeaderDelegate({required this.letter, required this.key, required this.colors});

  @override
  double get minExtent => 30.0;

  @override
  double get maxExtent => 30.0;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      key: key,
      color: colors.background.withAlpha(240),
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      alignment: Alignment.centerLeft,
      child: Text(
        letter,
        style: TextStyle(
          color: colors.accent,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) => letter != oldDelegate.letter;
}
