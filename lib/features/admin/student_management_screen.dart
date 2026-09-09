import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../core/school_classes.dart';
import '../../core/widgets/app_modal_sheet.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../core/widgets/fade_in_and_slide.dart';
import 'package:nfc_manager/nfc_manager.dart';
import '../../services/nfc_tag_reader.dart';
import 'route_stop_picker_screen.dart';

Future<String> _resolveStudentBusId(
  BuildContext context,
  String routeId,
) async {
  final strings = AppLocalizations.of(context);
  final buses = await FirebaseService.getBusesForRoute(routeId);
  if (buses.isEmpty) {
    throw Exception(strings.routeNeedsAssignedBus);
  }
  if (buses.length > 1) {
    throw Exception(strings.routeHasMultipleAssignedBuses);
  }
  return buses.single.id;
}

Future<int?> _pickStudentPickupPoint(
  BuildContext context,
  PlannedRoute route,
  int? initialStopIndex,
) {
  return Navigator.push<int>(
    context,
    MaterialPageRoute(
      builder: (_) => RouteStopPickerScreen(
        route: route,
        initialStopIndex: initialStopIndex,
      ),
    ),
  );
}

InputDecoration _pillFieldDecoration({required String hintText}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(fontFamily: 'Lexend'),
    filled: true,
    fillColor: SchoolWayTheme.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: SchoolWayTheme.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: SchoolWayTheme.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: SchoolWayTheme.navy),
    ),
  );
}

