import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'care_repository.dart';
import 'pay_visit.dart';

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  Map<String, dynamic>? _current;
  List<Map<String, dynamic>> _plans = [];
  bool _yearly = true;
  bool _loading = true;
  String? _error;
  String? _payingTier;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<CareRepository>().membershipMe();
      if (!mounted) return;
      setState(() {
        _current = data['current'] is Map ? Map<String, dynamic>.from(data['current'] as Map) : null;
        _plans = ((data['plans'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load memberships.';
        _loading = false;
      });
    }
  }

  Future<void> _subscribe(Map<String, dynamic> plan) async {
    final tier = plan['tier']?.toString() ?? '';
    final period = _yearly ? 'yearly' : 'monthly';
    setState(() => _payingTier = tier);
    final care = context.read<CareRepository>();
    final result = await completePaystackFlow(
      context,
      initialize: () => care.initializeMembership(tier: tier, period: period),
      verify: (ref) async {
        await care.activateMembership(tier: tier, period: period, reference: ref);
      },
      successFallback: '${plan['name']} is now active.',
    );
    if (!mounted) return;
    setState(() => _payingTier = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: digiPaper,
      appBar: AppBar(
        title: Text('Membership', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
        backgroundColor: digiPaper,
        foregroundColor: digiInk,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: digiForest))
          : _error != null
              ? ClinicalErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    Text(
                      'Care that stays with the house',
                      style: GoogleFonts.sourceSerif4(fontSize: 30, fontWeight: FontWeight.w600, height: 1.15, color: digiInk),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Four memberships. Same Paystack checkout as Bytz Go — MoMo, card, or bank. Yearly is ten months; two are with the house.',
                      style: GoogleFonts.dmSans(color: digiSlate, height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    if (_current != null) _currentBanner(),
                    _periodToggle(),
                    const SizedBox(height: 18),
                    ..._plans.map(_planCard),
                  ],
                ),
    );
  }

  Widget _currentBanner() {
    final plan = _current!['plan'] is Map ? Map<String, dynamic>.from(_current!['plan'] as Map) : {};
    final name = plan['name']?.toString() ?? _current!['tier']?.toString() ?? 'Member';
    final ends = _current!['ends_at']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: digiForest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your house', style: GoogleFonts.dmSans(color: const Color(0xFFE8D5A3), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 4),
            Text(name, style: GoogleFonts.sourceSerif4(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
            if (ends.isNotEmpty)
              Text(
                'Active through ${ends.split('T').first}',
                style: GoogleFonts.dmSans(color: Colors.white70, fontSize: 13),
              ),
          ],
        ),
      ),
    );
  }

  Widget _periodToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: digiLine),
      ),
      child: Row(
        children: [
          _seg('Monthly', !_yearly, () => setState(() => _yearly = false)),
          _seg('Yearly · 2 months free', _yearly, () => setState(() => _yearly = true)),
        ],
      ),
    );
  }

  Widget _seg(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? digiForest : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: active ? Colors.white : digiSlate,
            ),
          ),
        ),
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final tier = plan['tier']?.toString() ?? '';
    final diamond = tier == 'diamond';
    final gold = tier == 'gold';
    final currentTier = _current?['tier']?.toString();
    final isCurrent = currentTier == tier;
    final price = _yearly ? plan['yearlyGhs'] : plan['monthlyGhs'];
    final unit = _yearly ? '/ year' : '/ month';
    final benefits = ((plan['benefits'] as List?) ?? []).map((e) => e.toString()).toList();
    final ink = diamond ? Colors.white : digiInk;
    final mute = diamond ? const Color(0xFFD4C4A8) : digiSlate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: diamond ? digiInk : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: gold ? digiGold : (diamond ? const Color(0xFF3A342C) : digiLine),
            width: gold ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  plan['name']?.toString() ?? tier,
                  style: GoogleFonts.sourceSerif4(fontSize: 26, fontWeight: FontWeight.w600, color: gold ? const Color(0xFF8A6A2F) : ink),
                ),
                const Spacer(),
                if (plan['recommended'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8D5A3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Kept most', style: GoogleFonts.dmSans(fontSize: 11, fontWeight: FontWeight.w800, color: digiInk)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(plan['tagline']?.toString() ?? '', style: GoogleFonts.dmSans(color: mute, height: 1.35)),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('GHS $price', style: GoogleFonts.sourceSerif4(fontSize: 28, fontWeight: FontWeight.w600, color: ink)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(unit, style: GoogleFonts.dmSans(color: mute, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...benefits.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, size: 18, color: diamond ? digiGold : digiForest),
                    const SizedBox(width: 8),
                    Expanded(child: Text(b, style: GoogleFonts.dmSans(color: ink, height: 1.35))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isCurrent || _payingTier != null ? null : () => _subscribe(plan),
                style: FilledButton.styleFrom(
                  backgroundColor: diamond ? digiGold : digiForest,
                  foregroundColor: diamond ? digiInk : Colors.white,
                  disabledBackgroundColor: diamond ? const Color(0xFF3A342C) : const Color(0xFFE8E4DC),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  isCurrent
                      ? 'Your current house'
                      : _payingTier == tier
                          ? 'Opening Paystack…'
                          : 'Join ${plan['name']} with MoMo or card',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
