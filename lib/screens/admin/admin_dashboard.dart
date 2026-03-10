import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/task_model.dart';
import '../../models/progress_request_model.dart';
import '../../models/user_model.dart';
import '../../models/ngo_model.dart';
import '../../services/auth_service.dart';
import '../../services/ngo_service.dart';
import '../../services/task_service.dart';
import '../../services/user_service.dart';
import '../auth/login_screen.dart';
import 'create_task_screen.dart';
import 'task_detail_screen.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
class _C {
  // Backgrounds
  static const bg = Color(0xFFEEF2F8);
  static const heroCard = Color(0xFF0D1B3E);

  // Accents
  static const blue = Color(0xFF4A6CF7);
  static const blueLight = Color(0xFFEEF2FF);
  static const green = Color(0xFF22C55E);
  static const greenLight = Color(0xFFECFDF5);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);

  // Text
  static const textPri = Color(0xFF0D1B3E);
  static const textSec = Color(0xFF6B7280);
  static const textTer = Color(0xFFB0B7C3);

  // Borders / Dividers
  static const border = Color(0xFFE5E9F0);
  static const divider = Color(0xFFF1F4F9);

}

// ─── Urgency colour helper ────────────────────────────────────────────────────
Color taskUrgencyColor(DateTime createdAt, DateTime deadline) {
  final now = DateTime.now();
  final total = deadline.difference(createdAt).inMinutes;
  final remaining = deadline.difference(now).inMinutes;
  if (remaining <= 0 || total <= 0) return _C.red;
  final pct = (remaining / total) * 100;
  if (pct > 50) return _C.green;
  if (pct > 30) return _C.orange;
  return _C.red;
}

