import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../core/widgets/app_modal_sheet.dart';

InputDecoration _pillFieldDecoration({
  required String hintText,
  Widget? prefixIcon,
  String? helperText,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(fontFamily: 'Lexend'),
    prefixIcon: prefixIcon,
    helperText: helperText,
    helperStyle: TextStyle(fontFamily: 'Lexend', fontSize: 12),
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

class BusManagementScreen extends StatefulWidget {
  const BusManagementScreen({super.key});

  @override
  State<BusManagementScreen> createState() => _BusManagementScreenState();
}

class _BusManagementScreenState extends State<BusManagementScreen> {
  final _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();
  String _searchQuery = '';
  bool _selectionMode = false;
  final Set<String> _selectedBusIds = {};
  List<String> _visibleBusIds = [];
  bool _isBatchActing = false;
  final bool _isImportingDemoCsv = false;
  bool _showSelectedOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

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
      _selectedBusIds.clear();
      _showSelectedOnly = false;
    });
  }

  void _clearSelectionOnly() {
    _preserveScrollWhile(() {
      _selectedBusIds.clear();
      _selectionMode = true;
      _showSelectedOnly = false;
    });
  }

  void _toggleSelection(String id) {
    _preserveScrollWhile(() {
      if (_selectedBusIds.contains(id)) {
        _selectedBusIds.remove(id);
        if (_selectedBusIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectionMode = true;
        _selectedBusIds.add(id);
      }
    });
  }

  void _enterSelectionMode(String id) {
    _preserveScrollWhile(() {
      _selectionMode = true;
      _selectedBusIds.add(id);
    });
  }

  bool _allVisibleSelected() {
    if (_visibleBusIds.isEmpty) return false;
    return _visibleBusIds.every(_selectedBusIds.contains);
  }

  void _toggleSelectAllVisibleBuses() {
    if (_visibleBusIds.isEmpty) return;
    _preserveScrollWhile(() {
      final allSelected = _allVisibleSelected();
      if (allSelected) {
        _selectedBusIds.removeAll(_visibleBusIds);
        if (_selectedBusIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectionMode = true;
        _selectedBusIds.addAll(_visibleBusIds);
      }
    });
  }

  Future<void> _batchUpdateStatus(String status) async {
    if (_isBatchActing) return;
    final ids = _selectedBusIds.toList();
    if (ids.isEmpty) return;
    setState(() => _isBatchActing = true);
    try {
      final batch = swFirestore.batch();
      for (final id in ids) {
        batch.update(swFirestore.collection('buses').doc(id), {
          'status': status,
        });
      }
      await batch.commit();
      if (!mounted) return;
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${ids.length} bus(es) to $status',
            style: TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorReporter.userMessage(
              context,
              e,
              StackTrace.current,
              category: 'buses',
              message: 'Bus operation failed.',
            ),
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBatchActing = false);
      }
    }
  }

  Future<void> _batchDeleteBuses() async {
    if (_isBatchActing) return;
    final ids = _selectedBusIds.toList();
    if (ids.isEmpty) return;
    setState(() => _isBatchActing = true);
    try {
      final batch = swFirestore.batch();
      for (final id in ids) {
        batch.delete(swFirestore.collection('buses').doc(id));
      }
      await batch.commit();
      if (!mounted) return;
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted ${ids.length} bus(es)',
            style: TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorReporter.userMessage(
              context,
              e,
              StackTrace.current,
              category: 'buses',
              message: 'Bus operation failed.',
            ),
            style: TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBatchActing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isImportingDemoCsv,
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
              ? Text('${_selectedBusIds.length} selected')
              : Text(AppLocalizations.of(context).busManagement),
          actions: _selectionMode
              ? [
                  TextButton(
                    onPressed: _isBatchActing || _visibleBusIds.isEmpty
                        ? null
                        : _toggleSelectAllVisibleBuses,
                    child: Text(
                      _allVisibleSelected() ? 'Deselect All' : 'Select All',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _isBatchActing || _selectedBusIds.isEmpty
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
                    onPressed: _isBatchActing || _selectedBusIds.isEmpty
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
                    onPressed: () => _showAddBusDialog(context),
                    tooltip: AppLocalizations.of(context).addBus2,
                  ),
                ],
        ),
        body: Column(
          children: [
            // Search Bar
            if (!_selectionMode)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context).searchBuses,
                    hintStyle: TextStyle(fontFamily: 'Lexend'),
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: SchoolWayTheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                  ),
                ),
              ),
            if (_selectionMode) SizedBox(height: 8),
            // Bus List
            Expanded(
              child: StreamBuilder<List<Bus>>(
                stream: FirebaseService.getBuses(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: SchoolWayTheme.primary,
                      ),
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

                  var buses = snapshot.data ?? [];

                  // Apply search filter
                  if (_searchQuery.isNotEmpty) {
                    buses = buses.where((bus) {
                      return bus.busNumber.toLowerCase().contains(
                            _searchQuery,
                          ) ||
                          (bus.currentDriverUid?.toLowerCase().contains(
                                _searchQuery,
                              ) ??
                              false) ||
                          (bus.currentRoute?.toLowerCase().contains(
                                _searchQuery,
                              ) ??
                              false);
                    }).toList();
                  }

                  if (_selectionMode && _showSelectedOnly) {
                    buses = buses
                        .where((bus) => _selectedBusIds.contains(bus.id))
                        .toList();
                  }
                  _visibleBusIds = buses
                      .map((b) => b.id)
                      .toList(growable: false);

                  if (buses.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.directions_bus_outlined,
                            size: 64,
                            color: SchoolWayTheme.accent,
                          ),
                          SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context).noBusesYet,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _showAddBusDialog(context),
                            icon: Icon(Icons.add),
                            label: Text(
                              AppLocalizations.of(context).addFirstBus,
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

                  return StreamBuilder<List<Student>>(
                    stream: FirebaseService.getAllStudents(),
                    builder: (context, studentSnapshot) {
                      final countsByBus = <String, int>{};
                      for (final student
                          in studentSnapshot.data ?? const <Student>[]) {
                        final busId = student.assignedBusId;
                        if (busId != null &&
                            student.status.toLowerCase() == 'active') {
                          countsByBus[busId] = (countsByBus[busId] ?? 0) + 1;
                        }
                      }
                      return Column(
                        children: [
                          if (_selectionMode) _buildSelectAllBar(buses),
                          Expanded(
                            child: ListView.builder(
                              key: const PageStorageKey<String>(
                                'bus_management_list',
                              ),
                              controller: _listScrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: buses.length,
                              itemBuilder: (context, index) {
                                final bus = buses[index];
                                return _BusCard(
                                  bus: bus,
                                  assignedStudentCount:
                                      countsByBus[bus.id] ?? 0,
                                  isSelectionMode: _selectionMode,
                                  isSelected: _selectedBusIds.contains(bus.id),
                                  onLongPress: () =>
                                      _enterSelectionMode(bus.id),
                                  onSelectToggle: () =>
                                      _toggleSelection(bus.id),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_selectionMode && _selectedBusIds.isNotEmpty)
              Container(
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
                        child: _BusBatchBtn(
                          icon: Icons.pause_circle_outline,
                          label: AppLocalizations.of(context).setIdle,
                          color: SchoolWayTheme.warning,
                          enabled: !_isBatchActing,
                          onTap: () => _batchUpdateStatus('Idle'),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: _BusBatchBtn(
                          icon: Icons.play_circle_outline,
                          label: AppLocalizations.of(context).setActive,
                          color: SchoolWayTheme.successBright,
                          enabled: !_isBatchActing,
                          onTap: () => _batchUpdateStatus('Active'),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: _BusBatchBtn(
                          icon: Icons.delete_outline,
                          label: AppLocalizations.of(context).delete,
                          color: SchoolWayTheme.danger,
                          enabled: !_isBatchActing,
                          onTap: _batchDeleteBuses,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectAllBar(List<Bus> buses) {
    final allSelected =
        buses.isNotEmpty && buses.every((b) => _selectedBusIds.contains(b.id));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            activeColor: SchoolWayTheme.primary,
            onChanged: (_) {
              setState(() {
                if (allSelected) {
                  _selectedBusIds.removeAll(buses.map((b) => b.id));
                  if (_selectedBusIds.isEmpty) {
                    _selectionMode = false;
                  }
                } else {
                  _selectionMode = true;
                  _selectedBusIds.addAll(buses.map((b) => b.id));
                }
              });
            },
          ),
          Flexible(
            child: Text(
              allSelected ? 'Deselect all' : 'Select all (${buses.length})',
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

  void _showAddBusDialog(BuildContext context) {
    final busNumberController = TextEditingController();
    final capacityController = TextEditingController();
    final plateNumberController = TextEditingController();
    String? selectedDriverId;
    String? selectedPlannedRouteId;
    String selectedStatus = 'Idle';

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
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
                      AppLocalizations.of(context).addNewBus,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        color: SchoolWayTheme.navy,
                      ),
                    ),
                    SizedBox(height: 14),
                    TextField(
                      controller: busNumberController,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).busNumber,
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: plateNumberController,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).plateNumber,
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: capacityController,
                      keyboardType: TextInputType.number,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).capacity,
                      ),
                    ),
                    SizedBox(height: 12),
                    StreamBuilder<List<PlannedRoute>>(
                      stream: FirebaseService.getPlannedRoutes(),
                      builder: (context, routeSnap) {
                        final routes = routeSnap.data ?? [];
                        if (routes.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              AppLocalizations.of(
                                context,
                              ).noSavedRoutesYetOpenRoutePlanner,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 13,
                                color: SchoolWayTheme.warning,
                                height: 1.35,
                              ),
                            ),
                          );
                        }
                        return DropdownButtonFormField<String>(
                          key: ValueKey<String?>(selectedPlannedRouteId),
                          initialValue: selectedPlannedRouteId,
                          decoration: _pillFieldDecoration(
                            hintText: AppLocalizations.of(context).plannedRoute,
                            prefixIcon: Icon(
                              Icons.alt_route_outlined,
                              size: 20,
                            ),
                            helperText: AppLocalizations.of(
                              context,
                            ).routeRequiredForTrips,
                          ),
                          items: routes
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r.id,
                                  child: Text(
                                    r.name,
                                    style: TextStyle(fontFamily: 'Lexend'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => selectedPlannedRouteId = value);
                          },
                        );
                      },
                    ),
                    SizedBox(height: 12),
                    // Driver Selection
                    StreamBuilder<QuerySnapshot>(
                      stream: swFirestore
                          .collection('users')
                          .where('role', isEqualTo: 'driver')
                          .snapshots(),
                      builder: (context, snapshot) {
                        final drivers = snapshot.data?.docs ?? [];
                        return DropdownButtonFormField<String>(
                          initialValue: selectedDriverId,
                          decoration: _pillFieldDecoration(
                            hintText: AppLocalizations.of(context).assignDriver,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(
                                AppLocalizations.of(context).noDriver,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                            ...drivers.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return DropdownMenuItem(
                                value: doc.id,
                                child: Text(
                                  '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                      .trim(),
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                              );
                            }),
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedDriverId = value;
                            });
                          },
                        );
                      },
                    ),
                    SizedBox(height: 12),
                    // Status Selection
                    DropdownButtonFormField<String>(
                      initialValue: selectedStatus,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).status,
                      ),
                      items: ['Idle', 'Active', 'Maintenance']
                          .map(
                            (status) => DropdownMenuItem(
                              value: status,
                              child: Text(
                                status,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedStatus = value!;
                        });
                      },
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (busNumberController.text.isEmpty ||
                              plateNumberController.text.isEmpty ||
                              capacityController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).pleaseFillRequiredFields,
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                              ),
                            );
                            return;
                          }

                          if (selectedPlannedRouteId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).selectAPlannedRouteForThisBus,
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                                backgroundColor: SchoolWayTheme.warning,
                              ),
                            );
                            return;
                          }

                          final planned =
                              await FirebaseService.getPlannedRouteById(
                                selectedPlannedRouteId!,
                              );
                          if (planned == null) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).thatPlannedRouteNoLongerExistsRefresh,
                                    style: TextStyle(fontFamily: 'Lexend'),
                                  ),
                                  backgroundColor: SchoolWayTheme.danger,
                                ),
                              );
                            }
                            return;
                          }

                          try {
                            // Use license plate as document ID (sanitized for Firestore)
                            final plateNumber = plateNumberController.text
                                .trim();
                            // Sanitize plate number for Firestore document ID
                            // Firestore document IDs can contain letters, numbers, and these characters: -_~!*()
                            final documentId = plateNumber.replaceAll(
                              RegExp(r'[^a-zA-Z0-9\-_~!*()]'),
                              '_',
                            );

                            // Check if bus with this license plate already exists
                            final existingBus = await swFirestore
                                .collection('buses')
                                .doc(documentId)
                                .get();

                            if (existingBus.exists) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'A bus with license plate $plateNumber already exists',
                                      style: TextStyle(fontFamily: 'Lexend'),
                                    ),
                                    backgroundColor: SchoolWayTheme.danger,
                                  ),
                                );
                              }
                              return;
                            }

                            final routeAlreadyAssigned =
                                await FirebaseService.isRouteAssignedToAnotherBus(
                                  planned.id,
                                );
                            if (routeAlreadyAssigned) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      AppLocalizations.of(
                                        context,
                                      ).routeAlreadyAssignedToBus,
                                      style: const TextStyle(
                                        fontFamily: 'Lexend',
                                      ),
                                    ),
                                    backgroundColor: SchoolWayTheme.warning,
                                  ),
                                );
                              }
                              return;
                            }

                            // Create bus document with license plate as document ID
                            // No Auth account needed - buses are data entities, not users
                            final newBus = Bus(
                              id: documentId,
                              busNumber: busNumberController.text,
                              licensePlate: plateNumber,
                              capacity: int.parse(capacityController.text),
                              currentDriverUid: selectedDriverId,
                              currentRoute: planned.name,
                              assignedRouteId: planned.id,
                              status: selectedStatus,
                              createdAt: DateTime.now(),
                            );

                            await swFirestore
                                .collection('buses')
                                .doc(documentId)
                                .set(newBus.toFirestore());
                            await FirebaseService.syncAssignedRouteForStudentsOnBus(
                              documentId,
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).busAddedSuccessfully,
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
                              category: 'buses',
                              message: 'Bus creation failed.',
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
                          AppLocalizations.of(context).addBus,
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

