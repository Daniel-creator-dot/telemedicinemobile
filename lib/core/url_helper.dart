import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> launchExternalUrl(
  String url, {
  BuildContext? context,
  String errorMessage = 'Could not open link.',
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    }
    return false;
  }

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return true;
  }

  if (context != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
  }
  return false;
}

Future<bool> launchPhoneCall(String number, {BuildContext? context}) {
  return launchExternalUrl(
    'tel:$number',
    context: context,
    errorMessage: 'Could not start phone call.',
  );
}
