import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/notification_service.dart';
import '../../core/url_helper.dart';
import '../../models/appointment.dart';
import 'appointment_utils.dart';
import 'book_appointment_dialog.dart';
import 'appointments_repository.dart';
import 'paystack_checkout_screen.dart';
// ==================== APPOINTMENTS VIEW ====================
class AppointmentsView extends StatefulWidget {
  const AppointmentsView({super.key});

  @override
  State<AppointmentsView> createState() => _AppointmentsViewState();
}

class _AppointmentsViewState extends State<AppointmentsView> {
  int _activeTab = 0; // 0: Upcoming, 1: Past, 2: Calendar
  DateTime _calendarMonth = DateTime.now();
  List<Appointment> _appointments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAppointments();
  }

  Future<void> _fetchAppointments() async {
    setState(() => _loading = true);
    try {
      final repo = context.read<AppointmentsRepository>();
      final list = await repo.getMyAppointments();
      
      // Schedule notifications for telemedicine appointments
      final notificationService = NotificationService();
      await notificationService.scheduleAppointmentReminders(list);
      
      setState(() {
        _appointments = list;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load appointments: $e')),
        );
      }
    }
  }

  void _bookAppointment() {
    showDialog(
      context: context,
      builder: (context) => const BookAppointmentDialog(),
    ).then((val) {
      if (val != null) {
        _fetchAppointments();
      }
    });
  }

  Future<void> _payCopay(Appointment apt) async {
    final repo = context.read<AppointmentsRepository>();
    try {
      final init = await repo.initializePaystackPayment(apt.id);
      if (init['mock'] == true) {
        await repo.payForAppointment(apt.id);
      } else {
        final url = init['authorization_url']?.toString();
        final reference = init['reference']?.toString();
        if (url == null || reference == null) {
          throw Exception('Invalid payment response from server');
        }
        if (!mounted) return;
        final returnedRef = await PaystackCheckoutScreen.open(
          context,
          authorizationUrl: url,
          reference: reference,
        );
        if (returnedRef == null) return;
        await repo.verifyPaystackPayment(apt.id, returnedRef);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment approved! Your meeting link is ready.')),
      );
      _fetchAppointments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
    }
  }

  // Helper: get the set of date strings ('yyyy-MM-dd') that have appointments in the current month
  Set<String> _appointmentDatesInMonth(DateTime month) {
    final result = <String>{};
    for (final apt in _appointments) {
      try {
        // preferredDate may be 'YYYY-MM-DD' or 'Month DD, YYYY'
        DateTime? d = parseAppointmentDate(apt.preferredDate);
        if (d != null && d.year == month.year && d.month == month.month) {
          result.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
        }
      } catch (_) {}
    }
    return result;
  }

  List<Appointment> _appointmentsForDay(DateTime day) {
    final key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _appointments.where((apt) {
      final d = parseAppointmentDate(apt.preferredDate);
      if (d == null) return false;
      final dKey = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return dKey == key;
    }).toList();
  }

  void _showDayAppointments(BuildContext context, DateTime day, List<Appointment> apts) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '${monthName(day.month)} ${day.day}, ${day.year}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            ...apts.map((apt) {
              Color sc;
              switch (apt.status) {
                case 'approved': sc = const Color(0xFF22C55E); break;
                case 'completed': sc = const Color(0xFF00D2C4); break;
                case 'cancelled': sc = Colors.redAccent; break;
                default: sc = const Color(0xFFFBBF24);
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      apt.isTelemedicine ? Icons.videocam_rounded : Icons.local_hospital_rounded,
                      color: theme.colorScheme.primary, size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(apt.doctorName ?? 'Consultation', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(apt.preferredTime, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: sc.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(apt.status.toUpperCase(), style: TextStyle(color: sc, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarTab(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final month = _calendarMonth;
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // weekday: 1=Mon ... 7=Sun. We want Sun=0 offset
    int startOffset = firstDay.weekday % 7; // Sun=0, Mon=1 ... Sat=6
    final aptDates = _appointmentDatesInMonth(month);
    final dayLabels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

    return Column(
      children: [
        // Month navigation header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () => setState(() {
                _calendarMonth = DateTime(month.year, month.month - 1);
              }),
              icon: const Icon(Icons.chevron_left_rounded, color: Colors.white54),
            ),
            Text(
              '${monthName(month.month)} ${month.year}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: () => setState(() {
                _calendarMonth = DateTime(month.year, month.month + 1);
              }),
              icon: const Icon(Icons.chevron_right_rounded, color: Colors.white54),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Day of week headers
        Row(
          children: dayLabels.map((label) => Expanded(
            child: Center(
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 8),
        // Calendar grid
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1,
          ),
          itemCount: startOffset + daysInMonth,
          itemBuilder: (ctx, i) {
            if (i < startOffset) return const SizedBox();
            final day = i - startOffset + 1;
            final date = DateTime(month.year, month.month, day);
            final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            final hasApt = aptDates.contains(key);
            final isToday = date.year == now.year && date.month == now.month && date.day == now.day;

            return GestureDetector(
              onTap: hasApt ? () {
                _showDayAppointments(context, date, _appointmentsForDay(date));
              } : null,
              child: Container(
                decoration: BoxDecoration(
                  color: isToday
                      ? theme.colorScheme.primary.withOpacity(0.18)
                      : hasApt
                          ? theme.colorScheme.secondary.withOpacity(0.15)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: isToday
                      ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                      : hasApt
                          ? Border.all(color: theme.colorScheme.secondary.withOpacity(0.4), width: 1)
                          : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      '$day',
                      style: TextStyle(
                        color: isToday
                            ? theme.colorScheme.primary
                            : hasApt
                                ? const Color(0xFFC084FC)
                                : const Color(0xFF94A3B8),
                        fontWeight: (isToday || hasApt) ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    if (hasApt)
                      Positioned(
                        bottom: 3,
                        child: Container(
                          width: 4, height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _calLegend(theme.colorScheme.primary, 'Today'),
            const SizedBox(width: 20),
            _calLegend(theme.colorScheme.secondary, 'Has Appointment'),
          ],
        ),
        const SizedBox(height: 16),
        if (aptDates.isEmpty)
          const Text('No appointments this month.', style: TextStyle(color: Colors.white24, fontSize: 13))
        else
          Text(
            'Tap a purple day to see details',
            style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 11),
          ),
      ],
    );
  }

  Widget _calLegend(Color color, String label) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = _appointments.where((a) => a.status == 'pending' || a.status == 'approved').toList()
      ..sort((a, b) => compareAppointmentDates(a.preferredDate, b.preferredDate));
    final past = _appointments.where((a) => a.status == 'completed' || a.status == 'cancelled').toList()
      ..sort((a, b) => compareAppointmentDates(a.preferredDate, b.preferredDate, descending: true));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Schedule Planner',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontSize: 26,
                  letterSpacing: -0.5,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle, color: Color(0xFF00D2C4), size: 28),
                onPressed: _bookAppointment,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Manage your clinical checkups and teleconsultations',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),

          // 3-Tab Selector
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _tabButton(context, 0, 'Upcoming (${upcoming.length})'),
                _tabButton(context, 1, 'History (${past.length})'),
                _tabButton(context, 2, 'Calendar'),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2C4)))
                : _activeTab == 2
                    ? SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: _buildCalendarTab(context),
                      )
                    : (() {
                        final activeList = _activeTab == 0 ? upcoming : past;
                        return activeList.isEmpty
                            ? Center(
                                child: Text(
                                  _activeTab == 0
                                      ? 'No upcoming consultations booked.'
                                      : 'No consultation logs found.',
                                  style: const TextStyle(color: Colors.white24, fontSize: 13),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _fetchAppointments,
                                color: theme.colorScheme.primary,
                                child: ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                  itemCount: activeList.length,
                                  itemBuilder: (context, index) {
                                    final apt = activeList[index];
                                    return _buildAppointmentItem(context, apt);
                                  },
                                ),
                              );
                      })(),
          )
        ],
      ),
    );
  }

  Widget _tabButton(BuildContext context, int index, String label) {
    final theme = Theme.of(context);
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? theme.colorScheme.primary.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isActive ? theme.colorScheme.primary : const Color(0xFF64748B),
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppointmentItem(BuildContext context, Appointment apt) {
    final isUnpaid = apt.paymentStatus == 'unpaid';

    Color statusColor;
    switch (apt.status) {
      case 'approved':
        statusColor = const Color(0xFF22C55E);
        break;
      case 'completed':
        statusColor = const Color(0xFF00D2C4);
        break;
      case 'cancelled':
        statusColor = Colors.redAccent;
        break;
      case 'pending':
      default:
        statusColor = const Color(0xFFFBBF24);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.03),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                apt.doctorName ?? 'General Practitioner',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  apt.status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 4),
          Text(
            apt.fullName,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Text(
                apt.preferredDate,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(width: 15),
              const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Text(
                apt.preferredTime,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
          
          if (apt.status == 'approved' && apt.isTelemedicine) ...[
            const SizedBox(height: 15),
            if (isUnpaid)
              ElevatedButton.icon(
                onPressed: () => _payCopay(apt),
                icon: const Icon(Icons.payment, size: 16),
                label: const Text('Pay Visit Copay (GHS 50.00)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D2C4),
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )
            else if (apt.meetingLink != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: () => launchExternalUrl(apt.meetingLink!, context: context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.videocam, color: Color(0xFFC084FC), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Secure Link: ${apt.meetingLink}',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                          const Icon(Icons.open_in_new_rounded, color: Color(0xFFC084FC), size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => launchExternalUrl(apt.meetingLink!, context: context),
                    icon: const Icon(Icons.videocam, size: 16),
                    label: const Text('Join Video Room'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              )
          ]
        ],
      ),
    );
  }
}
