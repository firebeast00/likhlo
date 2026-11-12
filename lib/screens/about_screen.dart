import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.primary.withValues(alpha: 0.12),
                        colors.surface
                      ],
                    ),
                    border: Border.all(
                        color: colors.primary.withValues(alpha: 0.18)),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Image.asset('assets/app_logo.png',
                            width: 64, height: 64, excludeFromSemantics: true),
                        const SizedBox(width: 16),
                        Expanded(
                            child: Text(strings.text('about_project_badge'),
                                style: TextStyle(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    letterSpacing: 0.4))),
                      ]),
                      const SizedBox(height: 20),
                      Text('Likhlo',
                          style: TextStyle(
                              fontSize: 36,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                              color: colors.onSurface)),
                      const SizedBox(height: 8),
                      Text(strings.text('about_tagline'),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface)),
                      const SizedBox(height: 16),
                      Text(strings.text('about_description'),
                          style: TextStyle(
                              fontSize: 14,
                              height: 1.65,
                              color: colors.onSurfaceVariant)),
                      const SizedBox(height: 18),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _Tag(
                            label: strings.text('about_language_tag'),
                            icon: Icons.language_rounded),
                        _Tag(
                            label: strings.text('about_local_tag'),
                            icon: Icons.phone_android_rounded),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                _SectionTitle(
                    title: strings.text('about_features_title'),
                    subtitle: strings.text('about_features_intro')),
                const SizedBox(height: 14),
                LayoutBuilder(builder: (context, constraints) {
                  final twoColumns = constraints.maxWidth >= 560 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3;
                  final width = twoColumns
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final feature in const [
                      (
                        Icons.auto_awesome_rounded,
                        'about_entry_title',
                        'about_entry_body'
                      ),
                      (
                        Icons.account_balance_wallet_outlined,
                        'about_money_title',
                        'about_money_body'
                      ),
                      (
                        Icons.track_changes_rounded,
                        'about_plan_title',
                        'about_plan_body'
                      ),
                      (
                        Icons.handshake_outlined,
                        'about_udhaar_title',
                        'about_udhaar_body'
                      ),
                    ])
                      SizedBox(
                          width: width,
                          child: _FeatureCard(
                              icon: feature.$1,
                              title: strings.text(feature.$2),
                              body: strings.text(feature.$3))),
                  ]);
                }),
                const SizedBox(height: 30),
                _SectionTitle(
                    title: strings.text('about_team_title'),
                    subtitle: strings.text('about_team_intro')),
                const SizedBox(height: 14),
                _Panel(
                    child: Column(children: [
                  _TeamMember(
                      name: 'Jawad Rajper',
                      initials: 'JR',
                      rollNumber: '23BSIT-08',
                      role: strings.text('lead_developer_f82e5e')),
                  const Divider(height: 28),
                  const _TeamMember(
                      name: 'Fayaz Ahmed',
                      initials: 'FA',
                      rollNumber: '23BSIT-03'),
                  const Divider(height: 28),
                  const _TeamMember(
                      name: 'Saira', initials: 'S', rollNumber: '23BSIT-43'),
                ])),
                const SizedBox(height: 14),
                _Panel(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(strings.text('about_academic_title'),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: colors.primary)),
                      const SizedBox(height: 8),
                      Text('BS Information Technology',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface)),
                      const SizedBox(height: 6),
                      Text(
                          'Shaheed Benazir Bhutto University, Shaheed Benazirabad',
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: colors.onSurfaceVariant)),
                      const SizedBox(height: 14),
                      Text(strings.text('about_supervisor'),
                          style: TextStyle(
                              fontSize: 12, color: colors.onSurfaceVariant)),
                      const SizedBox(height: 3),
                      Text('Ms. Mah Saba Maheen',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface)),
                    ])),
                const SizedBox(height: 30),
                _FeatureCard(
                    icon: Icons.shield_outlined,
                    title: strings.text('about_storage_title'),
                    body: strings.text('about_storage_body')),
                const SizedBox(height: 14),
                _Panel(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(strings.text('about_contact_title'),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface)),
                      const SizedBox(height: 14),
                      const _ContactLine(
                          icon: Icons.alternate_email_rounded,
                          value: 'jawadrajper5001@gmail.com'),
                      const SizedBox(height: 12),
                      const _ContactLine(
                          icon: Icons.chat_bubble_outline_rounded,
                          value: '+92 307 3156483'),
                    ])),
                const SizedBox(height: 28),
                Center(
                    child: Text(
                        strings.text(
                            'likhlo_app_c9fcc6', {'p0': DateTime.now().year}),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: colors.onSurfaceVariant))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5))),
        child: child,
      );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface)),
        const SizedBox(height: 5),
        Text(subtitle,
            style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _FeatureCard(
      {required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _Panel(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: colors.primary, size: 22),
      const SizedBox(width: 14),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.onSurface)),
        const SizedBox(height: 7),
        Text(body,
            style: TextStyle(
                fontSize: 13, height: 1.55, color: colors.onSurfaceVariant)),
      ])),
    ]));
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final IconData icon;
  const _Tag({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10)),
        child: Text.rich(
            TextSpan(children: [
              WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(icon,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary))),
              TextSpan(text: label),
            ]),
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

class _TeamMember extends StatelessWidget {
  final String name;
  final String initials;
  final String rollNumber;
  final String? role;
  const _TeamMember(
      {required this.name,
      required this.initials,
      required this.rollNumber,
      this.role});
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
          child: FittedBox(
              child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(initials,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: colors.primary))))),
      const SizedBox(width: 14),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.onSurface)),
        const SizedBox(height: 4),
        SelectableText(
            AppStrings.of(context)
                .text('about_roll_number', {'p0': rollNumber}),
            style: TextStyle(
                fontSize: 12, height: 1.5, color: colors.onSurfaceVariant)),
        if (role != null) ...[
          const SizedBox(height: 4),
          Text(role!,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.primary)),
        ],
      ])),
    ]);
  }
}

class _ContactLine extends StatelessWidget {
  final IconData icon;
  final String value;
  const _ContactLine({required this.icon, required this.value});
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
            child: SelectableText(value,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
      ]);
}
