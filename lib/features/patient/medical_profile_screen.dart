import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../models/patient_profile.dart';
import 'care_repository.dart';

class MedicalProfileScreen extends StatefulWidget {
  const MedicalProfileScreen({super.key});

  @override
  State<MedicalProfileScreen> createState() => _MedicalProfileScreenState();
}

class _MedicalProfileScreenState extends State<MedicalProfileScreen> {
  PatientProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _dob = TextEditingController();
  final _sex = TextEditingController();
  final _region = TextEditingController();
  final _town = TextEditingController();
  final _address = TextEditingController();
  final _occupation = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _kinName = TextEditingController();
  final _kinPhone = TextEditingController();
  final _blood = TextEditingController();
  final _genotype = TextEditingController();
  final _allergies = TextEditingController();
  final _chronic = TextEditingController();
  final _meds = TextEditingController();
  final _diagnoses = TextEditingController();
  final _surgeries = TextEditingController();
  final _family = TextEditingController();
  final _social = TextEditingController();
  final _location = TextEditingController();
  final _nationwide = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _phone, _email, _dob, _sex, _region, _town, _address, _occupation,
      _emergencyName, _emergencyPhone, _kinName, _kinPhone, _blood, _genotype,
      _allergies, _chronic, _meds, _diagnoses, _surgeries, _family, _social,
      _location, _nationwide,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await context.read<CareRepository>().getMyProfile();
      _profile = profile;
      _name.text = profile.fullName;
      _phone.text = profile.phoneNumber;
      _email.text = profile.email ?? '';
      _dob.text = profile.dateOfBirth?.split('T').first ?? '';
      _sex.text = profile.sex ?? '';
      _region.text = profile.region ?? '';
      _town.text = profile.town ?? '';
      _address.text = profile.address ?? '';
      _occupation.text = profile.occupation ?? '';
      _emergencyName.text = profile.emergencyName ?? '';
      _emergencyPhone.text = profile.emergencyPhone ?? '';
      _kinName.text = profile.nextOfKinName ?? '';
      _kinPhone.text = profile.nextOfKinPhone ?? '';
      _blood.text = profile.bloodGroup ?? '';
      _genotype.text = profile.genotype ?? '';
      _allergies.text = profile.allergies ?? '';
      _chronic.text = profile.chronicConditions ?? '';
      _meds.text = profile.currentMedications ?? '';
      _diagnoses.text = profile.previousDiagnoses ?? '';
      _surgeries.text = profile.surgeries ?? '';
      _family.text = profile.familyHistory ?? '';
      _social.text = profile.socialHistory ?? '';
      _location.text = profile.preferredLocation ?? '';
      _nationwide.text = profile.nationwideId ?? '';
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await context.read<CareRepository>().saveMyProfile({
        'full_name': _name.text.trim(),
        'phone_number': _phone.text.trim(),
        'email': _email.text.trim(),
        'date_of_birth': _dob.text.trim(),
        'sex': _sex.text.trim(),
        'region': _region.text.trim(),
        'town': _town.text.trim(),
        'address': _address.text.trim(),
        'occupation': _occupation.text.trim(),
        'emergency_name': _emergencyName.text.trim(),
        'emergency_phone': _emergencyPhone.text.trim(),
        'next_of_kin_name': _kinName.text.trim(),
        'next_of_kin_phone': _kinPhone.text.trim(),
        'blood_group': _blood.text.trim(),
        'genotype': _genotype.text.trim(),
        'allergies': _allergies.text.trim(),
        'chronic_conditions': _chronic.text.trim(),
        'current_medications': _meds.text.trim(),
        'previous_diagnoses': _diagnoses.text.trim(),
        'surgeries': _surgeries.text.trim(),
        'family_history': _family.text.trim(),
        'social_history': _social.text.trim(),
        'preferred_location': _location.text.trim(),
        'nationwide_id': _nationwide.text.trim(),
      });
      if (!mounted) return;
      final session = context.read<Session>();
      if (session.user != null) {
        session.patchUser(session.user!.copyWith(
          name: saved.fullName,
          phoneNumber: saved.phoneNumber,
          email: saved.email,
          patientCode: saved.patientCode,
        ));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medical profile saved.')),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Medical Profile', style: GoogleFonts.roboto(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_profile?.patientCode != null)
                  Text('Patient ID: ${_profile!.patientCode}', style: GoogleFonts.roboto(color: const Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                _section('Demographics'),
                _field(_name, 'Full name'),
                _field(_phone, 'Phone number (SMS)'),
                _field(_email, 'Email'),
                _field(_dob, 'Date of birth (YYYY-MM-DD)'),
                _field(_sex, 'Sex'),
                _field(_region, 'Region'),
                _field(_town, 'Town / city'),
                _field(_address, 'Address'),
                _field(_occupation, 'Occupation'),
                _field(_nationwide, 'National / insurance ID'),
                _field(_location, 'Preferred location'),
                _section('Emergency & next of kin'),
                _field(_emergencyName, 'Emergency contact name'),
                _field(_emergencyPhone, 'Emergency contact phone'),
                _field(_kinName, 'Next of kin name'),
                _field(_kinPhone, 'Next of kin phone'),
                _section('Clinical information'),
                _field(_blood, 'Blood group'),
                _field(_genotype, 'Genotype'),
                _field(_allergies, 'Allergies', maxLines: 2),
                _field(_chronic, 'Chronic conditions', maxLines: 2),
                _field(_meds, 'Current medications', maxLines: 2),
                _field(_diagnoses, 'Previous diagnoses', maxLines: 2),
                _field(_surgeries, 'Surgeries', maxLines: 2),
                _field(_family, 'Family history', maxLines: 2),
                _field(_social, 'Social history', maxLines: 2),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(_saving ? 'Saving…' : 'Save profile'),
                ),
              ],
            ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(title, style: GoogleFonts.roboto(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
