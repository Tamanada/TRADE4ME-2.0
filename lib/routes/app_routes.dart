import 'package:flutter/material.dart';

import '../presentation/admin_dashboard_screen/admin_dashboard_screen.dart';
import '../presentation/dashboard_screen/dashboard_screen.dart';
import '../presentation/leaderboard_screen/leaderboard_screen.dart';
import '../presentation/login_screen/login_screen.dart';
import '../presentation/map_home_screen/map_home_screen.dart';
import '../presentation/onboarding_screen/onboarding_screen.dart';
import '../presentation/place_details_screen/place_details_screen.dart';
import '../presentation/place_management_screen/place_management_screen.dart';
import '../presentation/profile_settings_screen/profile_settings_screen.dart';
import '../presentation/referral_management_screen/referral_management_screen.dart';
import '../presentation/registration_screen/registration_screen.dart';
import '../presentation/splash_screen/splash_screen.dart';
import '../presentation/pitch_screen/pitch_screen.dart';
import '../presentation/user_reports_management_screen/user_reports_management_screen.dart';

class AppRoutes {
  // TODO: Add your routes here
  static const String initial = '/';
  static const String profileSettings = '/profile-settings-screen';
  static const String dashboard = '/dashboard-screen';
  static const String splash = '/splash-screen';
  static const String referralManagement = '/referral-management-screen';
  static const String login = '/login-screen';
  static const String registration = '/registration-screen';
  static const String onboardingScreen = '/onboarding-screen';

  static const String mapHomeScreen = '/map-home-screen';
  static const String placeDetailsScreen = '/place-details-screen';
  static const String addPlaceScreen = '/add-place-screen';

  static const String adminDashboardScreen = '/admin-dashboard-screen';
  static const String placeManagementScreen = '/place-management-screen';

  static const String userReportsManagementScreen =
      '/user-reports-management-screen';

  static const String leaderboardScreen = '/leaderboard-screen';
  static const String pitchScreen = '/pitch-screen';

  static Map<String, WidgetBuilder> get routes => {
    profileSettings: (context) => const ProfileSettingsScreen(),
    dashboard: (context) => const DashboardScreen(),
    splash: (context) => const SplashScreen(),
    referralManagement: (context) => const ReferralManagementScreen(),
    login: (context) => const LoginScreen(),
    registration: (context) => const RegistrationScreen(),
    mapHomeScreen: (context) => const MapHomeScreen(),
    placeDetailsScreen: (context) => const PlaceDetailsScreen(),
    adminDashboardScreen: (context) => const AdminDashboardScreen(),
    placeManagementScreen: (context) => const PlaceManagementScreen(),
    userReportsManagementScreen: (context) =>
        const UserReportsManagementScreen(),
    onboardingScreen: (context) => const OnboardingScreen(),
    leaderboardScreen: (context) => const LeaderboardScreen(),
    pitchScreen: (context) => const PitchScreen(),
  };
}
