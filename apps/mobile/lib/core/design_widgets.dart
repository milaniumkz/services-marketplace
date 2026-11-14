import 'package:flutter/material.dart';
import 'api.dart';
import 'design_icons.dart';
import 'l10n.dart';
import 'theme.dart';

const muted = Color(0xFF627187);

class JobaHomeHeadline extends StatelessWidget {
  const JobaHomeHeadline({super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '${localize(context, 'Хорошие мастера.')}\n'),
            TextSpan(
                text: localize(context, 'Ваши задачи.'),
                style: const TextStyle(color: primary))
          ]),
          style: const TextStyle(
              fontSize: 28,
              height: 1.25,
              letterSpacing: -.9,
              fontWeight: FontWeight.w700)));
}

class JobaBadge extends StatelessWidget {
  final String label;
  final Color background, foreground;
  const JobaBadge(this.label,
      {this.background = const Color(0xFFEAF0FC),
      this.foreground = primary,
      super.key});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: background, borderRadius: BorderRadius.circular(7)),
      child: UiText(label,
          style: TextStyle(
              color: foreground,
              fontSize: 10,
              height: 1.6,
              fontWeight: FontWeight.w700)));
}

class JobaMenuEntry {
  final String title, icon;
  final String? subtitle;
  final bool translateSubtitle;
  final double minHeight;
  final VoidCallback onTap;
  const JobaMenuEntry(this.title, this.icon, this.onTap,
      {this.subtitle, this.translateSubtitle = true, this.minHeight = 64});
}

class JobaMenu extends StatelessWidget {
  final List<JobaMenuEntry> entries;
  const JobaMenu(this.entries, {super.key});
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var index = 0; index < entries.length; index++) ...[
          if (index > 0) const Divider(height: 1),
          Material(
              color: Colors.white,
              child: InkWell(
                  onTap: entries[index].onTap,
                  child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: entries[index].minHeight),
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 12),
                          child: Row(children: [
                            JobaIcon(entries[index].icon, color: navy),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  UiText(entries[index].title,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.54,
                                          fontWeight: FontWeight.w700)),
                                  if (entries[index].subtitle != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                            entries[index].translateSubtitle
                                                ? localize(context,
                                                    entries[index].subtitle!)
                                                : entries[index].subtitle!,
                                            style: const TextStyle(
                                                fontSize: 11,
                                                color: muted,
                                                height: 1.55)))
                                ])),
                            const SizedBox(width: 8),
                            const JobaIcon('right', size: 18, color: navy)
                          ])))))
        ]
      ]));
}

class JobaAvatar extends StatelessWidget {
  final JobaApi api;
  final String name;
  final String? id;
  final double size;
  final Color backgroundColor, foregroundColor;
  final VoidCallback? onTap;
  const JobaAvatar(
      {required this.api,
      required this.name,
      this.id,
      this.size = 56,
      this.backgroundColor = const Color(0xFFDDE8F5),
      this.foregroundColor = const Color(0xFF3D6078),
      this.onTap,
      super.key});
  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty);
    final initials = words.take(2).map((s) => s.characters.first).join();
    final fallback = Center(
        child: Text(initials.isEmpty ? 'J' : initials.toUpperCase(),
            style: TextStyle(
                color: foregroundColor,
                fontSize: size * .32,
                fontWeight: FontWeight.w700)));
    return Semantics(
        label: name,
        button: onTap != null,
        child: ClipRRect(
            borderRadius: BorderRadius.circular(size * .3),
            child: Material(
                color: backgroundColor,
                child: InkWell(
                    onTap: onTap,
                    child: SizedBox(
                        width: size,
                        height: size,
                        child: id == null
                            ? fallback
                            : _AvatarPreview(
                                key: ValueKey('${api.sessionGeneration}:$id'),
                                api: api,
                                id: id!,
                                size: size,
                                fallback: fallback))))));
  }
}

