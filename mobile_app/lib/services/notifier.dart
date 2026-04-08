import 'package:flutter/material.dart';

class Notifier {
  Notifier._();

  static String sanitizeMessage(String message) {
    if (message.isEmpty) return 'Something went wrong';

    // 1. Try to extract "message" from JSON-like strings
    // Matches both "message": "..." and "message":"..."
    final jsonMsg = RegExp(
      r'"message"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(message);
    if (jsonMsg != null) {
      final inner = jsonMsg.group(1);
      if (inner != null && inner.trim().isNotEmpty) return inner.trim();
    }

    // 2. Try to extract message: '...'/message: "..." (unquoted keys or single quotes)
    final colonMsg = RegExp(
      'message\\s*[:=]\\s*["\'](.+?)["\']',
      caseSensitive: false,
    ).firstMatch(message);
    if (colonMsg != null) {
      final inner = colonMsg.group(1);
      if (inner != null && inner.trim().isNotEmpty) return inner.trim();
    }

    // 3. Drop common technical prefixes like "Exception:", "API error:", etc.
    final prefixes = [
      'Exception',
      'API error',
      'Error',
      'BadRequestException',
      'UnauthorizedException',
      'FormatException',
      'HttpException',
      'SocketException',
    ];

    var cleaned = message;

    // Remove "Login failed :" or similar prefixes that end with a colon
    // but keep the rest if it's not a technical error
    final genericPrefix = RegExp(r'^[a-zA-Z\s]+[:]\s*');
    if (genericPrefix.hasMatch(cleaned)) {
      // Only strip if what follows looks like a technical error
      final remaining = cleaned.replaceFirst(genericPrefix, '').trim();
      bool isTechnical = false;
      for (final p in prefixes) {
        if (remaining.toLowerCase().startsWith(p.toLowerCase())) {
          isTechnical = true;
          break;
        }
      }
      if (isTechnical) {
        cleaned = remaining;
      }
    }

    for (final p in prefixes) {
      // Remove prefix at start: "Exception: ..." -> "..."
      cleaned = cleaned.replaceAll(
        RegExp('^$p[: ]*', caseSensitive: false),
        '',
      );
      // Remove anywhere if followed by colon: "... Error: message" -> "... message"
      cleaned = cleaned.replaceAll(
        RegExp('\\b$p[: ]+', caseSensitive: false),
        '',
      );
    }

    // 4. Handle some specific formats like "401 success : false, message ..."
    cleaned = cleaned.replaceAll(
      RegExp(r'\d{3}\s+success\s*:\s*false\s*,?\s*', caseSensitive: false),
      '',
    );

    // 5. Final attempt to extract message if it was buried deep after cleaning
    final fallbackJson = RegExp(
      r'"message"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (fallbackJson != null) {
      final inner = fallbackJson.group(1);
      if (inner != null && inner.trim().isNotEmpty) return inner.trim();
    }

    cleaned = cleaned.trim();

    // Remove trailing/leading quotes that might remain
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }

    // Clamp to a reasonable length
    if (cleaned.length > 200) {
      cleaned = '${cleaned.substring(0, 200)}…';
    }

    return cleaned.isEmpty ? 'Something went wrong' : cleaned;
  }

  static void _show(
    BuildContext context, {
    required String message,
    required IconData icon,
    required ColorScheme colorScheme,
    Color? bg,
    Color? fg,
    Duration? duration,
  }) {
    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(icon, color: fg ?? colorScheme.onPrimary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      backgroundColor: bg,
      duration: duration ?? const Duration(seconds: 3),
    );

    // Use addPostFrameCallback to ensure the widget tree is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(snackBar);
      }
    });
  }

  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    final scheme = Theme.of(context).colorScheme;
    _show(
      context,
      message: message,
      icon: Icons.check_circle_rounded,
      colorScheme: scheme,
      bg: scheme.secondaryContainer,
      fg: scheme.onSecondaryContainer,
      duration: duration ?? const Duration(seconds: 2),
    );
  }

  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
    bool sanitize = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    _show(
      context,
      message: sanitize ? sanitizeMessage(message) : message,
      icon: Icons.error_rounded,
      colorScheme: scheme,
      bg: scheme.errorContainer,
      fg: scheme.onErrorContainer,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  static void info(BuildContext context, String message, {Duration? duration}) {
    final scheme = Theme.of(context).colorScheme;
    _show(
      context,
      message: message,
      icon: Icons.info_rounded,
      colorScheme: scheme,
      bg: scheme.primaryContainer,
      fg: scheme.onPrimaryContainer,
      duration: duration ?? const Duration(seconds: 3),
    );
  }
}
