import 'package:flutter/material.dart';
import '../models/app_profile.dart';
import 'coach_panel_screen.dart';

/// The owner account. Same workspace as a coach, with the Codes tab added —
/// CoachPanelScreen switches that on from the profile's role.
class AdminHomeScreen extends StatelessWidget {
  final AppProfile profile;

  /// Same trainee-preview hook the coach panel uses.
  final ValueChanged<SessionAccess> onOpenTraineeView;

  const AdminHomeScreen({
    super.key,
    required this.profile,
    required this.onOpenTraineeView,
  });

  @override
  Widget build(BuildContext context) => CoachPanelScreen(
        profile: profile,
        onOpenTraineeView: onOpenTraineeView,
      );
}
