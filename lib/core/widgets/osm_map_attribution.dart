import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// OSM attribution plus “Report a map issue” and support email (OSM / tile policy).
class OsmMapAttribution extends StatefulWidget {
  const OsmMapAttribution({
    super.key,
    this.compact = false,
  });

  final bool compact;

  @override
  State<OsmMapAttribution> createState() => _OsmMapAttributionState();
}

class _OsmMapAttributionState extends State<OsmMapAttribution> {
  late final TapGestureRecognizer _reportTap;
  late final TapGestureRecognizer _emailTap;

  @override
  void initState() {
    super.initState();
    _reportTap = TapGestureRecognizer()
      ..onTap = () => _openUrl(AppConfig.openStreetMapReportIssueUrl);
    _emailTap = TapGestureRecognizer()..onTap = _openEmail;
  }

  @override
  void dispose() {
    _reportTap.dispose();
    _emailTap.dispose();
    super.dispose();
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openEmail() async {
    final uri = Uri.parse('mailto:${AppConfig.supportContactEmail}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: widget.compact ? 9 : 11,
      color: Colors.black87,
      height: 1.25,
    );
    final linkStyle = baseStyle.copyWith(
      color: const Color(0xFF0077B6),
      decoration: TextDecoration.underline,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text.rich(
          TextSpan(
            style: baseStyle,
            children: widget.compact
                ? [
                    const TextSpan(text: '© OSM · '),
                    TextSpan(
                      text: 'Report map issue',
                      style: linkStyle,
                      recognizer: _reportTap,
                    ),
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: AppConfig.supportContactEmail,
                      style: linkStyle,
                      recognizer: _emailTap,
                    ),
                  ]
                : [
                    const TextSpan(text: '© OpenStreetMap contributors · '),
                    TextSpan(
                      text: 'Report a map issue',
                      style: linkStyle,
                      recognizer: _reportTap,
                    ),
                    const TextSpan(text: '\nSupport: '),
                    TextSpan(
                      text: AppConfig.supportContactEmail,
                      style: linkStyle,
                      recognizer: _emailTap,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
