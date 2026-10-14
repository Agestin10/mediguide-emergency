// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:mediguide_emergency/main.dart';

void main() {
  testWidgets('MediGuide app loads successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MediGuideApp());

    expect(find.text('MediGuide AI'), findsWidgets);
    expect(find.text('Emergency Assistance System'), findsOneWidget);
  });

  test('findAvailableAmbulanceInList picks the first available ambulance', () {
    final ambulances = [
      {'ambulance_id': 'A-101', 'status': 'Busy'},
      {'ambulance_id': 'A-202', 'status': 'Available'},
      {'ambulance_id': 'A-303', 'status': 'Available'},
    ];

    final selected = EmergencyRequestScreen.findAvailableAmbulanceInList(
      ambulances,
    );

    expect(selected, isNotNull);
    expect(selected!['ambulance_id'], 'A-202');
  });

  test(
    'findAvailableAmbulanceInList returns null when no ambulance is available',
    () {
      final ambulances = [
        {'ambulance_id': 'A-101', 'status': 'Busy'},
        {'ambulance_id': 'A-202', 'status': 'On Route'},
      ];

      final selected = EmergencyRequestScreen.findAvailableAmbulanceInList(
        ambulances,
      );

      expect(selected, isNull);
    },
  );
}
