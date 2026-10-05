import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/clinical_ui.dart';

/// Fixed choices on a home care request. More than one can be on.
const homeCareOptionLabels = <String>[
  'Stay-in',
  'Day visit',
  'Overnight',
  'Wound care',
  'Mobility help',
  'Medication reminder',
  'Companionship',
];

const homeCareStayInLine = 'The caregiver stays in the home.';

const _customOptionMax = 48;

bool _isStayIn(String value) {
  final key = value.trim().toLowerCase();
  return key == 'stay-in' || key == 'stay in';
}

/// Known labels only, in catalog order.
List<String> normalizeHomeCareOptions(Iterable<String> raw) {
  final picked = <String>{};
  for (final item in raw) {
    final key = item.trim().toLowerCase();
    for (final label in homeCareOptionLabels) {
      if (label.toLowerCase() == key) {
        picked.add(label);
        break;
      }
    }
  }
  return [
    for (final label in homeCareOptionLabels)
      if (picked.contains(label)) label,
  ];
}

String? normalizeHomeCareCustomOption(String? raw) {
  final text = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return null;
  if (text.length <= _customOptionMax) return text;
  return text.substring(0, _customOptionMax);
}

List<String> homeCareOptionsFromJson(dynamic raw) {
  if (raw is! List) return const [];
  return normalizeHomeCareOptions(raw.map((item) => item.toString()));
}

bool homeCareShowsStayIn(List<String> options, String? customOption) {
  if (options.any(_isStayIn)) return true;
  final extra = customOption?.trim() ?? '';
  return extra.isNotEmpty && _isStayIn(extra);
}

/// Selected catalog labels, then the extra label when it is not already shown.
List<String> homeCareChipLabels(List<String> options, String? customOption) {
  final chips = normalizeHomeCareOptions(options);
  final extra = normalizeHomeCareCustomOption(customOption);
  if (extra == null) return chips;
  final duplicate = chips.any(
    (label) => label.toLowerCase() == extra.toLowerCase(),
  );
  if (duplicate) return chips;
  return [...chips, extra];
}

/// Toggles plus the one optional extra label, shared by post and edit.
class HomeCareOptionFields extends StatelessWidget {
  const HomeCareOptionFields({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.custom,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final TextEditingController custom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeCareOptionPicker(selected: selected, onChanged: onChanged),
        const SizedBox(height: 12),
        TextField(
          controller: custom,
          textCapitalization: TextCapitalization.sentences,
          decoration: clinicalFieldDecoration(
            'Other option',
            helper: 'Optional. One short label, such as feeding help.',
          ),
        ),
      ],
    );
  }
}

class HomeCareOptionPicker extends StatelessWidget {
  const HomeCareOptionPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final stayIn = selected.contains('Stay-in');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Care options',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: healynksInk,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Turn on any that apply.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            color: healynksMuted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final label in homeCareOptionLabels)
              _OptionToggle(
                label: label,
                selected: selected.contains(label),
                onTap: () {
                  final next = Set<String>.from(selected);
                  if (!next.add(label)) next.remove(label);
                  onChanged(next);
                },
              ),
          ],
        ),
        if (stayIn) ...[
          const SizedBox(height: 8),
          Text(
            homeCareStayInLine,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: healynksMuted,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionToggle extends StatelessWidget {
  const _OptionToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? const Color(0xFFEAF1FF) : Colors.white;
    final foreground = selected ? healynksBlue : healynksInk;
    final border = selected ? healynksBlue : healynksLine;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: foreground,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small labels on a request card or the share page.
class HomeCareOptionChips extends StatelessWidget {
  const HomeCareOptionChips({
    super.key,
    required this.options,
    this.customOption,
  });

  final List<String> options;
  final String? customOption;

  @override
  Widget build(BuildContext context) {
    final labels = homeCareChipLabels(options, customOption);
    if (labels.isEmpty) return const SizedBox.shrink();
    final stayIn = homeCareShowsStayIn(options, customOption);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [for (final label in labels) _OptionChip(label: label)],
        ),
        if (stayIn) ...[
          const SizedBox(height: 6),
          Text(
            homeCareStayInLine,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: healynksMuted,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: healynksLine),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: healynksInk,
          height: 1.2,
        ),
      ),
    );
  }
}
