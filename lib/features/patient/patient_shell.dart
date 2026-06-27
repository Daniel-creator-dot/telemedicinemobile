import 'package:flutter/material.dart';
import 'dashboard_view.dart';
import 'appointments_view.dart';
import 'messages_view.dart';
import 'profile_view.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  void _switchTab(int index) {
    if (index < 0 || index > 3) return;
    setState(() => _currentIndex = index);
  }

  Widget _screenFor(int index) {
    switch (index) {
      case 0:
        return DashboardView(onSwitchTab: _switchTab);
      case 1:
        return const AppointmentsView();
      case 2:
        return const MessagesView();
      case 3:
        return const ProfileView();
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: KeyedSubtree(
            key: ValueKey(_currentIndex),
            child: _screenFor(_currentIndex),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(4, (index) {
                const icons = [
                  Icons.grid_view_rounded,
                  Icons.calendar_month_rounded,
                  Icons.chat_bubble_outline_rounded,
                  Icons.person_outline_rounded,
                ];
                const activeIcons = [
                  Icons.grid_view_rounded,
                  Icons.calendar_month_rounded,
                  Icons.chat_bubble_rounded,
                  Icons.person_rounded,
                ];
                const labels = ['Overview', 'Schedule', 'Chats', 'Profile'];
                final isActive = _currentIndex == index;
                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? theme.colorScheme.primary.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? activeIcons[index] : icons[index],
                          color: isActive ? theme.colorScheme.primary : const Color(0xFF64748B),
                          size: 22,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          labels[index],
                          style: TextStyle(
                            color: isActive ? theme.colorScheme.primary : const Color(0xFF64748B),
                            fontSize: 10,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
