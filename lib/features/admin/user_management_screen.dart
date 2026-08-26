import 'package:schoolway/l10n/app_localizations.dart';
import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:schoolway/core/diagnostics/error_reporter.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:schoolway/services/admin_account_service.dart';
import '../../core/widgets/app_modal_sheet.dart';
import '../../core/widgets/shimmer_loading.dart';
import '../../core/widgets/fade_in_and_slide.dart';

/// True when this Firestore user row is the signed-in account (authUid or email).
bool _userDocIsCurrentUser(Map<String, dynamic> data) {
  final auth = FirebaseAuth.instance.currentUser;
  if (auth == null) return false;
  final authUid = data['authUid'] as String?;
  if (authUid != null && authUid == auth.uid) return true;
  final email = (data['email'] as String?)?.trim().toLowerCase();
  final authEmail = auth.email?.toLowerCase();
  return email != null && authEmail != null && email == authEmail;
}

InputDecoration _pillFieldDecoration({
  required String hintText,
  Widget? suffixIcon,
}) {
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
    suffixIcon: suffixIcon,
  );
}

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  String _selectedFilter = 'All';
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
  List<String> _visibleUserIds = [];
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
    if (_visibleUserIds.isEmpty) return false;
    return _visibleUserIds.every(_selectedIds.contains);
  }

  void _toggleSelectAllVisibleUsers() {
    if (_visibleUserIds.isEmpty) return;
    _preserveScrollWhile(() {
      final allSelected = _allVisibleSelected();
      if (allSelected) {
        _selectedIds.removeAll(_visibleUserIds);
        if (_selectedIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectionMode = true;
        _selectedIds.addAll(_visibleUserIds);
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

  String _normalizeRole(String rawRole) {
    switch (rawRole.trim().toLowerCase()) {
      case 'parent':
        return 'Parent';
      case 'driver':
        return 'Driver';
      case 'admin':
        return 'Admin';
      default:
        return '';
    }
  }

  Future<void> _createUserRecord({
    required String username,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String role,
    required String gender,
    required String phoneNumber,
    required String countryCode,
  }) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty ||
        firstName.trim().isEmpty ||
        lastName.trim().isEmpty ||
        email.trim().isEmpty ||
        password.isEmpty) {
      throw Exception('Please fill all required fields');
    }

    if (trimmedUsername.contains(' ')) {
      throw Exception('Username cannot contain spaces');
    }

    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }

    final normalizedRole = _normalizeRole(role);
    if (normalizedRole.isEmpty) {
      throw Exception('Role must be Parent, Driver, or Admin');
    }

    await AdminAccountService.createUser(
      username: trimmedUsername,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: email.trim(),
      password: password,
      role: normalizedRole,
      gender: gender.trim().isEmpty ? 'Other' : gender.trim(),
      phoneNumber: phoneNumber.trim(),
      countryCode: countryCode.trim().isEmpty ? '+60' : countryCode.trim(),
    );
  }

  Future<void> _batchAction(String action) async {
    if (_isBatchActing) return;
    var ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    if (action == 'delete') {
      final filtered = <String>[];
      for (final id in ids) {
        final snap = await swFirestore.collection('users').doc(id).get();
        final d = snap.data();
        if (d != null && _userDocIsCurrentUser(d)) continue;
        filtered.add(id);
      }
      if (filtered.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).youCannotDeleteYourOwnAccount,
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: SchoolWayTheme.danger,
            ),
          );
        }
        return;
      }
      ids = filtered;
    }

    final count = ids.length;

    String title;
    String description;
    Color btnColor;
    String btnLabel;

    switch (action) {
      case 'delete':
        title = 'Delete $count user${count > 1 ? 's' : ''}?';
        description = 'This action cannot be undone.';
        btnColor = SchoolWayTheme.danger;
        btnLabel = 'DELETE ALL';
        break;
      case 'disable':
        title = 'Disable $count user${count > 1 ? 's' : ''}?';
        description = 'Selected users will not be able to sign in.';
        btnColor = SchoolWayTheme.warning;
        btnLabel = 'DISABLE ALL';
        break;
      case 'enable':
        title = 'Enable $count user${count > 1 ? 's' : ''}?';
        description = 'Selected users will be able to sign in again.';
        btnColor = SchoolWayTheme.successBright;
        btnLabel = 'ENABLE ALL';
        break;
      default:
        return;
    }

    if (!mounted) return;

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
    final usersCol = swFirestore.collection('users');
    for (final id in ids) {
      final ref = usersCol.doc(id);
      switch (action) {
        case 'delete':
          batch.delete(ref);
          break;
        case 'disable':
          batch.update(ref, {'isActive': false});
          break;
        case 'enable':
          batch.update(ref, {'isActive': true});
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
                  ? '$count user${count > 1 ? 's' : ''} deleted'
                  : '$count user${count > 1 ? 's' : ''} ${action}d',
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
                category: 'users',
                message: 'User operation failed.',
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
        backgroundColor: SchoolWayTheme.background,
        appBar: AppBar(
          backgroundColor: SchoolWayTheme.background,
          elevation: 0,
          foregroundColor: SchoolWayTheme.navy,
          leading: _selectionMode
              ? IconButton(
                  icon: Icon(Icons.close),
                  onPressed: _exitSelectionMode,
                )
              : null,
          title: _selectionMode
              ? Text(
                  '${_selectedIds.length} selected',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    color: SchoolWayTheme.navy,
                  ),
                )
              : Text(
                  AppLocalizations.of(context).userManagement,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    color: SchoolWayTheme.navy,
                  ),
                ),
          actions: _selectionMode
              ? [
                  TextButton(
                    onPressed: _isBatchActing || _visibleUserIds.isEmpty
                        ? null
                        : _toggleSelectAllVisibleUsers,
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
                    onPressed: () => _showAddUserDialog(context),
                    tooltip: AppLocalizations.of(context).addUser2,
                  ),
                ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                if (!_selectionMode) ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            if (_debounce?.isActive ?? false) {
                              _debounce!.cancel();
                            }
                            _debounce = Timer(Duration(milliseconds: 300), () {
                              if (mounted) {
                                setState(() {
                                  _searchQuery = value.toLowerCase();
                                });
                              }
                            });
                          },
                          decoration: InputDecoration(
                            hintText: AppLocalizations.of(
                              context,
                            ).searchByNameOrEmail,
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
                              borderSide: BorderSide(
                                color: SchoolWayTheme.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: SchoolWayTheme.border,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: SchoolWayTheme.navy,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildFilterChip('All'),
                              _buildFilterChip('Parent'),
                              _buildFilterChip('Driver'),
                              _buildFilterChip('Admin'),
                              _buildFilterChip('Unassigned'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  SizedBox(height: 8),
                ],
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: swFirestore
                        .collection('users')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
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

                      var docs = snapshot.data?.docs ?? [];

                      docs = docs.where((doc) {
                        final data = doc.data();
                        final role =
                            (data['role'] as String?)?.toLowerCase() ?? '';
                        final email =
                            (data['email'] as String?)?.toLowerCase() ?? '';
                        final firstName =
                            (data['firstName'] as String?)?.toLowerCase() ?? '';
                        final lastName =
                            (data['lastName'] as String?)?.toLowerCase() ?? '';

                        if (_searchQuery.isNotEmpty) {
                          if (!email.contains(_searchQuery) &&
                              !firstName.contains(_searchQuery) &&
                              !lastName.contains(_searchQuery)) {
                            return false;
                          }
                        }

                        if (_selectedFilter == 'All') return true;
                        if (_selectedFilter == 'Unassigned') {
                          return role.isEmpty;
                        }
                        return role == _selectedFilter.toLowerCase();
                      }).toList();

                      if (_selectionMode && _showSelectedOnly) {
                        docs = docs
                            .where((doc) => _selectedIds.contains(doc.id))
                            .toList();
                      }

                      _visibleUserIds = docs
                          .map((d) => d.id)
                          .toList(growable: false);

                      if (docs.isEmpty) {
                        return Center(
                          child: Text(
                            AppLocalizations.of(context).noUsersFound,
                            style: TextStyle(fontFamily: 'Lexend'),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          if (_selectionMode) _buildSelectAllBar(docs),
                          Expanded(
                            child: ListView.builder(
                              key: const PageStorageKey<String>(
                                'user_management_list',
                              ),
                              controller: _listScrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final doc = docs[index];
                                return FadeInAndSlide(
                                  index: index,
                                  child: _UserCard(
                                    key: ValueKey(doc.id),
                                    userDoc: doc,
                                    isSelectionMode: _selectionMode,
                                    isSelected: _selectedIds.contains(doc.id),
                                    allowDelete: !_userDocIsCurrentUser(
                                      doc.data(),
                                    ),
                                    onLongPress: () =>
                                        _enterSelectionMode(doc.id),
                                    onSelectToggle: () =>
                                        _toggleSelection(doc.id),
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

  Widget _buildSelectAllBar(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final allSelected =
        docs.isNotEmpty && docs.every((d) => _selectedIds.contains(d.id));
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
                  _selectedIds.removeAll(docs.map((d) => d.id));
                } else {
                  _selectionMode = true;
                  _selectedIds.addAll(docs.map((d) => d.id));
                }
              });
            },
          ),
          Flexible(
            child: Text(
              allSelected ? 'Deselect all' : 'Select all (${docs.length})',
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
              child: _BatchBtn(
                icon: Icons.block,
                label: AppLocalizations.of(context).disable,
                color: SchoolWayTheme.warning,
                enabled: !_isBatchActing,
                onTap: () => _batchAction('disable'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _BatchBtn(
                icon: Icons.check_circle_outline,
                label: AppLocalizations.of(context).enable,
                color: SchoolWayTheme.successBright,
                enabled: !_isBatchActing,
                onTap: () => _batchAction('enable'),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _BatchBtn(
                icon: Icons.delete_outline,
                label: AppLocalizations.of(context).delete,
                color: SchoolWayTheme.danger,
                enabled: !_isBatchActing,
                onTap: () => _batchAction('delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            color: isSelected ? SchoolWayTheme.surface : SchoolWayTheme.primary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = label;
          });
        },
        selectedColor: SchoolWayTheme.primary,
        backgroundColor: SchoolWayTheme.surface,
        checkmarkColor: SchoolWayTheme.surface,
      ),
    );
  }

  void _showAddUserDialog(BuildContext context) {
    final usernameController = TextEditingController();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final countryCodeController = TextEditingController(text: '+60');
    final passwordController = TextEditingController();
    String selectedRole = 'Parent';
    String selectedGender = 'Male';
    bool obscurePassword = true;

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
                      AppLocalizations.of(context).addNewUser,
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
                      controller: usernameController,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).username,
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
                    TextField(
                      controller: emailController,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).email2,
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(
                          context,
                        ).temporaryPassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(
                            () => obscurePassword = !obscurePassword,
                          ),
                        ),
                      ),
                      obscureText: obscurePassword,
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: countryCodeController,
                            decoration: _pillFieldDecoration(
                              hintText: AppLocalizations.of(context).code,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: phoneController,
                            decoration: _pillFieldDecoration(
                              hintText: AppLocalizations.of(
                                context,
                              ).phoneNumber,
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedGender,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).gender,
                      ),
                      items: ['Male', 'Female', 'Other']
                          .map(
                            (gender) => DropdownMenuItem(
                              value: gender,
                              child: Text(
                                gender,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedGender = value!;
                        });
                      },
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: _pillFieldDecoration(
                        hintText: AppLocalizations.of(context).role2,
                      ),
                      items: ['Parent', 'Driver', 'Admin']
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(
                                role,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedRole = value!;
                        });
                      },
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          final username = usernameController.text.trim();

                          if (username.isEmpty ||
                              firstNameController.text.isEmpty ||
                              lastNameController.text.isEmpty ||
                              emailController.text.isEmpty ||
                              passwordController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).pleaseFillAllRequiredFields,
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                              ),
                            );
                            return;
                          }

                          // Validate username (no spaces)
                          if (username.contains(' ')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).usernameCannotContainSpaces,
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                              ),
                            );
                            return;
                          }

                          if (passwordController.text.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppLocalizations.of(
                                    context,
                                  ).passwordMustBeAtLeast6Characters,
                                  style: TextStyle(fontFamily: 'Lexend'),
                                ),
                              ),
                            );
                            return;
                          }

                          try {
                            await _createUserRecord(
                              username: username,
                              firstName: firstNameController.text,
                              lastName: lastNameController.text,
                              email: emailController.text,
                              password: passwordController.text,
                              role: selectedRole,
                              gender: selectedGender,
                              phoneNumber: phoneController.text,
                              countryCode: countryCodeController.text,
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'User created successfully!\nUsername: $username\nEmail: ${emailController.text}',
                                    style: TextStyle(fontFamily: 'Lexend'),
                                  ),
                                  duration: Duration(seconds: 3),
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
                          elevation: 0,
                        ),
                        child: Text(
                          AppLocalizations.of(context).addUser,
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

class _UserCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> userDoc;
  final bool isSelectionMode;
  final bool isSelected;
  final bool allowDelete;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectToggle;

  const _UserCard({
    super.key,
    required this.userDoc,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.allowDelete = true,
    this.onLongPress,
    this.onSelectToggle,
  });

  @override
  Widget build(BuildContext context) {
    final data = userDoc.data();
    final uid = userDoc.id;
    final email = data['email'] as String? ?? '(no email)';
    final firstName = data['firstName'] as String? ?? '';
    final lastName = data['lastName'] as String? ?? '';
    final role = (data['role'] as String?)?.toLowerCase() ?? '';
    final isActive = data['isActive'] as bool? ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isSelected ? SchoolWayTheme.primary.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: isSelectionMode
            ? onSelectToggle
            : () => _showUserDetailsDialog(context, uid, data),
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
                backgroundColor: _getRoleColor(role).withValues(alpha: 0.2),
                child: Text(
                  _getInitials(firstName, lastName),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    color: _getRoleColor(role),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: 16),
              // User Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$firstName $lastName'.trim().isEmpty
                          ? email
                          : '$firstName $lastName',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14,
                        color: SchoolWayTheme.primary,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        // Role Badge
                        if (role.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getRoleColor(role).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              role.toUpperCase(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _getRoleColor(role),
                              ),
                            ),
                          ),
                        if (role.isNotEmpty) SizedBox(width: 8),
                        // Status Indicators
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
                              AppLocalizations.of(context).disabled,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: SchoolWayTheme.muted,
                              ),
                            ),
                          ),
                        Spacer(),
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
                  tooltip: AppLocalizations.of(context).userActions,
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
                  onSelected: (value) =>
                      _handleAction(context, value, uid, data),
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
                            isActive ? 'Disable User' : 'Enable User',
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
                    if (allowDelete) ...[
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
                              AppLocalizations.of(context).deleteUser,
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return SchoolWayTheme.danger;
      case 'driver':
        return SchoolWayTheme.info;
      case 'parent':
        return SchoolWayTheme.success;
      default:
        return SchoolWayTheme.muted;
    }
  }

  String _getInitials(String firstName, String lastName) {
    final first = firstName.isNotEmpty ? firstName[0].toUpperCase() : '';
    final last = lastName.isNotEmpty ? lastName[0].toUpperCase() : '';
    return first + last;
  }

  void _handleAction(
    BuildContext context,
    String action,
    String uid,
    Map<String, dynamic> data,
  ) async {
    switch (action) {
      case 'edit':
        _showEditDialog(context, uid, data);
        break;
      case 'toggle_status':
        await _toggleUserStatus(
          context,
          uid,
          data['isActive'] as bool? ?? true,
        );
        break;
      case 'delete':
        if (_userDocIsCurrentUser(data)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context).youCannotDeleteYourOwnAccount,
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
                backgroundColor: SchoolWayTheme.danger,
              ),
            );
          }
          return;
        }
        await _deleteUser(context, uid);
        break;
    }
  }

  void _showUserDetailsDialog(
    BuildContext context,
    String uid,
    Map<String, dynamic> data,
  ) {
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
                    AppLocalizations.of(context).userDetails,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                  SizedBox(height: 12),
                  _DetailRow(
                    'Name',
                    '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}',
                  ),
                  _DetailRow('Email', data['email'] ?? 'N/A'),
                  _DetailRow(
                    'Role',
                    (data['role'] as String?)?.toUpperCase() ?? 'UNASSIGNED',
                  ),
                  _DetailRow(
                    'Phone',
                    '${data['countryCode'] ?? ''} ${data['phoneNumber'] ?? ''}'
                        .trim(),
                  ),
                  _DetailRow('Gender', data['gender'] ?? 'N/A'),
                  _DetailRow(
                    'Status',
                    (data['isActive'] ?? true) ? 'Active' : 'Disabled',
                  ),
                  _DetailRow('UID', uid),
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

  void _showEditDialog(
    BuildContext context,
    String uid,
    Map<String, dynamic> data,
  ) {
    final firstNameController = TextEditingController(
      text: data['firstName'] ?? '',
    );
    final lastNameController = TextEditingController(
      text: data['lastName'] ?? '',
    );
    final emailController = TextEditingController(text: data['email'] ?? '');
    final phoneController = TextEditingController(
      text: data['phoneNumber'] ?? '',
    );
    final countryCodeController = TextEditingController(
      text: data['countryCode'] ?? '',
    );

    // Handle role case-insensitively
    final userRole = (data['role'] as String?)?.toLowerCase() ?? '';
    String selectedRole = 'Parent'; // Default
    if (userRole == 'admin') {
      selectedRole = 'Admin';
    } else if (userRole == 'driver') {
      selectedRole = 'Driver';
    } else if (userRole == 'parent') {
      selectedRole = 'Parent';
    }

    // Handle gender case-insensitively
    final userGender = (data['gender'] as String?) ?? '';
    String selectedGender = 'Male'; // Default
    if (userGender.toLowerCase() == 'female') {
      selectedGender = 'Female';
    } else if (userGender.toLowerCase() == 'other') {
      selectedGender = 'Other';
    } else if (userGender.toLowerCase() == 'male') {
      selectedGender = 'Male';
    }

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
                    Text(
                      AppLocalizations.of(context).editUserDetails,
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
                    SizedBox(height: 12),
                    TextField(
                      controller: lastNameController,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).lastName,
                        labelStyle: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).email,
                        labelStyle: TextStyle(fontFamily: 'Lexend'),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: countryCodeController,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context).code,
                              labelStyle: TextStyle(fontFamily: 'Lexend'),
                              hintText: AppLocalizations.of(context).text60,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: phoneController,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(
                                context,
                              ).phoneNumber,
                              labelStyle: TextStyle(fontFamily: 'Lexend'),
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedGender,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).gender,
                        labelStyle: TextStyle(fontFamily: 'Lexend'),
                      ),
                      items: ['Male', 'Female', 'Other']
                          .map(
                            (gender) => DropdownMenuItem(
                              value: gender,
                              child: Text(
                                gender,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedGender = value!;
                        });
                      },
                    ),
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(context).role,
                        labelStyle: TextStyle(fontFamily: 'Lexend'),
                      ),
                      items: ['Parent', 'Driver', 'Admin']
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(
                                role,
                                style: TextStyle(fontFamily: 'Lexend'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedRole = value!;
                        });
                      },
                    ),
                    SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (firstNameController.text.isEmpty ||
                              lastNameController.text.isEmpty ||
                              emailController.text.isEmpty) {
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

                          try {
                            await AdminAccountService.updateUser(uid, {
                              'firstName': firstNameController.text,
                              'lastName': lastNameController.text,
                              'email': emailController.text,
                              'phoneNumber': phoneController.text,
                              'countryCode': countryCodeController.text,
                              'gender': selectedGender,
                              'role': selectedRole,
                            });
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    AppLocalizations.of(
                                      context,
                                    ).userUpdatedSuccessfully,
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
        ),
      ),
    );
  }

  Future<void> _toggleUserStatus(
    BuildContext context,
    String uid,
    bool currentStatus,
  ) async {
    try {
      await AdminAccountService.updateUser(uid, {'isActive': !currentStatus});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !currentStatus ? 'User enabled' : 'User disabled',
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
                category: 'users',
                message: 'User operation failed.',
              ),
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(BuildContext context, String uid) async {
    final snap = await swFirestore.collection('users').doc(uid).get();
    final row = snap.data();
    if (row != null && _userDocIsCurrentUser(row)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).youCannotDeleteYourOwnAccount,
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: SchoolWayTheme.danger,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

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
                  AppLocalizations.of(context).deleteUser2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  AppLocalizations.of(context).thisActionCannotBeUndoneAreYou,
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
        await AdminAccountService.deleteUser(uid);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context).userDeleted,
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

class _BatchBtn extends StatelessWidget {
  const _BatchBtn({
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
