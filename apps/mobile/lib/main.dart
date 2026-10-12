import 'package:flutter/material.dart';

void main() => runApp(const MarketplaceDemo());

class MarketplaceDemo extends StatelessWidget {
  const MarketplaceDemo({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'JOBA',
        home: Scaffold(
          appBar: AppBar(title: const Text('JOBA · DEMO')),
          body: const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
                'RS / KZ / RU / BY\n\nЗаказчики ищут исполнителей. Исполнители ищут заказы по своим услугам.\n\nТехнический каркас: аккаунты, GPS, чат и оплаты не подключены.'),
          ),
        ),
      );
}
