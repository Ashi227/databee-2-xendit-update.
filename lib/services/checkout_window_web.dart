import 'package:web/web.dart' as web;

class CheckoutWindow {
  CheckoutWindow._(this._window);

  final web.Window _window;

  static CheckoutWindow? open() {
    final window = web.window.open('about:blank', '_blank');
    if (window == null) return null;
    window.opener = null;
    return CheckoutWindow._(window);
  }

  void navigate(String url) {
    _window.location.href = url;
  }

  void close() {
    _window.close();
  }
}
