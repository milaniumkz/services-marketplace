import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/widgets.dart';

/// Read-only browse flow. No credentials, location permission or account data.
class GuestCatalog extends StatefulWidget {
  const GuestCatalog({
    super.key,
    required this.api,
    required this.country,
    required this.onSignIn,
  });

  final JobaApi api;
  final String country;
  final VoidCallback onSignIn;

  @override
  State<GuestCatalog> createState() => _GuestCatalogState();
}

class _GuestCatalogState extends State<GuestCatalog> {
  final search = TextEditingController();
  final cursors = <String?>[null];
  String query = '';

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void submit(String value) {
    setState(() {
      query = value.trim();
      cursors
        ..clear()
        ..add(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cursor = cursors.last;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: search,
            maxLength: 100,
            textInputAction: TextInputAction.search,
            onSubmitted: submit,
            decoration: InputDecoration(
              labelText: 'Поиск услуг',
              counterText: '',
              suffixIcon: IconButton(
                tooltip: 'Найти',
                icon: const Icon(Icons.search),
                onPressed: () => submit(search.text),
              ),
            ),
          ),
        ),
        Expanded(
          child: ApiView(
            key: ValueKey((widget.country, query, cursor)),
            load: () => widget.api.request(
              '/public/contractors',
              authenticated: false,
              query: {
                'country': widget.country,
                if (query.isNotEmpty) 'q': query,
                if (cursor != null) 'after': cursor,
              },
            ),
            builder: (context, data, reload) {
              final records = (data['items'] as List).cast<Json>();
              final next = data['next_cursor'] as String?;
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (records.isEmpty) const Text('Подходящих услуг пока нет.'),
                  for (final item in records)
                    Card(
                      child: ExpansionTile(
                        title: Text('${item['title'] ?? 'Услуга'}'),
                        subtitle: Text('${item['city'] ?? ''}'),
                        childrenPadding: const EdgeInsets.all(16),
                        children: [Text('${item['description'] ?? ''}')],
                      ),
                    ),
                  if (cursors.length > 1)
                    TextButton(
                      onPressed: () => setState(cursors.removeLast),
                      child: const Text('Предыдущая страница'),
                    ),
                  if (next != null)
                    TextButton(
                      onPressed: () => setState(() => cursors.add(next)),
                      child: const Text('Следующая страница'),
                    ),
                ],
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: widget.onSignIn,
              child: const Text('Войти или создать аккаунт'),
            ),
          ),
        ),
      ],
    );
  }
}
