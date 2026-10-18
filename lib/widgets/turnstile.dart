import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme.dart';
import 'clay.dart';

String _html(String siteKey, String action) => '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body{margin:0;background:transparent;overflow:hidden}#w{width:100%}</style>
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer></script></head><body><div id="w"></div>
<script>
var post=function(o){Cap.postMessage(JSON.stringify(o))};
var id=null;
function boot(){ if(!window.turnstile){return setTimeout(boot,150)}
  id=turnstile.render('#w',{sitekey:${jsonEncode(siteKey)},action:${jsonEncode(action)},theme:'light',size:'flexible',retry:'auto','refresh-expired':'auto',
   callback:function(t){post({t:t})},'expired-callback':function(){post({t:null})},'timeout-callback':function(){post({t:null})},'error-callback':function(){post({t:null,error:1})}});}
boot();
window.resetWidget=function(){try{turnstile.reset(id)}catch(e){}};
</script></body></html>''';

/// Cloudflare Turnstile inside a small WebView. [baseUrl] must be a hostname that is allowed on the widget.
class Turnstile extends StatefulWidget {
  final String siteKey, baseUrl;
  final String action;
  final ValueChanged<String?> onToken;
  const Turnstile({super.key, required this.siteKey, required this.baseUrl, required this.onToken, this.action = 'login'});

  @override
  State<Turnstile> createState() => TurnstileState();
}

class TurnstileState extends State<Turnstile> {
  late final WebViewController _c;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel('Cap', onMessageReceived: (m) {
        try {
          final d = jsonDecode(m.message) as Map<String, dynamic>;
          if (mounted) setState(() => _err = d['error'] != null);
          widget.onToken(d['t'] as String?);
        } catch (_) {}
      })
      ..setNavigationDelegate(NavigationDelegate(onWebResourceError: (_) {
        if (mounted) setState(() => _err = true);
      }))
      ..loadHtmlString(_html(widget.siteKey, widget.action), baseUrl: widget.baseUrl);
  }

  /// A token only works once: call after every failed sign-in.
  void reset() {
    widget.onToken(null);
    _c.runJavaScript('window.resetWidget&&window.resetWidget();');
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SizedBox(
          height: 70,
          child: Stack(children: [
            WebViewWidget(controller: _c),
            if (_err) const Positioned(left: 0, bottom: 0, child: T('The security check could not load.', s: 12.5, c: C.bad)),
          ]),
        ),
      );
}
