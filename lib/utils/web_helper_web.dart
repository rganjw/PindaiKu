import 'dart:js_interop';

@JS('runWebOcr')
external JSPromise<JSString> _runWebOcr(JSString imageUrl);

@JS('downloadWebImage')
external void _downloadWebImage(JSString dataUrl, JSString filename);

Future<String> runWebOcr(String imagePath) async {
  final JSString result = await _runWebOcr(imagePath.toJS).toDart;
  return result.toDart.trim();
}

void downloadWebImage(String dataUrl, String filename) {
  _downloadWebImage(dataUrl.toJS, filename.toJS);
}
