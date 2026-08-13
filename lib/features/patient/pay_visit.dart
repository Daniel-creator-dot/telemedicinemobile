import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../shared/widgets/clinical_ui.dart';
import 'appointments_repository.dart';
import 'paystack_checkout_screen.dart';

class PayVisitResult {
  const PayVisitResult({
    required this.success,
    required this.message,
    this.cancelled = false,
  });

  final bool success;
  final String message;
  final bool cancelled;
}

Future<PayVisitResult> completePaystackFlow(
  BuildContext context, {
  required Future<Map<String, dynamic>> Function() initialize,
  required Future<void> Function(String reference) verify,
  String successFallback = 'Payment confirmed.',
}) async {
  try {
    final init = await initialize();
    if (!context.mounted) {
      return const PayVisitResult(success: false, message: 'Left the screen.', cancelled: true);
    }
    if (init['alreadyProcessed'] == true) {
      return PayVisitResult(
        success: true,
        message: init['message']?.toString() ?? 'Visit is already paid.',
      );
    }

    final url = init['authorization_url']?.toString() ?? '';
    final reference = init['reference']?.toString() ?? '';
    if (url.isEmpty || reference.isEmpty) {
      return const PayVisitResult(
        success: false,
        message: 'Paystack did not return a checkout URL. Add keys in Admin → Settings.',
      );
    }

    final confirmedRef = await PaystackCheckoutScreen.open(
      context,
      authorizationUrl: url,
      reference: reference,
    );
    if (!context.mounted) {
      return const PayVisitResult(success: false, message: 'Left the screen.', cancelled: true);
    }

    var useRef = confirmedRef?.trim() ?? '';
    if (useRef.isEmpty) {
      useRef = (await _askManualReference(context))?.trim() ?? '';
      if (useRef.isEmpty) {
        return const PayVisitResult(
          success: false,
          message: 'Payment was not completed.',
          cancelled: true,
        );
      }
    }

    await verify(useRef);
    final amount = init['amount'];
    return PayVisitResult(
      success: true,
      message: amount != null ? 'Payment confirmed. GHS $amount.' : successFallback,
    );
  } catch (e) {
    final message = e is DioException
        ? ApiClient.messageFromDio(e, 'Payment failed')
        : e.toString();
    return PayVisitResult(success: false, message: message);
  }
}

/// Same initialize → hosted checkout → verify flow as Bytz Go wallet top-up.
Future<PayVisitResult> payVisitWithPaystack(
  BuildContext context, {
  required int appointmentId,
}) async {
  final repo = context.read<AppointmentsRepository>();
  return completePaystackFlow(
    context,
    initialize: () => repo.initializePay(appointmentId),
    verify: (ref) => repo.verifyPay(appointmentId, ref),
    successFallback: 'Visit payment confirmed.',
  );
}

Future<String?> _askManualReference(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFF6F3EE),
      title: Text('Paste Paystack reference', style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'If checkout closed before returning here, paste the payment reference from Paystack or your SMS.',
            style: GoogleFonts.dmSans(color: digiSlate, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'digihealth_…',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Confirm payment'),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}
