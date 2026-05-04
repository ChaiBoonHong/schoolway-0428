import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import '../../models/models.dart';
import '../../services/firebase_service.dart';
import '../../core/widgets/app_modal_sheet.dart';

InputDecoration _pillFieldDecoration({
  required String hintText,
  Widget? prefixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(fontFamily: 'Lexend'),
    prefixIcon: prefixIcon,
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
  List<String> _visibleBusIds = const [];
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
        batch.update(
          swFirestore.collection('buses').doc(id),
          {'status': status},
        );
      }
      await batch.commit();
      if (!mounted) return;
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Updated ${ids.length} bus(es) to $status',
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: const TextStyle(fontFamily: 'Lexend')),
          backgroundColor: Colors.red,
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
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: const TextStyle(fontFamily: 'Lexend')),
          backgroundColor: Colors.red,
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
                '${_selectedBusIds.length} selected',
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: Color(0xFF03045E),
                ),
              )
            : const Text(
                'Bus Management',
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
                  onPressed: _isBatchActing || _visibleBusIds.isEmpty
                      ? null
                      : _toggleSelectAllVisibleBuses,
                  child: Text(
                    _allVisibleSelected() ? 'Deselect All' : 'Select All',
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      color: Color(0xFF0077B6),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isBatchActing || _selectedBusIds.isEmpty
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
                  onPressed: _isBatchActing || _selectedBusIds.isEmpty
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
            onPressed: () => _showAddBusDialog(context),
            tooltip: 'Add Bus',
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
                  hintText: 'Search buses...',
                  hintStyle: const TextStyle(fontFamily: 'Lexend'),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
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
              ),
            ),
          if (_selectionMode) const SizedBox(height: 8),
          // Bus List
          Expanded(
            child: StreamBuilder<List<Bus>>(
              stream: FirebaseService.getBuses(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0077B6)),
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

                var buses = snapshot.data ?? [];

                // Apply search filter
                if (_searchQuery.isNotEmpty) {
                  buses = buses.where((bus) {
                    return bus.busNumber.toLowerCase().contains(_searchQuery) ||
                        (bus.currentDriverId?.toLowerCase().contains(_searchQuery) ?? false) ||
                        (bus.currentRoute?.toLowerCase().contains(_searchQuery) ?? false);
                  }).toList();
                }

                if (_selectionMode && _showSelectedOnly) {
                  buses = buses
                      .where((bus) => _selectedBusIds.contains(bus.id))
                      .toList();
                }
                _visibleBusIds = buses.map((b) => b.id).toList(growable: false);

                if (buses.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.directions_bus_outlined,
                          size: 64,
                          color: Color(0xFF00B4D8),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No buses yet',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showAddBusDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text(
                            'Add First Bus',
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
                    if (_selectionMode) _buildSelectAllBar(buses),
                    Expanded(
                      child: ListView.builder(
                        key: const PageStorageKey<String>('bus_management_list'),
                        controller: _listScrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: buses.length,
                        itemBuilder: (context, index) {
                          final bus = buses[index];
                          return _BusCard(
                            bus: bus,
                            isSelectionMode: _selectionMode,
                            isSelected: _selectedBusIds.contains(bus.id),
                            onLongPress: () => _enterSelectionMode(bus.id),
                            onSelectToggle: () => _toggleSelection(bus.id),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_selectionMode && _selectedBusIds.isNotEmpty)
            Container(
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
                      child: _BusBatchBtn(
                        icon: Icons.pause_circle_outline,
                        label: 'Set Idle',
                        color: const Color(0xFFFF9800),
                        enabled: !_isBatchActing,
                        onTap: () => _batchUpdateStatus('Idle'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BusBatchBtn(
                        icon: Icons.play_circle_outline,
                        label: 'Set Active',
                        color: const Color(0xFF4CAF50),
                        enabled: !_isBatchActing,
                        onTap: () => _batchUpdateStatus('Active'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _BusBatchBtn(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        color: Colors.red,
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
            activeColor: const Color(0xFF0077B6),
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
          Text(
            allSelected ? 'Deselect all' : 'Select all (${buses.length})',
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
                      'Add New Bus',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        color: Color(0xFF03045E),
                      ),
                    ),
                    const SizedBox(height: 14),
                TextField(
                  controller: busNumberController,
                  decoration: _pillFieldDecoration(hintText: 'Bus Number *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: plateNumberController,
                  decoration: _pillFieldDecoration(hintText: 'Plate Number *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: capacityController,
                  keyboardType: TextInputType.number,
                  decoration: _pillFieldDecoration(hintText: 'Capacity *'),
                ),
                const SizedBox(height: 12),
                StreamBuilder<List<PlannedRoute>>(
                  stream: FirebaseService.getPlannedRoutes(),
                  builder: (context, routeSnap) {
                    final routes = routeSnap.data ?? [];
                    if (routes.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'No saved routes yet. Open Route planner from the admin toolbar and save a route first.',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13,
                            color: Colors.orange.shade800,
                            height: 1.35,
                          ),
                        ),
                      );
                    }
                    return DropdownButtonFormField<String>(
                      key: ValueKey<String?>(selectedPlannedRouteId),
                      initialValue: selectedPlannedRouteId,
                      decoration: _pillFieldDecoration(
                        hintText: 'Planned route *',
                        prefixIcon: const Icon(Icons.alt_route_outlined, size: 20),
                      ),
                      items: routes
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(
                                r.name,
                                style: const TextStyle(fontFamily: 'Lexend'),
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
                const SizedBox(height: 12),
                // Driver Selection
                StreamBuilder<QuerySnapshot>(
                  stream: swFirestore
                      .collection('users')
                      .where('role', isEqualTo: 'Driver')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final drivers = snapshot.data?.docs ?? [];
                    return DropdownButtonFormField<String>(
                      initialValue: selectedDriverId,
                      decoration: _pillFieldDecoration(hintText: 'Assign Driver'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No driver', style: TextStyle(fontFamily: 'Lexend')),
                        ),
                        ...drivers.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem(
                            value: data['authUid'] as String?,
                            child: Text(
                              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim(),
                              style: const TextStyle(fontFamily: 'Lexend'),
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
                const SizedBox(height: 12),
                // Status Selection
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: _pillFieldDecoration(hintText: 'Status'),
                  items: ['Idle', 'Active', 'Maintenance']
                      .map((status) => DropdownMenuItem(
                            value: status,
                            child: Text(status, style: const TextStyle(fontFamily: 'Lexend')),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedStatus = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                if (busNumberController.text.isEmpty ||
                    plateNumberController.text.isEmpty ||
                    capacityController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please fill required fields',
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                  );
                  return;
                }

                if (selectedPlannedRouteId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Select a planned route for this bus',
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                      backgroundColor: Color(0xFFFF9800),
                    ),
                  );
                  return;
                }

                final planned =
                    await FirebaseService.getPlannedRouteById(selectedPlannedRouteId!);
                if (planned == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'That planned route no longer exists. Refresh and try again.',
                          style: TextStyle(fontFamily: 'Lexend'),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }

                try {
                  // Use license plate as document ID (sanitized for Firestore)
                  final plateNumber = plateNumberController.text.trim();
                  // Sanitize plate number for Firestore document ID
                  // Firestore document IDs can contain letters, numbers, and these characters: -_~!*()
                  final documentId = plateNumber.replaceAll(RegExp(r'[^a-zA-Z0-9\-_~!*()]'), '_');
                  
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
                            style: const TextStyle(fontFamily: 'Lexend'),
                          ),
                          backgroundColor: Colors.red,
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
                    currentDriverId: selectedDriverId,
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
                        const SnackBar(
                          content: Text(
                            'Bus added successfully',
                            style: TextStyle(fontFamily: 'Lexend'),
                          ),
                        ),
                      );
                    }
                } catch (e) {
                  String errorMessage = 'An error occurred while adding the bus';
                  
                  if (e.toString().contains('license plate') && e.toString().contains('already exists')) {
                    errorMessage = e.toString().replaceAll('Exception: ', '');
                  } else {
                    errorMessage = 'Error: ${e.toString()}';
                  }
                  
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(errorMessage, style: const TextStyle(fontFamily: 'Lexend')),
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
                      'ADD BUS',
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
                    style: TextStyle(fontFamily: 'Lexend', color: Color(0xFF0077B6)),
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
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;

  const _BusCard({
    required this.bus,
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
      color: isSelected ? const Color(0xFF0077B6).withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: isSelectionMode ? onSelectToggle : () => _showBusDetails(context),
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
              const SizedBox(width: 16),
              // Bus Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bus.busNumber,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Plate: ${bus.licensePlate}',
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14,
                        color: Color(0xFF0077B6),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                            color: _getStatusColor(bus.status).withValues(alpha: 0.1),
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
                              color: const Color(0xFF00B4D8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${bus.capacity} seats',
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12,
                                color: Color(0xFF0077B6),
                              ),
                            ),
                          ],
                        ),
                        if (bus.currentDriverId != null)
                          FutureBuilder<Map<String, dynamic>?>(
                            future: FirebaseService.getUserDataByAuthUid(bus.currentDriverId!),
                            builder: (context, snapshot) {
                              final data = snapshot.data;
                              final driverName = data != null
                                  ? '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim()
                                  : 'Driver';
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person,
                                    size: 14,
                                    color: const Color(0xFF00B4D8),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      driverName,
                                      style: const TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 12,
                                        color: Color(0xFF0077B6),
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
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                  ),
                  child: PopupMenuButton<String>(
                    tooltip: 'Bus actions',
                    icon: const Icon(
                      Icons.more_vert,
                      color: Color(0xFF1F2937),
                    ),
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
                          Icon(Icons.edit_outlined, size: 20, color: Color(0xFF111827)),
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
                    const PopupMenuItem(
                      value: 'driver',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(Icons.person_add_alt_1_rounded, size: 20, color: Color(0xFF111827)),
                          SizedBox(width: 12),
                          Text(
                            'Assign Driver',
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
                      value: 'status',
                      height: 50,
                      child: Row(
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 20, color: Color(0xFF111827)),
                          SizedBox(width: 12),
                          Text(
                            'Change Status',
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
                          Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          SizedBox(width: 12),
                          Text(
                            'Delete Bus',
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green;
      case 'Idle':
        return Colors.orange;
      case 'Maintenance':
        return Colors.red;
      default:
        return Colors.grey;
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
                  Text(
                    bus.busNumber,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 24),
                  ),
                  const SizedBox(height: 12),
                  _DetailRow('Bus Number', bus.busNumber),
                  _DetailRow('Plate Number', bus.licensePlate),
                  _DetailRow('Capacity', '${bus.capacity} seats'),
                  _DetailRow('Status', bus.status),
                  if (bus.currentRoute != null || bus.assignedRouteId != null)
                    _DetailRow(
                      'Planned route',
                      bus.currentRoute ??
                          (bus.assignedRouteId != null ? 'Route #${bus.assignedRouteId}' : '—'),
                    ),
                  if (bus.currentDriverId != null)
                    FutureBuilder<Map<String, dynamic>?>(
                      future: FirebaseService.getUserDataByAuthUid(bus.currentDriverId!),
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
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close', style: TextStyle(fontFamily: 'Lexend')),
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
    final capacityController = TextEditingController(text: bus.capacity.toString());
    var selectedRouteId = bus.assignedRouteId;

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),
                        const Text(
                          'Edit Bus Details',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: busNumberController,
                          decoration: _pillFieldDecoration(hintText: 'Bus Number'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: plateNumberController,
                          decoration: _pillFieldDecoration(hintText: 'Plate Number'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: capacityController,
                          keyboardType: TextInputType.number,
                          decoration: _pillFieldDecoration(hintText: 'Capacity'),
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<List<PlannedRoute>>(
                          stream: FirebaseService.getPlannedRoutes(),
                          builder: (context, routeSnap) {
                            final routes = routeSnap.data ?? [];
                            if (routes.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'No saved routes. Create one in Route planner first.',
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 13,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              );
                            }
                            final validIds = routes.map((r) => r.id).toSet();
                            final value = selectedRouteId != null &&
                                    validIds.contains(selectedRouteId)
                                ? selectedRouteId
                                : null;
                            return DropdownButtonFormField<String?>(
                              key: ValueKey<String?>('$value-${bus.id}'),
                              initialValue: value,
                              decoration: _pillFieldDecoration(
                                hintText: 'Planned route',
                                prefixIcon: const Icon(Icons.alt_route_outlined, size: 20),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(
                                    'No route assigned',
                                    style: TextStyle(fontFamily: 'Lexend'),
                                  ),
                                ),
                                ...routes.map(
                                  (r) => DropdownMenuItem<String?>(
                                    value: r.id,
                                    child: Text(
                                      r.name,
                                      style: const TextStyle(fontFamily: 'Lexend'),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (v) => setModalState(() => selectedRouteId = v),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: () async {
                              try {
                                PlannedRoute? pr;
                                if (selectedRouteId != null) {
                                  pr = await FirebaseService.getPlannedRouteById(
                                    selectedRouteId!,
                                  );
                                  if (pr == null) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Selected route no longer exists',
                                            style: TextStyle(fontFamily: 'Lexend'),
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                }
                                await swFirestore
                                    .collection('buses')
                                    .doc(bus.id)
                                    .update({
                                  'busNumber': busNumberController.text,
                                  'licensePlate': plateNumberController.text,
                                  'capacity': int.parse(capacityController.text),
                                  'assignedRouteId': selectedRouteId,
                                  'currentRoute': pr?.name,
                                });
                                await FirebaseService
                                    .syncAssignedRouteForStudentsOnBus(bus.id);
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Bus updated',
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
        );
      },
    );
  }

  void _showAssignDriverDialog(BuildContext context) {
    String? selectedDriverId = bus.currentDriverId;

    showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Assign Driver', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 24)),
                  const SizedBox(height: 12),
                  StreamBuilder<QuerySnapshot>(
            stream: swFirestore
                .collection('users')
                .where('role', isEqualTo: 'Driver')
                .snapshots(),
            builder: (context, snapshot) {
              final drivers = snapshot.data?.docs ?? [];
              // Validate that selectedDriverId exists in the list of driver authUids
              final driverAuthUids = drivers.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return data['authUid'] as String?;
              }).where((authUid) => authUid != null).toList();
              
              // If current selectedDriverId is not in the list of authUids, reset it
              if (selectedDriverId != null && !driverAuthUids.contains(selectedDriverId)) {
                // Try to find the driver by document ID (for migration)
                final matchingDriver = drivers.where((doc) => doc.id == selectedDriverId).firstOrNull;
                if (matchingDriver != null) {
                  final data = matchingDriver.data() as Map<String, dynamic>;
                  selectedDriverId = data['authUid'] as String?;
                } else {
                  selectedDriverId = null;
                }
              }
              
              return DropdownButtonFormField<String>(
                initialValue: selectedDriverId,
                decoration: _pillFieldDecoration(hintText: 'Select Driver'),
                selectedItemBuilder: (context) {
                  return [
                    const Text('No driver', style: TextStyle(fontFamily: 'Lexend')),
                    ...drivers.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
                      return Text(
                        name.isEmpty ? (data['email'] ?? '') : name,
                        style: const TextStyle(fontFamily: 'Lexend'),
                        overflow: TextOverflow.ellipsis,
                      );
                    }),
                  ];
                },
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No driver', style: TextStyle(fontFamily: 'Lexend')),
                  ),
                  ...drivers.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
                    return DropdownMenuItem(
                      value: data['authUid'] as String?,
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name.isEmpty ? (data['email'] ?? '') : name,
                              style: const TextStyle(fontFamily: 'Lexend'),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              data['email'] ?? '',
                              style: const TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12,
                                color: Color(0xFF0077B6),
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
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                try {
                  await swFirestore
                      .collection('buses')
                      .doc(bus.id)
                      .update({'currentDriverId': selectedDriverId});
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          selectedDriverId != null
                              ? 'Driver assigned'
                              : 'Driver removed',
                          style: const TextStyle(fontFamily: 'Lexend'),
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e', style: const TextStyle(fontFamily: 'Lexend')),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF03045E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text('ASSIGN', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(fontFamily: 'Lexend')),
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
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Change Bus Status', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 24)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
            initialValue: selectedStatus,
            decoration: _pillFieldDecoration(hintText: 'Status'),
            items: ['Idle', 'Active', 'Maintenance']
                .map((status) => DropdownMenuItem(
                      value: status,
                      child: Text(status, style: const TextStyle(fontFamily: 'Lexend')),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                selectedStatus = value!;
              });
            },
          ),
                  const SizedBox(height: 16),
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
                      const SnackBar(
                        content: Text('Status updated', style: TextStyle(fontFamily: 'Lexend')),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e', style: const TextStyle(fontFamily: 'Lexend')),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF03045E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: const Text('UPDATE', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700)),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(fontFamily: 'Lexend')),
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
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Delete Bus?', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 24)),
                const SizedBox(height: 12),
                Text('Delete ${bus.busNumber}? This action cannot be undone.', style: const TextStyle(fontFamily: 'Lexend')),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
                    child: const Text('DELETE', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel', style: TextStyle(fontFamily: 'Lexend')),
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
            const SnackBar(
              content: Text('Bus deleted', style: TextStyle(fontFamily: 'Lexend')),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e', style: const TextStyle(fontFamily: 'Lexend')),
              backgroundColor: Colors.red,
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
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
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


