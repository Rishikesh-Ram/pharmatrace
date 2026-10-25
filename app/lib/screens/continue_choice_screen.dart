import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pharma_artwork.dart';
import 'role_dashboard_screen.dart';
import 'role_select_screen.dart';

class ContinueChoiceScreen extends StatelessWidget {
  const ContinueChoiceScreen({super.key});

  void _openConsumer(BuildContext context) {
    api.clearSession();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RoleDashboardScreen(role: UserRole.consumer),
      ),
    );
  }

  void _openOrganization(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RoleSelectScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.warmIvory,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.softMint,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          size: 18,
                          color: AppColors.primaryTeal,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'PharmaTrace',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepTeal,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'How would you like to continue?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.deepTeal,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Choose Consumer verification or Organization supply-chain access.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 36),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 620;
                      final consumerCard = _AccessPathCard(
                        artwork: const ConsumerShieldArtwork(),
                        badgeText: 'No login required',
                        title: 'Consumer',
                        description: 'Check medicine authenticity by scanning a QR code or entering a batch ID.',
                        actionLabel: 'Verify a Medicine',
                        primary: true,
                        onTap: () => _openConsumer(context),
                      );
                      final orgCard = _AccessPathCard(
                        artwork: const OrganizationTraceArtwork(),
                        badgeText: 'Supply-chain portal',
                        title: 'Organization',
                        description: 'Access manufacturer, distributor, pharmacy, or administrator supply-chain tools.',
                        actionLabel: 'Organization Access',
                        primary: false,
                        onTap: () => _openOrganization(context),
                      );

                      if (wide) {
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: consumerCard),
                              const SizedBox(width: 22),
                              Expanded(child: orgCard),
                            ],
                          ),
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          consumerCard,
                          const SizedBox(height: 18),
                          orgCard,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessPathCard extends StatelessWidget {
  final Widget artwork;
  final String badgeText;
  final String title;
  final String description;
  final String actionLabel;
  final bool primary;
  final VoidCallback onTap;

  const _AccessPathCard({
    required this.artwork,
    required this.badgeText,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: primary
              ? AppColors.primaryTeal.withValues(alpha: 0.45)
              : AppColors.hairline,
          width: primary ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      artwork,
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.softMint,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badgeText,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.deepTeal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.deepTeal,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: AppColors.secondaryText,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: primary
                        ? AppColors.primaryTeal
                        : AppColors.deepTeal,
                    foregroundColor: AppColors.white,
                  ),
                  onPressed: onTap,
                  child: Text(actionLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
