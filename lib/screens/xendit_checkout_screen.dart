import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/store_repository.dart';

class XenditCheckoutScreen extends StatefulWidget {
  const XenditCheckoutScreen({
    super.key,
    required this.invoiceUrl,
    required this.externalId,
  });

  final String invoiceUrl;
  final String externalId;

  @override
  State<XenditCheckoutScreen> createState() => _XenditCheckoutScreenState();
}

class _XenditCheckoutScreenState extends State<XenditCheckoutScreen> {
  final _repository = StoreRepository();
  late final WebViewController? _controller;
  Timer? _statusTimer;
  bool _checkingStatus = false;
  bool _isLoading = true;
  String? _loadError;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    unawaited(_checkOrderStatus());
    _statusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_checkOrderStatus()),
    );
    if (kIsWeb) {
      _controller = null;
    } else {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _isLoading = true);
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _isLoading = false);
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame == false) return;
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _loadError = error.description;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.invoiceUrl));
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkOrderStatus() async {
    if (_checkingStatus) return;
    _checkingStatus = true;
    try {
      final status = await _repository.orderStatus(widget.externalId);
      if (!mounted) return;
      if (_statusError != null) setState(() => _statusError = null);
      if (status == 'PAID' ||
          status == 'SETTLED' ||
          status == 'EXPIRED' ||
          status == 'FAILED') {
        Navigator.pop(context, status);
      }
    } catch (error) {
      if (mounted) setState(() => _statusError = error.toString());
    } finally {
      _checkingStatus = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Secure checkout')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Complete your payment in the Xendit tab. This screen will '
                  'update automatically when payment is confirmed.',
                  textAlign: TextAlign.center,
                ),
                if (_statusError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Waiting for payment status: $_statusError',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final controller = _controller!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure checkout'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (_isLoading) const LinearProgressIndicator(),
          if (_loadError != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 48),
                    const SizedBox(height: 12),
                    const Text('Unable to load Xendit checkout.'),
                    const SizedBox(height: 8),
                    Text(_loadError!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _loadError = null;
                          _isLoading = true;
                        });
                        controller.reload();
                      },
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
