import 'package:web/web.dart' as web;

class WhatsAppPopup {
  WhatsAppPopup(this._window);

  final web.Window _window;

  bool navigate(String url) {
    if (_window.closed) return false;
    _window.location.href = url;
    return true;
  }

  void close() {
    if (!_window.closed) _window.close();
  }
}

WhatsAppPopup? openWhatsAppPopup() {
  final window = web.window.open('about:blank', '_blank');
  return window == null ? null : WhatsAppPopup(window);
}
