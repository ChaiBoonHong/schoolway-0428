import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nfc_manager/nfc_manager.dart';

import 'package:schoolway/core/diagnostics/app_logger.dart';
import 'package:schoolway/core/school_classes.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/widgets/app_modal_sheet.dart';
import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/models/models.dart';
import 'package:schoolway/services/admin_account_service.dart';
import 'package:schoolway/services/firebase_service.dart';
import 'package:schoolway/services/nfc_tag_reader.dart';

/// Single-flow admin onboarding: register a student, link or create the
/// parent account, then assign the route stop and bus.
class QuickSetupWizard extends StatefulWidget {
  const QuickSetupWizard({super.key});

  static Future<void> show(BuildContext context) {
    return showAppModalSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 24),
        child: QuickSetupWizard(),
      ),
    );
  }

  @override
  State<QuickSetupWizard> createState() => _QuickSetupWizardState();
}

class _QuickSetupWizardState extends State<QuickSetupWizard> {
  static const int _totalSteps = 3;

  int _step = 0;
  bool _saving = false;

  // Step 0 — student
  final _studentIdController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _nfcCardIdController = TextEditingController();
  String _classId = kSchoolClassIds.first;
  bool _isScanningNfc = false;
  String? _nfcScanError;

  // Step 1 — parent
  bool _createNewParent = false;
  final Set<String> _existingParentIds = {};
  final _parentUsernameController = TextEditingController();
  final _parentFirstNameController = TextEditingController();
  final _parentLastNameController = TextEditingController();
  final _parentEmailController = TextEditingController();
  final _parentPasswordController = TextEditingController();

