import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:schoolway/core/schoolway_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
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
  List<String> _visibleUserIds = const [];
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

  Future<FirebaseApp> _createSecondaryApp() async {
    final defaultApp = Firebase.app();
    return Firebase.initializeApp(
      name: 'SecondaryApp_${DateTime.now().microsecondsSinceEpoch}',
      options: defaultApp.options,
    );
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
    required FirebaseAuth secondaryAuth,
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

    final usernameDoc = await swFirestore
        .collection('users')
        .doc(trimmedUsername)
        .get();
    if (usernameDoc.exists) {
      throw Exception('Username is already taken');
    }

    UserCredential? userCredential;
    var createdNewAuthUser = false;
    try {
      try {
        userCredential = await secondaryAuth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        createdNewAuthUser = true;
      } on FirebaseAuthException catch (e) {
        if (e.code != 'email-already-in-use') rethrow;

        // "Delete user" in this app removes Firestore profile only. If Auth user
        // already exists for this email, reuse it and recreate the Firestore doc.
        userCredential = await secondaryAuth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      }

      final authUid = userCredential.user?.uid;
      if (authUid == null) {
        throw Exception('Failed to create user account');
      }

      final newUserData = {
        'authUid': authUid,
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'email': email.trim(),
        'phoneNumber': phoneNumber.trim(),
        'countryCode': countryCode.trim().isEmpty ? '+60' : countryCode.trim(),
        'gender': gender.trim().isEmpty ? 'Other' : gender.trim(),
        'role': normalizedRole,
        'emailVerified': false,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await swFirestore
          .collection('users')
          .doc(trimmedUsername)
          .set(newUserData);
    } catch (e) {
      final createdUser = userCredential?.user;
      if (createdNewAuthUser && createdUser != null) {
        try {
          await createdUser.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      // Keep secondary auth isolated and clean between row imports.
      if (secondaryAuth.currentUser != null) {
        await secondaryAuth.signOut();
      }
    }
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
            const SnackBar(
              content: Text(
                'You cannot delete your own account',
                style: TextStyle(fontFamily: 'Lexend'),
              ),
              backgroundColor: Colors.red,
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
        btnColor = Colors.red;
        btnLabel = 'DELETE ALL';
        break;
      case 'disable':
        title = 'Disable $count user${count > 1 ? 's' : ''}?';
        description = 'Selected users will not be able to sign in.';
        btnColor = const Color(0xFFFF9800);
        btnLabel = 'DISABLE ALL';
        break;
      case 'enable':
        title = 'Enable $count user${count > 1 ? 's' : ''}?';
        description = 'Selected users will be able to sign in again.';
        btnColor = const Color(0xFF4CAF50);
        btnLabel = 'ENABLE ALL';
        break;
      default:
        return;
    }

    if (!mounted) return;

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
                'User Management',
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
                  onPressed: _isBatchActing || _visibleUserIds.isEmpty
                      ? null
                      : _toggleSelectAllVisibleUsers,
                  child: Text(_allVisibleSelected() ? 'Deselect All' : 'Select All',
                      style: TextStyle(
                          fontFamily: 'Lexend', color: Color(0xFF0077B6))),
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
                  onPressed: () => _showAddUserDialog(context),
                  tooltip: 'Add User',
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
                      hintText: 'Search by name or email...',
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
                  const SizedBox(height: 12),
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
            const SizedBox(height: 8),
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

                var docs = snapshot.data?.docs ?? [];

                docs = docs.where((doc) {
                  final data = doc.data();
                  final role = (data['role'] as String?)?.toLowerCase() ?? '';
                  final email = (data['email'] as String?)?.toLowerCase() ?? '';
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
                  if (_selectedFilter == 'Unassigned') return role.isEmpty;
                  return role == _selectedFilter.toLowerCase();
                }).toList();

                if (_selectionMode && _showSelectedOnly) {
                  docs = docs.where((doc) => _selectedIds.contains(doc.id)).toList();
                }

                _visibleUserIds = docs.map((d) => d.id).toList(growable: false);

                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No users found',
                      style: TextStyle(fontFamily: 'Lexend'),
                    ),
                  );
                }

                return Column(
                  children: [
                    if (_selectionMode)
                      _buildSelectAllBar(docs),
                    Expanded(
                      child: ListView.builder(
                        key: const PageStorageKey<String>('user_management_list'),
                        controller: _listScrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
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
                              allowDelete: !_userDocIsCurrentUser(doc.data()),
                              onLongPress: () => _enterSelectionMode(doc.id),
                              onSelectToggle: () => _toggleSelection(doc.id),
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

  Widget _buildSelectAllBar(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final allSelected =
        docs.isNotEmpty && docs.every((d) => _selectedIds.contains(d.id));
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
                  _selectedIds.removeAll(docs.map((d) => d.id));
                } else {
                  _selectionMode = true;
                  _selectedIds.addAll(docs.map((d) => d.id));
                }
              });
            },
          ),
          Text(
            allSelected ? 'Deselect all' : 'Select all (${docs.length})',
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
              child: _BatchBtn(
                icon: Icons.block,
                label: 'Disable',
                color: const Color(0xFFFF9800),
                enabled: !_isBatchActing,
                onTap: () => _batchAction('disable'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BatchBtn(
                icon: Icons.check_circle_outline,
                label: 'Enable',
                color: const Color(0xFF4CAF50),
                enabled: !_isBatchActing,
                onTap: () => _batchAction('enable'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _BatchBtn(
                icon: Icons.delete_outline,
                label: 'Delete',
                color: Colors.red,
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
            color: isSelected ? Colors.white : const Color(0xFF0077B6),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = label;
          });
        },
        selectedColor: const Color(0xFF0077B6),
        backgroundColor: Colors.white,
        checkmarkColor: Colors.white,
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
                      'Add New User',
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
                  controller: usernameController,
                  decoration: _pillFieldDecoration(hintText: 'Username *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: firstNameController,
                  decoration: _pillFieldDecoration(hintText: 'First Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastNameController,
                  decoration: _pillFieldDecoration(hintText: 'Last Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: _pillFieldDecoration(hintText: 'Email *'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: _pillFieldDecoration(
                    hintText: 'Temporary Password *',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => obscurePassword = !obscurePassword),
                    ),
                  ),
                  obscureText: obscurePassword,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: countryCodeController,
                        decoration: _pillFieldDecoration(hintText: 'Code'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        decoration: _pillFieldDecoration(hintText: 'Phone Number'),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedGender,
                  decoration: _pillFieldDecoration(hintText: 'Gender'),
                  items: ['Male', 'Female', 'Other']
                      .map(
                        (gender) => DropdownMenuItem(
                          value: gender,
                          child: Text(
                            gender,
                            style: const TextStyle(fontFamily: 'Lexend'),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: _pillFieldDecoration(hintText: 'Role *'),
                  items: ['Parent', 'Driver', 'Admin']
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          child: Text(
                            role,
                            style: const TextStyle(fontFamily: 'Lexend'),
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
                const SizedBox(height: 16),
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
                    const SnackBar(
                      content: Text(
                        'Please fill all required fields',
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                  );
                  return;
                }

                // Validate username (no spaces)
                if (username.contains(' ')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Username cannot contain spaces',
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                  );
                  return;
                }

                if (passwordController.text.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Password must be at least 6 characters',
                        style: TextStyle(fontFamily: 'Lexend'),
                      ),
                    ),
                  );
                  return;
                }

                FirebaseApp? secondaryApp;
                try {
                  secondaryApp = await _createSecondaryApp();
                  final secondaryAuth = FirebaseAuth.instanceFor(
                    app: secondaryApp,
                  );

                  await _createUserRecord(
                    secondaryAuth: secondaryAuth,
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

                  await secondaryApp.delete();
                  secondaryApp = null;

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'User created successfully!\nUsername: $username\nEmail: ${emailController.text}',
                          style: const TextStyle(fontFamily: 'Lexend'),
                        ),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  // Clean up secondary app if it exists
                  if (secondaryApp != null) {
                    try {
                      await secondaryApp.delete();
                    } catch (_) {}
                  }

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
                      elevation: 0,
                    ),
                    child: const Text(
                      'ADD USER',
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
      color: isSelected ? const Color(0xFF0077B6).withValues(alpha: 0.08) : null,
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
                  activeColor: const Color(0xFF0077B6),
                  onChanged: (_) => onSelectToggle?.call(),
                ),
                const SizedBox(width: 4),
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
              const SizedBox(width: 16),
              // User Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$firstName $lastName'.trim().isEmpty
                          ? email
                          : '$firstName $lastName',
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 14,
                        color: Color(0xFF0077B6),
                      ),
                    ),
                    const SizedBox(height: 8),
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
                        if (role.isNotEmpty) const SizedBox(width: 8),
                        // Status Indicators
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
                              'DISABLED',
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        const Spacer(),
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
                  tooltip: 'User actions',
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
                  onSelected: (value) => _handleAction(context, value, uid, data),
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
                            isActive ? 'Disable User' : 'Enable User',
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
                    if (allowDelete) ...[
                      const PopupMenuDivider(height: 1),
                      const PopupMenuItem(
                        value: 'delete',
                        height: 50,
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: Colors.red),
                            SizedBox(width: 12),
                            Text(
                              'Delete User',
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
        return Colors.red;
      case 'driver':
        return Colors.blue;
      case 'parent':
        return Colors.green;
      default:
        return Colors.grey;
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
              const SnackBar(
                content: Text(
                  'You cannot delete your own account',
                  style: TextStyle(fontFamily: 'Lexend'),
                ),
                backgroundColor: Colors.red,
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
                  const Text(
                    'User Details',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 24),
                  ),
                  const SizedBox(height: 12),
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
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Edit User Details',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 24),
                    ),
                    const SizedBox(height: 12),
                TextField(
                  controller: firstNameController,
                  decoration: const InputDecoration(
                    labelText: 'First Name',
                    labelStyle: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Last Name',
                    labelStyle: TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(fontFamily: 'Lexend'),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: countryCodeController,
                        decoration: const InputDecoration(
                          labelText: 'Code',
                          labelStyle: TextStyle(fontFamily: 'Lexend'),
                          hintText: '+60',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          labelStyle: TextStyle(fontFamily: 'Lexend'),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedGender,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    labelStyle: TextStyle(fontFamily: 'Lexend'),
                  ),
                  items: ['Male', 'Female', 'Other']
                      .map(
                        (gender) => DropdownMenuItem(
                          value: gender,
                          child: Text(
                            gender,
                            style: const TextStyle(fontFamily: 'Lexend'),
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
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    labelStyle: TextStyle(fontFamily: 'Lexend'),
                  ),
                  items: ['Parent', 'Driver', 'Admin']
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          child: Text(
                            role,
                            style: const TextStyle(fontFamily: 'Lexend'),
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
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                if (firstNameController.text.isEmpty ||
                    lastNameController.text.isEmpty ||
                    emailController.text.isEmpty) {
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

                try {
                  await swFirestore
                      .collection('users')
                      .doc(uid)
                      .update({
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
                      const SnackBar(
                        content: Text(
                          'User updated successfully',
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: const Text('SAVE', style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
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
      ),
    );
  }

  Future<void> _toggleUserStatus(
    BuildContext context,
    String uid,
    bool currentStatus,
  ) async {
    try {
      await swFirestore.collection('users').doc(uid).update({
        'isActive': !currentStatus,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !currentStatus ? 'User enabled' : 'User disabled',
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

  Future<void> _deleteUser(BuildContext context, String uid) async {
    final snap = await swFirestore.collection('users').doc(uid).get();
    final row = snap.data();
    if (row != null && _userDocIsCurrentUser(row)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You cannot delete your own account',
              style: TextStyle(fontFamily: 'Lexend'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

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
                const Text('Delete User?', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.bold, fontSize: 24)),
                const SizedBox(height: 12),
                const Text('This action cannot be undone. Are you sure?', style: TextStyle(fontFamily: 'Lexend')),
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
        await swFirestore.collection('users').doc(uid).delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'User deleted',
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
              Icon(
                icon,
                color: enabled ? color : Colors.grey,
                size: 22,
              ),
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

