import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'paystack_utils.dart';

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
      return extractPaystackReference(Uri.parse(url)) ?? widget.reference;
    } catch (_) {
      return widget.reference;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: const Text(
          'Pay with MoMo or Card',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00D2C4)),
            ),
        ],
      ),
    );
  }
}
