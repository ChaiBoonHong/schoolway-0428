import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:archive/archive.dart';

import '../../core/utils/csv_file_io.dart';
import '../../services/csv_import_service.dart';

class CsvImporterScreen extends StatefulWidget {
  const CsvImporterScreen({super.key, this.initialType});

  final CsvImportType? initialType;

  @override
  State<CsvImporterScreen> createState() => _CsvImporterScreenState();
}

class _CsvImporterScreenState extends State<CsvImporterScreen> {
  CsvImportType _selectedType = CsvImportType.route;
  CsvExportType _selectedExportType = CsvExportType.users;

  /// Order that satisfies Firestore references (users → buses → routes → students).
  static const List<CsvImportType> _recommendedImportOrder = [
    CsvImportType.user,
    CsvImportType.bus,
    CsvImportType.route,
    CsvImportType.student,
  ];

  static const List<CsvImportType> _displayOrder = [
    CsvImportType.user,
    CsvImportType.student,
    CsvImportType.bus,
    CsvImportType.route,
  ];
  bool _isImporting = false;
  bool _isMigratingRoutes = false;
  bool _isDownloadingTemplate = false;
  bool _isExporting = false;
  bool _cancelRequested = false;
  String _phase = 'Ready to import';
  int _current = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) {
      _selectedType = widget.initialType!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isImporting || _isMigratingRoutes;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: const Color(0xFFCAF0F8),
        appBar: AppBar(
          backgroundColor: const Color(0xFFCAF0F8),
          elevation: 0,
          foregroundColor: const Color(0xFF03045E),
          title: const Text(
            'CSV Management',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w600,
              fontSize: 20,
              color: Color(0xFF03045E),
            ),
          ),
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF94D2F3)),
                  ),
                  child: Text(
                    'Import order: ${_recommendedImportOrder.map(CsvImportService.label).join(' -> ')}',
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Import',
                  children: [
                    DropdownButtonFormField<CsvImportType>(
                      initialValue: _selectedType,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                      items: _displayOrder
                          .map(
                            (t) => DropdownMenuItem<CsvImportType>(
                              value: t,
                              child: Text(
                                CsvImportService.label(t),
                                style: const TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: busy
                          ? null
                          : (v) {
                              if (v != null) setState(() => _selectedType = v);
                            },
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: (_isDownloadingTemplate || busy)
                          ? null
                          : _downloadTemplate,
                      icon: _isDownloadingTemplate
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_outlined),
                      label: const Text('Download Template'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0077B6),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: busy ? null : _validateAndPreviewCsv,
                      icon: _isImporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file_outlined),
                      label: Text(
                        'Upload & Preview ${CsvImportService.label(_selectedType)} CSV',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF03045E),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Route Maintenance',
                  children: [
                    ElevatedButton.icon(
                      onPressed: busy ? null : _migrateExistingRouteGeometry,
                      icon: _isMigratingRoutes
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.alt_route),
                      label: const Text(
                        'Rebuild Existing Route Geometry (OSRM)',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6A1B9A),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Export',
                  children: [
                    DropdownButtonFormField<CsvExportType>(
                      initialValue: _selectedExportType,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(),
                      ),
                      items: CsvExportType.values
                          .map(
                            (t) => DropdownMenuItem<CsvExportType>(
                              value: t,
                              child: Text(CsvImportService.exportLabel(t)),
                            ),
                          )
                          .toList(),
                      onChanged: (busy || _isExporting)
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _selectedExportType = v);
                              }
                            },
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: (_isExporting || busy)
                          ? null
                          : _exportSingleType,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_for_offline_outlined),
                      label: Text(
                        'Export ${CsvImportService.exportLabel(_selectedExportType)} CSV',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B8A6A),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: (_isExporting || busy)
                          ? null
                          : _exportAllAsZip,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.folder_zip_outlined),
                      label: const Text('Export All (ZIP)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_isImporting || _isMigratingRoutes)
              Positioned.fill(
                child: Stack(
                  children: [
                    const ModalBarrier(
                      dismissible: false,
                      color: Color(0x88000000),
                    ),
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _phase,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Color(0xFF03045E),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${_current.clamp(0, _total)} of $_total',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 14,
                                color: Color(0xFF334155),
                              ),
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: _total > 0 ? _current / _total : null,
                              color: const Color(0xFF0077B6),
                              backgroundColor: const Color(0xFFE2E8F0),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _cancelRequested
                                  ? null
                                  : () {
                                      setState(() {
                                        _cancelRequested = true;
                                        _phase = _isMigratingRoutes
                                            ? 'Cancel requested, finishing current route...'
                                            : 'Cancel requested, finishing current row...';
                                      });
                                    },
                              child: Text(
                                _cancelRequested
                                    ? 'Canceling...'
                                    : (_isMigratingRoutes
                                          ? 'Cancel Migration'
                                          : 'Cancel Import'),
                                style: const TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadTemplate() async {
    if (_isDownloadingTemplate) return;
    setState(() => _isDownloadingTemplate = true);
    try {
      await downloadCsvTemplate(
        content: CsvImportService.templateCsv(_selectedType),
        fileName: CsvImportService.templateFileName(_selectedType),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${CsvImportService.label(_selectedType)} template downloaded',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Template download failed: $e',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isDownloadingTemplate = false);
    }
  }

  Future<void> _importSelectedType(String csv) async {
    if (_isImporting) return;
    try {
      if (csv.trim().isEmpty) return;

      if (!mounted) return;
      setState(() {
        _isImporting = true;
        _cancelRequested = false;
        _phase = 'Preparing import...';
        _current = 0;
        _total = 0;
      });

      if (_cancelRequested) return;


      final result = await CsvImportService.importCsv(
        type: _selectedType,
        csvText: csv,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _phase = progress.phase;
            _current = progress.current;
            _total = progress.total;
          });
        },
        shouldCancel: () => _cancelRequested,
      );

      if (!mounted) return;
      final summary = StringBuffer()
        ..writeln('Type: ${CsvImportService.label(_selectedType)}')
        ..writeln('Imported: ${result.imported}')
        ..writeln('Failed: ${result.failed}');
      if (result.cancelled) {
        summary.writeln('Canceled gracefully. Completed rows were kept.');
      }
      if (result.errors.isNotEmpty) {
        summary
          ..writeln()
          ..writeln(result.errors.take(6).join('\n'));
        if (result.errors.length > 6) {
          summary.writeln('... and ${result.errors.length - 6} more error(s).');
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            summary.toString(),
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          duration: const Duration(seconds: 7),
          backgroundColor: result.failed == 0
              ? const Color(0xFF2E7D32)
              : const Color(0xFFF57C00),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e', style: const TextStyle(fontFamily: 'Lexend')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _cancelRequested = false;
          _phase = 'Ready to import';
          _current = 0;
          _total = 0;
        });
      }
    }
  }

  Future<void> _migrateExistingRouteGeometry() async {
    if (_isMigratingRoutes || _isImporting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Rebuild Existing Routes?',
          style: TextStyle(fontFamily: 'Lexend'),
        ),
        content: const Text(
          'This will recalculate and overwrite saved route waypoints using OSRM driving geometry for all planned routes. Stops remain unchanged.',
          style: TextStyle(fontFamily: 'Lexend'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rebuild'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _isMigratingRoutes = true;
      _cancelRequested = false;
      _phase = 'Loading planned routes...';
      _current = 0;
      _total = 0;
    });
    try {
      final result = await CsvImportService.migratePlannedRoutesToOsrm(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _phase = progress.phase;
            _current = progress.current;
            _total = progress.total;
          });
        },
        shouldCancel: () => _cancelRequested,
      );
      if (!mounted) return;
      final summary = StringBuffer()
        ..writeln('Scanned: ${result.scanned}')
        ..writeln('Migrated: ${result.migrated}')
        ..writeln('Skipped: ${result.skipped}')
        ..writeln('Failed: ${result.failed}');
      if (result.cancelled) {
        summary.writeln('Canceled gracefully. Completed routes were kept.');
      }
      if (result.errors.isNotEmpty) {
        summary
          ..writeln()
          ..writeln(result.errors.take(5).join('\n'));
        if (result.errors.length > 5) {
          summary.writeln('... and ${result.errors.length - 5} more error(s).');
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            summary.toString(),
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          duration: const Duration(seconds: 8),
          backgroundColor: result.failed == 0
              ? const Color(0xFF2E7D32)
              : const Color(0xFFF57C00),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Route migration failed: $e',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isMigratingRoutes = false;
          _cancelRequested = false;
          _phase = 'Ready to import';
          _current = 0;
          _total = 0;
        });
      }
    }
  }

  Future<void> _exportAllAsZip() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final files = await CsvImportService.exportCurrentData();
      final archive = Archive();
      for (final f in files) {
        final bytes = utf8.encode(f.content);
        archive.addFile(ArchiveFile(f.fileName, bytes.length, bytes));
      }

      final zipBytes = ZipEncoder().encode(archive);

      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

      await downloadZipFile(
        bytes: zipBytes,
        fileName: 'schoolway_export_$stamp.zip',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Export complete: schoolway_export_$stamp.zip',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Export failed: $e',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportSingleType() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final file = await CsvImportService.exportCurrentDataByType(
        _selectedExportType,
      );
      await downloadCsvTemplate(content: file.content, fileName: file.fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Export complete: ${file.fileName}',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Export failed: $e',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _validateAndPreviewCsv() async {
    final rawContent = await pickCsvText();
    if (rawContent == null || rawContent.isEmpty) return;

    final report = await CsvImportService.validateCsvPreCommit(rawContent, _selectedType);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('CSV Pre-Commit Preview (${CsvImportService.label(_selectedType)})'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _previewStatBadge('Total', '${report.totalRows}', Colors.blue),
                    _previewStatBadge('Valid', '${report.validRows}', Colors.green),
                    _previewStatBadge('Invalid', '${report.invalidRows}', Colors.red),
                    _previewStatBadge('Duplicates', '${report.duplicateRows}', Colors.orange),
                    _previewStatBadge('Existing in DB', '${report.existingInFirestore}', Colors.purple),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Row Diagnostic Details:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (report.rows.isEmpty)
                  const Text('File contains no data rows.')
                else
                  Column(
                    children: report.rows.take(25).map((row) {
                      final bg = row.hasErrors
                          ? (row.isDuplicate
                              ? Colors.orange.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15))
                          : Colors.green.withValues(alpha: 0.08);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
                        child: Row(
                          children: [
                            Text('#${row.rowNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                row.hasErrors ? row.errors.join(', ') : 'Valid record: ${row.rowData.values.take(3).join(" | ")} ${row.existsInFirestore ? '(Update existing)' : '(New record)'}',
                                style: TextStyle(color: row.hasErrors ? Colors.red.shade900 : Colors.green.shade900, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          if (report.invalidRows > 0 || report.duplicateRows > 0)
            ElevatedButton.icon(
              onPressed: () async {
                final errCsv = CsvImportService.generateErrorReportCsv(report);
                await downloadCsvTemplate(content: errCsv, fileName: 'csv_error_report_${DateTime.now().millisecondsSinceEpoch}.csv');
              },
              icon: const Icon(Icons.download),
              label: const Text('Download Error Report'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ElevatedButton.icon(
            onPressed: report.validRows == 0
                ? null
                : () {
                    Navigator.pop(ctx);
                    _importSelectedType(rawContent);
                  },
            icon: const Icon(Icons.upload),
            label: Text('Import ${report.validRows} Valid Rows'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF03045E),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }


  Widget _previewStatBadge(String label, String val, Color color) {
    return Column(
      children: [
        Text(val, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}


class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Color(0xFF03045E),
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