class StudentManagementScreen extends StatefulWidget {
  const StudentManagementScreen({super.key});

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen> {
  final _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  String _searchQuery = '';
  Timer? _debounce;
  final bool _isImportingCsv = false;
  final int _importProgressCurrent = 0;
  final int _importProgressTotal = 0;
  bool _cancelImportRequested = false;
  String _importProgressPhase = 'Preparing import...';

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  List<String> _visibleStudentIds = [];
  bool _isBatchActing = false;
  bool _showSelectedOnly = false;

  void _preserveScrollWhile(VoidCallback mutation) {
    final hadClients = _listScrollController.hasClients;
    final previousOffset = hadClients ? _listScrollController.offset : 0.0;

    setState(mutation);

    if (!hadClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_listScrollController.hasClients) return;
      final max = _listScrollController.position.maxScrollExtent;
      final target = previousOffset.clamp(0.0, max);
      final current = _listScrollController.offset;
      if ((current - target).abs() > 0.5) {
        _listScrollController.jumpTo(target);
      }
    });
  }

  void _exitSelectionMode() {
    _preserveScrollWhile(() {
      _selectionMode = false;
      _selectedIds.clear();
      _showSelectedOnly = false;
    });
  }

  void _toggleSelection(String id) {
    _preserveScrollWhile(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectionMode = true;
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(String id) {
    _preserveScrollWhile(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  bool _allVisibleSelected() {
    if (_visibleStudentIds.isEmpty) return false;
    return _visibleStudentIds.every(_selectedIds.contains);
  }

  void _toggleSelectAllVisibleStudents() {
    if (_visibleStudentIds.isEmpty) return;
    _preserveScrollWhile(() {
      final allSelected = _allVisibleSelected();
      if (allSelected) {
        _selectedIds.removeAll(_visibleStudentIds);
        if (_selectedIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectionMode = true;
        _selectedIds.addAll(_visibleStudentIds);
      }
    });
  }

  void _clearSelectionOnly() {
    _preserveScrollWhile(() {
      _selectedIds.clear();
      _selectionMode = true;
      _showSelectedOnly = false;
    });
  }

  Future<void> _createStudentRecord({
    required String studentId,
    required String firstName,
    required String lastName,
    required String classId,
    required String nfcCardId,
    required List<String> parentAuthUids,
    String? assignedBusId,
    String? assignedRouteId,
    int? pickupStopIndex,
    int? dropoffStopIndex,
    String? status,
  }) async {
    final trimmedStudentId = studentId.trim();
    final trimmedFirstName = firstName.trim();
    final trimmedLastName = lastName.trim();
    final trimmedClassId = classId.trim();
    final trimmedNfcCardId = nfcCardId.trim();

    if (trimmedStudentId.isEmpty ||
        trimmedFirstName.isEmpty ||
        trimmedLastName.isEmpty ||
        trimmedClassId.isEmpty ||
        trimmedNfcCardId.isEmpty) {
      throw Exception('Please fill all required fields');
    }

    if (!kSchoolClassIds.contains(trimmedClassId)) {
      throw Exception('Class must be one of: ${kSchoolClassIds.join(', ')}');
    }

    final documentId = trimmedStudentId.replaceAll('/', '_');

    final existingStudent = await swFirestore
        .collection('students')
        .doc(documentId)
        .get();
    if (existingStudent.exists) {
      throw Exception('A student with this Student ID already exists');
    }

    final existingNfc = await swFirestore
        .collection('students')
        .where('nfcCardId', isEqualTo: trimmedNfcCardId)
        .limit(1)
        .get();
    if (existingNfc.docs.isNotEmpty) {
      throw Exception(
        'This NFC Card ID is already assigned to another student',
      );
    }

    final resolvedStatus = (status ?? '').trim().toLowerCase() == 'inactive'
        ? 'Inactive'
        : 'Active';

    final normalizedParentIds = parentAuthUids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    final routeId = (assignedRouteId ?? '').trim();
    if (routeId.isNotEmpty && pickupStopIndex == null) {
      throw Exception(
        'pickupStop is required when assignedRouteId is provided',
      );
    }

    final newStudent = Student(
      id: documentId,
      studentId: trimmedStudentId,
      firstName: trimmedFirstName,
      lastName: trimmedLastName,
      nfcCardId: trimmedNfcCardId,
      parentAuthUids: normalizedParentIds,
      assignedBusId: (assignedBusId ?? '').trim().isEmpty
          ? null
          : assignedBusId!.trim(),
      assignedRouteId: routeId.isEmpty ? null : routeId,
      pickupStopIndex: pickupStopIndex,
      dropoffStopIndex: dropoffStopIndex,
      status: resolvedStatus,
      classId: trimmedClassId,
      createdAt: DateTime.now(),
    );

    await swFirestore
        .collection('students')
        .doc(documentId)
        .set(newStudent.toFirestore());
  }

  Future<void> _batchStudentAction(String action) async {
    if (_isBatchActing) return;
    final ids = _selectedIds.toList();
    final count = ids.length;
    if (count == 0) return;

    String title;
    String description;
    Color btnColor;
    String btnLabel;

    switch (action) {
      case 'delete':
        title = 'Delete $count student${count > 1 ? 's' : ''}?';
        description = 'This action cannot be undone.';
        btnColor = SchoolWayTheme.danger;
        btnLabel = 'DELETE ALL';
        break;
      case 'disable':
        title = 'Disable $count student${count > 1 ? 's' : ''}?';
        description = 'Selected students will be marked as Inactive.';
        btnColor = SchoolWayTheme.warning;
        btnLabel = 'DISABLE ALL';
        break;
      case 'enable':
        title = 'Enable $count student${count > 1 ? 's' : ''}?';
        description = 'Selected students will be marked as Active.';
        btnColor = SchoolWayTheme.successBright;
        btnLabel = 'ENABLE ALL';
        break;
      default:
        return;
    }

    final confirmed = await showAppModalSheet<bool>(
      context: context,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: SchoolWayTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
                SizedBox(height: 12),
                Text(description, style: TextStyle(fontFamily: 'Lexend')),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: SchoolWayTheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    btnLabel,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    AppLocalizations.of(context).cancel,
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isBatchActing = true);
    final batch = swFirestore.batch();
    final col = swFirestore.collection('students');
    for (final id in ids) {
      final ref = col.doc(id);
      switch (action) {
        case 'delete':
          batch.delete(ref);
          break;
        case 'disable':
          batch.update(ref, {'status': 'Inactive'});
          break;
        case 'enable':
          batch.update(ref, {'status': 'Active'});
          break;
      }
    }

    try {
      await batch.commit();
      if (mounted) {
        _exitSelectionMode();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'delete'
                  ? '$count student${count > 1 ? 's' : ''} deleted'
                  : '$count student${count > 1 ? 's' : ''} ${action}d',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorReporter.userMessage(
                context,
                e,
                StackTrace.current,
                category: 'students',
                message: 'Student operation failed.',
              ),
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBatchActing = false);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isImportingCsv,
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          leading: _selectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _exitSelectionMode,
                )
              : null,
          title: _selectionMode
              ? Text('${_selectedIds.length} selected')
              : Text(AppLocalizations.of(context).studentManagement),
          actions: _selectionMode
              ? [
                  TextButton(
                    onPressed: _isBatchActing || _visibleStudentIds.isEmpty
                        ? null
                        : _toggleSelectAllVisibleStudents,
                    child: Text(
                      _allVisibleSelected() ? 'Deselect All' : 'Select All',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isBatchActing || _selectedIds.isEmpty
                        ? null
                        : _clearSelectionOnly,
                    child: Text(
                      AppLocalizations.of(context).clear,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isBatchActing || _selectedIds.isEmpty
                        ? null
                        : () {
                            _preserveScrollWhile(() {
                              _showSelectedOnly = !_showSelectedOnly;
                            });
                          },
                    child: Text(
                      _showSelectedOnly ? 'Show All' : 'View Selected',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                  ),
                ]
              : [
                  IconButton(
                    icon: Icon(Icons.checklist_outlined),
                    onPressed: () => setState(() => _selectionMode = true),
                    tooltip: AppLocalizations.of(context).selectMultiple,
                  ),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline),
                    onPressed: () => _showAddStudentDialog(context),
                    tooltip: AppLocalizations.of(context).addStudent2,
                  ),
                ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                if (!_selectionMode)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) {
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce = Timer(Duration(milliseconds: 300), () {
                          if (mounted) {
                            setState(() {
                              _searchQuery = value.toLowerCase();
                            });
                          }
                        });
                      },
                      decoration: InputDecoration(
                        hintText: AppLocalizations.of(context).searchStudents,
                        hintStyle: TextStyle(fontFamily: 'Lexend'),
                        prefixIcon: Icon(Icons.search),
                        filled: true,
                        fillColor: SchoolWayTheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  )
                else
                  SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<List<Student>>(
                    stream: FirebaseService.getAllStudents(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: 6,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6.0,
                              ),
                              child: ShimmerLoading(
                                child: ShimmerPlaceholder(
                                  width: double.infinity,
                                  height: 120,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          },
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snapshot.error}',
                            style: TextStyle(fontFamily: 'Lexend'),
                          ),
                        );
                      }

                      var students = snapshot.data ?? [];

                      if (_searchQuery.isNotEmpty) {
                        students = students.where((student) {
                          return student.firstName.toLowerCase().contains(
                                _searchQuery,
                              ) ||
                              student.lastName.toLowerCase().contains(
                                _searchQuery,
                              ) ||
                              student.nfcCardId.toLowerCase().contains(
                                _searchQuery,
                              );
                        }).toList();
                      }

                      if (_selectionMode && _showSelectedOnly) {
                        students = students
                            .where(
                              (student) => _selectedIds.contains(student.id),
                            )
                            .toList();
                      }

                      _visibleStudentIds = students
                          .map((s) => s.id)
                          .toList(growable: false);

                      if (students.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.child_care,
                                size: 64,
                                color: SchoolWayTheme.accent,
                              ),
                              SizedBox(height: 16),
                              Text(
                                AppLocalizations.of(context).noStudentsYet,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showAddStudentDialog(context),
                                icon: Icon(Icons.add),
                                label: Text(
                                  AppLocalizations.of(context).addFirstStudent,
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: SchoolWayTheme.primary,
                                  foregroundColor: SchoolWayTheme.surface,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        children: [
                          if (_selectionMode) _buildSelectAllBar(students),
                          Expanded(
                            child: ListView.builder(
                              key: const PageStorageKey<String>(
                                'student_management_list',
                              ),
                              controller: _listScrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: students.length,
                              itemBuilder: (context, index) {
                                final s = students[index];
                                return FadeInAndSlide(
                                  index: index,
                                  child: _StudentCard(
                                    key: ValueKey(s.id),
                                    student: s,
                                    isSelectionMode: _selectionMode,
                                    isSelected: _selectedIds.contains(s.id),
                                    onLongPress: () =>
                                        _enterSelectionMode(s.id),
                                    onSelectToggle: () =>
                                        _toggleSelection(s.id),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                if (_selectionMode && _selectedIds.isNotEmpty)
                  _buildBatchActionBar(),
              ],
            ),
            if (_isImportingCsv)
              Positioned.fill(
                child: Stack(
                  children: [
                    ModalBarrier(
                      dismissible: false,
                      color: SchoolWayTheme.scrim,
                    ),
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                        decoration: BoxDecoration(
                          color: SchoolWayTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _importProgressPhase,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: SchoolWayTheme.navy,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              '${_importProgressCurrent.clamp(0, _importProgressTotal)} of $_importProgressTotal',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 14,
                                color: SchoolWayTheme.mutedStrong,
                              ),
                            ),
                            SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: _importProgressTotal > 0
                                  ? _importProgressCurrent /
                                        _importProgressTotal
                                  : null,
                              color: SchoolWayTheme.primary,
                              backgroundColor: SchoolWayTheme.borderSubtle,
                            ),
                            SizedBox(height: 12),
                            TextButton(
                              onPressed: _cancelImportRequested
                                  ? null
                                  : () {
                                      setState(() {
                                        _cancelImportRequested = true;
                                        _importProgressPhase =
                                            'Cancel requested, finishing current row...';
                                      });
                                    },
                              child: Text(
                                _cancelImportRequested
                                    ? 'Canceling...'
                                    : 'Cancel Import',
                                style: TextStyle(fontFamily: 'Lexend'),
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

  Widget _buildSelectAllBar(List<Student> students) {
    final allSelected =
        students.isNotEmpty &&
        students.every((s) => _selectedIds.contains(s.id));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            activeColor: SchoolWayTheme.primary,
            onChanged: (_) {
              _preserveScrollWhile(() {
                if (allSelected) {
                  _selectedIds.removeAll(students.map((s) => s.id));
                } else {
                  _selectionMode = true;
                  _selectedIds.addAll(students.map((s) => s.id));
                }
              });
            },
          ),
          Flexible(
            child: Text(
              allSelected ? 'Deselect all' : 'Select all (${students.length})',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14,
                color: SchoolWayTheme.navy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: SchoolWayTheme.surface,
        boxShadow: [
          BoxShadow(
            color: SchoolWayTheme.text.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _StudentBatchBtn(
                icon: Icons.block,
                label: AppLocalizations.of(context).disable,
                color: SchoolWayTheme.warning,
                enabled: !_isBatchActing,
                onTap: () => _batchStudentAction('disable'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _StudentBatchBtn(
                icon: Icons.check_circle_outline,
                label: AppLocalizations.of(context).enable,
                color: SchoolWayTheme.successBright,
                enabled: !_isBatchActing,
                onTap: () => _batchStudentAction('enable'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _StudentBatchBtn(
                icon: Icons.delete_outline,
                label: AppLocalizations.of(context).delete,
                color: SchoolWayTheme.danger,
                enabled: !_isBatchActing,
                onTap: () => _batchStudentAction('delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddStudentDialog(BuildContext context) {
    final studentIdController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final nfcCardIdController = TextEditingController();
    String? selectedRouteId;
    int? selectedStopIndex;
    String? selectedClassId = kSchoolClassIds.first;
    final selectedParentIds = <String>[];
    bool isScanningNfc = false;
    String? nfcScanError;

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: SchoolWayTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 52,
                        height: 4,
                        decoration: BoxDecoration(
                          color: SchoolWayTheme.navy,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(
                      AppLocalizations.of(context).addNewStudent,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        color: SchoolWayTheme.navy,
                      ),
                    ),
                    SizedBox(height: 8),

                    SizedBox(height: 14),
                    TextField(
                      controller: studentIdController,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).studentId,
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: firstNameController,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).firstName2,
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: lastNameController,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).lastName2,
                      ),
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedClassId,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).class2,
                      ),
                      items: kSchoolClassIds
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setModalState(() {
                          selectedClassId = value;
                        });
                      },
                    ),
                    SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: nfcCardIdController,
                            decoration:
                                _pillFieldDecoration(
                                  hintText: AppLocalizations.of(
                                    context,
                                  ).nfcCardId2,
                                ).copyWith(
                                  prefixIcon: Icon(
                                    Icons.nfc,
                                    color: SchoolWayTheme.primary,
                                  ),
                                ),
                          ),
                        ),
                        SizedBox(width: 8),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: isScanningNfc
                                ? () async {
                                    try {
                                      await NfcManager.instance.stopSession();
                                    } catch (e) {
                                      AppLogger.debug(
                                        'nfc',
                                        'NFC stop session handled: $e',
                                      );
                                    }
                                    setModalState(() {
                                      isScanningNfc = false;
                                    });
                                  }
                                : () async {
                                    try {
                                      final isAvailable = await NfcManager
                                          .instance
                                          .checkAvailability();
                                      if (isAvailable !=
                                          NfcAvailability.enabled) {
                                        setModalState(() {
                                          nfcScanError = AppLocalizations.of(
                                            context,
                                          ).nfcNotAvailable;
                                        });
                                        return;
                                      }
                                      setModalState(() {
                                        isScanningNfc = true;
                                        nfcScanError = null;
                                      });
                                      await NfcManager.instance.startSession(
                                        pollingOptions: {
                                          NfcPollingOption.iso14443,
                                        },
                                        onDiscovered: (NfcTag tag) async {
                                          try {
                                            final id =
                                                await readNfcTagIdentifier(tag);
                                            if (id != null) {
                                              setModalState(() {
                                                nfcCardIdController.text = id;
                                                isScanningNfc = false;
                                                nfcScanError = null;
                                              });
                                            } else {
                                              setModalState(() {
                                                nfcScanError =
                                                    AppLocalizations.of(
                                                      context,
                                                    ).nfcScanFailed;
                                                isScanningNfc = false;
                                              });
                                            }
                                          } catch (e) {
                                            AppLogger.debug(
                                              'nfc',
                                              'NFC tag read failed: $e',
                                            );
                                            setModalState(() {
                                              nfcScanError =
                                                  AppLocalizations.of(
                                                    context,
                                                  ).nfcScanFailed;
                                              isScanningNfc = false;
                                            });
                                          } finally {
                                            try {
                                              await NfcManager.instance
                                                  .stopSession();
                                            } catch (e) {
                                              AppLogger.debug(
                                                'nfc',
                                                'NFC finally stop session handled: $e',
                                              );
                                            }
                                          }
                                        },
                                      );
                                    } catch (e) {
                                      AppLogger.debug(
                                        'nfc',
                                        'NFC start session failed: $e',
                                      );
                                      setModalState(() {
                                        nfcScanError = AppLocalizations.of(
                                          context,
                                        ).nfcNotAvailable;
                                        isScanningNfc = false;
                                      });
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isScanningNfc
                                  ? SchoolWayTheme.danger
                                  : SchoolWayTheme.primary,
                              foregroundColor: SchoolWayTheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                            ),
                            icon: isScanningNfc
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: SchoolWayTheme.surface,
                                    ),
                                  )
                                : Icon(Icons.contactless, size: 20),
                            label: Text(
                              isScanningNfc
                                  ? AppLocalizations.of(context).cancelScan
                                  : AppLocalizations.of(context).scanNfcCard,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isScanningNfc) ...[
                      SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: SchoolWayTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: SchoolWayTheme.primary.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.sensors,
                              size: 16,
                              color: SchoolWayTheme.primary,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context).scanningNfcCard,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: SchoolWayTheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (nfcScanError != null) ...[
                      SizedBox(height: 8),
                      Text(
                        nfcScanError!,
                        style: TextStyle(
                          color: SchoolWayTheme.danger,
                          fontFamily: 'Lexend',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    SizedBox(height: 12),
                    StreamBuilder<List<PlannedRoute>>(
                      stream: FirebaseService.getPlannedRoutes(),
                      builder: (context, snapshot) {
                        final routes = snapshot.data ?? const <PlannedRoute>[];
                        final hasSelectedRoute =
                            selectedRouteId != null &&
                            routes.any((r) => r.id == selectedRouteId);
                        final selectedRoute = selectedRouteId == null
                            ? null
                            : routes
                                  .where((r) => r.id == selectedRouteId)
                                  .firstOrNull;
                        final stopCount =
                            selectedRoute?.editableStops.length ?? 0;
                        return Column(
                          children: [
                            DropdownButtonFormField<String>(
                              key: ValueKey<String?>(
                                'add_route_${routes.length}_$selectedRouteId',
                              ),
                              initialValue: hasSelectedRoute
                                  ? selectedRouteId
                                  : null,
                              decoration: _pillFieldDecoration(
                                hintText: AppLocalizations.of(
                                  context,
                                ).plannedRoute3,
                              ),
                              items: routes
                                  .map(
                                    (route) => DropdownMenuItem(
                                      value: route.id,
                                      child: Text(
                                        route.name,
                                        style: TextStyle(fontFamily: 'Lexend'),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) async {
                                final route = routes
                                    .where((route) => route.id == value)
                                    .firstOrNull;
                                setState(() {
                                  selectedRouteId = value;
                                  selectedStopIndex = null;
                                });
                                if (route == null ||
                                    route.editableStops.isEmpty) {
                                  return;
                                }
                                final stopIndex = await _pickStudentPickupPoint(
                                  context,
                                  route,
                                  null,
                                );
                                if (!context.mounted || stopIndex == null) {
                                  return;
                                }
                                setState(() => selectedStopIndex = stopIndex);
                              },
                            ),
                            SizedBox(height: 12),
                            OutlinedButton.icon(
                              key: ValueKey<String?>(
                                'add_stop_${selectedRouteId}_${stopCount}_$selectedStopIndex',
                              ),
                              onPressed: selectedRoute == null
                                  ? null
                                  : () async {
                                      final stopIndex =
                                          await _pickStudentPickupPoint(
                                            context,
                                            selectedRoute,
                                            selectedStopIndex,
                                          );
                                      if (!context.mounted ||
                                          stopIndex == null) {
                                        return;
                                      }
                                      setState(
                                        () => selectedStopIndex = stopIndex,
                                      );
                                    },
                              icon: const Icon(Icons.map_outlined),
                              label: Text(
                                selectedStopIndex == null
                                    ? AppLocalizations.of(
                                        context,
                                      ).studentPickupPointRequired
                                    : AppLocalizations.of(
                                        context,
                                      ).pickupPointNumber(
                                        selectedStopIndex! + 1,
                                      ),
                                style: const TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                            if (selectedRouteId != null)
                              FutureBuilder<List<Bus>>(
                                future: FirebaseService.getBusesForRoute(
                                  selectedRouteId!,
                                ),
                                builder: (context, busSnapshot) {
                                  final buses =
                                      busSnapshot.data ?? const <Bus>[];
                                  if (buses.length != 1) {
                                    return const SizedBox();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).busAssignedAutomatically(
                                        buses.single.busNumber,
                                      ),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        color: SchoolWayTheme.success,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: 16),
                    // Parent Selection
                    StreamBuilder<QuerySnapshot>(
                      stream: swFirestore
                          .collection('users')
                          .where('role', isEqualTo: 'parent')
                          .snapshots(),
                      builder: (context, snapshot) {
                        final parents = snapshot.data?.docs ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLocalizations.of(context).assignedParents,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                color: SchoolWayTheme.navy,
                              ),
                            ),
                            SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: SchoolWayTheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: SchoolWayTheme.border,
                                ),
                              ),
                              child: selectedParentIds.isEmpty
                                  ? Text(
                                      AppLocalizations.of(
                                        context,
                                      ).noParentSelected,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 13,
                                        color: SchoolWayTheme.neutral600,
                                      ),
                                    )
                                  : Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: selectedParentIds.map((pid) {
                                        final matchingParents = parents
                                            .where((doc) => doc.id == pid)
                                            .toList();
                                        final parentEmail =
                                            matchingParents.isEmpty
                                            ? pid
                                            : ((matchingParents.first.data()
                                                          as Map<
                                                            String,
                                                            dynamic
                                                          >?)?['email']
                                                      as String? ??
                                                  pid);
                                        return InputChip(
                                          label: Text(
                                            parentEmail,
                                            style: TextStyle(
                                              fontFamily: 'Lexend',
                                              fontSize: 13,
                                              color: SchoolWayTheme.textStrong,
                                            ),
                                          ),
                                          onDeleted: () {
                                            setState(() {
                                              selectedParentIds.remove(pid);
                                            });
                                          },
                                          backgroundColor:
                                              SchoolWayTheme.surfaceSubtle,
                                          side: BorderSide(
                                            color: SchoolWayTheme.neutralBorder,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          deleteIconColor:
                                              SchoolWayTheme.textStrong,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        );
                                      }).toList(),
                                    ),
                            ),
                            SizedBox(height: 10),
                            SizedBox(
                              height: 46,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final selected = await showAppModalSheet<String>(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: SchoolWayTheme.transparent,
                                    builder: (context) => SafeArea(
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          16,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            12,
                                            20,
                                            20,
                                          ),
                                          decoration: BoxDecoration(
                                            color: SchoolWayTheme.surface,
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                AppLocalizations.of(
                                                  context,
                                                ).selectParent,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontFamily: 'Lexend',
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 24,
                                                ),
                                              ),
                                              SizedBox(height: 12),
                                              SizedBox(
                                                width: double.maxFinite,
                                                child: ListView(
                                                  shrinkWrap: true,
                                                  children: parents.map((doc) {
                                                    final data =
                                                        doc.data()
                                                            as Map<
                                                              String,
                                                              dynamic
                                                            >;
                                                    return ListTile(
                                                      title: Text(
                                                        '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                                            .trim(),
                                                        style: TextStyle(
                                                          fontFamily: 'Lexend',
                                                        ),
                                                      ),
                                                      subtitle: Text(
                                                        data['email'] ?? '',
                                                        style: TextStyle(
                                                          fontFamily: 'Lexend',
                                                        ),
                                                      ),
                                                      onTap: () =>
                                                          Navigator.pop(
                                                            context,
                                                            doc.id,
                                                          ),
                                                    );
                                                  }).toList(),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                  if (selected != null &&
                                      !selectedParentIds.contains(selected)) {
                                    setState(() {
                                      selectedParentIds.add(selected);
                                    });
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: SchoolWayTheme.primary,
                                  side: BorderSide(
                                    color: SchoolWayTheme.primary,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                ),
                                icon: Icon(Icons.add, size: 20),
                                label: Text(
                                  AppLocalizations.of(context).addParent,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (studentIdController.text.isEmpty ||
                              firstNameController.text.isEmpty ||
                              lastNameController.text.isEmpty ||
                              nfcCardIdController.text.isEmpty ||
                              selectedRouteId == null ||
                              selectedStopIndex == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).pleaseFillRequiredFieldsIncludingRouteAnd,
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                              ),
                            );
                            return;
                          }

                          try {
                            final assignedBusId = await _resolveStudentBusId(
                              context,
                              selectedRouteId!,
                            );
                            await _createStudentRecord(
                              studentId: studentIdController.text,
                              firstName: firstNameController.text,
                              lastName: lastNameController.text,
                              classId: selectedClassId ?? '',
                              nfcCardId: nfcCardIdController.text,
                              parentAuthUids: selectedParentIds,
                              assignedBusId: assignedBusId,
                              assignedRouteId: selectedRouteId,
                              pickupStopIndex: selectedStopIndex,
                              dropoffStopIndex: selectedStopIndex,
                              status: 'Active',
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).studentAddedSuccessfully,
                                    style: TextStyle(fontFamily: 'Lexend'),
                                  ),
                                ),
                              );
                            }
                          } catch (error, stackTrace) {
                            if (!context.mounted) return;
                            final errorMessage = ErrorReporter.userMessage(
                              context,
                              error,
                              stackTrace,
                              category: 'students',
                              message: 'Student creation failed.',
                            );

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    errorMessage,
                                    style: TextStyle(fontFamily: 'Lexend'),
                                  ),
                                  backgroundColor: SchoolWayTheme.danger,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SchoolWayTheme.navy,
                          foregroundColor: SchoolWayTheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          AppLocalizations.of(context).addStudent,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        AppLocalizations.of(context).cancel,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          color: SchoolWayTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _studentIsActive(Student s) {
  final st = s.status.trim().toLowerCase();
  return st != 'inactive';
}

class _StudentCard extends StatelessWidget {
  final Student student;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;

  const _StudentCard({
    super.key,
    required this.student,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = _studentIsActive(student);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isSelected ? SchoolWayTheme.primary.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: isSelectionMode
            ? onSelectToggle
            : () => _showStudentDetails(context),
        onLongPress: isSelectionMode ? null : onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (isSelectionMode) ...[
                Checkbox(
                  value: isSelected,
                  activeColor: SchoolWayTheme.primary,
                  onChanged: (_) => onSelectToggle?.call(),
                ),
                SizedBox(width: 4),
              ],
              CircleAvatar(
                radius: 24,
                backgroundColor: SchoolWayTheme.primary.withValues(alpha: 0.2),
                child: Text(
                  student.firstName[0].toUpperCase() +
                      student.lastName[0].toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    color: SchoolWayTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 16),
              // Student Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            student.fullName,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: SchoolWayTheme.muted.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              AppLocalizations.of(context).inactive,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: SchoolWayTheme.muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      'NFC: ${student.nfcCardId}',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14,
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                    if (student.classId != null &&
                        student.classId!.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(
                        'Class: ${student.classId}',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14,
                          color: SchoolWayTheme.primary,
                        ),
                      ),
                    ],
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.people,
                          size: 14,
                          color: SchoolWayTheme.accent,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '${student.parentAuthUids.length} parent(s)',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            color: SchoolWayTheme.primary,
                          ),
                        ),
                        if (student.assignedBusId != null) ...[
                          SizedBox(width: 16),
                          Icon(
                            Icons.directions_bus,
                            size: 14,
                            color: SchoolWayTheme.accent,
                          ),
                          SizedBox(width: 4),
                          FutureBuilder<Bus?>(
                            future: FirebaseService.getBusById(
                              student.assignedBusId!,
                            ),
                            builder: (context, snapshot) {
                              return Text(
                                snapshot.data?.busNumber ?? 'Bus assigned',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 12,
                                  color: SchoolWayTheme.primary,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Actions Menu (same styling as Bus Management)
              Theme(
                data: Theme.of(context).copyWith(
                  splashColor: SchoolWayTheme.transparent,
                  highlightColor: SchoolWayTheme.transparent,
                  hoverColor: SchoolWayTheme.transparent,
                ),
                child: PopupMenuButton<String>(
                  tooltip: AppLocalizations.of(context).studentActions,
                  icon: Icon(Icons.more_vert, color: SchoolWayTheme.textStrong),
                  iconSize: 22,
                  color: SchoolWayTheme.surface,
                  surfaceTintColor: SchoolWayTheme.surface,
                  elevation: 10,
                  shadowColor: SchoolWayTheme.text26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: SchoolWayTheme.accent.withValues(alpha: 0.20),
                    ),
                  ),
                  constraints: BoxConstraints(minWidth: 240),
                  menuPadding: const EdgeInsets.symmetric(vertical: 6),
                  onSelected: (value) => _handleAction(context, value),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: SchoolWayTheme.text,
                          ),
                          SizedBox(width: 12),
                          Text(
                            AppLocalizations.of(context).editDetails,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: SchoolWayTheme.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuDivider(height: 1),
                    PopupMenuItem(
                      value: 'toggle_status',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            isActive ? Icons.block : Icons.check_circle_outline,
                            size: 20,
                            color: SchoolWayTheme.text,
                          ),
                          SizedBox(width: 12),
                          Text(
                            isActive ? 'Disable Student' : 'Enable Student',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: SchoolWayTheme.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuDivider(height: 1),
                    PopupMenuItem(
                      value: 'parents',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 20,
                            color: SchoolWayTheme.text,
                          ),
                          SizedBox(width: 12),
                          Text(
                            AppLocalizations.of(context).manageParents,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: SchoolWayTheme.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuDivider(height: 1),
                    PopupMenuItem(
                      value: 'nfc',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.nfc_outlined,
                            size: 20,
                            color: SchoolWayTheme.text,
                          ),
                          SizedBox(width: 12),
                          Text(
                            AppLocalizations.of(context).updateNfcTag,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: SchoolWayTheme.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuDivider(height: 1),
                    PopupMenuItem(
                      value: 'delete',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: SchoolWayTheme.danger,
                          ),
                          SizedBox(width: 12),
                          Text(
                            AppLocalizations.of(context).deleteStudent,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: SchoolWayTheme.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, String action) {
    switch (action) {
      case 'edit':
        _showEditDialog(context);
        break;
      case 'toggle_status':
        _toggleStudentStatus(context);
        break;
      case 'parents':
        _showManageParentsDialog(context);
        break;
      case 'nfc':
        _showUpdateNfcDialog(context);
        break;
      case 'delete':
        _deleteStudent(context);
        break;
    }
  }

  Future<void> _toggleStudentStatus(BuildContext context) async {
    final currentlyActive = _studentIsActive(student);
    final newStatus = currentlyActive ? 'Inactive' : 'Active';
    try {
      await swFirestore.collection('students').doc(student.id).update({
        'status': newStatus,
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'Active'
                ? 'Student is now active'
                : 'Student has been disabled',
            style: TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorReporter.userMessage(
              context,
              e,
              StackTrace.current,
              category: 'students',
              message: 'Student operation failed.',
            ),
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.danger,
        ),
      );
    }
  }

  void _showStudentDetails(BuildContext context) {
    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: SchoolWayTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    student.fullName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 12),
                  _DetailRow('Student ID', student.studentId),
                  if (student.classId != null && student.classId!.isNotEmpty)
                    _DetailRow('Class', student.classId!),
                  _DetailRow('NFC Card ID', student.nfcCardId),
                  _DetailRow('Status', student.status),
                  if (student.pickupStopIndex != null)
                    _DetailRow(
                      AppLocalizations.of(context).studentPickupPoint,
                      'Stop ${student.pickupStopIndex! + 1}',
                    ),
                  _DetailRow('Parents', '${student.parentAuthUids.length}'),
                  if (student.assignedBusId != null)
                    FutureBuilder<Bus?>(
                      future: FirebaseService.getBusById(
                        student.assignedBusId!,
                      ),
                      builder: (context, snapshot) {
                        return _DetailRow(
                          'Assigned Bus',
                          snapshot.data?.busNumber ?? 'Loading...',
                        );
                      },
                    ),
                  if (student.assignedRouteId != null)
                    FutureBuilder<PlannedRoute?>(
                      future: FirebaseService.getPlannedRouteById(
                        student.assignedRouteId!,
                      ),
                      builder: (context, snapshot) {
                        final name = snapshot.data?.name;
                        return _DetailRow(
                          'Planned route',
                          name ?? student.assignedRouteId!,
                        );
                      },
                    ),
                  SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      AppLocalizations.of(context).close,
                      style: TextStyle(fontFamily: 'Lexend'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    // Similar to add dialog but with existing data
    final firstNameController = TextEditingController(text: student.firstName);
    final lastNameController = TextEditingController(text: student.lastName);
    String? selectedRouteId = student.assignedRouteId;
    int? selectedStopIndex = student.pickupStopIndex;
    var selectedClassId = student.classId != null && student.classId!.isNotEmpty
        ? student.classId!
        : kSchoolClassIds.first;

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: SchoolWayTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        AppLocalizations.of(context).editStudent,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: firstNameController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).firstName,
                          labelStyle: TextStyle(fontFamily: 'Lexend'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: lastNameController,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).lastName,
                          labelStyle: TextStyle(fontFamily: 'Lexend'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedClassId,
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(context).schoolClass,
                          labelStyle: TextStyle(fontFamily: 'Lexend'),
                        ),
                        items: kSchoolClassIds
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c,
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setModalState(() {
                            selectedClassId = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<List<PlannedRoute>>(
                        stream: FirebaseService.getPlannedRoutes(),
                        builder: (context, snapshot) {
                          final routes =
                              snapshot.data ?? const <PlannedRoute>[];
                          final hasSelectedRoute =
                              selectedRouteId != null &&
                              routes.any((r) => r.id == selectedRouteId);
                          final selectedRoute = selectedRouteId == null
                              ? null
                              : routes
                                    .where((r) => r.id == selectedRouteId)
                                    .firstOrNull;
                          final stopCount =
                              selectedRoute?.editableStops.length ?? 0;
                          return Column(
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey<String?>(
                                  'edit_route_${routes.length}_$selectedRouteId',
                                ),
                                initialValue: hasSelectedRoute
                                    ? selectedRouteId
                                    : null,
                                decoration: InputDecoration(
                                  labelText: AppLocalizations.of(
                                    context,
                                  ).plannedRoute2,
                                  labelStyle: TextStyle(fontFamily: 'Lexend'),
                                ),
                                items: routes
                                    .map(
                                      (route) => DropdownMenuItem(
                                        value: route.id,
                                        child: Text(
                                          route.name,
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) async {
                                  final route = routes
                                      .where((route) => route.id == value)
                                      .firstOrNull;
                                  setModalState(() {
                                    selectedRouteId = value;
                                    selectedStopIndex = null;
                                  });
                                  if (route == null ||
                                      route.editableStops.isEmpty) {
                                    return;
                                  }
                                  final stopIndex =
                                      await _pickStudentPickupPoint(
                                        context,
                                        route,
                                        null,
                                      );
                                  if (!context.mounted || stopIndex == null) {
                                    return;
                                  }
                                  setModalState(
                                    () => selectedStopIndex = stopIndex,
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                key: ValueKey<String?>(
                                  'edit_stop_${selectedRouteId}_${stopCount}_$selectedStopIndex',
                                ),
                                onPressed: selectedRoute == null
                                    ? null
                                    : () async {
                                        final stopIndex =
                                            await _pickStudentPickupPoint(
                                              context,
                                              selectedRoute,
                                              selectedStopIndex,
                                            );
                                        if (!context.mounted ||
                                            stopIndex == null) {
                                          return;
                                        }
                                        setModalState(
                                          () => selectedStopIndex = stopIndex,
                                        );
                                      },
                                icon: const Icon(Icons.map_outlined),
                                label: Text(
                                  selectedStopIndex == null
                                      ? AppLocalizations.of(
                                          context,
                                        ).studentPickupPointRequired
                                      : AppLocalizations.of(
                                          context,
                                        ).pickupPointNumber(
                                          selectedStopIndex! + 1,
                                        ),
                                  style: const TextStyle(fontFamily: 'Lexend'),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              if (selectedRouteId == null ||
                                  selectedStopIndex == null) {
                                throw Exception(
                                  AppLocalizations.of(
                                    context,
                                  ).studentPickupPointRequired,
                                );
                              }
                              final assignedBusId = await _resolveStudentBusId(
                                context,
                                selectedRouteId!,
                              );
                              await swFirestore
                                  .collection('students')
                                  .doc(student.id)
                                  .update({
                                    'firstName': firstNameController.text,
                                    'lastName': lastNameController.text,
                                    'classId': selectedClassId,
                                    'assignedRouteId': selectedRouteId,
                                    'assignedBusId': assignedBusId,
                                    'pickupStopIndex': selectedStopIndex,
                                    'dropoffStopIndex': selectedStopIndex,
                                  });
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).studentUpdated,
                                      style: TextStyle(fontFamily: 'Lexend'),
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Error: $e',
                                      style: TextStyle(fontFamily: 'Lexend'),
                                    ),
                                    backgroundColor: SchoolWayTheme.danger,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SchoolWayTheme.navy,
                            foregroundColor: SchoolWayTheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppLocalizations.of(context).save2,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          AppLocalizations.of(context).cancel,
                          style: TextStyle(fontFamily: 'Lexend'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showManageParentsDialog(BuildContext context) {
    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => _ManageParentsDialog(student: student),
    );
  }

  void _showUpdateNfcDialog(BuildContext context) {
    final nfcController = TextEditingController(text: student.nfcCardId);
    bool isScanning = false;
    String? scanError;

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: SchoolWayTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLocalizations.of(context).updateNfcTagId,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: nfcController,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context).nfcCardId,
                      labelStyle: TextStyle(fontFamily: 'Lexend'),
                    ),
                  ),
                  if (scanError != null) ...[
                    SizedBox(height: 8),
                    Text(
                      scanError!,
                      style: TextStyle(
                        color: SchoolWayTheme.danger,
                        fontFamily: 'Lexend',
                        fontSize: 12,
                      ),
                    ),
                  ],
                  SizedBox(height: 16),
                  if (isScanning)
                    Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text(
                            AppLocalizations.of(context).pleaseTapNfcCard,
                            style: TextStyle(fontFamily: 'Lexend'),
                          ),
                        ],
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final isAvailable = await NfcManager.instance
                              .checkAvailability();
                          if (isAvailable != NfcAvailability.enabled) {
                            setModalState(() {
                              scanError = 'NFC is not available on this device';
                            });
                            return;
                          }
                          setModalState(() {
                            isScanning = true;
                            scanError = null;
                          });
                          await NfcManager.instance.startSession(
                            pollingOptions: {NfcPollingOption.iso14443},
                            onDiscovered: (NfcTag tag) async {
                              try {
                                final id = await readNfcTagIdentifier(tag);
                                if (id != null) {
                                  setModalState(() {
                                    nfcController.text = id;
                                    isScanning = false;
                                  });
                                } else {
                                  setModalState(() {
                                    scanError = 'Could not read NFC tag';
                                    isScanning = false;
                                  });
                                }
                              } catch (e) {
                                setModalState(() {
                                  scanError = 'Error reading tag: $e';
                                  isScanning = false;
                                });
                              } finally {
                                await NfcManager.instance.stopSession();
                              }
                            },
                          );
                        } catch (e) {
                          setModalState(() {
                            scanError = 'Failed to start NFC: $e';
                            isScanning = false;
                          });
                        }
                      },
                      icon: Icon(Icons.nfc),
                      label: Text(
                        AppLocalizations.of(context).scanNfcTag,
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                  SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isScanning
                          ? null
                          : () async {
                              try {
                                final trimmedNfc = nfcController.text.trim();
                                if (trimmedNfc.isEmpty) {
                                  throw Exception(
                                    'NFC Card ID cannot be empty',
                                  );
                                }

                                final existingNfc = await swFirestore
                                    .collection('students')
                                    .where('nfcCardId', isEqualTo: trimmedNfc)
                                    .limit(1)
                                    .get();

                                if (existingNfc.docs.isNotEmpty &&
                                    existingNfc.docs.first.id != student.id) {
                                  throw Exception(
                                    'This NFC Card ID is already assigned to another student',
                                  );
                                }

                                await swFirestore
                                    .collection('students')
                                    .doc(student.id)
                                    .update({'nfcCardId': trimmedNfc});
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLocalizations.of(
                                          context,
                                        ).nfcTagUpdated,
                                        style: TextStyle(fontFamily: 'Lexend'),
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Error: $e',
                                        style: TextStyle(fontFamily: 'Lexend'),
                                      ),
                                      backgroundColor: SchoolWayTheme.danger,
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SchoolWayTheme.navy,
                        foregroundColor: SchoolWayTheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context).update,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (isScanning) {
                        try {
                          await NfcManager.instance.stopSession();
                        } catch (error, stackTrace) {
                          AppLogger.warning(
                            'data',
                            'Malformed or unavailable optional data was ignored.',
                            error: error,
                            stackTrace: stackTrace,
                          );
                        }
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: Text(
                      AppLocalizations.of(context).cancel,
                      style: TextStyle(fontFamily: 'Lexend'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _deleteStudent(BuildContext context) async {
    final confirmed = await showAppModalSheet<bool>(
      context: context,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: SchoolWayTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppLocalizations.of(context).deleteStudent2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Delete ${student.fullName}? This action cannot be undone.',
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
                SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SchoolWayTheme.danger,
                      foregroundColor: SchoolWayTheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.of(context).delete2,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    AppLocalizations.of(context).cancel,
                    style: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed == true) {
      try {
        await swFirestore.collection('students').doc(student.id).delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).studentDeleted,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error: $e',
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: SchoolWayTheme.danger,
            ),
          );
        }
      }
    }
  }
}

class _AssignBusDialog extends StatefulWidget {
  final Student student;

  const _AssignBusDialog({required this.student});

  @override
  State<_AssignBusDialog> createState() => _AssignBusDialogState();
}

class _AssignBusDialogState extends State<_AssignBusDialog> {
  late String? selectedBusId;

  @override
  void initState() {
    super.initState();
    selectedBusId = widget.student.assignedBusId;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: SchoolWayTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: StreamBuilder<List<Bus>>(
            stream: FirebaseService.getBuses(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  width: 200,
                  height: 100,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: SchoolWayTheme.primary,
                    ),
                  ),
                );
              }

              final buses = snapshot.data ?? [];
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppLocalizations.of(context).assignBus,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        color: SchoolWayTheme.navy,
                      ),
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedBusId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).bus,
                        labelStyle: TextStyle(fontFamily: 'Lexend'),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            AppLocalizations.of(context).noBusUnassign,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        ...buses.map(
                          (bus) => DropdownMenuItem(
                            value: bus.id,
                            child: Text(
                              '${bus.busNumber} • ${bus.licensePlate}',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => selectedBusId = value),
                    ),
                    if (selectedBusId != null) ...[
                      SizedBox(height: 12),
                      _BusCapacityInfo(
                        busId: selectedBusId!,
                        studentId: widget.student.id,
                      ),
                    ],
                    SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => _assignBus(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SchoolWayTheme.navy,
                          foregroundColor: SchoolWayTheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context).assign,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        AppLocalizations.of(context).cancel,
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _assignBus(BuildContext context) async {
    try {
      await FirebaseService.applyStudentBusAssignment(
        studentId: widget.student.id,
        assignedBusId: selectedBusId,
      );
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selectedBusId != null
                  ? 'Bus assigned successfully'
                  : 'Bus unassigned',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ErrorReporter.userMessage(
                context,
                e,
                StackTrace.current,
                category: 'students',
                message: 'Student operation failed.',
              ),
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.danger,
          ),
        );
      }
    }
  }
}

class _BusCapacityInfo extends StatelessWidget {
  final String busId;
  final String studentId;

  const _BusCapacityInfo({required this.busId, required this.studentId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Bus?>(
      future: FirebaseService.getBusById(busId),
      builder: (context, busSnapshot) {
        final bus = busSnapshot.data;
        if (bus == null) return const SizedBox.shrink();

        return StreamBuilder<QuerySnapshot>(
          stream: swFirestore
              .collection('students')
              .where('assignedBusId', isEqualTo: bus.id)
              .snapshots(),
          builder: (context, studentsSnapshot) {
            final allStudentsInBus = studentsSnapshot.data?.docs ?? [];

            final isStudentAlreadyInBus = allStudentsInBus.any(
              (doc) => doc.id == studentId,
            );
            final currentCount = allStudentsInBus.length;
            final isOverCapacity = isStudentAlreadyInBus
                ? false
                : currentCount >= bus.capacity;

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isOverCapacity
                    ? SchoolWayTheme.danger.withValues(alpha: 0.1)
                    : SchoolWayTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    isOverCapacity ? Icons.warning : Icons.info_outline,
                    size: 16,
                    color: isOverCapacity
                        ? SchoolWayTheme.danger
                        : SchoolWayTheme.primary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOverCapacity
                          ? 'Bus is at full capacity ($currentCount/${bus.capacity})'
                          : isStudentAlreadyInBus
                          ? 'Student already in this bus ($currentCount/${bus.capacity})'
                          : 'Current: $currentCount/${bus.capacity} students',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12,
                        color: isOverCapacity
                            ? SchoolWayTheme.danger
                            : SchoolWayTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ManageParentsDialog extends StatefulWidget {
  final Student student;

  const _ManageParentsDialog({required this.student});

  @override
  State<_ManageParentsDialog> createState() => _ManageParentsDialogState();
}

class _ManageParentsDialogState extends State<_ManageParentsDialog> {
  late List<String> parentAuthUids;

  @override
  void initState() {
    super.initState();
    parentAuthUids = List.from(widget.student.parentAuthUids);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: SchoolWayTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppLocalizations.of(context).manageParents,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                ),
              ),
              SizedBox(height: 8),
              ...parentAuthUids.map(
                (pid) => FutureBuilder<Map<String, dynamic>?>(
                  future: FirebaseService.getUserData(pid),
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    return ListTile(
                      leading: Icon(Icons.person),
                      title: Text(
                        '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'
                            .trim(),
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                      subtitle: Text(
                        data?['email'] ?? pid,
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.remove_circle,
                          color: SchoolWayTheme.danger,
                        ),
                        onPressed: () =>
                            setState(() => parentAuthUids.remove(pid)),
                      ),
                    );
                  },
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final selected = await _selectParent(context);
                  if (selected != null && !parentAuthUids.contains(selected)) {
                    setState(() => parentAuthUids.add(selected));
                  }
                },
                icon: Icon(Icons.add),
                label: Text(
                  AppLocalizations.of(context).addParent,
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SchoolWayTheme.primary,
                  foregroundColor: SchoolWayTheme.surface,
                ),
              ),
              SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      await swFirestore
                          .collection('students')
                          .doc(widget.student.id)
                          .update({'parentAuthUids': parentAuthUids});
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              AppLocalizations.of(context).parentsUpdated,
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Error: $e',
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                            backgroundColor: SchoolWayTheme.danger,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SchoolWayTheme.navy,
                    foregroundColor: SchoolWayTheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context).save2,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  AppLocalizations.of(context).cancel,
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _selectParent(BuildContext context) async {
    return showAppModalSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: SchoolWayTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: swFirestore
                  .collection('users')
                  .where('role', isEqualTo: 'parent')
                  .snapshots(),
              builder: (context, snapshot) {
                final parents = snapshot.data?.docs ?? [];
                return ListView(
                  shrinkWrap: true,
                  children: parents.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      leading: Icon(Icons.person),
                      title: Text(
                        '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                            .trim(),
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                      subtitle: Text(
                        data['email'] ?? '',
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                      onTap: () => Navigator.pop(context, doc.id),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontFamily: 'Lexend')),
          ),
        ],
      ),
    );
  }
}

class _StudentBatchBtn extends StatelessWidget {
  const _StudentBatchBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? color.withValues(alpha: 0.1)
          : SchoolWayTheme.muted.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: enabled ? color : SchoolWayTheme.muted,
                size: 22,
              ),
              SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabled ? color : SchoolWayTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
