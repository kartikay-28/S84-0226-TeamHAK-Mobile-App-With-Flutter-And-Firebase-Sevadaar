import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../widgets/notification_wrapper.dart';
import 'auth/login_screen.dart';
import 'super_admin/super_admin_dashboard.dart';
import 'admin/admin_dashboard.dart';
import 'volunteer/volunteer_dashboard.dart';
import 'volunteer/no_ngo_dashboard.dart';
import 'developer_admin/developer_admin_dashboard.dart';
import 'landing_page.dart';

/// ───────────────────────────────────────────────────────────────
/// ROLE ROUTER — Sevadaar
/// Reads the current user's Firestore role and routes to the
/// correct dashboard. Shows a themed loading screen while fetching.
/// ───────────────────────────────────────────────────────────────
class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    try {
      final firebaseUser = _authService.currentUser;
      if (firebaseUser == null) {
        _goTo(const LoginScreen());
        return;
      }

      final profile = await _authService.getUserProfile(firebaseUser.uid);
      final uid = firebaseUser.uid;

      if (!mounted) return;

      switch (profile.role) {
        case 'developer_admin':
          _goTo(NotificationWrapper(
            uid: uid,
            child: const DeveloperAdminDashboard(),
          ));
          break;
        case 'super_admin':
          _goTo(NotificationWrapper(
            uid: uid,
            child: const SuperAdminDashboard(),
          ));
          break;
        case 'admin':
          _goTo(NotificationWrapper(
            uid: uid,
            child: const AdminDashboard(),
          ));
          break;
        case 'volunteer':
        default:
          // If volunteer has no NGO assigned, show the no-NGO dashboard
          if (profile.ngoId == null || profile.ngoId!.isEmpty) {
            _goTo(NotificationWrapper(
              uid: uid,
              child: const NoNgoDashboard(),
            ));
          } else {
            _goTo(NotificationWrapper(
              uid: uid,
              child: const VolunteerDashboard(),
            ));
          }
          break;
      }
    } catch (e) {
      // Firebase not available (Linux/Windows dev mode) — show landing page
      if (!mounted) return;
      if (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows) {
        _goTo(const LandingPage());
      } else {
        _goTo(const LoginScreen());
      }
    }
  }

  void _goTo(Widget screen) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06110B),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: Color(0xFF4CAF50),
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 20),
            Text(
              'Loading your dashboard...',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: const Color(0xFF81C784),
                fontWeight: FontWeight.w300,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
