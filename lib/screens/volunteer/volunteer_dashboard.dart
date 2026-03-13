import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/task_model.dart';
import '../../models/task_assignment_model.dart';
import '../../models/progress_request_model.dart';
import '../../models/user_model.dart';
import '../../models/ngo_model.dart';
import '../../services/auth_service.dart';
import '../../services/ngo_service.dart';
import '../../services/task_service.dart';
import '../auth/login_screen.dart';
import '../chat/chat_list_screen.dart';

// ─── Design Tokens (matches admin dashboard) ─────────────────────────────────
class _C {
  static const bg = Color(0xFFEEF2F8);
  static const heroCard = Color(0xFF0D1B3E);
  static const blue = Color(0xFF4A6CF7);
  static const blueLight = Color(0xFFEEF2FF);
  static const green = Color(0xFF22C55E);
  static const greenLight = Color(0xFFECFDF5);
  static const orange = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const textPri = Color(0xFF0D1B3E);
  static const textSec = Color(0xFF6B7280);
  static const textTer = Color(0xFFB0B7C3);
  static const border = Color(0xFFE5E9F0);
  static const divider = Color(0xFFF1F4F9);
}

// ─── Urgency colour helper ────────────────────────────────────────────────────
Color _urgencyColor(DateTime createdAt, DateTime deadline) {
  final now = DateTime.now();
  final total = deadline.difference(createdAt).inMinutes;
  final remaining = deadline.difference(now).inMinutes;
  if (remaining <= 0 || total <= 0) return _C.red;
  final pct = (remaining / total) * 100;
  if (pct > 50) return _C.green;
  if (pct > 30) return _C.orange;
  return _C.red;
}

const Duration _kNetworkTimeout = Duration(seconds: 20);

Future<T> _withNetworkTimeout<T>(Future<T> operation) {
  return operation.timeout(
    _kNetworkTimeout,
    onTimeout: () => throw Exception(
      'Request timed out. Please check your connection and try again.',
    ),
  );
}

// ─── Root Dashboard ───────────────────────────────────────────────────────────
class VolunteerDashboard extends StatefulWidget {
  const VolunteerDashboard({super.key});
  @override
  State<VolunteerDashboard> createState() => _VolunteerDashboardState();
}

