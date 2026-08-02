import 'dart:convert';
import 'dart:io';

import 'package:store_collection_app/services/legacy_catalog_importer.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    _writeUsage();
    return;
  }

  try {
    final options = _parseOptions(arguments);
    final profileValue = _required(options, 'profile');
    final sourcePath = _required(options, 'file');
    final brandId = _required(options, 'brand-id');
    final brandName = _required(options, 'brand-name');
    final details = options['details'] == 'true';
    final report = await const LegacyCatalogImporter().createDryRun(
      sourceFile: File(sourcePath),
      profileId: LegacyCatalogSourceProfileId.parse(profileValue),
      brandSelection: LegacyCatalogBrandSelection.contractOnly(
        documentId: brandId,
        name: brandName,
      ),
    );

    final encoder = const JsonEncoder.withIndent('  ');
    stdout.writeln(
      encoder.convert(
        details ? report.toDetailedJson() : report.toSummaryJson(),
      ),
    );
  } on LegacyCatalogImportException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 2;
  }
}

Map<String, String> _parseOptions(List<String> arguments) {
  final options = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--details') {
      options['details'] = 'true';
      continue;
    }
    if (!argument.startsWith('--')) {
      throw FormatException('Unexpected argument: $argument');
    }
    final name = argument.substring(2);
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw FormatException('Missing value for --$name.');
    }
    options[name] = arguments[++index];
  }
  const supported = {'profile', 'file', 'brand-id', 'brand-name', 'details'};
  final unknown = options.keys
      .where((key) => !supported.contains(key))
      .toList();
  if (unknown.isNotEmpty) {
    throw FormatException('Unknown option(s): ${unknown.join(', ')}');
  }
  return options;
}

String _required(Map<String, String> options, String name) {
  final value = options[name]?.trim();
  if (value == null || value.isEmpty) {
    throw FormatException('Required option --$name is missing.');
  }
  return value;
}

void _writeUsage() {
  stdout.writeln('''
Read-only SpreadsheetML catalog preview

Usage:
  dart run tool/legacy_catalog_dry_run.dart \\
    --profile <al_asalah_legacy_catalog|eqlid_legacy_catalog> \\
    --file <absolute-source-path> \\
    --brand-id <existing-brand-document-id> \\
    --brand-name <expected-brand-name> [--details]

The command never writes to Firebase or to the source workbook. It validates
the exact profile/brand contract locally. The resulting report intentionally
marks production brand-document validation as pending. Use --details to emit
all row-level suggestions and findings as JSON on stdout. Missing source groups
are previewed against the deterministic brand-scoped "غير مصنف" system group;
the plan reports an idempotent ensure operation because production existence is
not checked in this phase. Legacy prefix suggestions remain advisory and are
never applied automatically.
''');
}
