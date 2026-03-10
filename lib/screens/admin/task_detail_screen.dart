import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/task_model.dart';
import '../../models/task_assignment_model.dart';
import '../../models/progress_request_model.dart';
import '../../models/user_model.dart';
import '../../services/task_service.dart';
import '../../services/user_service.dart';
import 'admin_dashboard.dart' show taskUrgencyColor;

// ─── Shared Design Tokens ─────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFFEEF2F8);
  static const blue = Color(0xFF4A6CF7);
  static const blueLight = Color(0xFFEEF2FF);
  static const green = Color(0xFF22C55E);
  static const greenLight = Color(0xFFECFDF5);
  static const orange = Color(0xFFF59E0B);
  static const orangeLight = Color(0xFFFFFBEB);
  static const red = Color(0xFFEF4444);
  static const redLight = Color(0xFFFEF2F2);
  static const textPri = Color(0xFF0D1B3E);
  static const textSec = Color(0xFF6B7280);
  static const textTer = Color(0xFFB0B7C3);
  static const border = Color(0xFFE5E9F0);
  static const divider = Color(0xFFF1F4F9);
}

class TaskDetailScreen extends StatefulWidget {
  final String taskId;
  final String adminId;
  final String ngoId;
  final TaskService taskService;
  final UserService userService;

  const TaskDetailScreen({
    super.key,
    required this.taskId,
    required this.adminId,
    required this.ngoId,
    required this.taskService,
    required this.userService,
  });

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final Set<String> _selectedToInvite = {};
  final TextEditingController _finalNoteCtrl = TextEditingController();
  bool _completingTask = false;