class _VolunteerDashboardState extends State<VolunteerDashboard>
    with TickerProviderStateMixin {
  final _auth = AuthService();
  final _taskService = TaskService();
  final _ngoService = NgoService();

  int _selectedTab = 0;
  UserModel? _currentUser;
  NgoModel? _currentNgo;
  bool _loadingUser = true;
  String? _profileLoadError;

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
    _loadUser();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    try {
      final uid = _auth.currentUser?.uid ?? '';
      if (uid.isEmpty) {
        throw Exception('Session expired. Please sign in again.');
      }
      final profile = await _auth.getUserProfile(uid);
      NgoModel? ngo;
      final ngoId = profile.ngoId;
      if (ngoId != null && ngoId.isNotEmpty) {
        ngo = await _withNetworkTimeout(_ngoService.getNgoById(ngoId));
      }
      if (mounted) {
        setState(() {
          _currentUser = profile;
          _currentNgo = ngo;
          _loadingUser = false;
          _profileLoadError = null;
        });
        _fadeCtrl.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingUser = false;
          _profileLoadError = e.toString().replaceAll('Exception: ', '');
        });
      }
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
          child: _buildBody(),
        ),
        bottomNavigationBar: _BottomNav(
          selected: _selectedTab,
          inviteBadge: _currentUser != null
              ? StreamBuilder<List<TaskModel>>(
                  stream: _taskService.streamVolunteerInvites(
                    _currentUser!.uid,
                    ngoId: _currentUser!.ngoId,
                  ),
                  builder: (_, snap) => (snap.data ?? []).isNotEmpty
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
          ngoTasksBadge: _currentUser != null &&
                  _currentUser!.ngoId != null &&
                  _currentUser!.ngoId!.isNotEmpty
              ? StreamBuilder<List<TaskModel>>(
                  stream: _taskService.streamNgoTasks(_currentUser!.ngoId!),
                  builder: (_, snap) {
                    final uid = _currentUser!.uid;
                    final open = (snap.data ?? []).where((t) =>
                        t.status == 'inviting' &&
                        !t.assignedVolunteers.contains(uid) &&
                        !t.declinedBy.contains(uid)).toList();
                    return open.isNotEmpty
                        ? Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: _C.orange,
                              shape: BoxShape.circle,
                            ),
                          )
                        : const SizedBox.shrink();
                  },
                )
              : null,
          onTab: (i) {
            if (i == 4) {
              _confirmSignOut();
              return;
            }
            setState(() => _selectedTab = i);
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_currentUser == null) {
      return _EmptyState(
        icon: Icons.error_outline_rounded,
        message: _profileLoadError ?? 'Could not load profile.',
      );
    }
    switch (_selectedTab) {
      case 1:
        return _InvitesTab(
          currentUser: _currentUser!,
          taskService: _taskService,
        );
      case 2:
        return _NgoTasksTab(
          currentUser: _currentUser!,
          taskService: _taskService,
        );
      case 3:
        return ChatListScreen(currentUser: _currentUser!);
      default:
        return _TasksTab(
          currentUser: _currentUser!,
          currentNgo: _currentNgo,
          taskService: _taskService,
        );
    }
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
  final Widget? inviteBadge;
  final Widget? ngoTasksBadge;
  const _BottomNav({
    required this.selected,
    required this.onTab,
    this.inviteBadge,
    this.ngoTasksBadge,
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
                label: 'My Tasks',
                selected: selected == 0,
                onTap: () => onTab(0),
              ),
              _NavItem(
                icon: Icons.mail_outline_rounded,
                label: 'Invites',
                selected: selected == 1,
                onTap: () => onTab(1),
                badge: inviteBadge,
              ),
              _NavItem(
                icon: Icons.business_rounded,
                label: 'NGO Tasks',
                selected: selected == 2,
                onTap: () => onTab(2),
                badge: ngoTasksBadge,
              ),
              _NavItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Messages',
                selected: selected == 3,
                onTap: () => onTab(3),
              ),
              _NavItem(
                icon: Icons.logout_rounded,
                label: 'Sign Out',
                selected: false,
                onTap: () => onTab(4),
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

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1 — MY TASKS
// ═══════════════════════════════════════════════════════════════════════════════
class _TasksTab extends StatefulWidget {
  final UserModel currentUser;
  final NgoModel? currentNgo;
  final TaskService taskService;
  const _TasksTab({
    required this.currentUser,
    this.currentNgo,
    required this.taskService,
  });

  @override
  State<_TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<_TasksTab> {
  String? _filter; // null = all, 'active', 'completed'

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TaskModel>>(
      stream: widget.taskService.streamVolunteerAssignedTasks(
        widget.currentUser.uid,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: _PulseLoader());
        }
        if (snap.hasError) {
          return const _EmptyState(
            icon: Icons.error_outline_rounded,
            message: 'Error loading tasks.',
          );
        }

        final allTasks = (snap.data ?? [])
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final active = allTasks.where((t) => t.status == 'active').length;
        final completed = allTasks.where((t) => t.status == 'completed').length;

        final tasks = _filter == null
            ? allTasks
            : allTasks.where((t) => t.status == _filter).toList();

        return CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            // ── Header ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: _Header(
                currentUser: widget.currentUser,
                currentNgo: widget.currentNgo,
              ),
            ),

            // ── Stat bar ────────────────────────────────────────
            if (allTasks.isNotEmpty)
              SliverToBoxAdapter(
                child: _StatBar(
                  active: active,
                  completed: completed,
                  total: allTasks.length,
                  selected: _filter,
                  onFilter: (f) =>
                      setState(() => _filter = _filter == f ? null : f),
                ),
              ),

            // ── Task list or empty ──────────────────────────────
            if (tasks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.assignment_outlined,
                  message: _filter != null
                      ? 'No $_filter tasks.'
                      : 'No tasks assigned yet.\nAccept invitations to get started!',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _TaskCard(
                      task: tasks[i],
                      volunteerId: widget.currentUser.uid,
                      taskService: widget.taskService,
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

// ─── Header (matches admin dashboard) ─────────────────────────────────────────
class _Header extends StatelessWidget {
  final UserModel currentUser;
  final NgoModel? currentNgo;
  const _Header({required this.currentUser, this.currentNgo});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _C.heroCard,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.volunteer_activism_rounded,
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
                      'Volunteer',
                      style: GoogleFonts.dmSans(
                        color: _C.textSec,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
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
                      const Icon(
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

          // ── Hero Card ────────────────────────────────────────────
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
                  // Avatar
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
                                : 'V',
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

                  // ── NGO Info Row ────────────────────────────────
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
                                  currentNgo!.description.isNotEmpty
                                      ? currentNgo!.description
                                      : 'NGO',
                                  style: GoogleFonts.dmSans(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                  Container(
                    height: 1,
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
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
                          Icons.volunteer_activism_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Volunteer Portal',
                            style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Track your contributions',
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
                          'VOLUNTEER',
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

          // ── Section label ────────────────────────────────────────
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
  final int active, completed, total;
  final String? selected;
  final ValueChanged<String> onFilter;
  const _StatBar({
    required this.active,
    required this.completed,
    required this.total,
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
            label: 'Done',
            value: completed,
            color: _C.textSec,
            bgColor: _C.divider,
            isSelected: selected == 'completed',
            onTap: () => onFilter('completed'),
          ),
          const SizedBox(width: 8),
          _StatPill(
            label: 'Total',
            value: total,
            color: _C.blue,
            bgColor: _C.blueLight,
            isSelected: false,
            onTap: () {},
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

// ─── Task Card (My Tasks) ─────────────────────────────────────────────────────
class _TaskCard extends StatefulWidget {
  final TaskModel task;
  final String volunteerId;
  final TaskService taskService;
  const _TaskCard({
    required this.task,
    required this.volunteerId,
    required this.taskService,
  });

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _expanded = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isCompleted = task.status == 'completed';
    final urgency = isCompleted ? _C.green : _urgencyColor(task.createdAt, task.deadline);
    final sd = _statusData(task.status);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() {
          _pressed = false;
          _expanded = !_expanded;
        });
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
              color: _expanded
                  ? _C.blue.withValues(alpha: 0.3)
                  : _C.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: _expanded ? 0.07 : 0.05),
                blurRadius: _expanded ? 16 : 12,
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
                    color: isCompleted ? _C.green : urgency,
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
                            _Chip(label: sd.$1, color: sd.$2),
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
                            const Icon(
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
                            const Icon(
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
                        // Expanded details
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: _ExpandedTaskDetails(
                            task: task,
                            volunteerId: widget.volunteerId,
                            taskService: widget.taskService,
                          ),
                          crossFadeState: _expanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 200),
                        ),
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

  (String, Color) _statusData(String s) => switch (s) {
        'active' => ('ACTIVE', _C.green),
        'completed' => ('DONE', _C.textSec),
        _ => ('INVITING', _C.blue),
      };
}

// ─── Expanded Task Details ────────────────────────────────────────────────────
class _ExpandedTaskDetails extends StatelessWidget {
  final TaskModel task;
  final String volunteerId;
  final TaskService taskService;
  const _ExpandedTaskDetails({
    required this.task,
    required this.volunteerId,
    required this.taskService,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(color: _C.border, height: 1),
        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.calendar_today_rounded,
          label: 'Deadline',
          value:
              '${task.deadline.day}/${task.deadline.month}/${task.deadline.year}',
        ),
        const SizedBox(height: 6),
        _InfoRow(
          icon: Icons.people_rounded,
          label: 'Volunteers',
          value: '${task.assignedVolunteers.length}/${task.maxVolunteers}',
        ),
        const SizedBox(height: 14),

        // ── Individual progress stream ──
        StreamBuilder<TaskAssignmentModel?>(
          stream:
              taskService.streamVolunteerAssignment(task.taskId, volunteerId),
          builder: (context, assignSnap) {
            if (assignSnap.hasError) {
              return const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Could not load your assignment progress.',
                  style: TextStyle(color: _C.red, fontSize: 12),
                ),
              );
            }

            final assignment = assignSnap.data;
            final myProgress = assignment?.individualProgress ?? 0.0;

            return StreamBuilder<List<ProgressRequestModel>>(
              stream: taskService.streamVolunteerProgressRequests(
                  task.taskId, volunteerId),
              builder: (context, reqSnap) {
                if (reqSnap.hasError) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Could not load your progress requests.',
                      style: TextStyle(color: _C.red, fontSize: 12),
                    ),
                  );
                }

                final requests = reqSnap.data ?? [];
                final pendingReq = requests
                    .where((r) => r.status == 'pending')
                    .fold<ProgressRequestModel?>(
                        null,
                        (prev, r) => prev == null ||
                                r.createdAt.isAfter(prev.createdAt)
                            ? r
                            : prev);
                final pendingProgress = pendingReq?.requestedProgress;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProgressBarWithPending(
                      label: 'My Progress',
                      progress: myProgress,
                      pendingProgress: pendingProgress,
                      color: _C.green,
                    ),
                    if (pendingReq != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.hourglass_top_rounded,
                              size: 13, color: _C.textTer),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Progress update to ${pendingProgress?.toStringAsFixed(0)}% is yet to be reviewed',
                              style: GoogleFonts.dmSans(
                                fontSize: 11,
                                color: _C.textSec,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (task.status == 'active' &&
                        myProgress < 100 &&
                        pendingReq == null)
                      _UpdateProgressButton(
                        task: task,
                        volunteerId: volunteerId,
                        currentProgress: myProgress,
                        taskService: taskService,
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

// ─── Progress Bar with Pending Progress ───────────────────────────────────────
class _ProgressBarWithPending extends StatelessWidget {
  final String label;
  final double progress;
  final double? pendingProgress;
  final Color color;
  const _ProgressBarWithPending({
    required this.label,
    required this.progress,
    this.pendingProgress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final hasPending =
        pendingProgress != null && pendingProgress! > progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _C.textSec,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${progress.toStringAsFixed(0)}%',
                  style: GoogleFonts.dmSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                if (hasPending) ...[
                  Text(
                    ' \u2192 ${pendingProgress!.toStringAsFixed(0)}%',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _C.textTer,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 6,
            child: Stack(
              children: [
                // Background
                Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                // Pending progress (grey)
                if (hasPending)
                  FractionallySizedBox(
                    widthFactor:
                        (pendingProgress! / 100).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFBDBDBD),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                // Approved progress (green)
                FractionallySizedBox(
                  widthFactor: (progress / 100).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Info Row ─────────────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: _C.textTer),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: GoogleFonts.dmSans(
            fontSize: 12,
            color: _C.textSec,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            color: _C.textPri,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Update Progress Button + Dialog ──────────────────────────────────────────
class _UpdateProgressButton extends StatelessWidget {
  final TaskModel task;
  final String volunteerId;
  final double currentProgress;
  final TaskService taskService;
  const _UpdateProgressButton({
    required this.task,
    required this.volunteerId,
    required this.currentProgress,
    required this.taskService,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () => _showProgressDialog(context),
        style: TextButton.styleFrom(
          backgroundColor: _C.blue.withValues(alpha: 0.08),
          foregroundColor: _C.blue,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.trending_up_rounded, size: 18),
        label: Text(
          'Request Progress Update',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
    );
  }

  void _showProgressDialog(BuildContext context) {
    double requested = currentProgress;
    final noteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setD) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Update Progress',
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: _C.textPri,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current: ${currentProgress.toStringAsFixed(0)}%',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: _C.textSec,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'New: ${requested.toStringAsFixed(0)}%',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _C.blue,
                      ),
                    ),
                    Slider(
                      value: requested,
                      min: currentProgress,
                      max: 100,
                      divisions:
                          (100 - currentProgress).toInt().clamp(1, 100),
                      activeColor: _C.blue,
                      onChanged: (v) => setD(() => requested = v),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Describe what you completed...',
                        hintStyle: GoogleFonts.dmSans(
                          fontSize: 13,
                          color: _C.textTer,
                        ),
                        filled: true,
                        fillColor: _C.divider,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: _C.textPri,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.dmSans(color: _C.textSec),
                  ),
                ),
                FilledButton(
                  onPressed: () async {
                    if (noteCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Please describe your progress.',
                            style: GoogleFonts.dmSans(),
                          ),
                          backgroundColor: _C.red,
                        ),
                      );
                      return;
                    }
                    if (requested <= currentProgress) {
                      Navigator.pop(ctx);
                      return;
                    }
                    try {
                      await _withNetworkTimeout(taskService.submitProgressRequest(
                        taskId: task.taskId,
                        taskTitle: task.title,
                        volunteerId: volunteerId,
                        adminId: task.adminId,
                        currentProgress: currentProgress,
                        requestedProgress: requested,
                        note: noteCtrl.text.trim(),
                      ));
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Progress request submitted!',
                              style: GoogleFonts.dmSans(),
                            ),
                            backgroundColor: _C.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Failed to submit request.',
                              style: GoogleFonts.dmSans(),
                            ),
                            backgroundColor: _C.red,
                          ),
                        );
                      }
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _C.blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Submit',
                    style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2 — INVITATIONS
// ═══════════════════════════════════════════════════════════════════════════════
class _InvitesTab extends StatelessWidget {
  final UserModel currentUser;
  final TaskService taskService;
  const _InvitesTab({
    required this.currentUser,
    required this.taskService,
  });

  @override
  Widget build(BuildContext context) {
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
                  'Invitations',
                  style: GoogleFonts.dmSans(
                    color: _C.textPri,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Review task invitations from your admin',
                  style: GoogleFonts.dmSans(color: _C.textSec, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<TaskModel>>(
            stream: taskService.streamVolunteerInvites(
              currentUser.uid,
              ngoId: currentUser.ngoId,
            ),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: _PulseLoader());
              }
              if (snap.hasError) {
                return const _EmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Error loading invitations.',
                );
              }

              final invites = (snap.data ?? [])
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              if (invites.isEmpty) {
                return const _EmptyState(
                  icon: Icons.mail_outline_rounded,
                  message: 'All clear!\nNo pending invitations.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                itemCount: invites.length,
                itemBuilder: (_, i) => _InviteCard(
                  task: invites[i],
                  volunteerId: currentUser.uid,
                  taskService: taskService,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Invite Card ──────────────────────────────────────────────────────────────
class _InviteCard extends StatefulWidget {
  final TaskModel task;
  final String volunteerId;
  final TaskService taskService;
  const _InviteCard({
    required this.task,
    required this.volunteerId,
    required this.taskService,
  });

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  bool _loading = false;

  Future<void> _accept() async {
    setState(() => _loading = true);
    try {
      await _withNetworkTimeout(widget.taskService
          .acceptInvite(widget.task.taskId, widget.volunteerId));
      if (mounted) {
        _snack(context, 'Joined "${widget.task.title}"!', _C.green,
            Icons.check_circle_rounded);
      }
    } catch (e) {
      if (mounted) {
        _snack(context, 'Failed to accept.', _C.red, Icons.error_rounded);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _loading = true);
    try {
      await _withNetworkTimeout(widget.taskService
          .declineInvite(widget.task.taskId, widget.volunteerId));
      if (mounted) {
        _snack(context, 'Declined invitation.', _C.textSec,
            Icons.remove_circle_rounded);
      }
    } catch (e) {
      if (mounted) {
        _snack(context, 'Failed to decline.', _C.red, Icons.error_rounded);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final urgency = _urgencyColor(task.createdAt, task.deadline);
    final daysLeft = task.deadline.difference(DateTime.now()).inDays;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.orange.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: _C.orange.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Orange urgency strip
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: _C.orange,
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
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _C.textPri,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _Chip(label: 'INVITE', color: _C.orange),
                      ],
                    ),
                    const SizedBox(height: 5),
                    if (task.description.isNotEmpty)
                      Text(
                        task.description,
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: _C.textSec,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.people_outline_rounded,
                            size: 13, color: _C.textTer),
                        const SizedBox(width: 4),
                        Text(
                          '${task.assignedVolunteers.length}/${task.maxVolunteers}',
                          style: GoogleFonts.dmSans(
                            color: _C.textSec,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.schedule_outlined,
                            size: 13, color: _C.textTer),
                        const SizedBox(width: 4),
                        Text(
                          daysLeft < 0
                              ? 'Overdue'
                              : daysLeft == 0
                                  ? 'Today'
                                  : '${daysLeft}d left',
                          style: GoogleFonts.dmSans(
                            color: urgency,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_loading)
                      const Center(child: _PulseLoader())
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _OutlineActionBtn(
                              label: 'Decline',
                              icon: Icons.close_rounded,
                              color: _C.red,
                              onTap: _decline,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: _FilledActionBtn(
                              label: 'Accept',
                              icon: Icons.check_rounded,
                              color: _C.green,
                              onTap: _accept,
                            ),
                          ),
                        ],
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3 — NGO TASKS
// ═══════════════════════════════════════════════════════════════════════════════
class _NgoTasksTab extends StatefulWidget {
  final UserModel currentUser;
  final TaskService taskService;
  const _NgoTasksTab({
    required this.currentUser,
    required this.taskService,
  });

  @override
  State<_NgoTasksTab> createState() => _NgoTasksTabState();
}

class _NgoTasksTabState extends State<_NgoTasksTab> {
  String? _filter; // null = all, 'active', 'inviting', 'completed'

  @override
  Widget build(BuildContext context) {
    final ngoId = widget.currentUser.ngoId;
    if (ngoId == null || ngoId.isEmpty) {
      return const _EmptyState(
        icon: Icons.business_outlined,
        message: 'No NGO assigned.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NGO Tasks',
                  style: GoogleFonts.dmSans(
                    color: _C.textPri,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Browse and join tasks from your NGO',
                  style: GoogleFonts.dmSans(color: _C.textSec, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<TaskModel>>(
            stream: widget.taskService.streamNgoTasks(ngoId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: _PulseLoader());
              }
              if (snap.hasError) {
                final err = snap.error.toString();
                if (err.contains('failed-precondition') ||
                    err.contains('index')) {
                  return const _EmptyState(
                    icon: Icons.cloud_off_rounded,
                    message:
                        'Database index required.\nPlease contact your developer.',
                  );
                }
                return const _EmptyState(
                  icon: Icons.error_outline_rounded,
                  message: 'Error loading NGO tasks.',
                );
              }

              final allTasks = (snap.data ?? [])
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              if (allTasks.isEmpty) {
                return const _EmptyState(
                  icon: Icons.folder_open_rounded,
                  message: 'No tasks in your NGO yet.',
                );
              }

              final active =
                  allTasks.where((t) => t.status == 'active').length;
              final inviting =
                  allTasks.where((t) => t.status == 'inviting').length;
              final completed =
                  allTasks.where((t) => t.status == 'completed').length;

              final tasks = _filter == null
                  ? allTasks
                  : allTasks.where((t) => t.status == _filter).toList();

              return Column(
                children: [
                  // ── Filterable stat bar ──
                  _NgoStatBar(
                    active: active,
                    inviting: inviting,
                    completed: completed,
                    selected: _filter,
                    onFilter: (f) =>
                        setState(() => _filter = _filter == f ? null : f),
                  ),
                  Expanded(
                    child: tasks.isEmpty
                        ? _EmptyState(
                            icon: Icons.filter_list_rounded,
                            message: 'No ${_filter ?? ''} tasks.',
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 120),
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            itemCount: tasks.length,
                            itemBuilder: (_, i) => _NgoTaskCard(
                              task: tasks[i],
                              volunteerId: widget.currentUser.uid,
                              taskService: widget.taskService,
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── NGO Stat Bar ─────────────────────────────────────────────────────────────
class _NgoStatBar extends StatelessWidget {
  final int active, inviting, completed;
  final String? selected;
  final ValueChanged<String> onFilter;
  const _NgoStatBar({
    required this.active,
    required this.inviting,
    required this.completed,
    required this.selected,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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

// ─── NGO Task Card with Join / Accept / Decline ───────────────────────────────
class _NgoTaskCard extends StatefulWidget {
  final TaskModel task;
  final String volunteerId;
  final TaskService taskService;
  const _NgoTaskCard({
    required this.task,
    required this.volunteerId,
    required this.taskService,
  });

  @override
  State<_NgoTaskCard> createState() => _NgoTaskCardState();
}

class _NgoTaskCardState extends State<_NgoTaskCard> {
  bool _loading = false;

  Future<void> _join() async {
    setState(() => _loading = true);
    try {
      await _withNetworkTimeout(widget.taskService
          .joinTask(widget.task.taskId, widget.volunteerId));
      if (mounted) {
        _snack(context, 'Joined "${widget.task.title}"!', _C.green,
            Icons.check_circle_rounded);
      }
    } catch (e) {
      if (mounted) {
        _snack(context, e.toString().replaceAll('Exception: ', ''), _C.red,
            Icons.error_rounded);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acceptInvite() async {
    setState(() => _loading = true);
    try {
      await _withNetworkTimeout(widget.taskService
          .acceptInvite(widget.task.taskId, widget.volunteerId));
      if (mounted) {
        _snack(context, 'Accepted invite for "${widget.task.title}"!',
            _C.green, Icons.check_circle_rounded);
      }
    } catch (e) {
      if (mounted) {
        _snack(context, 'Failed to accept.', _C.red, Icons.error_rounded);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dismiss() async {
    setState(() => _loading = true);
    try {
      await _withNetworkTimeout(widget.taskService
          .dismissTask(widget.task.taskId, widget.volunteerId));
      if (mounted) {
        _snack(context, 'Task dismissed.', _C.textSec,
            Icons.remove_circle_rounded);
      }
    } catch (e) {
      if (mounted) {
        _snack(context, 'Failed to dismiss.', _C.red, Icons.error_rounded);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _declineInvite() async {
    setState(() => _loading = true);
    try {
      await _withNetworkTimeout(widget.taskService
          .declineInvite(widget.task.taskId, widget.volunteerId));
      if (mounted) {
        _snack(context, 'Declined invitation.', _C.textSec,
            Icons.remove_circle_rounded);
      }
    } catch (e) {
      if (mounted) {
        _snack(context, 'Failed to decline.', _C.red, Icons.error_rounded);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isCompleted = task.status == 'completed';
    final urgency = isCompleted ? _C.green : _urgencyColor(task.createdAt, task.deadline);
    final isAssigned = task.assignedVolunteers.contains(widget.volunteerId);
    final isPending = task.pendingInvites.contains(widget.volunteerId);
    final isDeclined = task.declinedBy.contains(widget.volunteerId);
    final isFull =
        task.assignedVolunteers.length >= task.maxVolunteers && !isAssigned;

    // Chip label
    String chipLabel;
    Color chipColor;
    if (isAssigned) {
      chipLabel = 'ASSIGNED';
      chipColor = _C.green;
    } else if (isPending) {
      chipLabel = 'INVITED';
      chipColor = _C.orange;
    } else if (isCompleted) {
      chipLabel = 'DONE';
      chipColor = _C.textSec;
    } else if (isFull) {
      chipLabel = 'FULL';
      chipColor = _C.textTer;
    } else {
      chipLabel = task.status == 'active' ? 'ACTIVE' : 'INVITING';
      chipColor = task.status == 'active' ? _C.green : _C.blue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: isCompleted ? _C.green : urgency,
              width: 4,
            ),
          ),
        ),
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
                    if (task.description.isNotEmpty)
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
                        const Icon(Icons.people_outline_rounded,
                            size: 13, color: _C.textTer),
                        const SizedBox(width: 4),
                        Text(
                          '${task.assignedVolunteers.length}/${task.maxVolunteers}',
                          style: GoogleFonts.dmSans(
                            color: _C.textSec,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.schedule_outlined,
                            size: 13, color: _C.textTer),
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
                    // ── Action buttons ──
                    _buildActions(
                      isAssigned: isAssigned,
                      isPending: isPending,
                      isDeclined: isDeclined,
                      isCompleted: isCompleted,
                      isFull: isFull,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildActions({
    required bool isAssigned,
    required bool isPending,
    required bool isDeclined,
    required bool isCompleted,
    required bool isFull,
  }) {
    // Already assigned
    if (isAssigned) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _C.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 16, color: _C.green),
              const SizedBox(width: 6),
              Text(
                'You\'re assigned to this task',
                style: GoogleFonts.dmSans(
                  color: _C.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Completed → no actions
    if (isCompleted) return const SizedBox.shrink();

    // Full & not invited → can't join
    if (isFull && !isPending) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _C.divider,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block_rounded, size: 16, color: _C.textTer),
              const SizedBox(width: 6),
              Text(
                'Task is full',
                style: GoogleFonts.dmSans(
                  color: _C.textTer,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Loading
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Center(child: _PulseLoader()),
      );
    }

    // Pending invite → Accept / Decline
    if (isPending) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          children: [
            Expanded(
              child: _OutlineActionBtn(
                label: 'Decline',
                icon: Icons.close_rounded,
                color: _C.red,
                onTap: _declineInvite,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: _FilledActionBtn(
                label: 'Accept Invite',
                icon: Icons.check_rounded,
                color: _C.green,
                onTap: _acceptInvite,
              ),
            ),
          ],
        ),
      );
    }

    // Previously declined → allow re-join
    if (isDeclined) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(
          children: [
            Expanded(
              child: _FilledActionBtn(
                label: 'Join Anyway',
                icon: Icons.add_rounded,
                color: _C.blue,
                onTap: _join,
              ),
            ),
          ],
        ),
      );
    }

    // Not involved → Join / Not Interested
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          Expanded(
            child: _OutlineActionBtn(
              label: 'Not Interested',
              icon: Icons.close_rounded,
              color: _C.textSec,
              onTap: _dismiss,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: _FilledActionBtn(
              label: 'Join Task',
              icon: Icons.add_rounded,
              color: _C.blue,
              onTap: _join,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable Small Widgets ───────────────────────────────────────────────────
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
                Flexible(
                  child: Text(
                    widget.label,
                    style: GoogleFonts.dmSans(
                      color: widget.color,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                Flexible(
                  child: Text(
                    widget.label,
                    style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
  const _EmptyState({
    required this.icon,
    required this.message,
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
                  color: _C.textTer.withValues(alpha: 0.08),
                ),
                child: Icon(icon, size: 40, color: _C.textTer),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  color: _C.textTer,
                  fontSize: 14,
                  height: 1.6,
                ),
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
