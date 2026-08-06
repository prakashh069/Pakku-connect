import 'package:flutter/material.dart';

class ContactAvatar extends StatelessWidget {
  final String name;
  final double radius;

  const ContactAvatar({
    super.key,
    required this.name,
    this.radius = 20.0,
  });

  String _getInitials(String contactName) {
    if (contactName.isEmpty) return '?';
    final parts = contactName.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    return '${parts[0].substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  Color _getColor(String contactName) {
    if (contactName.isEmpty) return Colors.grey;
    final int hash = contactName.codeUnits.fold(0, (prev, curr) => prev + curr);
    final List<Color> colors = [
      Colors.redAccent,
      Colors.pinkAccent,
      Colors.purpleAccent,
      Colors.deepPurpleAccent,
      Colors.indigoAccent,
      Colors.blueAccent,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.orangeAccent,
      Colors.deepOrangeAccent,
      Colors.blueGrey,
    ];
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _getColor(name).withValues(alpha: (0.2)),
      child: Text(
        _getInitials(name),
        style: TextStyle(
          color: _getColor(name),
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