  @override
  void dispose() {
    _finalNoteCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, Color bg, IconData icon) {
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

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _C.bg,
        body: StreamBuilder<TaskModel?>(
          stream: widget.taskService.streamTask(widget.taskId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: _Loader());
            }
            final task = snap.data;
            if (task == null) {
              return Center(
                child: Text(
                  'Task not found.',
                  style: GoogleFonts.dmSans(color: _C.textSec),
                ),
              );
            }
            return _buildBody(task);
          },
        ),
      ),
    );
  }

  Widget _buildBody(TaskModel task) {
    final isCompleted = task.status == 'completed';
    final urgency = isCompleted ? _C.green : taskUrgencyColor(task.createdAt, task.deadline);

    return SafeArea(
      child: Column(
        children: [
          // ── App Bar ────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
            child: Row(
              children: [
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _C.divider,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.border),
                    ),
                    child: Icon(
                      Icons.arrow_back_rounded,
                      color: _C.textPri,
                      size: 18,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    task.title,
                    style: GoogleFonts.dmSans(
                      color: _C.textPri,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: task.status),
              ],
            ),
          ),

          // ── Content ──────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                // Progress hero card
                _ProgressHeroCard(task: task, urgency: urgency),
                const SizedBox(height: 20),

                // Pending requests
                StreamBuilder<List<ProgressRequestModel>>(
                  stream: widget.taskService.streamPendingRequestsForAdmin(
                    widget.adminId,
                  ),
                  builder: (_, reqSnap) {
                    final taskReqs = (reqSnap.data ?? [])
                        .where((r) => r.taskId == widget.taskId)
                        .toList();
                    if (taskReqs.isEmpty) return const SizedBox.shrink();
                    return _Section(
                      icon: Icons.pending_actions_rounded,
                      label: 'Pending Requests',
                      color: _C.orange,
                      bgColor: _C.orangeLight,
                      count: taskReqs.length,
                      child: Column(
                        children: taskReqs
                            .map(
                              (r) => _InlineRequestCard(
                                request: r,
                                taskService: widget.taskService,
                                userService: widget.userService,
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                ),

                // Assigned volunteers
                StreamBuilder<List<TaskAssignmentModel>>(
                  stream: widget.taskService.streamTaskAssignments(
                    widget.taskId,
                  ),
                  builder: (_, aSnap) {
                    final assignments = aSnap.data ?? [];
                    if (task.assignedVolunteers.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return _Section(
                      icon: Icons.group_rounded,
                      label: 'Assigned Volunteers',
                      color: _C.green,
                      bgColor: _C.greenLight,
                      count: task.assignedVolunteers.length,
                      child: Column(
                        children: task.assignedVolunteers.map((uid) {
                          final assignment = assignments
                              .where((a) => a.volunteerId == uid)
                              .firstOrNull;
                          return _AssignedVolunteerRow(
                            volunteerId: uid,
                            progress: assignment?.individualProgress ?? 0.0,
                            userService: widget.userService,
                            onRemove: task.status != 'completed'
                                ? () => _confirmRemove(task, uid)
                                : null,
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),

                // Pending invites
                if (task.pendingInvites.isNotEmpty && task.status == 'inviting')
                  _Section(
                    icon: Icons.mail_outline_rounded,
                    label: 'Pending Invites',
                    color: _C.blue,
                    bgColor: _C.blueLight,
                    count: task.pendingInvites.length,
                    child: Column(
                      children: task.pendingInvites
                          .map(
                            (uid) => _PendingInviteRow(
                              volunteerId: uid,
                              userService: widget.userService,
                              onCancel: () => widget.taskService.cancelInvite(
                                widget.taskId,
                                uid,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),

                // Invite volunteers
                if (task.status == 'inviting' &&
                    task.assignedVolunteers.length < task.maxVolunteers)
                  _Section(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'Invite Volunteers',
                    color: _C.textSec,
                    bgColor: _C.divider,
                    child: StreamBuilder<List<UserModel>>(
                      stream: widget.taskService.streamNgoVolunteers(
                        widget.ngoId,
                      ),
                      builder: (_, volSnap) {
                        final allVols = volSnap.data ?? [];
                        final already = {
                          ...task.assignedVolunteers,
                          ...task.pendingInvites,
                          ...task.declinedBy,
                        };
                        final eligible = allVols
                            .where((v) => !already.contains(v.uid))
                            .toList();

                        if (eligible.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'All NGO volunteers have been invited.',
                              style: GoogleFonts.dmSans(
                                color: _C.textTer,
                                fontSize: 13,
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: [
                            ...eligible.map(
                              (v) => _InviteCheckRow(
                                volunteer: v,
                                selected: _selectedToInvite.contains(v.uid),
                                onToggle: (val) => setState(() {
                                  val
                                      ? _selectedToInvite.add(v.uid)
                                      : _selectedToInvite.remove(v.uid);
                                }),
                              ),
                            ),
                            if (_selectedToInvite.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _GradientBtn(
                                label:
                                    'Send Invites (${_selectedToInvite.length})',
                                icon: Icons.send_rounded,
                                onTap: _sendInvites,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),

                // Complete task
                if (task.status != 'completed')
                  _Section(
                    icon: Icons.flag_rounded,
                    label: 'Complete Task',
                    color: _C.green,
                    bgColor: _C.greenLight,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _finalNoteCtrl,
                          maxLines: 3,
                          style: GoogleFonts.dmSans(
                            color: _C.textPri,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Final note (optional)...',
                            hintStyle: GoogleFonts.dmSans(
                              color: _C.textTer,
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: _C.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: _C.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: _C.green,
                                width: 1.5,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _completingTask
                            ? const Center(child: _Loader())
                            : _GradientBtn(
                                label: 'Mark as Completed',
                                icon: Icons.check_circle_outline_rounded,
                                color1: _C.green,
                                color2: const Color(0xFF16A34A),
                                onTap: () => _completeTask(task),
                              ),
                      ],
                    ),
                  ),

                // Final note (completed)
                if (task.status == 'completed' &&
                    task.adminFinalNote.isNotEmpty)
                  _Section(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Final Note',
                    color: _C.textSec,
                    bgColor: _C.divider,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _C.border),
                      ),
                      child: Text(
                        task.adminFinalNote,
                        style: GoogleFonts.dmSans(
                          color: _C.textSec,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendInvites() async {
    try {
      await widget.taskService.inviteVolunteers(
        widget.taskId,
        _selectedToInvite.toList(),
      );
      setState(() => _selectedToInvite.clear());
      if (!mounted) return;
      _snack('Invites sent!', _C.blue, Icons.send_rounded);
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e', _C.red, Icons.error_rounded);
    }
  }

  Future<void> _confirmRemove(TaskModel task, String volunteerId) async {
    final ok = await showDialog<bool>(
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
                color: Colors.black.withValues(alpha: 0.1),
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
                'Remove Volunteer?',
                style: GoogleFonts.dmSans(
                  color: _C.textPri,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This volunteer will be removed and progress recalculated.',
                style: GoogleFonts.dmSans(
                  color: _C.textSec,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
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
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _C.red,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _C.red.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Remove',
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
      ),
    );
    if (ok != true) return;
    try {
      await widget.taskService.removeVolunteer(widget.taskId, volunteerId);
      if (!mounted) return;
      _snack('Volunteer removed.', _C.orange, Icons.person_remove_rounded);
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e', _C.red, Icons.error_rounded);
    }
  }

  Future<void> _completeTask(TaskModel task) async {
    setState(() => _completingTask = true);
    try {
      await widget.taskService.completeTask(
        widget.taskId,
        _finalNoteCtrl.text.trim(),
      );
      if (!mounted) return;
      _snack('Task completed!', _C.green, Icons.check_circle_rounded);
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e', _C.red, Icons.error_rounded);
    } finally {
      if (mounted) setState(() => _completingTask = false);
    }
  }
}

// ─── Progress Hero Card ───────────────────────────────────────────────────────
class _ProgressHeroCard extends StatelessWidget {
  final TaskModel task;
  final Color urgency;
  const _ProgressHeroCard({required this.task, required this.urgency});

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.status == 'completed';
    final now = DateTime.now();
    final total = task.deadline.difference(task.createdAt).inMinutes;
    final remaining = task.deadline.difference(now).inMinutes;
    final pct = total > 0 ? (remaining / total) * 100 : 0.0;
    final timeLabel = isCompleted ? 'COMPLETED' : (pct > 50 ? 'ON TRACK' : (pct > 30 ? 'CAUTION' : 'URGENT'));

    // Hero card uses dark navy theme like SA dashboard hero
    return Container(
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
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Circular progress
                SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 88,
                        height: 88,
                        child: CircularProgressIndicator(
                          value: task.mainProgress / 100,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          valueColor: AlwaysStoppedAnimation(urgency),
                          strokeWidth: 7,
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCompleted)
                            Icon(Icons.check_circle_rounded, color: urgency, size: 32)
                          else
                            Text(
                              '${task.mainProgress.toStringAsFixed(0)}%',
                              style: GoogleFonts.dmSans(
                                color: urgency,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          Text(
                            isCompleted ? 'Completed' : 'done',
                            style: GoogleFonts.dmSans(
                              color: urgency.withValues(alpha: 0.6),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.description,
                        style: GoogleFonts.dmSans(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 13,
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      _MetaRow(
                        Icons.schedule_outlined,
                        '${task.deadline.day}/${task.deadline.month}/${task.deadline.year}',
                      ),
                      const SizedBox(height: 5),
                      _MetaRow(
                        Icons.people_outline_rounded,
                        '${task.assignedVolunteers.length}/${task.maxVolunteers} volunteers',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Bottom urgency bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: urgency.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
              border: Border(top: BorderSide(color: urgency.withValues(alpha: 0.2))),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: urgency,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: urgency.withValues(alpha: 0.5), blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  timeLabel,
                  style: GoogleFonts.dmSans(
                    color: urgency,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  isCompleted
                      ? 'Task finished'
                      : (remaining > 0
                          ? '${(remaining / 60).floor()}h ${remaining % 60}m left'
                          : 'Overdue'),
                  style: GoogleFonts.dmSans(
                    color: urgency.withValues(alpha: 0.7),
                    fontSize: 12,
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

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaRow(this.icon, this.label);
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 13, color: Colors.white38),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          label,
          style: GoogleFonts.dmSans(color: Colors.white54, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

// ─── Section Wrapper ─────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final int? count;
  final Widget child;
  const _Section({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.child,
    this.count,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.dmSans(
                color: _C.textPri,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.dmSans(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    ),
  );
}

// ─── Assigned Volunteer Row ───────────────────────────────────────────────────
class _AssignedVolunteerRow extends StatefulWidget {
  final String volunteerId;
  final double progress;
  final UserService userService;
  final VoidCallback? onRemove;
  const _AssignedVolunteerRow({
    required this.volunteerId,
    required this.progress,
    required this.userService,
    this.onRemove,
  });
  @override
  State<_AssignedVolunteerRow> createState() => _AssignedVolunteerRowState();
}

class _AssignedVolunteerRowState extends State<_AssignedVolunteerRow> {
  String? _name;
  @override
  void initState() {
    super.initState();
    widget.userService.getUserById(widget.volunteerId).then((u) {
      if (mounted && u != null) setState(() => _name = u.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = _name ?? '…';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          _VolAvatar(name: name, color: _C.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.dmSans(
                    color: _C.textPri,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: widget.progress / 100,
                          backgroundColor: _C.border,
                          valueColor: const AlwaysStoppedAnimation(_C.green),
                          minHeight: 5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${widget.progress.toStringAsFixed(0)}%',
                      style: GoogleFonts.dmSans(
                        color: _C.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.onRemove != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: widget.onRemove,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _C.redLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person_remove_rounded,
                  color: _C.red,
                  size: 15,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Pending Invite Row ───────────────────────────────────────────────────────
class _PendingInviteRow extends StatefulWidget {
  final String volunteerId;
  final UserService userService;
  final Future<void> Function() onCancel;
  const _PendingInviteRow({
    required this.volunteerId,
    required this.userService,
    required this.onCancel,
  });
  @override
  State<_PendingInviteRow> createState() => _PendingInviteRowState();
}

class _PendingInviteRowState extends State<_PendingInviteRow> {
  String? _name;
  bool _cancelling = false;
  @override
  void initState() {
    super.initState();
    widget.userService.getUserById(widget.volunteerId).then((u) {
      if (mounted && u != null) setState(() => _name = u.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        children: [
          _VolAvatar(name: _name ?? '?', color: _C.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _name ?? widget.volunteerId,
              style: GoogleFonts.dmSans(color: _C.textSec, fontSize: 13),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _C.blueLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'INVITED',
              style: GoogleFonts.dmSans(
                color: _C.blue,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _cancelling
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: _C.orange,
                    strokeWidth: 2,
                  ),
                )
              : GestureDetector(
                  onTap: () async {
                    setState(() => _cancelling = true);
                    await widget.onCancel();
                    if (mounted) setState(() => _cancelling = false);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _C.divider,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: _C.textTer,
                      size: 14,
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ─── Invite Checkbox Row ──────────────────────────────────────────────────────
class _InviteCheckRow extends StatelessWidget {
  final UserModel volunteer;
  final bool selected;
  final ValueChanged<bool> onToggle;
  const _InviteCheckRow({
    required this.volunteer,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => onToggle(!selected),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? _C.blueLight : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? _C.blue.withValues(alpha: 0.4) : _C.border,
        ),
      ),
      child: Row(
        children: [
          _VolAvatar(name: volunteer.name, color: _C.textSec),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  volunteer.name,
                  style: GoogleFonts.dmSans(color: _C.textPri, fontSize: 13),
                ),
                Text(
                  volunteer.email,
                  style: GoogleFonts.dmSans(color: _C.textTer, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              key: ValueKey(selected),
              color: selected ? _C.blue : _C.textTer,
              size: 20,
            ),
          ),
        ],
      ),
    ),
  );
}

// ─── Inline Request Card ──────────────────────────────────────────────────────
class _InlineRequestCard extends StatefulWidget {
  final ProgressRequestModel request;
  final TaskService taskService;
  final UserService userService;
  const _InlineRequestCard({
    required this.request,
    required this.taskService,
    required this.userService,
  });
  @override
  State<_InlineRequestCard> createState() => _InlineRequestCardState();
}

class _InlineRequestCardState extends State<_InlineRequestCard> {
  String? _name;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    widget.userService.getUserById(widget.request.volunteerId).then((u) {
      if (mounted && u != null) setState(() => _name = u.name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.request;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.orangeLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _VolAvatar(name: _name ?? '?', color: _C.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _name ?? req.volunteerId,
                  style: GoogleFonts.dmSans(
                    color: _C.textPri,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _C.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${req.currentProgress.toStringAsFixed(0)}% → ${req.requestedProgress.toStringAsFixed(0)}%',
                  style: GoogleFonts.dmSans(
                    color: _C.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (req.mandatoryNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              req.mandatoryNote,
              style: GoogleFonts.dmSans(
                color: _C.textSec,
                fontSize: 12,
                height: 1.5,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          _processing
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: _C.blue,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _act(approve: false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _C.red.withValues(alpha: 0.4)),
                            color: _C.redLight,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.close_rounded,
                                color: _C.red,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Reject',
                                style: GoogleFonts.dmSans(
                                  color: _C.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _act(approve: true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: _C.green,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: _C.green.withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Approve',
                                style: GoogleFonts.dmSans(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Future<void> _act({required bool approve}) async {
    setState(() => _processing = true);
    try {
      approve
          ? await widget.taskService.approveProgressRequest(widget.request)
          : await widget.taskService.rejectProgressRequest(widget.request);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e', style: GoogleFonts.dmSans()),
          backgroundColor: _C.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }
}

// ─── Status Badge ─────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color, bg) = switch (status) {
      'active' => ('ACTIVE', _C.green, _C.greenLight),
      'completed' => ('DONE', _C.textSec, _C.divider),
      _ => ('INVITING', _C.blue, _C.blueLight),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Gradient Button ──────────────────────────────────────────────────────────
class _GradientBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color1, color2;
  final VoidCallback onTap;
  const _GradientBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color1 = _C.blue,
    this.color2 = const Color(0xFF1A2B5E),
  });
  @override
  State<_GradientBtn> createState() => _GradientBtnState();
}

class _GradientBtnState extends State<_GradientBtn> {
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
      scale: _p ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 90),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [widget.color1, widget.color2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: widget.color1.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(widget.icon, color: Colors.white, size: 17),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Vol Avatar ───────────────────────────────────────────────────────────────
class _VolAvatar extends StatelessWidget {
  final String name;
  final Color color;
  const _VolAvatar({required this.name, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Center(
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: GoogleFonts.dmSans(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    ),
  );
}

// ─── Loader ───────────────────────────────────────────────────────────────────
class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) =>
      const CircularProgressIndicator(color: _C.blue, strokeWidth: 2.5);
}
