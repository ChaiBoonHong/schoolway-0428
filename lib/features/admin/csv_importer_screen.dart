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
  int _currentStep = 0;
  CsvImportType get _currentImportType => _recommendedImportOrder[_currentStep];
  CsvExportType _selectedExportType = CsvExportType.users;

  /// Order that satisfies Firestore references (users → buses → routes → students).
  static const List<CsvImportType> _recommendedImportOrder = [
    CsvImportType.user,
    CsvImportType.bus,
    CsvImportType.route,
    CsvImportType.student,
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
      final index = _recommendedImportOrder.indexOf(widget.initialType!);
      if (index != -1) _currentStep = index;
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

                _SectionCard(
                  title: 'Import Wizard',
                  children: [
                    Stepper(
                      physics: const ClampingScrollPhysics(),
                      currentStep: _currentStep,
                      onStepTapped: busy ? null : (step) => setState(() => _currentStep = step),
                      controlsBuilder: (context, details) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
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
                                label: Text('Download ${CsvImportService.label(_currentImportType)} Template'),
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
                                  'Upload & Preview ${CsvImportService.label(_currentImportType)} CSV',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF03045E),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      steps: _recommendedImportOrder.map((type) {
                        final index = _recommendedImportOrder.indexOf(type);
                        String subtitle = 'Follow this order to ensure data connects correctly.';
                        if (type == CsvImportType.student) {
                          subtitle = 'Include assignedRoute and assignedStop columns in the CSV for routing.';
                        }
                        return Step(
                          title: Text(
                            CsvImportService.label(type),
                            style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600),
                          ),
                          content: Text(
                            subtitle,
                            style: const TextStyle(fontFamily: 'Lexend', fontSize: 13),
                          ),
                          isActive: _currentStep == index,
                          state: _currentStep > index ? StepState.complete : StepState.indexed,
                        );
                      }).toList(),
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
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFFE4E9F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: const BorderSide(color: Color(0xFF03045E)),
                        ),
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
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: (_isImporting || _isMigratingRoutes)
                    ? Stack(
                        key: const ValueKey('busy_overlay'),
                        children: [
                          const ModalBarrier(
                            dismissible: false,
                            color: Color(0x88000000),
                          ),
                          Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.8, end: 1.0),
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutBack,
                              builder: (context, scale, child) {
                                return Transform.scale(
                                  scale: scale,
                                  child: child,
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 24),
                                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      child: Text(
                                        _phase,
                                        key: ValueKey(_phase),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'Lexend',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 18,
                                          color: Color(0xFF03045E),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 200),
                                      child: Text(
                                        '${_current.clamp(0, _total)} of $_total',
                                        key: ValueKey('$_current-$_total'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 15,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: _total > 0 ? _current / _total : null,
                                        minHeight: 8,
                                        color: const Color(0xFF0077B6),
                                        backgroundColor: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
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
                                        style: const TextStyle(fontFamily: 'Lexend', fontSize: 16),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('idle')),
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
        content: CsvImportService.templateCsv(_currentImportType),
        fileName: CsvImportService.templateFileName(_currentImportType),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${CsvImportService.label(_currentImportType)} template downloaded',
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
        type: _currentImportType,
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

      if (result.failed == 0 && _currentStep < _recommendedImportOrder.length - 1) {
        setState(() => _currentStep++);
      }

      final summary = StringBuffer()
        ..writeln('Type: ${CsvImportService.label(_currentImportType)}')
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

    final detectedType = CsvImportService.detectCsvType(rawContent);
    if (detectedType != null && detectedType != _currentImportType) {
      final index = _recommendedImportOrder.indexOf(detectedType);
      if (index != -1) setState(() => _currentStep = index);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Auto-detected as ${CsvImportService.label(detectedType)} CSV.',
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    final report = await CsvImportService.validateCsvPreCommit(rawContent, _currentImportType);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'CSV Preview (${CsvImportService.label(_currentImportType)})',
          style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold),
        ),
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
            child: const Text('Cancel', style: TextStyle(fontFamily: 'Lexend')),
          ),
          if (report.invalidRows > 0 || report.duplicateRows > 0)
            TextButton.icon(
              onPressed: () async {
                final errCsv = CsvImportService.generateErrorReportCsv(report);
                await downloadCsvTemplate(content: errCsv, fileName: 'csv_error_report_${DateTime.now().millisecondsSinceEpoch}.csv');
              },
              icon: const Icon(Icons.download),
              label: const Text('Download Errors', style: TextStyle(fontFamily: 'Lexend')),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ElevatedButton.icon(
            onPressed: report.validRows == 0
                ? null
                : () async {
                    Navigator.pop(ctx);
                    if (report.invalidRows > 0 || report.duplicateRows > 0) {
                      // Auto-download errors before importing
                      final errCsv = CsvImportService.generateErrorReportCsv(report);
                      await downloadCsvTemplate(content: errCsv, fileName: 'auto_error_report_${DateTime.now().millisecondsSinceEpoch}.csv');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Error report downloaded. Importing valid rows...'),
                            backgroundColor: Colors.orange,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                    _importSelectedType(rawContent);
                  },
            icon: const Icon(Icons.upload),
            label: Text('Import ${report.validRows} Valid Rows', style: const TextStyle(fontFamily: 'Lexend')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF03045E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewStatBadge(String label, String val, Color color) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(val, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
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
