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

InputDecoration _pillFieldDecoration({required String hintText}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(fontFamily: 'Lexend'),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
  );
}

String _plannedStopLabel(RouteWaypoint waypoint, int index) {
  final lat = waypoint.latitude.toStringAsFixed(5);
  final lng = waypoint.longitude.toStringAsFixed(5);
  return 'Stop ${index + 1} ($lat, $lng)';
}

List<String> _plannedStopLabels(PlannedRoute route) {
  // Use editable stops (map pins), not `waypoints` (OSRM polyline geometry).
  return route.editableStops
      .asMap()
      .entries
      .map((entry) => _plannedStopLabel(entry.value, entry.key))
      .toList();
}

/// Planned Stop menu items. Prepend [currentLabel] when it is not on the route so
/// edit forms still show legacy saves (e.g. plain text) until the admin re-picks.
List<String> _plannedStopDropdownItems(
  PlannedRoute? route,
  String? currentLabel,
) {
  final opts = route == null ? const <String>[] : _plannedStopLabels(route);
  final t = currentLabel?.trim();
  if (t != null && t.isNotEmpty && !opts.contains(t)) {
    return <String>[t, ...opts];
  }
  return List<String>.from(opts);
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
  List<String> _visibleStudentIds = const [];
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
    required List<String> parentIds,
    String? assignedBusId,
    String? assignedRouteId,
    String? pickupStop,
    String? dropoffStop,
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
      throw Exception('This NFC Card ID is already assigned to another student');
    }

    final resolvedStatus =
        (status ?? '').trim().toLowerCase() == 'inactive' ? 'Inactive' : 'Active';

    final normalizedParentIds = parentIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    final routeId = (assignedRouteId ?? '').trim();
    final stop = (pickupStop ?? '').trim();
    final dropoff = (dropoffStop ?? '').trim();
    if (routeId.isNotEmpty && stop.isEmpty) {
      throw Exception('pickupStop is required when assignedRouteId is provided');
    }

    final newStudent = Student(
      id: documentId,
      studentId: trimmedStudentId,
      firstName: trimmedFirstName,
      lastName: trimmedLastName,
      nfcCardId: trimmedNfcCardId,
      parentIds: normalizedParentIds,
      assignedBusId: (assignedBusId ?? '').trim().isEmpty
          ? null
          : assignedBusId!.trim(),
      assignedRouteId: routeId.isEmpty ? null : routeId,
      pickupStop: stop.isEmpty ? null : stop,
      dropoffStop: dropoff.isEmpty ? null : dropoff,
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
        btnColor = Colors.red;
        btnLabel = 'DELETE ALL';
        break;
      case 'disable':
        title = 'Disable $count student${count > 1 ? 's' : ''}?';
        description = 'Selected students will be marked as Inactive.';
        btnColor = const Color(0xFFFF9800);
        btnLabel = 'DISABLE ALL';
        break;
      case 'enable':
        title = 'Enable $count student${count > 1 ? 's' : ''}?';
        description = 'Selected students will be marked as Active.';
        btnColor = const Color(0xFF4CAF50);
        btnLabel = 'ENABLE ALL';
        break;
      default:
        return;
    }

    final confirmed = await showAppModalSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.bold,
                        fontSize: 22)),
                const SizedBox(height: 12),
                Text(description,
                    style: const TextStyle(fontFamily: 'Lexend')),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(btnLabel,
                      style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel',
                      style: TextStyle(fontFamily: 'Lexend')),
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
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e',
                style: const TextStyle(fontFamily: 'Lexend')),
            backgroundColor: Colors.red,
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
      backgroundColor: const Color(0xFFCAF0F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFCAF0F8),
        elevation: 0,
        foregroundColor: const Color(0xFF03045E),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: _selectionMode
            ? Text(
                '${_selectedIds.length} selected',
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: Color(0xFF03045E),
                ),
              )
            : const Text(
                'Student Management',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: Color(0xFF03045E),
                ),
              ),
        actions: _selectionMode
            ? [
                TextButton(
                  onPressed: _isBatchActing || _visibleStudentIds.isEmpty
                      ? null
                      : _toggleSelectAllVisibleStudents,
                  child: Text(
                    _allVisibleSelected() ? 'Deselect All' : 'Select All',
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      color: Color(0xFF0077B6),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isBatchActing || _selectedIds.isEmpty
                      ? null
                      : _clearSelectionOnly,
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      color: Color(0xFF0077B6),
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
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      color: Color(0xFF0077B6),
                    ),
                  ),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.checklist_outlined),
                  onPressed: () => setState(() => _selectionMode = true),
                  tooltip: 'Select multiple',
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _showAddStudentDialog(context),
                  tooltip: 'Add Student',
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
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    }
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search students...',
                  hintStyle: const TextStyle(fontFamily: 'Lexend'),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 8),
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
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: ShimmerLoading(
                          child: ShimmerPlaceholder(
                            width: double.infinity,
                            height: 120,
                            borderRadius: BorderRadius.circular(16),
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
                      style: const TextStyle(fontFamily: 'Lexend'),
                    ),
                  );
                }

                var students = snapshot.data ?? [];

                if (_searchQuery.isNotEmpty) {
                  students = students.where((student) {
                    return student.firstName.toLowerCase().contains(
                          _searchQuery,
                        ) ||
                        student.lastName.toLowerCase().contains(_searchQuery) ||
                        student.nfcCardId.toLowerCase().contains(_searchQuery);
                  }).toList();
                }

                if (_selectionMode && _showSelectedOnly) {
                  students = students
                      .where((student) => _selectedIds.contains(student.id))
                      .toList();
                }

                _visibleStudentIds =
                    students.map((s) => s.id).toList(growable: false);

                if (students.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.child_care,
                          size: 64,
                          color: Color(0xFF00B4D8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No students yet',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showAddStudentDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text(
                            'Add First Student',
                            style: TextStyle(fontFamily: 'Lexend'),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0077B6),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    if (_selectionMode)
                      _buildSelectAllBar(students),
                    Expanded(
                      child: ListView.builder(
                        key: const PageStorageKey<String>('student_management_list'),
                        controller: _listScrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                              onLongPress: () => _enterSelectionMode(s.id),
                              onSelectToggle: () => _toggleSelection(s.id),
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
                  const ModalBarrier(dismissible: false, color: Color(0x88000000)),
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
                            _importProgressPhase,
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
                            '${_importProgressCurrent.clamp(0, _importProgressTotal)} of $_importProgressTotal',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: _importProgressTotal > 0
                                ? _importProgressCurrent / _importProgressTotal
                                : null,
                            color: const Color(0xFF0077B6),
                            backgroundColor: const Color(0xFFE2E8F0),
                          ),
                          const SizedBox(height: 12),
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

  Widget _buildSelectAllBar(List<Student> students) {
    final allSelected =
        students.isNotEmpty && students.every((s) => _selectedIds.contains(s.id));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            activeColor: const Color(0xFF0077B6),
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
          Text(
            allSelected ? 'Deselect all' : 'Select all (${students.length})',
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14,
              color: Color(0xFF03045E),
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
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
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
                label: 'Disable',
                color: const Color(0xFFFF9800),
                enabled: !_isBatchActing,
                onTap: () => _batchStudentAction('disable'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StudentBatchBtn(
                icon: Icons.check_circle_outline,
                label: 'Enable',
                color: const Color(0xFF4CAF50),
                enabled: !_isBatchActing,
                onTap: () => _batchStudentAction('enable'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StudentBatchBtn(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: Colors.red,
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
    String? selectedBusId;
    String? selectedRouteId;
    String? selectedStopLabel;
    String? selectedClassId = kSchoolClassIds.first;
    final selectedParentIds = <String>[];

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
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
                          color: const Color(0xFF03045E),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Add New Student',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        color: Color(0xFF03045E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bulk CSV header: studentId,firstName,lastName,classId,nfcCardId,parentIds,assignedBusId,assignedRouteId,pickupStop,status',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: studentIdController,
                      decoration: _pillFieldDecoration(
                        hintText: 'Student ID *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: firstNameController,
                      decoration: _pillFieldDecoration(
                        hintText: 'First Name *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: lastNameController,
                      decoration: _pillFieldDecoration(hintText: 'Last Name *'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedClassId,
                      decoration: _pillFieldDecoration(hintText: 'Class *'),
                      items: kSchoolClassIds
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                style: const TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedClassId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nfcCardIdController,
                      decoration: _pillFieldDecoration(
                        hintText: 'NFC Card ID *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Bus Selection
                    StreamBuilder<List<Bus>>(
                      stream: FirebaseService.getBuses(),
                      builder: (context, snapshot) {
                        final buses = snapshot.data ?? [];
                        return DropdownButtonFormField<String>(
                          initialValue: selectedBusId,
                          decoration: _pillFieldDecoration(
                            hintText: 'Assigned Bus',
                          ),
                          items: buses
                              .map(
                                (bus) => DropdownMenuItem(
                                  value: bus.id,
                                  child: Text(
                                    bus.busNumber,
                                    style: const TextStyle(
                                      fontFamily: 'Lexend',
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedBusId = value;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<List<PlannedRoute>>(
                      stream: FirebaseService.getPlannedRoutes(),
                      builder: (context, snapshot) {
                        final routes = snapshot.data ?? const <PlannedRoute>[];
                        final hasSelectedRoute = selectedRouteId != null &&
                            routes.any((r) => r.id == selectedRouteId);
                        final selectedRoute = selectedRouteId == null
                            ? null
                            : routes
                                  .where((r) => r.id == selectedRouteId)
                                  .firstOrNull;
                        final stopItems = _plannedStopDropdownItems(
                          selectedRoute,
                          selectedStopLabel,
                        );
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
                                hintText: 'Planned Route *',
                              ),
                              items: routes
                                  .map(
                                    (route) => DropdownMenuItem(
                                      value: route.id,
                                      child: Text(
                                        route.name,
                                        style: const TextStyle(
                                          fontFamily: 'Lexend',
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  selectedRouteId = value;
                                  final route = routes
                                      .where((r) => r.id == value)
                                      .firstOrNull;
                                  final options = route == null
                                      ? const <String>[]
                                      : _plannedStopLabels(route);
                                  selectedStopLabel = options.isEmpty
                                      ? null
                                      : options.first;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              key: ValueKey<String?>(
                                'add_stop_${selectedRouteId}_${stopItems.length}_$selectedStopLabel',
                              ),
                              initialValue: selectedRoute != null &&
                                      selectedStopLabel != null &&
                                      stopItems.contains(selectedStopLabel)
                                  ? selectedStopLabel
                                  : null,
                              decoration: _pillFieldDecoration(
                                hintText: 'Planned Stop *',
                              ),
                              items: stopItems
                                  .map(
                                    (stop) => DropdownMenuItem(
                                      value: stop,
                                      child: Text(
                                        stop,
                                        style: const TextStyle(
                                          fontFamily: 'Lexend',
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: selectedRoute == null
                                  ? null
                                  : (value) {
                                      setState(() {
                                        selectedStopLabel = value;
                                      });
                                    },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    // Parent Selection
                    StreamBuilder<QuerySnapshot>(
                      stream: swFirestore
                          .collection('users')
                          .where('role', isEqualTo: 'Parent')
                          .snapshots(),
                      builder: (context, snapshot) {
                        final parents = snapshot.data?.docs ?? [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Assigned Parents:',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF03045E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(0xFFE4E9F0),
                                ),
                              ),
                              child: selectedParentIds.isEmpty
                                  ? const Text(
                                      'No parent selected',
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 13,
                                        color: Color(0xFF6B7280),
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
                                            style: const TextStyle(
                                              fontFamily: 'Lexend',
                                              fontSize: 13,
                                              color: Color(0xFF1F2937),
                                            ),
                                          ),
                                          onDeleted: () {
                                            setState(() {
                                              selectedParentIds.remove(pid);
                                            });
                                          },
                                          backgroundColor: const Color(
                                            0xFFF8FAFC,
                                          ),
                                          side: const BorderSide(
                                            color: Color(0xFFD1D5DB),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          deleteIconColor: const Color(
                                            0xFF374151,
                                          ),
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        );
                                      }).toList(),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 46,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final selected = await showAppModalSheet<String>(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
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
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              24,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              const Text(
                                                'Select Parent',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontFamily: 'Lexend',
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 24,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
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
                                                        style: const TextStyle(
                                                          fontFamily: 'Lexend',
                                                        ),
                                                      ),
                                                      subtitle: Text(
                                                        data['email'] ?? '',
                                                        style: const TextStyle(
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
                                  foregroundColor: const Color(0xFF0077B6),
                                  side: const BorderSide(
                                    color: Color(0xFF0077B6),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                ),
                                icon: const Icon(Icons.add, size: 20),
                                label: const Text(
                                  'Add Parent',
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
                              selectedStopLabel == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please fill required fields, including route and stop',
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                              ),
                            );
                            return;
                          }

                          try {
                            await _createStudentRecord(
                              studentId: studentIdController.text,
                              firstName: firstNameController.text,
                              lastName: lastNameController.text,
                              classId: selectedClassId ?? '',
                              nfcCardId: nfcCardIdController.text,
                              parentIds: selectedParentIds,
                              assignedBusId: selectedBusId,
                              assignedRouteId: selectedRouteId,
                              pickupStop: selectedStopLabel,
                              dropoffStop: null,
                              status: 'Active',
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Student added successfully',
                                    style: TextStyle(fontFamily: 'Lexend'),
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            String errorMessage =
                                'An error occurred while adding the student';

                            if (e.toString().contains('already exists')) {
                              errorMessage =
                                  'A student with this ID already exists. Please use a different Student ID.';
                            } else {
                              errorMessage = 'Error: ${e.toString()}';
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    errorMessage,
                                    style: const TextStyle(
                                      fontFamily: 'Lexend',
                                    ),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF03045E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'ADD STUDENT',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          color: Color(0xFF0077B6),
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
      color: isSelected ? const Color(0xFF0077B6).withValues(alpha: 0.08) : null,
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
                  activeColor: const Color(0xFF0077B6),
                  onChanged: (_) => onSelectToggle?.call(),
                ),
                const SizedBox(width: 4),
              ],
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF0077B6).withValues(alpha: 0.2),
                child: Text(
                  student.firstName[0].toUpperCase() +
                      student.lastName[0].toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Lexend',
                    color: Color(0xFF0077B6),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
                            style: const TextStyle(
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
                              color: Colors.grey.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'INACTIVE',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'NFC: ${student.nfcCardId}',
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14,
                        color: Color(0xFF0077B6),
                      ),
                    ),
                    if (student.classId != null &&
                        student.classId!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Class: ${student.classId}',
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14,
                          color: Color(0xFF0077B6),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.people,
                          size: 14,
                          color: const Color(0xFF00B4D8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${student.parentIds.length} parent(s)',
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12,
                            color: Color(0xFF0077B6),
                          ),
                        ),
                        if (student.assignedBusId != null) ...[
                          const SizedBox(width: 16),
                          Icon(
                            Icons.directions_bus,
                            size: 14,
                            color: const Color(0xFF00B4D8),
                          ),
                          const SizedBox(width: 4),
                          FutureBuilder<Bus?>(
                            future: FirebaseService.getBusById(
                              student.assignedBusId!,
                            ),
                            builder: (context, snapshot) {
                              return Text(
                                snapshot.data?.busNumber ?? 'Bus assigned',
                                style: const TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 12,
                                  color: Color(0xFF0077B6),
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
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                ),
                child: PopupMenuButton<String>(
                  tooltip: 'Student actions',
                  icon: const Icon(Icons.more_vert, color: Color(0xFF1F2937)),
                  iconSize: 22,
                  color: Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 10,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: const Color(0xFF00B4D8).withValues(alpha: 0.20),
                    ),
                  ),
                  constraints: const BoxConstraints(minWidth: 240),
                  menuPadding: const EdgeInsets.symmetric(vertical: 6),
                  onSelected: (value) => _handleAction(context, value),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.edit_outlined,
                            size: 20,
                            color: Color(0xFF111827),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Edit Details',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    PopupMenuItem(
                      value: 'toggle_status',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            isActive ? Icons.block : Icons.check_circle_outline,
                            size: 20,
                            color: const Color(0xFF111827),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            isActive ? 'Disable Student' : 'Enable Student',
                            style: const TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    const PopupMenuItem(
                      value: 'parents',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 20,
                            color: Color(0xFF111827),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Manage Parents',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    const PopupMenuItem(
                      value: 'nfc',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.nfc_outlined,
                            size: 20,
                            color: Color(0xFF111827),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Update NFC Tag',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    const PopupMenuItem(
                      value: 'bus',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.directions_bus_outlined,
                            size: 20,
                            color: Color(0xFF111827),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Assign Bus',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(height: 1),
                    const PopupMenuItem(
                      value: 'delete',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: Colors.red,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Delete Student',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.red,
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
      case 'bus':
        _showAssignBusDialog(context);
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
      await swFirestore
          .collection('students')
          .doc(student.id)
          .update({'status': newStatus});
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'Active'
                ? 'Student is now active'
                : 'Student has been disabled',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showStudentDetails(BuildContext context) {
    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    student.fullName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DetailRow('Student ID', student.studentId),
                  if (student.classId != null && student.classId!.isNotEmpty)
                    _DetailRow('Class', student.classId!),
                  _DetailRow('NFC Card ID', student.nfcCardId),
                  _DetailRow('Status', student.status),
                  if (student.pickupStop != null)
                    _DetailRow('Assigned Stop', student.pickupStop!),
                  _DetailRow('Parents', '${student.parentIds.length}'),
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
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Close',
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
    String? selectedStopLabel = student.pickupStop;
    var selectedClassId = student.classId != null && student.classId!.isNotEmpty
        ? student.classId!
        : kSchoolClassIds.first;

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Edit Student',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: firstNameController,
                        decoration: const InputDecoration(
                          labelText: 'First Name',
                          labelStyle: TextStyle(fontFamily: 'Lexend'),
                        ),
                      ),
                      TextField(
                        controller: lastNameController,
                        decoration: const InputDecoration(
                          labelText: 'Last Name',
                          labelStyle: TextStyle(fontFamily: 'Lexend'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedClassId,
                        decoration: const InputDecoration(
                          labelText: 'Class',
                          labelStyle: TextStyle(fontFamily: 'Lexend'),
                        ),
                        items: kSchoolClassIds
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  c,
                                  style: const TextStyle(fontFamily: 'Lexend'),
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
                      const SizedBox(height: 8),
                      StreamBuilder<List<PlannedRoute>>(
                        stream: FirebaseService.getPlannedRoutes(),
                        builder: (context, snapshot) {
                          final routes = snapshot.data ?? const <PlannedRoute>[];
                          final hasSelectedRoute = selectedRouteId != null &&
                              routes.any((r) => r.id == selectedRouteId);
                          final selectedRoute = selectedRouteId == null
                              ? null
                              : routes
                                    .where((r) => r.id == selectedRouteId)
                                    .firstOrNull;
                          final stopItems = _plannedStopDropdownItems(
                            selectedRoute,
                            selectedStopLabel,
                          );
                          return Column(
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey<String?>(
                                  'edit_route_${routes.length}_$selectedRouteId',
                                ),
                                initialValue: hasSelectedRoute
                                    ? selectedRouteId
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Planned Route',
                                  labelStyle: TextStyle(fontFamily: 'Lexend'),
                                ),
                                items: routes
                                    .map(
                                      (route) => DropdownMenuItem(
                                        value: route.id,
                                        child: Text(
                                          route.name,
                                          style: const TextStyle(
                                            fontFamily: 'Lexend',
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setModalState(() {
                                    selectedRouteId = value;
                                    final route = routes
                                        .where((r) => r.id == value)
                                        .firstOrNull;
                                    final options = route == null
                                        ? const <String>[]
                                        : _plannedStopLabels(route);
                                    selectedStopLabel = options.isEmpty
                                        ? null
                                        : options.first;
                                  });
                                },
                              ),
                              DropdownButtonFormField<String>(
                                key: ValueKey<String?>(
                                  'edit_stop_${selectedRouteId}_${stopItems.length}_$selectedStopLabel',
                                ),
                                initialValue: selectedRoute != null &&
                                        selectedStopLabel != null &&
                                        stopItems.contains(selectedStopLabel)
                                    ? selectedStopLabel
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Planned Stop',
                                  labelStyle: TextStyle(fontFamily: 'Lexend'),
                                ),
                                items: stopItems
                                    .map(
                                      (stop) => DropdownMenuItem(
                                        value: stop,
                                        child: Text(
                                          stop,
                                          style: const TextStyle(
                                            fontFamily: 'Lexend',
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: selectedRoute == null
                                    ? null
                                    : (value) {
                                        setModalState(() {
                                          selectedStopLabel = value;
                                        });
                                      },
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            try {
                              await swFirestore
                                  .collection('students')
                                  .doc(student.id)
                                  .update({
                                    'firstName': firstNameController.text,
                                    'lastName': lastNameController.text,
                                    'classId': selectedClassId,
                                    'assignedRouteId': selectedRouteId,
                                    'pickupStop': selectedStopLabel,
                                    'dropoffStop': null,
                                  });
                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Student updated',
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
                                      style: const TextStyle(
                                        fontFamily: 'Lexend',
                                      ),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF03045E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          child: const Text(
                            'SAVE',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
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
      backgroundColor: Colors.transparent,
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
      backgroundColor: Colors.transparent,
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Update NFC Tag ID',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nfcController,
                    decoration: const InputDecoration(
                      labelText: 'NFC Card ID',
                      labelStyle: TextStyle(fontFamily: 'Lexend'),
                    ),
                  ),
                  if (scanError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      scanError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontFamily: 'Lexend',
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (isScanning)
                    const Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 8),
                          Text(
                            'Please tap NFC card...',
                            style: TextStyle(fontFamily: 'Lexend'),
                          ),
                        ],
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final isAvailable = await NfcManager.instance.checkAvailability();
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
                      icon: const Icon(Icons.nfc),
                      label: const Text(
                        'Scan NFC Tag',
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isScanning ? null : () async {
                        try {
                          await swFirestore
                              .collection('students')
                              .doc(student.id)
                              .update({'nfcCardId': nfcController.text});
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'NFC tag updated',
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
                                  style: const TextStyle(fontFamily: 'Lexend'),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF03045E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: const Text(
                        'UPDATE',
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
                        } catch (_) {}
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                    child: const Text(
                      'Cancel',
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

  void _showAssignBusDialog(BuildContext context) {
    String? selectedBusId = student.assignedBusId;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _AssignBusDialog(student: student, initialBusId: selectedBusId),
    );
  }

  void _deleteStudent(BuildContext context) async {
    final confirmed = await showAppModalSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Delete Student?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Delete ${student.fullName}? This action cannot be undone.',
                  style: const TextStyle(fontFamily: 'Lexend'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text(
                      'DELETE',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    'Cancel',
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
        await swFirestore
            .collection('students')
            .doc(student.id)
            .delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Student deleted',
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
                style: const TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

class _AssignBusDialog extends StatefulWidget {
  final Student student;
  final String? initialBusId;

  const _AssignBusDialog({required this.student, this.initialBusId});

  @override
  State<_AssignBusDialog> createState() => _AssignBusDialogState();
}

class _AssignBusDialogState extends State<_AssignBusDialog> {
  late String? selectedBusId;

  @override
  void initState() {
    super.initState();
    selectedBusId = widget.initialBusId;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: StreamBuilder<List<Bus>>(
            stream: FirebaseService.getBuses(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  width: 200,
                  height: 100,
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF0077B6)),
                  ),
                );
              }

              final buses = snapshot.data ?? [];
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Assign Bus',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        color: Color(0xFF03045E),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedBusId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Bus',
                        labelStyle: TextStyle(fontFamily: 'Lexend'),
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text(
                            'No bus (unassign)',
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
                              style: const TextStyle(
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
                      const SizedBox(height: 12),
                      _BusCapacityInfo(
                        busId: selectedBusId!,
                        studentId: widget.student.id,
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => _assignBus(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF03045E),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        child: const Text(
                          'ASSIGN',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Cancel',
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
              style: const TextStyle(fontFamily: 'Lexend'),
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
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: Colors.red,
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
                    ? Colors.red.withValues(alpha: 0.1)
                    : const Color(0xFF00B4D8).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    isOverCapacity ? Icons.warning : Icons.info_outline,
                    size: 16,
                    color: isOverCapacity
                        ? Colors.red
                        : const Color(0xFF0077B6),
                  ),
                  const SizedBox(width: 8),
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
                            ? Colors.red
                            : const Color(0xFF0077B6),
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
  late List<String> parentIds;

  @override
  void initState() {
    super.initState();
    parentIds = List.from(widget.student.parentIds);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Manage Parents',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 8),
              ...parentIds.map(
                (pid) => FutureBuilder<Map<String, dynamic>?>(
                  future: FirebaseService.getUserData(pid),
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    return ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(
                        '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'
                            .trim(),
                        style: const TextStyle(fontFamily: 'Lexend'),
                      ),
                      subtitle: Text(
                        data?['email'] ?? pid,
                        style: const TextStyle(fontFamily: 'Lexend'),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.remove_circle,
                          color: Colors.red,
                        ),
                        onPressed: () => setState(() => parentIds.remove(pid)),
                      ),
                    );
                  },
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  final selected = await _selectParent(context);
                  if (selected != null && !parentIds.contains(selected)) {
                    setState(() => parentIds.add(selected));
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text(
                  'Add Parent',
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0077B6),
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      await swFirestore
                          .collection('students')
                          .doc(widget.student.id)
                          .update({'parentIds': parentIds});
                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Parents updated',
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
                              style: const TextStyle(fontFamily: 'Lexend'),
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF03045E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'SAVE',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
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
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: StreamBuilder<QuerySnapshot>(
              stream: swFirestore
                  .collection('users')
                  .where('role', isEqualTo: 'Parent')
                  .snapshots(),
              builder: (context, snapshot) {
                final parents = snapshot.data?.docs ?? [];
                return ListView(
                  shrinkWrap: true,
                  children: parents.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.person),
                      title: Text(
                        '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                            .trim(),
                        style: const TextStyle(fontFamily: 'Lexend'),
                      ),
                      subtitle: Text(
                        data['email'] ?? '',
                        style: const TextStyle(fontFamily: 'Lexend'),
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
            child: Text(value, style: const TextStyle(fontFamily: 'Lexend')),
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
          : Colors.grey.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: enabled ? color : Colors.grey, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: enabled ? color : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