class _AvatarPreview extends StatefulWidget {
  final JobaApi api;
  final String id;
  final double size;
  final Widget fallback;
  const _AvatarPreview(
      {required this.api,
      required this.id,
      required this.size,
      required this.fallback,
      super.key});
  @override
  State<_AvatarPreview> createState() => _AvatarPreviewState();
}

class _AvatarPreviewState extends State<_AvatarPreview> {
  late final Future<dynamic> preview;
  @override
  void initState() {
    super.initState();
    preview = widget.api.download(widget.id, variant: 'preview');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
      future: preview,
      builder: (context, snapshot) => snapshot.hasData
          ? Image.memory(snapshot.data,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              cacheWidth:
                  (widget.size * MediaQuery.devicePixelRatioOf(context)).ceil(),
              errorBuilder: (_, __, ___) => widget.fallback)
          : widget.fallback);
}

class JobaNavigation extends StatelessWidget {
  final String route;
  final bool executor;
  final ValueChanged<String> onSelect;
  final bool enabled;
  final int messageCount,notificationCount;
  const JobaNavigation(
      {required this.route,
      required this.executor,
      required this.onSelect,
      this.enabled = true,
      this.messageCount=0,this.notificationCount=0,
      super.key});
  @override
  Widget build(BuildContext context) => Container(
      decoration: const BoxDecoration(
          color: Colors.white, border: Border(top: BorderSide(color: line))),
      child: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                for (final item in [
                  ('home', 'Главная', 'home'),
                  (executor ? 'jobs' : 'catalog', 'Поиск', 'search'),
                  ('messages', 'Сообщения', 'chat'),
                  ('notifications', 'События', 'bell'),
                  ('account', 'Профиль', 'user')
                ])
                  Expanded(
                      child: Semantics(
                          selected: route == item.$1,
                          button: true,
                          child: InkWell(
                              onTap: enabled ? () => onSelect(item.$1) : null,
                              child: Padding(
                                  padding: const EdgeInsets.only(bottom: 11),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(height: 10),
                                        Badge(isLabelVisible:(item.$1=='messages'?messageCount:item.$1=='notifications'?notificationCount:0)>0,label:Text('${(item.$1=='messages'?messageCount:notificationCount)>99?'99+':item.$1=='messages'?messageCount:notificationCount}'),child:JobaIcon(item.$3,size:22,color:navy)),
                                        const SizedBox(height: 4),
                                        UiText(item.$2,
                                            style: TextStyle(
                                                fontSize: 9,
                                                height: 1.45,
                                                color: route == item.$1
                                                    ? primary
                                                    : const Color(0xFF68758A),
                                                fontWeight: route == item.$1
                                                    ? FontWeight.w700
                                                    : FontWeight.w400))
                                      ])))))
              ]))));
}

class JobaSection extends StatelessWidget {
  final String title, action;
  final VoidCallback onTap;
  const JobaSection(this.title, this.onTap, {this.action = 'Все', super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Row(children: [
        Expanded(
            child: UiText(title,
                style: const TextStyle(
                    fontSize: 19,
                    height: 1.4,
                    letterSpacing: -.4,
                    fontWeight: FontWeight.w700))),
        TextButton(
            style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                alignment: Alignment.centerRight),
            onPressed: onTap,
            child: UiText(action,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))
      ]));
}

class JobaUploadButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const JobaUploadButton(this.label, {required this.onPressed, super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: CustomPaint(
          foregroundPainter: const _UploadOutline(),
          child: Material(
              color: const Color(0xFFF6F9FF),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                  onTap: onPressed,
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 98),
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const JobaIcon('attach', size: 24),
                                const SizedBox(width: 12),
                                Flexible(
                                    child: UiText(label,
                                        style: TextStyle(
                                            color: onPressed == null
                                                ? muted
                                                : primary,
                                            fontSize: 14)))
                              ])))))));
}

class _UploadOutline extends CustomPainter {
  const _UploadOutline();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(14)));
    final paint = Paint()
      ..color = const Color(0xFFB9CBE9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 10) {
        canvas.drawPath(
            metric.extractPath(offset, (offset + 6).clamp(0, metric.length)),
            paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _UploadOutline oldDelegate) => false;
}
