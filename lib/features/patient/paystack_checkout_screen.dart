import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../shared/widgets/clinical_ui.dart';
import 'paystack_utils.dart';

/// Hosted Paystack checkout (MoMo, card, bank) — same flow as Bytz Go.
class PaystackCheckoutScreen extends StatefulWidget {
  const PaystackCheckoutScreen({
    super.key,
    required this.authorizationUrl,
    required this.reference,
  });

  final String authorizationUrl;
  final String reference;

  static Future<String?> open(
    BuildContext context, {
    required String authorizationUrl,
    required String reference,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaystackCheckoutScreen(
          authorizationUrl: authorizationUrl,
          reference: reference,
        ),
      ),
    );
  }

  @override
  State<PaystackCheckoutScreen> createState() => _PaystackCheckoutScreenState();
}

class _PaystackCheckoutScreenState extends State<PaystackCheckoutScreen> {
  late final WebViewController _controller;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final ref = _referenceFromUrl(request.url);
            if (ref != null) {
              Navigator.of(context).pop(ref);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  String? _referenceFromUrl(String url) {
    if (!isPaystackCallbackUrl(url)) return null;
    try {
      final ref = extractPaystackReference(Uri.parse(url));
      return ref ?? widget.reference;
    } catch (_) {
      return widget.reference;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3EE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F3EE),
        foregroundColor: digiInk,
        elevation: 0,
        title: Text(
          'Pay with MoMo or card',
          style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Color(0xFF1F4A3A))),
        ],
      ),
    );
  }
}
