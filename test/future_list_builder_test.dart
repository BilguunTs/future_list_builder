import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:future_list_builder/future_list_builder.dart';

void main() {
  group('FutureListBuilder Tests', () {
    testWidgets('should display loading indicator initially', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FutureListBuilder<String>(
              useFixedFetcher: true,
              fixedFutureList: () async {
                await Future.delayed(Duration(seconds: 1));
                return ['Item 1', 'Item 2'];
              },
              itemBuilder: (context, item, index) => Text(item),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('should display items after loading', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FutureListBuilder<String>(
              useFixedFetcher: true,
              fixedFutureList: () async => ['Item 1', 'Item 2'],
              itemBuilder: (context, item, index) => Text(item),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
    });
  });
}
