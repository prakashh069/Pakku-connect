class RemotePhone {
  final String label;
  final String number;

  RemotePhone({required this.label, required this.number});

  factory RemotePhone.fromJson(Map<String, dynamic> json) {
    return RemotePhone(
      label: json['label'] as String? ?? '',
      number: json['number'] as String? ?? '',
    );
  }
}

class RemoteContact {
  final String id;
  final String displayName;
  final List<RemotePhone> phones;

  RemoteContact({
    required this.id,
    required this.displayName,
    required this.phones,
  });

  factory RemoteContact.fromJson(Map<String, dynamic> json) {
    var phonesList = json['phones'] as List?;
    List<RemotePhone> parsedPhones = [];
    if (phonesList != null) {
      parsedPhones = phonesList
          .map((e) => RemotePhone.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return RemoteContact(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      phones: parsedPhones,
    );
  }
}
