import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../calling/services/call_manager.dart';
import '../../../core/constants/app_theme.dart';
import '../../../core/interfaces/device_transport.dart';
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
  bool _isSearching = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  DeviceTransport? _wsService;
  Timer? _timeoutTimer;
  final ScrollController _scrollController = ScrollController();
  
  // A-Z indexing map: letter -> GlobalKey (for scrolling)
  final Map<String, GlobalKey> _letterKeys = {};
  
  @override
  void initState() {
    super.initState();
    _initLetterKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wsService = context.read<DeviceTransport>();
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
    _searchFocus.dispose();
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

  

  Widget _buildFavoritesSection(CustomColors colors, FavoritesService favService) {
    final favorites = _filtered.where((c) => favService.isFavorite(c.id)).toList();
    if (favorites.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final c = favorites[index];
              return Container(
                width: 130,
                margin: const EdgeInsets.only(right: 12.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.accent.withAlpha(150), colors.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(30),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      if (c.phones.isNotEmpty) {
                        context.read<CallManager>().dial(c.phones.first.number, contactName: c.displayName);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          ContactAvatar(name: c.displayName, radius: 30),
                          const Spacer(),
                          Text(
                            c.displayName,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildProfileAndGroupsPills(CustomColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          _buildPillButton(Icons.person, 'My profile', colors),
          const SizedBox(height: 16),
          _buildPillButton(Icons.people, 'Groups', colors),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPillButton(IconData icon, String title, CustomColors colors) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: colors.accent.withAlpha(50),
                  radius: 20,
                  child: Icon(icon, color: colors.accent, size: 20),
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(color: colors.lightText, fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactRow(RemoteContact c, CustomColors colors, FavoritesService favService, {bool isLast = false}) {
    final isFav = favService.isFavorite(c.id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
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
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 72.0, right: 16.0),
            child: Divider(height: 1, thickness: 1, color: colors.lightText.withAlpha(20)),
          ),
      ],
    );
  }

  Widget _buildStickyHeaderList(Map<String, List<RemoteContact>> grouped, CustomColors colors, FavoritesService favService) {
    final letters = ['#', ...List.generate(26, (i) => String.fromCharCode(65 + i))];
    
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverToBoxAdapter(child: const SizedBox(height: 80)), // Space for floating pill
        SliverToBoxAdapter(child: _buildFavoritesSection(colors, favService)),
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(groupContacts.length, (index) {
                        final isLast = index == groupContacts.length - 1;
                        return _buildContactRow(groupContacts[index], colors, favService, isLast: isLast);
                      }),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
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
      body: Stack(
        children: [
          Row(
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
                    : _buildStickyHeaderList(grouped, colors, favService),
              ),
              if (_filtered.isNotEmpty) _buildAlphabetIndex(grouped, colors),
            ],
          ),
          if (_isSearching)
            Positioned(
              top: 24,
              left: 24,
              right: 180, // Give space for the floating actions
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
                  controller: _search,
                  focusNode: _searchFocus,
                  style: TextStyle(color: colors.lightText),
                  decoration: InputDecoration(
                    hintText: 'Search contacts...',
                    hintStyle: TextStyle(color: colors.lightText.withAlpha(100)),
                    border: InputBorder.none,
                    icon: Icon(Icons.search, color: colors.lightText.withAlpha(150)),
                  ),
                  onChanged: _filter,
                ),
              ),
            ),
          Positioned(
            top: 24,
            right: 48,
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
                        _isSearching = !_isSearching;
                        if (!_isSearching) {
                          _search.clear();
                          _filter('');
                          _searchFocus.unfocus();
                        }
                      });
                      if (_isSearching) {
                        _searchFocus.requestFocus();
                      }
                    },
                    tooltip: 'Search',
                  ),
                  IconButton(
                    icon: _loading 
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: colors.lightText, strokeWidth: 2)) 
                        : Icon(Icons.sync, color: colors.lightText),
                    onPressed: _loading ? null : _requestContactsWithTimeout,
                    tooltip: 'Sync Contacts',
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
      color: colors.background,
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      alignment: Alignment.centerLeft,
      child: Text(
        letter,
        style: TextStyle(
          color: colors.lightText.withAlpha(150),
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) => 
      letter != oldDelegate.letter || colors != oldDelegate.colors;
}