class _BusCard extends StatelessWidget {
  final Bus bus;
  final int assignedStudentCount;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;

  const _BusCard({
    required this.bus,
    required this.assignedStudentCount,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isSelected ? SchoolWayTheme.primary.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: isSelectionMode
            ? onSelectToggle
            : () => _showBusDetails(context),
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
              // Bus Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusColor(bus.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.directions_bus,
                  color: _getStatusColor(bus.status),
                  size: 32,
                ),
              ),
              SizedBox(width: 16),
              // Bus Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bus.busNumber,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Plate: ${bus.licensePlate}',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14,
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                              bus.status,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            bus.status,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(bus.status),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.airline_seat_recline_normal,
                              size: 14,
                              color: SchoolWayTheme.accent,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '${bus.capacity} seats',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12,
                                color: SchoolWayTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.groups_outlined,
                              size: 14,
                              color: SchoolWayTheme.accent,
                            ),
                            SizedBox(width: 4),
                            Text(
                              AppLocalizations.of(
                                context,
                              ).assignedStudentsCount(assignedStudentCount),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12,
                                color: SchoolWayTheme.primary,
                              ),
                            ),
                          ],
                        ),
                        if (bus.currentDriverUid != null)
                          FutureBuilder<Map<String, dynamic>?>(
                            future: FirebaseService.getUserDataByAuthUid(
                              bus.currentDriverUid!,
                            ),
                            builder: (context, snapshot) {
                              final data = snapshot.data;
                              final driverName = data != null
                                  ? '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                        .trim()
                                  : 'Driver';
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person,
                                    size: 14,
                                    color: SchoolWayTheme.accent,
                                  ),
                                  SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      driverName,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 12,
                                        color: SchoolWayTheme.primary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions Menu
              if (!isSelectionMode)
                Theme(
                  data: Theme.of(context).copyWith(
                    splashColor: SchoolWayTheme.transparent,
                    highlightColor: SchoolWayTheme.transparent,
                    hoverColor: SchoolWayTheme.transparent,
                  ),
                  child: PopupMenuButton<String>(
                    tooltip: AppLocalizations.of(context).busActions,
                    icon: Icon(
                      Icons.more_vert,
                      color: SchoolWayTheme.textStrong,
                    ),
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
                        value: 'driver',
                        height: 50,
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_add_alt_1_rounded,
                              size: 20,
                              color: SchoolWayTheme.text,
                            ),
                            SizedBox(width: 12),
                            Text(
                              AppLocalizations.of(context).assignDriver,
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
                        value: 'status',
                        height: 50,
                        child: Row(
                          children: [
                            Icon(
                              Icons.swap_horiz_rounded,
                              size: 20,
                              color: SchoolWayTheme.text,
                            ),
                            SizedBox(width: 12),
                            Text(
                              AppLocalizations.of(context).changeStatus,
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
                              AppLocalizations.of(context).deleteBus,
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return SchoolWayTheme.success;
      case 'Idle':
        return SchoolWayTheme.warning;
      case 'Maintenance':
        return SchoolWayTheme.danger;
      default:
        return SchoolWayTheme.muted;
    }
  }

  void _handleAction(BuildContext context, String action) {
    switch (action) {
      case 'edit':
        _showEditDialog(context);
        break;
      case 'driver':
        _showAssignDriverDialog(context);
        break;
      case 'status':
        _showChangeStatusDialog(context);
        break;
      case 'delete':
        _deleteBus(context);
        break;
    }
  }

  void _showBusDetails(BuildContext context) {
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
                    bus.busNumber,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 12),
                  _DetailRow('Bus Number', bus.busNumber),
                  _DetailRow('Plate Number', bus.licensePlate),
                  _DetailRow('Capacity', '${bus.capacity} seats'),
                  _DetailRow(
                    AppLocalizations.of(context).students,
                    AppLocalizations.of(
                      context,
                    ).assignedStudentsCount(assignedStudentCount),
                  ),
                  _DetailRow('Status', bus.status),
                  if (bus.currentRoute != null || bus.assignedRouteId != null)
                    _DetailRow(
                      'Planned route',
                      bus.currentRoute ??
                          (bus.assignedRouteId != null
                              ? 'Route #${bus.assignedRouteId}'
                              : '—'),
                    ),
                  if (bus.currentDriverUid != null)
                    FutureBuilder<Map<String, dynamic>?>(
                      future: FirebaseService.getUserDataByAuthUid(
                        bus.currentDriverUid!,
                      ),
                      builder: (context, snapshot) {
                        final data = snapshot.data;
                        return _DetailRow(
                          'Driver',
                          data != null
                              ? '${data['firstName']} ${data['lastName']}\n${data['email']}'
                              : 'Loading...',
                        );
                      },
                    )
                  else
                    const _DetailRow('Driver', 'Not assigned'),
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
    final busNumberController = TextEditingController(text: bus.busNumber);
    final plateNumberController = TextEditingController(text: bus.licensePlate);
    final capacityController = TextEditingController(
      text: bus.capacity.toString(),
    );
    var selectedRouteId = bus.assignedRouteId;

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) {
        return StatefulBuilder(
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
                        SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context).editBusDetails,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                        SizedBox(height: 12),
                        TextField(
                          controller: busNumberController,
                          decoration: _pillFieldDecoration(
                            hintText: AppLocalizations.of(context).busNumber2,
                          ),
                        ),
                        SizedBox(height: 12),
                        TextField(
                          controller: plateNumberController,
                          decoration: _pillFieldDecoration(
                            hintText: AppLocalizations.of(context).plateNumber2,
                          ),
                        ),
                        SizedBox(height: 12),
                        TextField(
                          controller: capacityController,
                          keyboardType: TextInputType.number,
                          decoration: _pillFieldDecoration(
                            hintText: AppLocalizations.of(context).capacity2,
                          ),
                        ),
                        SizedBox(height: 12),
                        StreamBuilder<List<PlannedRoute>>(
                          stream: FirebaseService.getPlannedRoutes(),
                          builder: (context, routeSnap) {
                            final routes = routeSnap.data ?? [];
                            if (routes.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).noSavedRoutesCreateOneInRoute,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 13,
                                    color: SchoolWayTheme.warning,
                                  ),
                                ),
                              );
                            }
                            final validIds = routes.map((r) => r.id).toSet();
                            final value =
                                selectedRouteId != null &&
                                    validIds.contains(selectedRouteId)
                                ? selectedRouteId
                                : null;
                            return DropdownButtonFormField<String?>(
                              key: ValueKey<String?>('$value-${bus.id}'),
                              initialValue: value,
                              decoration: _pillFieldDecoration(
                                hintText: AppLocalizations.of(
                                  context,
                                ).plannedRoute,
                                prefixIcon: Icon(
                                  Icons.alt_route_outlined,
                                  size: 20,
                                ),
                                helperText: AppLocalizations.of(
                                  context,
                                ).routeRequiredForTrips,
                              ),
                              items: [
                                // No "null" option, route is now mandatory
                                ...routes.map(
                                  (r) => DropdownMenuItem<String?>(
                                    value: r.id,
                                    child: Text(
                                      r.name,
                                      style: TextStyle(fontFamily: 'Lexend'),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) =>
                                  setModalState(() => selectedRouteId = v),
                            );
                          },
                        ),
                        SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () async {
                              try {
                                if (selectedRouteId == null) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).selectAPlannedRouteForThisBus,
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                          ),
                                        ),
                                        backgroundColor: SchoolWayTheme.warning,
                                      ),
                                    );
                                  }
                                  return;
                                }

                                final pr =
                                    await FirebaseService.getPlannedRouteById(
                                      selectedRouteId!,
                                    );
                                if (pr == null) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).selectedRouteNoLongerExists,
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                          ),
                                        ),
                                        backgroundColor: SchoolWayTheme.danger,
                                      ),
                                    );
                                  }
                                  return;
                                }
                                final routeAlreadyAssigned =
                                    await FirebaseService.isRouteAssignedToAnotherBus(
                                      selectedRouteId!,
                                      excludingBusId: bus.id,
                                    );
                                if (routeAlreadyAssigned) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLocalizations.of(
                                            context,
                                          ).routeAlreadyAssignedToBus,
                                          style: const TextStyle(
                                            fontFamily: 'Lexend',
                                          ),
                                        ),
                                        backgroundColor: SchoolWayTheme.warning,
                                      ),
                                    );
                                  }
                                  return;
                                }
                                await swFirestore
                                    .collection('buses')
                                    .doc(bus.id)
                                    .update({
                                      'busNumber': busNumberController.text,
                                      'licensePlate':
                                          plateNumberController.text,
                                      'capacity': int.parse(
                                        capacityController.text,
                                      ),
                                      'assignedRouteId': selectedRouteId,
                                      'currentRoute': pr.name,
                                    });
                                await FirebaseService.syncAssignedRouteForStudentsOnBus(
                                  bus.id,
                                );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLocalizations.of(context).busUpdated,
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
        );
      },
    );
  }

  void _showAssignDriverDialog(BuildContext context) {
    String? selectedDriverId = bus.currentDriverUid;

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
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
                    AppLocalizations.of(context).assignDriver,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
                    stream: swFirestore
                        .collection('users')
                        .where('role', isEqualTo: 'driver')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final drivers = snapshot.data?.docs ?? [];
                      // User document IDs are the authoritative Firebase Auth UIDs.
                      final driverAuthUids = drivers
                          .map((doc) => doc.id)
                          .toSet();

                      if (selectedDriverId != null &&
                          !driverAuthUids.contains(selectedDriverId)) {
                        selectedDriverId = null;
                      }

                      return DropdownButtonFormField<String>(
                        initialValue: selectedDriverId,
                        decoration: _pillFieldDecoration(
                          hintText: AppLocalizations.of(context).selectDriver,
                        ),
                        selectedItemBuilder: (context) {
                          return [
                            Text(
                              AppLocalizations.of(context).noDriver,
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                            ...drivers.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final name =
                                  '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                      .trim();
                              return Text(
                                name.isEmpty ? (data['email'] ?? '') : name,
                                style: TextStyle(fontFamily: 'Lexend'),
                                overflow: TextOverflow.ellipsis,
                              );
                            }),
                          ];
                        },
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              AppLocalizations.of(context).noDriver,
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                          ),
                          ...drivers.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            final name =
                                '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                    .trim();
                            return DropdownMenuItem(
                              value: doc.id,
                              child: SizedBox(
                                width: double.infinity,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      name.isEmpty
                                          ? (data['email'] ?? '')
                                          : name,
                                      style: TextStyle(fontFamily: 'Lexend'),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      data['email'] ?? '',
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 12,
                                        color: SchoolWayTheme.primary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedDriverId = value;
                          });
                        },
                      );
                    },
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await swFirestore
                              .collection('buses')
                              .doc(bus.id)
                              .update({'currentDriverUid': selectedDriverId});
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  selectedDriverId != null
                                      ? 'Driver assigned'
                                      : 'Driver removed',
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
            ),
          ),
        ),
      ),
    );
  }

  void _showChangeStatusDialog(BuildContext context) {
    String selectedStatus = bus.status;

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SchoolWayTheme.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
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
                    AppLocalizations.of(context).changeBusStatus,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: _pillFieldDecoration(
                      hintText: AppLocalizations.of(context).status,
                    ),
                    items: ['Idle', 'Active', 'Maintenance']
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(
                              status,
                              style: TextStyle(fontFamily: 'Lexend'),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        selectedStatus = value!;
                      });
                    },
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await swFirestore
                              .collection('buses')
                              .doc(bus.id)
                              .update({'status': selectedStatus});
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(context).statusUpdated,
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
      ),
    );
  }

  void _deleteBus(BuildContext context) async {
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
                  AppLocalizations.of(context).deleteBus2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Delete ${bus.busNumber}? This action cannot be undone.',
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
        await swFirestore.collection('buses').doc(bus.id).delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).busDeleted,
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

class _BusBatchBtn extends StatelessWidget {
  const _BusBatchBtn({
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
