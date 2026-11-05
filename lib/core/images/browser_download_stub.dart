import 'dart:typed_data';

/// Outside a browser there is nothing to download into (D-71).
void downloadInBrowser(Uint8List bytes, String filename, String mimeType) =>
    throw UnsupportedError('Browser downloads only exist on the web.');