  // Step 2 — transport
  String? _routeId;
  int? _stopIndex;
  String? _busId;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _studentIdController,
      _firstNameController,
      _lastNameController,
      _nfcCardIdController,
      _parentUsernameController,
      _parentFirstNameController,
      _parentLastNameController,
      _parentEmailController,
      _parentPasswordController,
    ]) {
      controller.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (_isScanningNfc) {
      try {
        NfcManager.instance.stopSession();
      } catch (e) {
        AppLogger.debug('nfc', 'NFC dispose stop session handled: $e');
      }
    }
    for (final controller in [
      _studentIdController,
      _firstNameController,
      _lastNameController,
      _nfcCardIdController,
      _parentUsernameController,
      _parentFirstNameController,
      _parentLastNameController,
      _parentEmailController,
      _parentPasswordController,
    ]) {
      controller.removeListener(_onFieldChanged);
      controller.dispose();
    }
    super.dispose();
  }

  bool get _stepValid {
    switch (_step) {
      case 0:
        return _studentIdController.text.trim().isNotEmpty &&
            _firstNameController.text.trim().isNotEmpty &&
            _lastNameController.text.trim().isNotEmpty &&
            _nfcCardIdController.text.trim().isNotEmpty;
      case 1:
        return _createNewParent
            ? _parentUsernameController.text.trim().isNotEmpty &&
                  _parentEmailController.text.trim().isNotEmpty &&
                  _parentPasswordController.text.length >= 6
            : _existingParentIds.isNotEmpty;
      case 2:
        return _routeId != null && _stopIndex != null;
    }
    return false;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Lexend')),
        backgroundColor: SchoolWayTheme.danger,
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final parentIds = Set<String>.from(_existingParentIds);
      if (_createNewParent) {
        final uid = await AdminAccountService.createUser(
          username: _parentUsernameController.text.trim(),
          firstName: _parentFirstNameController.text.trim(),
          lastName: _parentLastNameController.text.trim(),
          email: _parentEmailController.text.trim(),
          password: _parentPasswordController.text,
          role: 'parent',
        );
        parentIds.add(uid);
      }
      final documentId = _studentIdController.text.trim().replaceAll('/', '_');

      final existing = await swFirestore
          .collection('students')
          .doc(documentId)
          .get();
      if (existing.exists) {
        throw Exception('A student with this Student ID already exists');
      }
      final existingNfc = await swFirestore
          .collection('students')
          .where('nfcCardId', isEqualTo: _nfcCardIdController.text.trim())
          .limit(1)
          .get();
      if (existingNfc.docs.isNotEmpty) {
        throw Exception('This NFC Card ID is already assigned');
      }

      if (_busId != null) {
        final bus = await FirebaseService.getBusById(_busId!);
        final busRouteId = bus?.assignedRouteId;
        if (bus == null || busRouteId == null || busRouteId != _routeId) {
          throw Exception('Selected bus is not assigned to the selected route');
        }
      }

      final student = Student(
        id: documentId,
        studentId: _studentIdController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        nfcCardId: _nfcCardIdController.text.trim(),
        parentAuthUids: parentIds.toList(growable: false),
        assignedBusId: _busId,
        assignedRouteId: _routeId,
        pickupStopIndex: _stopIndex,
        status: 'Active',
        classId: _classId,
        createdAt: DateTime.now(),
      );
      await swFirestore
          .collection('students')
          .doc(documentId)
          .set(student.toFirestore());

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).quickSetupDone,
            style: const TextStyle(fontFamily: 'Lexend'),
          ),
          backgroundColor: SchoolWayTheme.success,
        ),
      );
    } catch (error) {
      _showError('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 640),
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
            const SizedBox(height: 14),
            Text(
              l10n.quickSetup,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 22,
                color: SchoolWayTheme.navy,
              ),
            ),
            Text(
              l10n.stepOf(_step + 1, _totalSteps),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Lexend', fontSize: 13),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey<int>(_step),
                child: switch (_step) {
                  0 => _buildStudentStep(l10n),
                  1 => _buildParentStep(l10n),
                  _ => _buildTransportStep(l10n),
                },
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _step -= 1),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        l10n.backTooltip,
                        style: const TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: !_stepValid || _saving
                        ? null
                        : () {
                            if (_step < _totalSteps - 1) {
                              setState(() => _step += 1);
                            } else {
                              _submit();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SchoolWayTheme.primary,
                      foregroundColor: SchoolWayTheme.surface,
                      disabledBackgroundColor: SchoolWayTheme.neutralBorder,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _step < _totalSteps - 1 ? l10n.next : l10n.save2,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: Text(
                l10n.cancel,
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  color: SchoolWayTheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontFamily: 'Lexend'),
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

  Widget _buildStudentStep(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _studentIdController,
        decoration: _decoration(l10n.studentId),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _firstNameController,
        decoration: _decoration(l10n.firstName2),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _lastNameController,
        decoration: _decoration(l10n.lastName2),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _classId,
        decoration: _decoration(l10n.class2),
        items: kSchoolClassIds
            .map(
              (c) => DropdownMenuItem(
                value: c,
                child: Text(c, style: const TextStyle(fontFamily: 'Lexend')),
              ),
            )
            .toList(),
        onChanged: (value) => setState(() => _classId = value!),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _nfcCardIdController,
              decoration: _decoration(l10n.nfcCardId2).copyWith(
                prefixIcon: const Icon(
                  Icons.nfc,
                  color: SchoolWayTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isScanningNfc
                  ? () async {
                      try {
                        await NfcManager.instance.stopSession();
                      } catch (e) {
                        AppLogger.debug('nfc', 'NFC stop session handled: $e');
                      }
                      if (mounted) {
                        setState(() {
                          _isScanningNfc = false;
                        });
                      }
                    }
                  : () async {
                      try {
                        final isAvailable = await NfcManager.instance
                            .checkAvailability();
                        if (isAvailable != NfcAvailability.enabled) {
                          if (mounted) {
                            setState(() {
                              _nfcScanError = l10n.nfcNotAvailable;
                            });
                          }
                          return;
                        }
                        if (mounted) {
                          setState(() {
                            _isScanningNfc = true;
                            _nfcScanError = null;
                          });
                        }
                        await NfcManager.instance.startSession(
                          pollingOptions: {NfcPollingOption.iso14443},
                          onDiscovered: (NfcTag tag) async {
                            try {
                              final id = await readNfcTagIdentifier(tag);
                              if (id != null) {
                                if (mounted) {
                                  setState(() {
                                    _nfcCardIdController.text = id;
                                    _isScanningNfc = false;
                                    _nfcScanError = null;
                                  });
                                }
                              } else {
                                if (mounted) {
                                  setState(() {
                                    _nfcScanError = l10n.nfcScanFailed;
                                    _isScanningNfc = false;
                                  });
                                }
                              }
                            } catch (e) {
                              AppLogger.debug('nfc', 'NFC tag read failed: $e');
                              if (mounted) {
                                setState(() {
                                  _nfcScanError = l10n.nfcScanFailed;
                                  _isScanningNfc = false;
                                });
                              }
                            } finally {
                              try {
                                await NfcManager.instance.stopSession();
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
                        AppLogger.debug('nfc', 'NFC start session failed: $e');
                        if (mounted) {
                          setState(() {
                            _nfcScanError = l10n.nfcNotAvailable;
                            _isScanningNfc = false;
                          });
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanningNfc
                    ? SchoolWayTheme.danger
                    : SchoolWayTheme.primary,
                foregroundColor: SchoolWayTheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              icon: _isScanningNfc
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: SchoolWayTheme.surface,
                      ),
                    )
                  : const Icon(Icons.contactless, size: 20),
              label: Text(
                _isScanningNfc ? l10n.cancelScan : l10n.scanNfcCard,
                style: const TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
      if (_isScanningNfc) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: SchoolWayTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: SchoolWayTheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.sensors,
                size: 16,
                color: SchoolWayTheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.scanningNfcCard,
                  style: const TextStyle(
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
      if (_nfcScanError != null) ...[
        const SizedBox(height: 8),
        Text(
          _nfcScanError!,
          style: const TextStyle(
            color: SchoolWayTheme.danger,
            fontFamily: 'Lexend',
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ],
  );

  Widget _buildParentStep(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<bool>(
        segments: [
          ButtonSegment<bool>(
            value: false,
            label: Text(
              l10n.useExistingParent,
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
            icon: const Icon(Icons.people_outline),
          ),
          ButtonSegment<bool>(
            value: true,
            label: Text(
              l10n.createNewParent,
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
        selected: {_createNewParent},
        onSelectionChanged: (selection) =>
            setState(() => _createNewParent = selection.first),
      ),
      const SizedBox(height: 12),
      if (_createNewParent) ...[
        TextField(
          controller: _parentUsernameController,
          decoration: _decoration(l10n.username),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _parentFirstNameController,
          decoration: _decoration(l10n.firstName2),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _parentLastNameController,
          decoration: _decoration(l10n.lastName2),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _parentEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: _decoration(l10n.email2),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _parentPasswordController,
          obscureText: true,
          decoration: _decoration(l10n.temporaryPassword),
        ),
      ] else
        StreamBuilder<QuerySnapshot>(
          stream: swFirestore
              .collection('users')
              .where('role', isEqualTo: 'parent')
              .snapshots(),
          builder: (context, snapshot) {
            final parents = snapshot.data?.docs ?? [];
            return Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                border: Border.all(color: SchoolWayTheme.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: parents.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        l10n.noUsersFound,
                        style: const TextStyle(fontFamily: 'Lexend'),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: parents.length,
                      itemBuilder: (context, index) {
                        final doc = parents[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final email = data['email'] as String? ?? doc.id;
                        final name =
                            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                .trim();
                        return CheckboxListTile(
                          value: _existingParentIds.contains(doc.id),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          title: Text(
                            name.isEmpty ? email : '$name ($email)',
                            style: const TextStyle(fontFamily: 'Lexend'),
                            overflow: TextOverflow.ellipsis,
                          ),
                          onChanged: (checked) => setState(() {
                            checked == true
                                ? _existingParentIds.add(doc.id)
                                : _existingParentIds.remove(doc.id);
                          }),
                        );
                      },
                    ),
            );
          },
        ),
    ],
  );

  Widget _buildTransportStep(AppLocalizations l10n) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StreamBuilder<List<PlannedRoute>>(
        stream: FirebaseService.getPlannedRoutes(),
        builder: (context, snapshot) {
          final routes = snapshot.data ?? const <PlannedRoute>[];
          final selectedRoute = routes
              .where((r) => r.id == _routeId)
              .firstOrNull;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey<String?>('qs_route_${routes.length}_$_routeId'),
                initialValue: selectedRoute != null ? _routeId : null,
                decoration: _decoration(l10n.plannedRoute3),
                items: routes
                    .map(
                      (route) => DropdownMenuItem(
                        value: route.id,
                        child: Text(
                          route.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Lexend'),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _routeId = value;
                  final route = routes.where((r) => r.id == value).firstOrNull;
                  _stopIndex = route == null || route.editableStops.isEmpty
                      ? null
                      : 0;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey<String?>(
                  'qs_stop_${_routeId}_${selectedRoute?.editableStops.length}',
                ),
                initialValue:
                    selectedRoute != null &&
                        _stopIndex != null &&
                        _stopIndex! < selectedRoute.editableStops.length
                    ? _stopIndex
                    : null,
                decoration: _decoration(l10n.plannedStop2),
                items: selectedRoute == null
                    ? const <DropdownMenuItem<int>>[]
                    : selectedRoute.editableStops
                          .asMap()
                          .entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                ).routeStopNumber(entry.key + 1),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                onChanged: selectedRoute == null
                    ? null
                    : (value) => setState(() => _stopIndex = value),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 12),
      StreamBuilder<List<Bus>>(
        stream: FirebaseService.getBuses(),
        builder: (context, snapshot) {
          final allBuses = snapshot.data ?? const <Bus>[];
          final routeBuses = _routeId == null
              ? allBuses
              : allBuses.where((b) => b.assignedRouteId == _routeId).toList();
          if (_busId != null && !routeBuses.any((b) => b.id == _busId)) {
            _busId = null;
          }
          return DropdownButtonFormField<String>(
            key: ValueKey<String?>(
              'qs_bus_${_routeId}_${routeBuses.length}_$_busId',
            ),
            initialValue: routeBuses.any((b) => b.id == _busId) ? _busId : null,
            decoration: _decoration(l10n.selectAssignedBus).copyWith(
              helperText: _routeId == null
                  ? l10n.selectRouteFirst
                  : l10n.busesOnSelectedRoute(routeBuses.length),
              helperStyle: const TextStyle(fontFamily: 'Lexend', fontSize: 12),
            ),
            items: [
              DropdownMenuItem<String>(
                value: null,
                child: Text(
                  l10n.noBusUnassign,
                  style: const TextStyle(fontFamily: 'Lexend'),
                ),
              ),
              ...routeBuses.map(
                (bus) => DropdownMenuItem(
                  value: bus.id,
                  child: Text(
                    bus.busNumber,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ),
            ],
            onChanged: _routeId == null
                ? null
                : (value) => setState(() => _busId = value),
          );
        },
      ),
    ],
  );
}
