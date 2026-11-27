import 'package:flutter/material.dart';
import '../core/l10n.dart';

class ProfileViews extends StatelessWidget {
  final int count;
  const ProfileViews({required this.count, super.key});
  @override
  Widget build(BuildContext context) => Tooltip(
      message: localize(context,
          'Уникальные зарегистрированные посетители. Ваши открытия и повторные просмотры не учитываются.'),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF667085)),
        const SizedBox(width: 6),
        Flexible(
            child: Text(
                localize(context, 'Просмотры анкеты: {count}')
                    .replaceAll('{count}', '$count'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF667085)))),
      ]));
}
