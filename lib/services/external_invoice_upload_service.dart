import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class UploadedInvoiceFile {
  final String name;
  final String path;
  final String url;
  final String contentType;
  final int size;

  const UploadedInvoiceFile({
    required this.name,
    required this.path,
    required this.url,
    required this.contentType,
    required this.size,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'path': path,
      'url': url,
      'content_type': contentType,
      'size': size,
      'provider': 'external_http',
    };
  }
}

class ExternalInvoiceUploadService {
  static const _uploadUrl = String.fromEnvironment('INVOICE_UPLOAD_URL');
  static const _uploadToken = String.fromEnvironment('INVOICE_UPLOAD_TOKEN');

  Future<UploadedInvoiceFile> uploadInvoice({
    required String requestId,
    required Uint8List fileBytes,
    required String fileName,
    required String contentType,
  }) async {
    if (_uploadUrl.trim().isEmpty) {
      throw Exception(
        'رابط رفع الفواتير غير مضبوط. شغّل التطبيق مع INVOICE_UPLOAD_URL أو اضبطه وقت البناء.',
      );
    }
    if (fileBytes.isEmpty) throw Exception('ملف الفاتورة فارغ.');

    final uri = Uri.tryParse(_uploadUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw Exception('رابط رفع الفواتير غير صحيح.');
    }

    final request = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..fields['request_id'] = requestId
      ..fields['content_type'] = contentType
      ..fields['token'] = _uploadToken;

    if (_uploadToken.isNotEmpty) {
      request.headers['X-Upload-Token'] = _uploadToken;
    }

    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(streamed);
    final decoded = _decodeResponse(response.body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error']?.toString() ?? 'تعذر رفع ملف الفاتورة.');
    }
    if (decoded['ok'] != true) {
      throw Exception(decoded['error']?.toString() ?? 'فشل رفع الفاتورة.');
    }

    final url = decoded['url']?.toString() ?? '';
    if (url.isEmpty) throw Exception('لم يرجع خادم الرفع رابط الملف.');

    return UploadedInvoiceFile(
      name: decoded['name']?.toString() ?? fileName,
      path: decoded['path']?.toString() ?? '',
      url: url,
      contentType: decoded['content_type']?.toString() ?? contentType,
      size:
          (decoded['size'] is num ? (decoded['size'] as num).toInt() : null) ??
          fileBytes.length,
    );
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'ok': false, 'error': 'رد خادم الرفع غير صالح.'};
    } catch (_) {
      return {'ok': false, 'error': body.trim().isEmpty ? 'رد فارغ.' : body};
    }
  }
}
