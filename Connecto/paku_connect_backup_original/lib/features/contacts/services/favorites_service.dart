import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService extends ChangeNotifier {
  static const String _favoritesKey = 'favorite_contact_ids';
  Set<String> _favoriteIds = {};
  bool _isInitialized = false;

  FavoritesService() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_favoritesKey) ?? [];
    _favoriteIds = list.toSet();
    _isInitialized = true;
    notifyListeners();
  }

  bool get isInitialized => _isInitialized;

  bool isFavorite(String contactId) {
    return _favoriteIds.contains(contactId);
  }

  Future<void> toggleFavorite(String contactId) async {
    if (_favoriteIds.contains(contactId)) {
      _favoriteIds.remove(contactId);
    } else {
      _favoriteIds.add(contactId);
    }
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favoriteIds.toList());
  }
}
