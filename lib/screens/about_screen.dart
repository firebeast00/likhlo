import '../l10n/app_strings.dart';
import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    AppStrings.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).primaryColor;
    final currentYear = DateTime.now().year;

    return Scaffold(
      backgroundColor: Colors.transparent, // Uses parent Scaffold logic
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --- 1. HERO LOGO SECTION ---
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(
                    color: primary.withValues(alpha: 0.15), width: 2),
              ),
              child: Image.asset(
                'assets/app_logo.png',
                width: 80,
                height: 80,
              ),
            ),
            const SizedBox(height: 24),

            // --- 2. APP IDENTITY ---
            Text(
              AppStrings.current.text('likhlo_6ef8c8'),
              style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.0,
                  color: isDark ? Colors.white : Colors.black87),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(
                AppStrings.current.text('version_2_5_0_stable_5ceaa9'),
                style: TextStyle(
                    fontSize: 12,
                    color: primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5),
              ),
            ),
            const SizedBox(height: 40),

            // --- 3. DEVELOPER SHOWCASE CARD ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.terminal_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppStrings.current.text('lead_developer_f82e5e'),
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5)),
                            SizedBox(height: 4),
                            Text(AppStrings.current.text('jawad_rajper_bb85e4'),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppStrings.current.text('full_stack_developer_bsit_sbbu_ef83d3'),
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.current.text('engineered_as_a_comprehensive_final_year_project_0e4603'),
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.5),
                  ),
                  const SizedBox(height: 20),

                  // Contact Information Block
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.email_rounded,
                                color: Colors.white70, size: 16),
                            SizedBox(width: 12),
                            Expanded(
                                child: Text(AppStrings.current.text('jawadrajper5001_gmail_com_2e3527'),
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600))),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.wechat_rounded,
                                color: Colors.white70,
                                size:
                                    16), // Using wechat or chat icon as WhatsApp alternative
                            SizedBox(width: 12),
                            Expanded(
                                child: Text("+92 307 3156483",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600))),
                          ],
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),

            // --- 4. APP MISSION & INFO GROUP ---
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.grey.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  _buildListTile(
                    context: context,
                    icon: Icons.rocket_launch_rounded,
                    iconColor: Colors.orange,
                    title: AppStrings.current.text('our_mission_e36a91'),
                    subtitle:
                        AppStrings.current.text('empowering_students_to_track_pocket_money_manage_b04d12'),
                  ),
                  Divider(
                      height: 1,
                      indent: 64,
                      color: isDark
                          ? Colors.white10
                          : Colors.grey.withValues(alpha: 0.1)),
                  _buildListTile(
                    context: context,
                    icon: Icons.shield_rounded,
                    iconColor: Colors.green,
                    title: AppStrings.current.text('privacy_first_b8351d'),
                    subtitle:
                        AppStrings.current.text('all_your_financial_data_is_stored_securely_and_l_f4ef75'),
                  ),
                  Divider(
                      height: 1,
                      indent: 64,
                      color: isDark
                          ? Colors.white10
                          : Colors.grey.withValues(alpha: 0.1)),
                  _buildListTile(
                    context: context,
                    icon: Icons.code_rounded,
                    iconColor: Colors.blue,
                    title: AppStrings.current.text('architecture_b040b4'),
                    subtitle:
                        AppStrings.current.text('built_with_flutter_riverpod_local_nlp_and_materi_36cf20'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // --- 5. FOOTER ---
            Icon(Icons.favorite_rounded, color: Colors.red.shade400, size: 24),
            const SizedBox(height: 12),
            Text(AppStrings.current.text('made_with_passion_in_sindh_pakistan_f99d0b'),
                style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(AppStrings.current.text('likhlo_app_c9fcc6', {'p0': currentYear}),
                style: TextStyle(
                    color: Colors.grey.withValues(alpha: 0.5), fontSize: 11)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildListTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(AppStrings.current.display(title),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 6),
                Text(AppStrings.current.display(subtitle),
                    style: TextStyle(
                        color: Colors.grey.shade500,
                        height: 1.4,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          )
        ],
      ),
    );
  }
}