// ─── Root Dashboard ───────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard>
    with TickerProviderStateMixin {
  final _auth = AuthService();
  final _taskService = TaskService();
  final _userService = UserService();
  final _ngoService = NgoService();

  int _selectedTab = 0;
  UserModel? _currentUser;
  NgoModel? _currentNgo;
  bool _loadingUser = true;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadCurrentUser();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final uid = _auth.currentUser?.uid ?? '';
      final profile = await _auth.getUserProfile(uid);
      NgoModel? ngo;
      final ngoId = profile.ngoId;
      if (ngoId != null && ngoId.isNotEmpty) {
        ngo = await _ngoService.getNgoById(ngoId);
      }
      if (mounted) {
        setState(() {
          _currentUser = profile;
          _currentNgo = ngo;
          _loadingUser = false;
        });
        _fadeCtrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingUser) {
      return const Scaffold(
        backgroundColor: _C.bg,
        body: Center(child: _PulseLoader()),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _C.bg,
        extendBody: true,
        body: FadeTransition(
          opacity: _fadeAnim,
          child: _selectedTab == 0
              ? _TasksTab(
                  currentUser: _currentUser,
                  currentNgo: _currentNgo,
                  taskService: _taskService,
                  userService: _userService,
                )
              : _RequestsTab(
                  currentUser: _currentUser,
                  taskService: _taskService,
                  userService: _userService,
                ),
        ),
        bottomNavigationBar: _BottomNav(
          selected: _selectedTab,
          pendingBadge: _currentUser != null
              ? StreamBuilder<List<ProgressRequestModel>>(
                  stream: _taskService.streamPendingRequestsForAdmin(
                    _currentUser!.uid,
                  ),
                  builder: (_, snap) => snap.data?.isNotEmpty == true
                      ? Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: _C.red,
                            shape: BoxShape.circle,
                          ),
                        )
                      : const SizedBox.shrink(),
                )
              : null,
          onTab: (i) {
            if (i == 2) {
              _confirmSignOut();
              return;
            }
            setState(() => _selectedTab = i);
          },
        ),
        floatingActionButton: _selectedTab == 0
            ? _FAB(
                onTap: () {
                  if (_currentUser == null) return;
                  Navigator.push(
                    context,
                    _fadeRoute(
                      CreateTaskScreen(
                        adminId: _currentUser!.uid,
                        ngoId: _currentUser!.ngoId ?? '',
                        ngoName: _currentNgo?.name,
                      ),
                    ),
                  );
                },
              )
            : null,
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _LightDialog(
        title: 'Sign Out?',
        body: 'You will be returned to the login screen.',
        confirmLabel: 'Sign Out',
        confirmColor: _C.red,
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    if (ok != true || !mounted) return;
    await _auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}

// ─── Bottom Nav ───────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onTab;
  final Widget? pendingBadge;
  const _BottomNav({
    required this.selected,
    required this.onTab,
    this.pendingBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _C.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.task_alt_rounded,
                label: 'Tasks',
                selected: selected == 0,
                onTap: () => onTab(0),
              ),
              _NavItem(
                icon: Icons.pending_actions_rounded,
                label: 'Requests',
                selected: selected == 1,
                onTap: () => onTab(1),
                badge: pendingBadge,
              ),
              _NavItem(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                selected: false,
                onTap: () => onTab(2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? badge;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? _C.blue : _C.textTer;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 3,
                width: selected ? 24 : 0,
                margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                  color: _C.blue,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: color, size: 22),
                  if (badge != null)
                    Positioned(top: -3, right: -5, child: badge!),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── FAB ─────────────────────────────────────────────────────────────────────
class _FAB extends StatelessWidget {
  final VoidCallback onTap;
  const _FAB({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4A6CF7), Color(0xFF1A2B5E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _C.blue.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — TASKS
// ═══════════════════════════════════════════════════════════════════════════════
class _TasksTab extends StatefulWidget {
  final UserModel? currentUser;
  final NgoModel? currentNgo;
  final TaskService taskService;
  final UserService userService;
  const _TasksTab({
    required this.currentUser,
    this.currentNgo,
    required this.taskService,
    required this.userService,
  });

  @override
  State<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<_TasksTab> {
  String? _filter; // null = show all, 'active', 'inviting', 'completed'

  @override
  Widget build(BuildContext context) {
    if (widget.currentUser == null) {
      return _EmptyState(
        icon: Icons.error_outline_rounded,
        message: 'Could not load profile.',
      );
    }

    return StreamBuilder<List<TaskModel>>(
      stream: widget.taskService.streamAdminTasks(widget.currentUser!.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: _PulseLoader());
        }
        if (snap.hasError) {
          final err = snap.error.toString();
          if (err.contains('failed-precondition') ||
              err.contains('index')) {
            return _EmptyState(
              icon: Icons.cloud_off_rounded,
              message:
                  'Database index required.\nPlease contact your developer to create the required Firestore index.',
              color: _C.orange,
            );
          }
          return _EmptyState(
            icon: Icons.error_outline_rounded,
            message: 'Error loading tasks.',
          );
        }

        final allTasks = (snap.data ?? [])
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final active = allTasks.where((t) => t.status == 'active').length;
        final inviting = allTasks.where((t) => t.status == 'inviting').length;
        final completed = allTasks.where((t) => t.status == 'completed').length;

        final tasks = _filter == null
            ? allTasks
            : allTasks.where((t) => t.status == _filter).toList();

        return CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // ── Header (scrolls away) ──────────────────────────────────
            SliverToBoxAdapter(
              child: _Header(
                currentUser: widget.currentUser!,
                currentNgo: widget.currentNgo,
              ),
            ),

            // ── Stat bar ───────────────────────────────────────────────
            if (allTasks.isNotEmpty)
              SliverToBoxAdapter(
                child: _StatBar(
                  active: active,
                  inviting: inviting,
                  completed: completed,
                  selected: _filter,
                  onFilter: (f) {
                    setState(() {
                      _filter = _filter == f ? null : f;
                    });
                  },
                ),
              ),

            // ── Task list or empty state ───────────────────────────────
            if (tasks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.assignment_outlined,
                  message: _filter != null
                      ? 'No $_filter tasks.'
                      : 'No tasks yet.\nTap + to create your first task.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _TaskCard(
                      task: tasks[i],
                      taskService: widget.taskService,
                      onTap: () => Navigator.push(
                        context,
                        _fadeRoute(
                          TaskDetailScreen(
                            taskId: tasks[i].taskId,
                            adminId: widget.currentUser!.uid,
                            ngoId: widget.currentUser!.ngoId ?? '',
                            taskService: widget.taskService,
                            userService: widget.userService,
                          ),
                        ),
                      ),
                    ),
                    childCount: tasks.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final UserModel currentUser;
  final NgoModel? currentNgo;
  const _Header({required this.currentUser, this.currentNgo});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                // Logo + title
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _C.heroCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.shield_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dashboard',
                      style: GoogleFonts.dmSans(
                        color: _C.textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Text(
                      'Admin',
                      style: GoogleFonts.dmSans(
                        color: _C.textSec,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Date pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _C.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 13,
                        color: _C.textSec,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${months[now.month - 1]} ${now.day}, ${now.year}',
                        style: GoogleFonts.dmSans(
                          color: _C.textSec,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Hero Card ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0D1B3E), Color(0xFF1A2B5E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0D1B3E).withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            currentUser.name.isNotEmpty
                                ? currentUser.name[0].toUpperCase()
                                : 'A',
                            style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome back',
                    style: GoogleFonts.dmSans(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    currentUser.name,
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  // ── NGO Info Row ──────────────────────────────────────
                  if (currentNgo != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.apartment_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentNgo!.name,
                                  style: GoogleFonts.dmSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Join Code: ${currentNgo!.joinCode}',
                                  style: GoogleFonts.dmSans(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _C.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'NGO',
                              style: GoogleFonts.dmSans(
                                color: _C.green,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.task_alt_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Task Manager',
                            style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Manage your NGO tasks',
                            style: GoogleFonts.dmSans(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          'ADMIN',
                          style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Section label ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: _C.blue,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Your Tasks',
                  style: GoogleFonts.dmSans(
                    color: _C.textPri,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Stat Bar ─────────────────────────────────────────────────────────────────
class _StatBar extends StatelessWidget {
  final int active, inviting, completed;
  final String? selected;
  final ValueChanged<String> onFilter;
  const _StatBar({
    required this.active,
    required this.inviting,
    required this.completed,
    required this.selected,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          _StatPill(
            label: 'Active',
            value: active,
            color: _C.green,
            bgColor: _C.greenLight,
            isSelected: selected == 'active',
            onTap: () => onFilter('active'),
          ),
          const SizedBox(width: 8),
          _StatPill(
            label: 'Inviting',
            value: inviting,
            color: _C.blue,
            bgColor: _C.blueLight,
            isSelected: selected == 'inviting',
            onTap: () => onFilter('inviting'),
          ),
          const SizedBox(width: 8),
          _StatPill(
            label: 'Done',
            value: completed,
            color: _C.textSec,
            bgColor: _C.divider,
            isSelected: selected == 'completed',
            onTap: () => onFilter('completed'),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final Color bgColor;
  final bool isSelected;
  final VoidCallback onTap;
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$value',
                style: GoogleFonts.dmSans(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.dmSans(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Task Card ────────────────────────────────────────────────────────────────
class _TaskCard extends StatefulWidget {
  final TaskModel task;
  final VoidCallback onTap;
  final TaskService taskService;
  const _TaskCard({required this.task, required this.onTap, required this.taskService});
  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _pressed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.task.status == 'inviting') {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isCompleted = task.status == 'completed';
    final urgency = isCompleted ? _C.green : taskUrgencyColor(task.createdAt, task.deadline);
    final isExpiredInviting = task.status == 'inviting' &&
        DateTime.now().isAfter(task.inviteDeadline);
    final (String chipLabel, Color chipColor) = isExpiredInviting
        ? ('EXPIRED', _C.orange)
        : switch (task.status) {
            'active' => ('ACTIVE', _C.green),
            'completed' => ('DONE', _C.textSec),
            _ => ('INVITING', _C.blue),
          };

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (isExpiredInviting) {
          _showExpiredDialog(context, task);
        } else {
          widget.onTap();
        }
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isExpiredInviting
                  ? _C.orange.withValues(alpha: 0.4)
                  : _C.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Urgency strip — green for completed
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: isCompleted ? _C.green : (isExpiredInviting ? _C.orange : urgency),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.title,
                                style: GoogleFonts.dmSans(
                                  color: _C.textPri,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _Chip(label: chipLabel, color: chipColor),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          task.description,
                          style: GoogleFonts.dmSans(
                            color: _C.textSec,
                            fontSize: 12,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        if (isCompleted)
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 18, color: _C.green),
                              const SizedBox(width: 6),
                              Text(
                                'Completed',
                                style: GoogleFonts.dmSans(
                                  color: _C.green,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          )
                        else ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: task.mainProgress / 100,
                            backgroundColor: _C.border,
                            valueColor: AlwaysStoppedAnimation(urgency),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.people_outline_rounded,
                              size: 13,
                              color: _C.textTer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${task.assignedVolunteers.length}/${task.maxVolunteers}',
                              style: GoogleFonts.dmSans(
                                color: _C.textSec,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.schedule_outlined,
                              size: 13,
                              color: _C.textTer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${task.deadline.day}/${task.deadline.month}/${task.deadline.year}',
                              style: GoogleFonts.dmSans(
                                color: _C.textSec,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${task.mainProgress.toStringAsFixed(0)}%',
                              style: GoogleFonts.dmSans(
                                color: urgency,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        ],
                        // ── Invite timer / expired banner ──
                        if (task.status == 'inviting') ...[
                          const SizedBox(height: 8),
                          if (isExpiredInviting)
                            Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    size: 13, color: _C.orange),
                                const SizedBox(width: 4),
                                Text(
                                  'Action required \u2014 Tap to resolve',
                                  style: GoogleFonts.dmSans(
                                    color: _C.orange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          else
                            Builder(builder: (_) {
                              final remaining =
                                  task.inviteDeadline.difference(DateTime.now());
                              final hours = remaining.inHours;
                              final minutes = remaining.inMinutes % 60;
                              return Row(
                                children: [
                                  const Icon(Icons.timer_outlined,
                                      size: 13, color: _C.blue),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${hours}h ${minutes}m left to accept invites',
                                    style: GoogleFonts.dmSans(
                                      color: _C.blue,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              );
                            }),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showExpiredDialog(BuildContext context, TaskModel task) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _C.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.timer_off_rounded,
                        color: _C.orange, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Invite Period Expired',
                      style: GoogleFonts.dmSans(
                        color: _C.textPri,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '${task.assignedVolunteers.length} of ${task.maxVolunteers} volunteers joined "${task.title}".',
                style: GoogleFonts.dmSans(
                  color: _C.textSec,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'What would you like to do?',
                style: GoogleFonts.dmSans(
                  color: _C.textSec,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              if (task.assignedVolunteers.isNotEmpty) ...[
                GestureDetector(
                  onTap: () async {
                    Navigator.pop(ctx);
                    await widget.taskService.activateTask(task.taskId);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: _C.green,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _C.green.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'Continue with ${task.assignedVolunteers.length} volunteer${task.assignedVolunteers.length > 1 ? 's' : ''}',
                          style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              GestureDetector(
                onTap: () async {
                  Navigator.pop(ctx);
                  await widget.taskService.deleteTask(task.taskId);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _C.red.withValues(alpha: 0.4)),
                    color: _C.red.withValues(alpha: 0.06),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: _C.red, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Delete Task',
                        style: GoogleFonts.dmSans(
                          color: _C.red,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onTap();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _C.border),
                    color: _C.divider,
                  ),
                  child: Center(
                    child: Text(
                      'View Details',
                      style: GoogleFonts.dmSans(
                        color: _C.textSec,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — REQUESTS
// ═══════════════════════════════════════════════════════════════════════════════
class _RequestsTab extends StatelessWidget {
  final UserModel? currentUser;
  final TaskService taskService;
  final UserService userService;
  const _RequestsTab({
    required this.currentUser,
    required this.taskService,
    required this.userService,
  });

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const _EmptyState(
        icon: Icons.error_outline_rounded,
        message: 'Could not load profile.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Requests',
                  style: GoogleFonts.dmSans(
                    color: _C.textPri,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Review volunteer progress updates',
                  style: GoogleFonts.dmSans(color: _C.textSec, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ProgressRequestModel>>(
            stream: taskService.streamPendingRequestsForAdmin(currentUser!.uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: _PulseLoader());
              }
              final requests = snap.data ?? [];
              if (requests.isEmpty) {
                return const _EmptyState(
                  icon: Icons.inbox_outlined,
                  message: 'All clear!\nNo pending requests.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                itemCount: requests.length,
                itemBuilder: (_, i) => _RequestCard(
                  request: requests[i],
                  taskService: taskService,
                  userService: userService,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Request Card ─────────────────────────────────────────────────────────────
class _RequestCard extends StatefulWidget {
  final ProgressRequestModel request;
  final TaskService taskService;
  final UserService userService;
  const _RequestCard({
    required this.request,
    required this.taskService,
    required this.userService,
  });
  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _processing = false;
  String? _volunteerName;

  @override
  void initState() {
    super.initState();
    _loadName();
  }

  Future<void> _loadName() async {
    final u = await widget.userService.getUserById(widget.request.volunteerId);
    if (mounted && u != null) setState(() => _volunteerName = u.name);
  }

  Future<void> _approve() async {
    setState(() => _processing = true);
    try {
      await widget.taskService.approveProgressRequest(widget.request);
      if (!mounted) return;
      _snack(
        context,
        'Progress approved!',
        _C.green,
        Icons.check_circle_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', _C.red, Icons.error_rounded);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _reject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _LightDialog(
        title: 'Reject Request?',
        body: "The volunteer's progress will not be updated.",
        confirmLabel: 'Reject',
        confirmColor: _C.red,
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    if (ok != true) return;
    setState(() => _processing = true);
    try {
      await widget.taskService.rejectProgressRequest(widget.request);
      if (!mounted) return;
      _snack(
        context,
        'Request rejected.',
        _C.orange,
        Icons.remove_circle_rounded,
      );
    } catch (e) {
      if (!mounted) return;
      _snack(context, 'Error: $e', _C.red, Icons.error_rounded);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    final name = _volunteerName ?? '…';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                _Avatar(name: name, color: _C.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.dmSans(
                          color: _C.textPri,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        req.taskTitle,
                        style: GoogleFonts.dmSans(
                          color: _C.textSec,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _C.divider,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _ProgressBadge(value: req.currentProgress, color: _C.textSec),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(height: 1, width: 20, color: _C.textTer),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: _C.textTer,
                            size: 14,
                          ),
                        ),
                        Container(height: 1, width: 20, color: _C.textTer),
                      ],
                    ),
                  ),
                  _ProgressBadge(value: req.requestedProgress, color: _C.green),
                ],
              ),
            ),
          ),
          if (req.mandatoryNote.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote_rounded, size: 14, color: _C.textTer),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      req.mandatoryNote,
                      style: GoogleFonts.dmSans(
                        color: _C.textSec,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: _processing
                ? const Center(child: _PulseLoader())
                : Row(
                    children: [
                      Expanded(
                        child: _OutlineActionBtn(
                          label: 'Reject',
                          icon: Icons.close_rounded,
                          color: _C.red,
                          onTap: _reject,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _FilledActionBtn(
                          label: 'Approve',
                          icon: Icons.check_rounded,
                          color: _C.green,
                          onTap: _approve,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable Small Widgets ───────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  final String name;
  final Color color;
  const _Avatar({required this.name, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Center(
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: GoogleFonts.dmSans(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: GoogleFonts.dmSans(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
  );
}

class _ProgressBadge extends StatelessWidget {
  final double value;
  final Color color;
  const _ProgressBadge({required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      '${value.toStringAsFixed(0)}%',
      style: GoogleFonts.dmSans(
        color: color,
        fontSize: 15,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _OutlineActionBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _OutlineActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  State<_OutlineActionBtn> createState() => _OutlineActionBtnState();
}

class _OutlineActionBtnState extends State<_OutlineActionBtn> {
  bool _p = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _p = true),
    onTapUp: (_) {
      setState(() => _p = false);
      widget.onTap();
    },
    onTapCancel: () => setState(() => _p = false),
    child: AnimatedScale(
      scale: _p ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 90),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.color.withValues(alpha: 0.4)),
          color: widget.color.withValues(alpha: 0.06),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: widget.color, size: 15),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: GoogleFonts.dmSans(
                color: widget.color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FilledActionBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _FilledActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  State<_FilledActionBtn> createState() => _FilledActionBtnState();
}

class _FilledActionBtnState extends State<_FilledActionBtn> {
  bool _p = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _p = true),
    onTapUp: (_) {
      setState(() => _p = false);
      widget.onTap();
    },
    onTapCancel: () => setState(() => _p = false),
    child: AnimatedScale(
      scale: _p ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 90),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: widget.color,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  const _EmptyState({
    required this.icon,
    required this.message,
    this.color = _C.textTer,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.08),
            ),
            child: Icon(icon, size: 40, color: color),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(color: color, fontSize: 14, height: 1.6),
          ),
        ],
      ),
    ),
  );
}

class _PulseLoader extends StatelessWidget {
  const _PulseLoader();
  @override
  Widget build(BuildContext context) =>
      const CircularProgressIndicator(color: _C.blue, strokeWidth: 2.5);
}

class _LightDialog extends StatelessWidget {
  final String title, body, confirmLabel;
  final Color confirmColor;
  final VoidCallback onConfirm, onCancel;
  const _LightDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.confirmColor,
    required this.onConfirm,
    required this.onCancel,
  });
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    child: Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              color: _C.textPri,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: GoogleFonts.dmSans(
              color: _C.textSec,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onCancel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _C.border),
                      color: _C.divider,
                    ),
                    child: Center(
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.dmSans(
                          color: _C.textSec,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onConfirm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: confirmColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: confirmColor.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        confirmLabel,
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
void _snack(BuildContext context, String msg, Color bg, IconData icon) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 8),
          Expanded(child: Text(msg, style: GoogleFonts.dmSans(fontSize: 13))),
        ],
      ),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 2),
    ),
  );
}

PageRoute _fadeRoute(Widget page) => PageRouteBuilder(
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, anim, _, child) =>
      FadeTransition(opacity: anim, child: child),
  transitionDuration: const Duration(milliseconds: 250),
);
