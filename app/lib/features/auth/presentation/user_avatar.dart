import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/profile.dart';
import 'auth_providers.dart';

class UserAvatar extends ConsumerWidget {
  const UserAvatar({super.key, required this.profile, this.radius = 18});

  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final path = profile.avatarPath;
    final url = path != null ? ref.watch(profileRepositoryProvider).urlFoto(path) : profile.avatarUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: url != null ? NetworkImage(url) : null,
      // Si la imagen no carga quedan las iniciales.
      onForegroundImageError: url != null ? (_, _) {} : null,
      child: Text(profile.iniciales,
          style: TextStyle(color: scheme.onPrimaryContainer, fontSize: radius * 0.8)),
    );
  }
}
