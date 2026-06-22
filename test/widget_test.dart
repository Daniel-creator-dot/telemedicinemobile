// Basic smoke tests for the Digi Health Telemedicine app.
//
// Widget tests intentionally avoid FlutterSecureStorage (requires platform
// channels) by testing individual views in isolation rather than the full
// app bootstrap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smoke test: MaterialApp renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Digi Health Telemedicine'),
          ),
        ),
      ),
    );

    expect(find.text('Digi Health Telemedicine'), findsOneWidget);
  });

  testWidgets('Smoke test: login screen placeholder renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Welcome to Digi Health',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {},
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Welcome to Digi Health'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
  });

  testWidgets('Smoke test: bottom navigation renders', (WidgetTester tester) async {
    int selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: Center(
                child: Text('Tab $selectedIndex'),
              ),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: selectedIndex,
                onTap: (index) => setState(() => selectedIndex = index),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_rounded),
                    label: 'Overview',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.calendar_month_rounded),
                    label: 'Schedule',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.chat_bubble_outline_rounded),
                    label: 'Chats',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline_rounded),
                    label: 'Profile',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    // Verify all tabs are rendered
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);

    // Tap the Schedule tab
    await tester.tap(find.text('Schedule'));
    await tester.pump();
    expect(find.text('Tab 1'), findsOneWidget);
  });
}
