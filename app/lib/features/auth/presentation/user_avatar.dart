import 'package:flutter/material.dart';

import '../domain/profile.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.profile, this.radius = 18});

  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = profile.avatarUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: url != null ? NetworkImage(url) : null,
      child: Text(profile.iniciales,
          style: TextStyle(color: scheme.onPrimaryContainer, fontSize: radius * 0.8)),
    );
  }
}
