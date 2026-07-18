import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/time_service.dart';
import '../../../core/utils/page_transitions.dart';
import '../../../core/widgets/access_gate.dart';
import '../../../core/widgets/offline_banner.dart';
import '../../settings/screens/subscription_screen.dart';
import 'dashboard_screen.dart';
import '../../customers/screens/customers_screen.dart';
import '../../orders/screens/orders_screen.dart';
import '../../settings/screens/settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int _dashboardRefreshKey = 0;
  Timer? _trialTimer;
  Duration? _trialRemaining;

  @override
  void initState() {
    super.initState();
    _loadTrialState();
  }

  Future<void> _loadTrialState() async {
    final endsAt = await SubscriptionService().getTrialEndTime();
    if (!mounted) return;
    if (endsAt == null) {
      // Not in trial (no user / invalid createdAt) — no banner, no timer.
      return;
    }
    final now = await TimeService().trustedNow();
    if (!mounted) return;
    if (now == null || now.isAfter(endsAt)) {
      // Time unverified or trial already over — AccessGate will route to
      // the lock screen on its next check. Don't render the banner.
      return;
    }
    setState(() => _trialRemaining = endsAt.difference(now));
    _trialTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final tickNow = await TimeService().trustedNow();
      if (!mounted) return;
      if (tickNow == null) {
        // Time unverified — leave the timer running; AccessGate's own
        // periodic check will route to the lock screen if needed.
        return;
      }
      if (tickNow.isAfter(endsAt)) {
        timer.cancel();
        return;
      }
      setState(() => _trialRemaining = endsAt.difference(tickNow));
    });
  }

  @override
  void dispose() {
    _trialTimer?.cancel();
    super.dispose();
  }

  Widget _buildTrialBanner(Duration remaining) {
    final String label;
    if (remaining.inHours >= 24) {
      final days = remaining.inDays;
      label = 'trial_banner_days'.tr(namedArgs: {'days': days.toString()});
    } else if (remaining.inHours >= 1) {
      final hours = remaining.inHours;
      label = 'trial_banner_hours'.tr(namedArgs: {'hours': hours.toString()});
    } else {
      final minutes = remaining.inMinutes.clamp(0, 60);
      label = 'trial_banner_minutes'.tr(namedArgs: {'minutes': minutes.toString()});
    }

    return Material(
      color: AppColors.primary,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.of(context).push<bool>(
            SlidePageRoute(page: const SubscriptionScreen()),
          );
          if (!mounted) return;
          if (result == true) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AccessGate()),
              (route) => false,
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.access_time, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                'trial_banner_cta'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      DashboardScreen(key: ValueKey(_dashboardRefreshKey)),
      const CustomersScreen(),
      const OrdersScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          if (_trialRemaining != null) _buildTrialBanner(_trialRemaining!),
          Expanded(child: screens[_currentIndex]),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: const Border(
            top: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() {
            if (index == 0 && _currentIndex != 0) {
              _dashboardRefreshKey++;
            }
            _currentIndex = index;
          }),
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.cardBackground,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          elevation: 0,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              activeIcon: const Icon(Icons.home),
              label: 'home'.tr(),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.people_outline),
              activeIcon: const Icon(Icons.people),
              label: 'customers'.tr(),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.receipt_long_outlined),
              activeIcon: const Icon(Icons.receipt_long),
              label: 'orders'.tr(),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
              label: 'settings'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}
